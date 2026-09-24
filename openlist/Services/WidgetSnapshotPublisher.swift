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
    /// The settings calendar, whose week the Agenda and heatmap follow.
    var settingsCalendar: () -> Calendar = { .current }
    var calendarFeed: CalendarFeed?

    /// Weeks of history the medium Activity widget draws.
    static let activityWeeks = 21

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
        var listsByID: [UUID: TaskList] = [:]
        for list in lists { listsByID[list.id] = list }
        let blocks = ((try? store.context.fetch(FetchDescriptor<Block>(predicate: #Predicate { $0.trashID == nil }))) ?? [])
            .filter { !$0.isDeleted }
        let tasks = ActiveTaskPolicy(lists: lists).tasks(in: blocks.filter(\.isTask))
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
                listIcon: list?.icon ?? "",
                accent: (list?.accent ?? .graphite).rawValue,
                dueDate: task.dueDate,
                includesTime: task.includesTime,
                isCompleted: task.isCompleted,
                completedAt: task.completedAt,
                isStarred: task.isStarred,
                hasRepeat: task.recurrenceData != nil,
                priority: task.priorityRaw
            )
        }

        var snapshot = WidgetSnapshot()
        snapshot.generatedAt = now
        snapshot.libraryID = libraryID
        snapshot.firstWeekday = calendar.firstWeekday
        snapshot.completedTodayDay = todayStart

        var soon: [Block] = []
        var inboxOpen: [Block] = []
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
            snapshot.dueStamps.append(WidgetSnapshot.DueStamp(id: task.id, due: due, includesTime: task.includesTime))
            // Overdue by day, as the app's Today: today's and tomorrow's too,
            // so entries after midnight still have the new day's rows.
            if due < soonEnd { soon.append(task) }
        }

        snapshot.todayItems = soon.sorted { a, b in
            let aDay = calendar.startOfDay(for: a.dueDate!), bDay = calendar.startOfDay(for: b.dueDate!)
            if aDay != bDay { return aDay < bDay }
            if a.includesTime != b.includesTime { return a.includesTime }
            return Block.byDueDate(a, b)
        }.prefix(40).map(item)

        snapshot.inboxCount = inboxOpen.count
        snapshot.inboxItems = inboxOpen.sorted { $0.createdAt > $1.createdAt }.prefix(4).map {
            WidgetSnapshot.InboxItem(id: $0.id, title: $0.displayTitle, createdAt: $0.createdAt)
        }

        let blocksByList = Dictionary(grouping: blocks.filter { $0.listID != nil }, by: { $0.listID! })
        snapshot.lists = lists.filter { !$0.isSystemInbox }.prefix(60).map { list in
            let owned = blocksByList[list.id] ?? []
            let open = ListTasksProjection(blocks: owned, listID: list.id, sorting: list.sorting, showsCompleted: false).tasks
            let done = owned.filter { $0.isTask && $0.isCompleted }.sorted(by: Block.byCompletionDate)
            return WidgetSnapshot.ListSummary(
                id: list.id,
                title: list.displayTitle,
                icon: list.icon,
                accent: list.accent.rawValue,
                openCount: listCounts[list.id]?.open ?? 0,
                doneCount: listCounts[list.id]?.done ?? 0,
                openItems: open.prefix(7).map(item),
                doneItems: done.prefix(6).map(item)
            )
        }

        if let calendarFeed {
            let feed = calendarFeed(now)
            snapshot.work = feed.work
            snapshot.agenda = feed.agenda
        }
        snapshot.activity = activity(now: now, calendar: calendar)
        return snapshot
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
