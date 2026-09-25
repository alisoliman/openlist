//
//  WidgetSnapshotPublisher.swift
//  openlist
//

import Foundation
import SwiftData
import WidgetKit

/// Keeps the widget's snapshot file in step with the app's data.
///
/// Rebuilding is cheap but not free, so writes are coalesced: a burst of edits
/// produces a single refresh once the user pauses.
@MainActor
final class WidgetSnapshotPublisher {
    /// Work and the week's agenda, from the calendar. Absent in tools that
    /// build snapshots without one.
    typealias CalendarFeed = (Date) -> (work: WidgetSnapshot.Work?, agenda: [WidgetSnapshot.AgendaDay])

    private let store: Store
    private let libraryID: UUID?
    private var pendingRefresh: Task<Void, Never>?
    private var lastWritten: WidgetSnapshot?
    private var heatmapCache: (key: [Int], activity: WidgetSnapshot.Activity?)?
    /// Each list's first open tasks in its own order, by list, with what the
    /// order was worked out from.
    private var listOrderCache: [UUID: (key: Int, ids: [UUID])] = [:]
    /// The settings calendar, whose week the Agenda and heatmap follow.
    var settingsCalendar: () -> Calendar = { .current }
    var calendarFeed: CalendarFeed?

    /// Weeks of history the medium Activity widget draws.
    static let activityWeeks = 21
    /// Today's rows kept for each day: the oldest overdue ones, then today's
    /// and tomorrow's, each with room of its own. Large Today draws up to 3
    /// overdue rows and 5 in all, as the design's; the rest are spares for
    /// ticks queued in the widget and, after midnight, tomorrow's rows.
    static let todayRows = (overdue: 10, perDay: 15)

    convenience init(store: Store) {
        self.init(store: store, libraryID: nil)
    }

    init(store: Store, libraryID: UUID?) {
        self.store = store
        self.libraryID = libraryID

        // Overdue / due-today / done-today are all relative to "today", and the
        // app computes them when it writes the snapshot. Without this the
        // widget would keep yesterday's counts until something else changed.
        // The publisher lives as long as the app, so the observation is never
        // torn down and needs no stored token.
        NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshNow() }
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

    /// Rebuilds and writes immediately. `forcingReload` reloads the widgets even
    /// when nothing changed, after actions a widget has been showing as done.
    func refreshNow(forcingReload: Bool = false) {
        pendingRefresh?.cancel()
        var snapshot = buildSnapshot()
        let now = Date.now
        let running = snapshot.work?.isRunning == true
        if running { snapshot.heartbeatAt = now }
        if snapshot != lastWritten {
            lastWritten = snapshot
            WidgetSnapshotStore.write(snapshot)
            WidgetCenter.shared.reloadAllTimelines()
        } else if running, now.timeIntervalSince(lastWritten?.heartbeatAt ?? .distantPast) >= 60 {
            // Nothing the widget shows changed, but a running timer's heartbeat
            // tells it the app is still recording. A rewrite is enough; the
            // widget reads it on its next reload.
            lastWritten = snapshot
            WidgetSnapshotStore.write(snapshot)
            if forcingReload { WidgetCenter.shared.reloadAllTimelines() }
        } else if forcingReload {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // MARK: - Building

    func buildSnapshot(now: Date = .now) -> WidgetSnapshot {
        let calendar = settingsCalendar()
        let lists = store.allLists()
        let hierarchy = ListHierarchy(lists)
        var listsByID: [UUID: TaskList] = [:]
        for list in lists { listsByID[list.id] = list }
        // Tasks only: prose never shows in a widget, and a library's
        // documents can hold many times more of it than tasks. This runs
        // after every save, the editor's autosave included.
        let allTasks = ((try? store.context.fetch(FetchDescriptor<Block>(predicate: #Predicate {
            $0.trashID == nil && $0.kindRaw == "task"
        }))) ?? []).filter { !$0.isDeleted }
        let tasks = ActiveTaskPolicy(hierarchy: hierarchy).tasks(in: allTasks)
        let inbox = InboxPolicy(lists: lists)

        let todayStart = calendar.startOfDay(for: now)
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart
        let soonEnd = calendar.date(byAdding: .day, value: 2, to: todayStart) ?? tomorrowStart

        func item(_ task: Block) -> WidgetSnapshot.Item {
            let list = task.listID.flatMap { listsByID[$0] }
            return WidgetSnapshot.Item(
                id: task.id,
                occurrenceID: task.occurrenceID,
                title: task.displayTitle,
                listID: task.listID,
                listName: list?.displayTitle ?? "",
                listIcon: list?.glyph ?? "",
                accent: list?.widgetAccent ?? ListAccent.graphite.rawValue,
                dueDate: task.dueDate,
                includesTime: task.includesTime,
                isCompleted: task.isCompleted,
                completedAt: task.completedAt,
                isStarred: task.isStarred,
                hasRepeat: task.recurrenceData != nil,
                priority: task.priorityRaw,
                isInbox: inbox.includes(task)
            )
        }

        var snapshot = WidgetSnapshot()
        snapshot.generatedAt = now
        snapshot.libraryID = libraryID
        snapshot.firstWeekday = calendar.firstWeekday
        snapshot.completedTodayDay = todayStart

        var soon: [Block] = []
        var inboxOpen: [Block] = []
        var dueDates: [Date] = []
        var listCounts: [UUID: (open: Int, done: Int)] = [:]
        for task in tasks {
            let listID = task.listID
            if task.isCompleted {
                if let completedAt = task.completedAt, completedAt >= todayStart, completedAt < tomorrowStart {
                    snapshot.completedTodayCount += 1
                }
                if let listID { listCounts[listID, default: (0, 0)].done += 1 }
                continue
            }
            snapshot.totalOpenCount += 1
            if let listID { listCounts[listID, default: (0, 0)].open += 1 }
            if inbox.includes(task) { inboxOpen.append(task) }
            guard let due = task.dueDate else { continue }
            dueDates.append(due)
            // Version 1's rule, for its widget: timed work is late once its time passes.
            if task.includesTime ? due < now : due < todayStart { snapshot.overdueCount += 1 }
            else if due < tomorrowStart { snapshot.dueTodayCount += 1 }
            // Overdue by day, as the app's Today: today's and tomorrow's too,
            // so entries after midnight still have the new day's rows.
            if due < soonEnd { soon.append(task) }
        }
        snapshot.dueDays = WidgetSnapshot.dueDays(dueDates, calendar: calendar)

        let sorted = soon.sorted { a, b in
            let aDay = calendar.startOfDay(for: a.dueDate!), bDay = calendar.startOfDay(for: b.dueDate!)
            if aDay != bDay { return aDay < bDay }
            if a.includesTime != b.includesTime { return a.includesTime }
            if a.dueDate != b.dueDate || a.priorityRaw != b.priorityRaw { return Block.byDueDate(a, b) }
            // Then capture order, as the app's Today, and one fixed order for
            // exact ties, so the rows and the snapshot compared on each
            // rebuild stay put however the fetch returns them.
            return a.createdAt == b.createdAt ? a.id.uuidString < b.id.uuidString : a.createdAt < b.createdAt
        }
        // By day, so however much is overdue, today's and tomorrow's rows still come.
        let overdue = sorted.prefix { $0.dueDate! < todayStart }
        let dueToday = sorted.dropFirst(overdue.count).prefix { $0.dueDate! < tomorrowStart }
        let dueTomorrow = sorted.dropFirst(overdue.count + dueToday.count)
        snapshot.todayItems = (overdue.prefix(Self.todayRows.overdue) + dueToday.prefix(Self.todayRows.perDay)
            + dueTomorrow.prefix(Self.todayRows.perDay)).map(item)

        snapshot.inboxCount = inboxOpen.count
        snapshot.inboxItems = inboxOpen.sorted { $0.createdAt > $1.createdAt }.prefix(WidgetSnapshot.inboxRows).map {
            WidgetSnapshot.InboxItem(id: $0.id, title: $0.displayTitle, createdAt: $0.createdAt)
        }

        let tasksByList = Dictionary(grouping: allTasks.filter { $0.listID != nil }, by: { $0.listID! })
        let above = blocksAbove(allTasks)
        var orders: [UUID: (key: Int, ids: [UUID])] = [:]
        // The List widget's picker and its default follow the sidebar. Every
        // active list is here, so the one a widget shows stays however many
        // lists are made, moved or reordered ahead of it.
        let sidebar = hierarchy.sidebarOrder(lists, sections: store.allSections())
        snapshot.lists = sidebar.filter { !$0.isSystemInbox }.map { list in
            let owned = tasksByList[list.id] ?? []
            let open = openTasks(in: list, tasks: owned, above: above, limit: WidgetSnapshot.ListSummary.openRows, orders: &orders)
            let done = owned.filter(\.isCompleted).sorted(by: Block.byCompletionDate)
            return WidgetSnapshot.ListSummary(
                id: list.id,
                title: list.displayTitle,
                icon: list.glyph,
                accent: list.widgetAccent,
                openCount: listCounts[list.id]?.open ?? 0,
                doneCount: listCounts[list.id]?.done ?? 0,
                openItems: open.map(item),
                doneItems: done.prefix(6).map(item)
            )
        }
        listOrderCache = orders

        if let calendarFeed {
            let feed = calendarFeed(now)
            snapshot.work = feed.work
            if let work = feed.work { snapshot.work?.item = tasks.first { $0.id == work.taskID }.map(item) }
            snapshot.agenda = feed.agenda
        }
        snapshot.activity = activity(now: now, calendar: calendar)
        return snapshot
    }

    /// The first `limit` open tasks of `list` in the list's own order.
    ///
    /// That order runs through the prose and headings above the tasks, so
    /// working it out reads every block in the list. Kept until the list's
    /// tasks, or a block above one, move or change what the list sorts by;
    /// typing in the list's prose leaves it be.
    private func openTasks(in list: TaskList, tasks: [Block], above: [UUID: Block], limit: Int,
                           orders: inout [UUID: (key: Int, ids: [UUID])]) -> [Block] {
        // A list with nothing open has no order to work out.
        guard tasks.contains(where: { !$0.isCompleted }) else { return [] }
        let sorting = list.sorting
        func hash(_ body: (inout Hasher) -> Void) -> Int {
            var hasher = Hasher()
            body(&hasher)
            return hasher.finalize()
        }
        // Summed, so the order the fetch returned the tasks in doesn't matter.
        var key = hash { $0.combine(sorting) }
        var seen: Set<UUID> = []
        for task in tasks {
            key &+= hash {
                $0.combine(task.id); $0.combine(task.parentID); $0.combine(task.sortIndex); $0.combine(task.createdAt)
                $0.combine(task.isCompleted); $0.combine(task.dueDate); $0.combine(task.priorityRaw)
                if sorting == .alphabetical { $0.combine(task.displayTitle) }
            }
            var parent = task.parentID
            while let id = parent, let block = above[id], seen.insert(id).inserted {
                key &+= hash { $0.combine(id); $0.combine(block.parentID); $0.combine(block.sortIndex); $0.combine(block.createdAt); $0.combine(block.listID) }
                parent = block.parentID
            }
        }
        let byID = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        if let cached = listOrderCache[list.id], cached.key == key {
            orders[list.id] = cached
            return cached.ids.compactMap { byID[$0] }
        }
        let listID = list.id
        let blocks = ((try? store.context.fetch(FetchDescriptor<Block>(predicate: #Predicate {
            $0.trashID == nil && $0.listID == listID
        }))) ?? []).filter { !$0.isDeleted }
        let open = Array(ListTasksProjection(blocks: blocks, listID: listID, sorting: sorting, showsCompleted: false).tasks.prefix(limit))
        orders[list.id] = (key, open.map(\.id))
        return open
    }

    /// The blocks other than tasks that hold tasks, at any depth, by id: the
    /// ones whose place decides where the tasks beneath them fall in a list.
    private func blocksAbove(_ tasks: [Block]) -> [UUID: Block] {
        let taskIDs = Set(tasks.map(\.id))
        var found: [UUID: Block] = [:]
        var wanted = Set(tasks.compactMap(\.parentID)).subtracting(taskIDs)
        var depth = 0
        while !wanted.isEmpty, depth < 64 {
            depth += 1
            let ids = Array(wanted)
            let parents = ((try? store.context.fetch(FetchDescriptor<Block>(predicate: #Predicate {
                $0.trashID == nil && ids.contains($0.id)
            }))) ?? []).filter { !$0.isDeleted }
            for parent in parents { found[parent.id] = parent }
            wanted = Set(parents.compactMap(\.parentID)).subtracting(taskIDs).subtracting(found.keys)
        }
        return found
    }

    /// The heatmap's counts, read again only when the day, the week's first day
    /// or the recorded activity changes: heartbeats rebuild the snapshot every
    /// minute while work runs.
    private func activity(now: Date, calendar: Calendar) -> WidgetSnapshot.Activity? {
        let completed = (try? store.context.fetchCount(FetchDescriptor<ActivityEvent>(predicate: #Predicate { $0.kindRaw == "completed" }))) ?? -1
        let events = (try? store.context.fetchCount(FetchDescriptor<ActivityEvent>())) ?? -1
        let key = [Int(calendar.startOfDay(for: now).timeIntervalSinceReferenceDate), calendar.firstWeekday, completed, events]
        if let heatmapCache, heatmapCache.key == key { return heatmapCache.activity }
        let activity = (try? store.activityHeatmap(now: now, calendar: calendar, weeks: Self.activityWeeks)).map {
            WidgetSnapshot.Activity(start: $0.start, counts: $0.days.map(\.count))
        }
        heatmapCache = (key, activity)
        return activity
    }
}

extension TaskList {
    /// The colour the widgets draw a list's tasks in, as the app draws them:
    /// Inbox's own blue (`NX.inbox`) as `#RRGGBB`, else the list's accent.
    var widgetAccent: String { isSystemInbox ? "#3A7BD8" : accent.rawValue }
}
