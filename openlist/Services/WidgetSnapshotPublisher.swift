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
    private let store: Store
    private var pendingRefresh: Task<Void, Never>?
    private var lastWritten: WidgetSnapshot?

    init(store: Store) {
        self.store = store

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

    /// Rebuilds and writes immediately.
    func refreshNow() {
        let snapshot = buildSnapshot()
        // Skip the write and the timeline reload when nothing the widget shows
        // has actually changed.
        guard snapshot != lastWritten else { return }
        lastWritten = snapshot
        WidgetSnapshotStore.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Building

    private func buildSnapshot() -> WidgetSnapshot {
        let descriptor = FetchDescriptor<Block>(predicate: #Predicate { $0.kindRaw == "task" })
        let tasks = (try? store.context.fetch(descriptor)) ?? []
        let lists = store.allLists()
        var listsByID: [UUID: TaskList] = [:]
        for list in lists { listsByID[list.id] = list }
        let inboxID = lists.first(where: \.isSystemInbox)?.id

        // One pass fills every counter; `isOverdue` and friends each build a
        // Calendar, so the day boundary is computed once up front.
        let todayStart = Calendar.current.startOfDay(for: .now)
        let tomorrowStart = todayStart.addingTimeInterval(86_400)
        let now = Date.now

        var dueSoon: [Block] = []
        var overdue = 0
        var dueToday = 0
        var completedToday = 0
        var inbox = 0
        var totalOpen = 0
        var listCounts: [UUID: (open: Int, done: Int)] = [:]

        for task in tasks {
            let listID = task.listID

            if task.isCompleted {
                if let completedAt = task.completedAt, completedAt >= todayStart, completedAt < tomorrowStart {
                    completedToday += 1
                }
                if let listID { listCounts[listID, default: (0, 0)].done += 1 }
                continue
            }

            totalOpen += 1
            if let listID {
                listCounts[listID, default: (0, 0)].open += 1
                if listID == inboxID { inbox += 1 }
            }

            guard let due = task.dueDate else { continue }
            let isOverdue = task.includesTime ? due < now : due < todayStart
            if isOverdue {
                overdue += 1
                dueSoon.append(task)
            } else if due < tomorrowStart {
                dueToday += 1
                dueSoon.append(task)
            }
        }

        dueSoon.sort(by: Block.byDueDate)

        let items = dueSoon.prefix(12).map { task -> WidgetSnapshot.Item in
            let list = task.listID.flatMap { listsByID[$0] }
            return WidgetSnapshot.Item(
                id: task.id,
                title: task.displayTitle,
                listName: list?.displayTitle ?? "",
                listIcon: list?.icon ?? "",
                accent: (list?.accent ?? .graphite).rawValue,
                dueDate: task.dueDate,
                includesTime: task.includesTime,
                isCompleted: task.isCompleted,
                isStarred: task.isStarred,
                hasRepeat: task.recurrenceData != nil
            )
        }

        let listSummaries = lists
            .filter { !$0.isSystemInbox && !$0.isArchived }
            .prefix(6)
            .map { list in
                WidgetSnapshot.ListSummary(
                    id: list.id,
                    title: list.displayTitle,
                    icon: list.icon,
                    accent: list.accent.rawValue,
                    openCount: listCounts[list.id]?.open ?? 0,
                    doneCount: listCounts[list.id]?.done ?? 0
                )
            }

        return WidgetSnapshot(
            todayItems: Array(items),
            overdueCount: overdue,
            dueTodayCount: dueToday,
            completedTodayCount: completedToday,
            inboxCount: inbox,
            totalOpenCount: totalOpen,
            lists: Array(listSummaries)
        )
    }
}
