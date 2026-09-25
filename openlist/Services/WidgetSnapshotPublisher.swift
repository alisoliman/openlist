//
//  WidgetSnapshotPublisher.swift
//  openlist
//

import Foundation
import SwiftData
import WidgetKit

/// What a snapshot needs from outside the Store: settings, the calendar plan
/// and the work timer, and whether the app is in front when it is written.
///
/// Each value is read when a snapshot is built, so a settings change shows on
/// the next refresh without replacing the sources. The defaults are the app's
/// own defaults with no calendar, which lets the publisher run on a Store
/// alone, as the check suites do; the app installs `live(calendar:settings:libraryID:)`.
@MainActor
struct WidgetSnapshotSources {
    var libraryID: UUID?
    /// The app's accent as 0xRRGGBB.
    var accentHex: @MainActor () -> UInt32 = { 0x7C4DF0 }
    var serifTitles: @MainActor () -> Bool = { true }
    /// The calendar the app uses for weeks, honouring its first-weekday setting.
    var calendar: @MainActor () -> Calendar = { .current }
    /// Meetings and task blocks overlapping the interval, in any order.
    var agenda: @MainActor (DateInterval) -> [WidgetSnapshot.AgendaEvent] = { _ in [] }
    /// The running or paused work at a date, if any.
    var work: @MainActor (Date) -> WidgetSnapshot.Work? = { _ in nil }
    /// Whether the app is frontmost. WidgetKit budgets only the reloads an
    /// app asks for from the background, so a sliding plan is held back only
    /// then.
    var isAppActive: @MainActor () -> Bool = { true }

    static var empty: WidgetSnapshotSources { WidgetSnapshotSources() }
}

/// Keeps the widget's snapshot file in step with the app's data.
///
/// Rebuilding runs on the main actor, so writes are coalesced (a burst of
/// edits produces a single refresh once the user pauses) and the rebuild
/// reads no more than the widgets show: tasks and the headings they sit
/// under, not every paragraph, and the completion history only when it has
/// changed.
///
/// Every changed snapshot is written straight away, but reloads are scoped:
/// WidgetKit budgets the reloads an app asks for from the background, and a
/// plan that slides every few minutes must not spend the other widgets'.
@MainActor
final class WidgetSnapshotPublisher {
    /// No widget size shows more rows than these, and the file is decoded on
    /// every timeline request.
    private enum Limit {
        /// Each of Today's groups, overdue, due today and tomorrow, on its
        /// own: more than a widget draws of any, so rows a cap leaves out
        /// never come before the rows a widget shows, even once a widget
        /// starts the next day with them (`WidgetState`).
        static let todayItems = 6
        static let inboxItems = 6
        static let openItems = 12
        static let doneItems = 6
        /// The medium Activity widget's heatmap.
        static let activityWeeks = 21
    }

    /// Which widget timelines a write reloads.
    enum Reload: Equatable {
        /// Every widget: tasks, counts, lists, activity or appearance changed.
        case all
        /// Up Next and Agenda: only the plan or the work session changed.
        case plan
    }

    /// How a snapshot differs from the one written before it.
    enum Change: Equatable {
        /// Anything outside the plan and the work session.
        case data
        /// The work session itself: started, paused, switched or stopped.
        case work
        /// Only where meetings and blocks sit: an unstarted block sliding to
        /// the next free time, a calendar edit, a running block extended.
        case plan
    }

    private let store: Store
    var sources: WidgetSnapshotSources
    /// Asks WidgetKit to reload. The check suites replace it to count reloads.
    var reloadTimelines: @MainActor (Reload) -> Void = { reload in
        switch reload {
        case .all: WidgetCenter.shared.reloadAllTimelines()
        case .plan: for kind in WidgetKind.plan { WidgetCenter.shared.reloadTimelines(ofKind: kind) }
        }
    }
    /// While the app is in the background, plan-only changes reload Up Next
    /// and Agenda at most this often. Agenda's own entries step every quarter
    /// hour, so a slid block shows at most one step late; the file is always
    /// current, so any earlier reload shows it sooner.
    var planReloadInterval: TimeInterval = 15 * 60
    private var pendingRefresh: Task<Void, Never>?
    private var lastWritten: WidgetSnapshot?
    private var lastPlanReload = Date.distantPast
    /// Reloads Up Next and Agenda once the interval is up, for the last of a
    /// run of held-back plan changes.
    private var pendingPlanReload: Task<Void, Never>?
    private var activityCache: ActivityCache?
    /// Each sorted list's task order, and the key it was worked out for.
    private var sortedOrders: [UUID: SortedOrder] = [:]

    /// A sorted list's tasks in its page's order. That order runs through the
    /// prose between the list's runs of tasks, so working it out reads the
    /// whole document, while most rebuilds (the editor's autosave as you
    /// type, a sliding plan) leave it as it was.
    private struct SortedOrder {
        var key: Int
        var ids: [UUID]
    }

    /// The Activity section and what it was built from. Building it reads the
    /// whole completion history, which most refreshes (a typing pause, a
    /// Start, a sliding plan) leave as it was.
    private struct ActivityCache {
        var history: CompletionHistorySignature
        var calendar: Calendar
        var day: Date
        /// See `ActivityHeatmap.nextCompletionAt`.
        var staleAt: Date?
        var activity: WidgetSnapshot.Activity
    }

    init(store: Store, sources: WidgetSnapshotSources = .empty) {
        self.store = store
        self.sources = sources

        // Overdue / due-today / done-today are all relative to "today", and the
        // app computes them when it writes the snapshot. Without this the
        // widget would keep yesterday's counts until something else changed.
        // Forced, because a day can start with the same rows and counts the
        // last one ended with (nothing due either day), and skipping that
        // write would leave `generatedAt` on yesterday: the widget reads it to
        // tell which day the counts are for, so it would move them forward
        // again, and after two such days take a running app's file as stale.
        // The publisher lives as long as the app, so the observation is never
        // torn down and needs no stored token.
        NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshNow(force: true) }
        }
    }

    /// Requests a refresh, debounced by half a second.
    func scheduleRefresh() {
        pendingRefresh?.cancel()
        pendingRefresh = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.refreshNow()
        }
    }

    /// Rebuilds and writes immediately. The write and the timeline reload are
    /// skipped when nothing the widget shows has changed, unless `force` asks
    /// for them anyway, such as after a widget action whose optimistic state
    /// the widget should now drop. A forced refresh reloads every widget at
    /// once, however little changed.
    func refreshNow(force: Bool = false, now: Date = .now) {
        pendingRefresh?.cancel()
        pendingRefresh = nil
        let snapshot = buildSnapshot(now: now)
        guard force || snapshot != lastWritten else { return }
        let change = force ? .data : lastWritten.map { Self.change(from: $0, to: snapshot) } ?? .data
        write(snapshot, change: change, now: now)
    }

    /// Writes, synchronously, what the widget should show once the app has quit.
    ///
    /// Quitting pauses running work, but that pause may land after this call
    /// and the process exits before a debounced refresh would run. Running
    /// work is therefore written as already paused at `now`, so a widget never
    /// keeps counting for an app that is no longer recording.
    func prepareForTermination(now: Date = .now) {
        pendingRefresh?.cancel()
        pendingRefresh = nil
        var snapshot = buildSnapshot(now: now)
        if var work = snapshot.work, work.state == .working {
            work.priorSeconds = work.elapsed(at: now)
            work.segmentStartedAt = nil
            work.state = .paused
            snapshot.work = work
        }
        write(snapshot, change: .data, now: now)
    }

    private func write(_ snapshot: WidgetSnapshot, change: Change, now: Date) {
        lastWritten = snapshot
        // Always written, so a reload for any reason shows the latest.
        WidgetSnapshotStore.write(snapshot)
        switch change {
        case .data:
            planWidgetsReloaded(at: now)
            reloadTimelines(.all)
        case .work:
            reloadPlanWidgets(now: now)
        case .plan:
            let due = lastPlanReload.addingTimeInterval(planReloadInterval)
            if sources.isAppActive() || now >= due {
                reloadPlanWidgets(now: now)
            } else if pendingPlanReload == nil {
                pendingPlanReload = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(due.timeIntervalSince(now)))
                    guard !Task.isCancelled else { return }
                    self?.reloadPlanWidgets(now: .now)
                }
            }
        }
    }

    private func reloadPlanWidgets(now: Date) {
        planWidgetsReloaded(at: now)
        reloadTimelines(.plan)
    }

    /// A reload reads the file as it is now, so a held-back one is moot.
    private func planWidgetsReloaded(at now: Date) {
        pendingPlanReload?.cancel()
        pendingPlanReload = nil
        lastPlanReload = now
    }

    /// Which widgets a new snapshot concerns. Up Next and Agenda draw only
    /// the plan, the work session and the day's done count; the others never
    /// draw the plan.
    nonisolated static func change(from old: WidgetSnapshot, to new: WidgetSnapshot) -> Change {
        var oldRest = old, newRest = new
        oldRest.agenda = []
        newRest.agenda = []
        oldRest.work = nil
        newRest.work = nil
        guard oldRest == newRest else { return .data }
        var oldWork = old.work, newWork = new.work
        oldWork?.blockStart = nil
        oldWork?.blockEnd = nil
        newWork?.blockStart = nil
        newWork?.blockEnd = nil
        return oldWork == newWork ? .plan : .work
    }

    // MARK: - Building

    /// Every field holds absolute values, never elapsed time, so the snapshot
    /// stays equal between work heartbeats and a running session does not
    /// reload the widgets every minute.
    func buildSnapshot(now: Date = .now) -> WidgetSnapshot {
        let calendar = sources.calendar()
        let hierarchy = store.listHierarchy()
        let lists = store.allLists()
        var listsByID: [UUID: TaskList] = [:]
        for list in lists { listsByID[list.id] = list }

        let blocks = outlineBlocks()
        let tasks = ActiveTaskPolicy(hierarchy: hierarchy).tasks(in: blocks)
        let inbox = InboxPolicy(hierarchy: hierarchy)
        let tasksByID = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        /// Whether an open task sits above this one, through its parent tasks.
        func isUnderOpenTask(_ task: Block) -> Bool {
            var seen: Set<UUID> = [task.id]
            var parentID = task.parentID
            while let id = parentID, let parent = tasksByID[id], seen.insert(id).inserted {
                if !parent.isCompleted { return true }
                parentID = parent.parentID
            }
            return false
        }
        var blocksByList: [UUID: [Block]] = [:]
        for block in blocks {
            if let listID = block.listID, listsByID[listID] != nil { blocksByList[listID, default: []].append(block) }
        }

        // One pass fills every counter; the day boundaries are computed once up front.
        let todayStart = calendar.startOfDay(for: now)
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart
        let dayAfterStart = calendar.date(byAdding: .day, value: 1, to: tomorrowStart) ?? tomorrowStart

        var overdue: [Block] = []
        var dueNow: [Block] = []
        var dueToday: [WidgetSnapshot.Due] = []
        var dueNext: [Block] = []
        var dueTomorrow: [WidgetSnapshot.Due] = []
        var totalOpen = 0
        var waiting: [Block] = []

        for task in tasks where !task.isCompleted {
            totalOpen += 1
            // Triage takes what the Inbox badge counts: a subtask goes with the
            // open task above it, whose card carries it; one under done tasks
            // only is a card of its own.
            if inbox.includes(task), !isUnderOpenTask(task) { waiting.append(task) }

            guard let due = task.dueDate else { continue }
            // By day, as the app's Today: a timed task whose time has passed
            // is still due today.
            if due < todayStart {
                overdue.append(task)
            } else if due < tomorrowStart {
                dueToday.append(WidgetSnapshot.Due(date: due, includesTime: task.includesTime))
                dueNow.append(task)
            } else if due < dayAfterStart {
                // Tomorrow's work, which the widget moves into today at
                // midnight. The app republishes then only if it is running;
                // quit, or before a login, the file is all the widget has.
                dueTomorrow.append(WidgetSnapshot.Due(date: due, includesTime: task.includesTime))
                dueNext.append(task)
            }
        }

        // Ties go by capture order, as the app's Today, then by id: the fetch
        // returns tasks in no fixed order, and a snapshot whose rows swapped
        // places would reload every widget with nothing changed.
        overdue.sort(by: Self.byDueDate)
        dueNow.sort(by: Self.byDueDate)
        dueNext.sort(by: Self.byDueDate)
        waiting.sort { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt > $1.createdAt }

        var snapshot = WidgetSnapshot()
        // The moment the counts are relative to, which the widget moves them
        // forward from; `now` is the wall clock except in the check suites.
        snapshot.generatedAt = now
        snapshot.libraryID = sources.libraryID
        snapshot.accentHex = sources.accentHex()
        snapshot.serifTitles = sources.serifTitles()
        snapshot.firstWeekday = calendar.firstWeekday
        // Capped group by group, so a long backlog still leaves today's own
        // work rows to draw.
        snapshot.todayItems = (overdue.prefix(Limit.todayItems) + dueNow.prefix(Limit.todayItems)).map { task in
            item(task, list: task.listID.flatMap { listsByID[$0] })
        }
        snapshot.overdueCount = overdue.count
        snapshot.dueTodayCount = dueToday.count
        snapshot.dueToday = dueToday.sorted(by: Self.byDate)
        // Ordered and capped as today's rows are, which they join after them.
        snapshot.tomorrowItems = dueNext.prefix(Limit.todayItems).map { task in
            item(task, list: task.listID.flatMap { listsByID[$0] })
        }
        snapshot.dueTomorrow = dueTomorrow.sorted(by: Self.byDate)
        snapshot.inboxCount = waiting.count
        snapshot.inboxItems = waiting.prefix(Limit.inboxItems).map {
            WidgetSnapshot.InboxItem(id: $0.id, title: $0.displayTitle, createdAt: $0.createdAt)
        }
        snapshot.totalOpenCount = totalOpen
        var orders: [UUID: SortedOrder] = [:]
        snapshot.lists = hierarchy.sidebarOrder(lists, sections: store.allSections()).map {
            summary(of: $0, blocks: blocksByList[$0.id] ?? [], hierarchy: hierarchy, orders: &orders)
        }
        // Only the lists still sorted keep an order.
        sortedOrders = orders

        let weekStart = Self.weekStart(containing: now, calendar: calendar)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        snapshot.weekStart = weekStart
        snapshot.agenda = sources.agenda(DateInterval(start: weekStart, end: weekEnd))
            .sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
        snapshot.work = sources.work(now)

        snapshot.activity = activity(now: now, weekStart: weekStart, calendar: calendar)
        // Done today as the app's Today counts it (`Block.isCompletedToday`):
        // tasks completed today, from current state, so a reopen or Undo takes
        // one away. A repeat rolls forward to its next occurrence instead of
        // staying completed, and a routine's steps reset with it, so, as in
        // the app, finishing one moves it off today without adding to done.
        // Activity, above, still counts those completions.
        snapshot.completedTodayCount = tasks.count { task in
            task.isCompleted && task.completedAt.map { $0 >= todayStart && $0 < tomorrowStart } == true
        }
        return snapshot
    }

    /// Every task, and the headings, paragraphs and tasks they sit under, up
    /// to the top of each document: enough for each list's outline to put its
    /// tasks where the full document does, without the prose around them.
    /// Siblings keep their order and the walk its roots, so the outline is
    /// the same as the one built from every block.
    private func outlineBlocks() -> [Block] {
        // A model deleted since the last save still turns up in a fetch.
        let tasks = ((try? store.context.fetch(FetchDescriptor<Block>(predicate: #Predicate { $0.trashID == nil && $0.kindRaw == "task" }))) ?? [])
            .filter { !$0.isDeleted }
        var blocks = tasks
        var fetched = Set(tasks.map(\.id))
        var missing = Set(tasks.compactMap(\.parentID)).subtracting(fetched)
        while !missing.isEmpty {
            fetched.formUnion(missing)
            let ids = Array(missing)
            let parents = ((try? store.context.fetch(FetchDescriptor<Block>(predicate: #Predicate { $0.trashID == nil && ids.contains($0.id) }))) ?? [])
                .filter { !$0.isDeleted }
            blocks += parents
            missing = Set(parents.compactMap(\.parentID)).subtracting(fetched)
        }
        return blocks
    }

    /// Open tasks in the order the list's page draws them. Subtasks are
    /// included: the list shows them, the open and done counts include them,
    /// and ticking one off from a widget is the same action as in the app.
    private func summary(of list: TaskList, blocks: [Block], hierarchy: ListHierarchy,
                         orders: inout [UUID: SortedOrder]) -> WidgetSnapshot.ListSummary {
        let tasks = blocks.contains(where: \.isTask) ? orderedTasks(of: list, blocks: blocks, orders: &orders) : []
        let open = tasks.filter { !$0.isCompleted }
        let done = tasks.filter(\.isCompleted).sorted { left, right in
            left.completedAt == right.completedAt ? left.id.uuidString < right.id.uuidString : Block.byCompletionDate(left, right)
        }
        return WidgetSnapshot.ListSummary(
            id: list.id,
            title: list.displayTitle,
            path: hierarchy.path(for: list.id),
            icon: list.glyph,
            accentHex: list.displayAccentHex,
            isInbox: list.isSystemInbox,
            openCount: open.count,
            doneCount: done.count,
            openItems: open.prefix(Limit.openItems).map { item($0, list: list) },
            doneItems: done.prefix(Limit.doneItems).map { item($0, list: list) }
        )
    }

    /// The list's tasks in its page's order: the document's outline, with the
    /// list's Sort reordering each run of top-level tasks between its prose
    /// and headings. Unsorted, the tasks and the blocks they sit under give
    /// that order. A sorted list reads its whole document, since the prose
    /// between runs is what keeps them apart, but only when its order may
    /// have changed: its tasks or the blocks they sit under moved or changed
    /// what the Sort reads, the Sort itself changed, or a block came or went
    /// at the top level, where the runs are. Typing leaves the order be.
    private func orderedTasks(of list: TaskList, blocks: [Block], orders: inout [UUID: SortedOrder]) -> [Block] {
        var seen: Set<UUID> = []
        let owned = blocks.filter { $0.listID == list.id && !$0.isTrashed && seen.insert($0.id).inserted }
        guard list.sorting != .manual else { return Self.outlineTasks(owned, sorting: .manual) }
        let key = sortingKey(of: list, blocks: owned)
        let tasksByID = Dictionary(owned.filter(\.isTask).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        if let cached = sortedOrders[list.id], cached.key == key {
            orders[list.id] = cached
            return cached.ids.compactMap { tasksByID[$0] }
        }
        let listID = list.id
        seen = []
        let document = ((try? store.context.fetch(FetchDescriptor<Block>(predicate: #Predicate {
            $0.trashID == nil && $0.listID == listID
        }))) ?? []).filter { !$0.isDeleted && !$0.isTrashed && seen.insert($0.id).inserted }
        let tasks = Self.outlineTasks(document, sorting: list.sorting)
        orders[list.id] = SortedOrder(key: key, ids: tasks.map(\.id))
        return tasks
    }

    private static func outlineTasks(_ blocks: [Block], sorting: ListSorting) -> [Block] {
        BlockTree.sortingTaskRuns(in: BlockTree.flatten(blocks, respectCollapse: false), by: sorting)
            .map(\.block).filter(\.isTask)
    }

    /// What a sorted list's order is worked out from, short of its prose:
    /// the Sort, every task and block above one, in place and in what the
    /// Sort reads, and how many blocks sit at the top level, a count the
    /// store answers without reading them. Summed, so the order a fetch
    /// returned the blocks in does not matter.
    private func sortingKey(of list: TaskList, blocks: [Block]) -> Int {
        func hash(_ body: (inout Hasher) -> Void) -> Int {
            var hasher = Hasher()
            body(&hasher)
            return hasher.finalize()
        }
        let sorting = list.sorting
        let listID = list.id
        let roots = (try? store.context.fetchCount(FetchDescriptor<Block>(predicate: #Predicate {
            $0.trashID == nil && $0.listID == listID && $0.parentID == nil
        }))) ?? -1
        var key = hash { $0.combine(sorting); $0.combine(roots) }
        for block in blocks {
            key &+= hash {
                $0.combine(block.id); $0.combine(block.parentID); $0.combine(block.sortIndex); $0.combine(block.kindRaw)
                guard block.isTask else { return }
                $0.combine(block.createdAt); $0.combine(block.isCompleted); $0.combine(block.dueDate)
                $0.combine(block.includesTime); $0.combine(block.priorityRaw)
                if sorting == .alphabetical { $0.combine(block.displayTitle) }
            }
        }
        return key
    }

    private func item(_ task: Block, list: TaskList?) -> WidgetSnapshot.Item {
        WidgetSnapshot.Item(
            id: task.id,
            occurrenceID: task.occurrenceID,
            title: task.displayTitle,
            listID: task.listID,
            listName: list?.displayTitle ?? "",
            listIcon: list?.glyph ?? "",
            accentHex: list?.displayAccentHex ?? ListAccent.graphite.hex,
            dueDate: task.dueDate,
            includesTime: task.includesTime,
            isCompleted: task.isCompleted,
            completedAt: task.completedAt,
            isStarred: task.isStarred,
            hasRepeat: task.recurrenceData != nil,
            priority: task.priorityRaw,
            createdAt: task.createdAt
        )
    }

    /// The heatmap counts retained completions, as the Activity screen does,
    /// so it is rebuilt only when that history, the day or the calendar
    /// changes.
    private func activity(now: Date, weekStart: Date, calendar: Calendar) -> WidgetSnapshot.Activity {
        let day = calendar.startOfDay(for: now)
        guard let history = try? store.completionHistorySignature() else {
            activityCache = nil
            return WidgetSnapshot.Activity()
        }
        if let cache = activityCache, cache.history == history, cache.calendar == calendar, cache.day == day,
           cache.staleAt.map({ now < $0 }) ?? true {
            return cache.activity
        }
        guard let heatmap = try? store.activityHeatmap(now: now, calendar: calendar, weeks: Limit.activityWeeks) else {
            activityCache = nil
            return WidgetSnapshot.Activity()
        }
        var activity = WidgetSnapshot.Activity()
        activity.days = heatmap.days.map { WidgetSnapshot.ActivityDay(date: $0.id, count: $0.count) }
        // The Activity screen's streak, over the whole history.
        activity.streak = heatmap.streak
        activity.today = heatmap.days.last?.count ?? 0
        activity.week = heatmap.days.filter { $0.id >= weekStart }.reduce(0) { $0 + $1.count }
        activity.month = heatmap.days.filter { calendar.isDate($0.id, equalTo: now, toGranularity: .month) }
            .reduce(0) { $0 + $1.count }
        activity.monthName = calendar.standaloneMonthSymbols[calendar.component(.month, from: now) - 1]
        activityCache = ActivityCache(history: history, calendar: calendar, day: day,
                                      staleAt: heatmap.nextCompletionAt, activity: activity)
        return activity
    }

    /// Soonest due first, as `Block.byDueDate`, then in capture order and by id.
    private static func byDueDate(_ left: Block, _ right: Block) -> Bool {
        if Block.byDueDate(left, right) { return true }
        if Block.byDueDate(right, left) { return false }
        return left.createdAt == right.createdAt ? left.id.uuidString < right.id.uuidString : left.createdAt < right.createdAt
    }

    private static func byDate(_ left: WidgetSnapshot.Due, _ right: WidgetSnapshot.Due) -> Bool {
        left.date == right.date ? !left.includesTime && right.includesTime : left.date < right.date
    }

    /// The first day of the week containing `date`, as the Activity heatmap
    /// aligns its columns.
    static func weekStart(containing date: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: date)
        let offset = (calendar.component(.weekday, from: today) - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -offset, to: today) ?? today
    }
}

