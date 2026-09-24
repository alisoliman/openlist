//
//  SnapshotOverlay.swift
//  OpenlistWidget
//

import Foundation

/// Shows queued widget actions as done before the app has applied them.
///
/// A tick in the extension queues the action and reloads the widget straight
/// away; the app may not be running to apply it. Laying the queue over the
/// published snapshot lets the row settle out on that reload, and keeps it out
/// until the app publishes the real result and removes the file.
enum SnapshotOverlay {
    static func apply(_ actions: [WidgetAction], to snapshot: WidgetSnapshot, calendar: Calendar = .current) -> WidgetSnapshot {
        var snapshot = snapshot
        for action in actions {
            switch action.kind {
            case .complete: complete(action, in: &snapshot, calendar: calendar)
            case .reopen: reopen(action, in: &snapshot, calendar: calendar)
            // Work only changes in the running app; its buttons invalidate
            // their content until the app publishes.
            case .startWork, .pauseWork, .resumeWork, .finishWork: break
            }
        }
        return snapshot
    }

    private static func matches(_ id: UUID, _ occurrence: UUID?, _ action: WidgetAction) -> Bool {
        id == action.taskID && (action.occurrenceID == nil || occurrence == nil || occurrence == action.occurrenceID)
    }

    private static func complete(_ action: WidgetAction, in snapshot: inout WidgetSnapshot, calendar: Calendar) {
        // Only an open row the snapshot still shows counts, for the occurrence
        // the widget showed: once the app has published the completion, or a
        // repeat has rolled on, the file lingering changes nothing.
        let listed = snapshot.lists.contains { $0.openItems.contains { matches($0.id, $0.occurrenceID, action) } }
        let shown = listed || snapshot.todayItems.contains { matches($0.id, $0.occurrenceID, action) && !$0.isCompleted }
        guard shown else { return }
        let row = snapshot.todayItems.first { matches($0.id, $0.occurrenceID, action) }
            ?? snapshot.lists.lazy.compactMap { $0.openItems.first { matches($0.id, $0.occurrenceID, action) } }.first
        if let due = row?.dueDate { snapshot.countDue(on: due, by: -1, calendar: calendar) }
        snapshot.todayItems.removeAll { matches($0.id, $0.occurrenceID, action) }
        for index in snapshot.lists.indices {
            var item: WidgetSnapshot.Item
            if let carried = snapshot.lists[index].openItems.firstIndex(where: { matches($0.id, $0.occurrenceID, action) }) {
                item = snapshot.lists[index].openItems.remove(at: carried)
            } else if !listed, let row, row.listID == snapshot.lists[index].id {
                // A Today row past the open rows its list carries: the list
                // still counts it done and shows it among its latest.
                item = row
            } else {
                continue
            }
            item.isCompleted = true
            item.completedAt = action.createdAt
            snapshot.lists[index].doneItems.insert(item, at: 0)
            snapshot.lists[index].openCount = max(0, snapshot.lists[index].openCount - 1)
            snapshot.lists[index].doneCount += 1
        }
        if let index = snapshot.inboxItems.firstIndex(where: { $0.id == action.taskID }) {
            snapshot.inboxItems.remove(at: index)
            snapshot.inboxCount = max(0, snapshot.inboxCount - 1)
        }
        for day in snapshot.agenda.indices {
            for index in snapshot.agenda[day].items.indices
            where snapshot.agenda[day].items[index].taskID.map({ matches($0, snapshot.agenda[day].items[index].occurrenceID, action) }) == true {
                snapshot.agenda[day].items[index].isCompleted = true
            }
        }
        if snapshot.work.map({ matches($0.taskID, $0.occurrenceID, action) }) == true {
            snapshot.work = nil
        }
        snapshot.totalOpenCount = max(0, snapshot.totalOpenCount - 1)
        let day = calendar.startOfDay(for: action.createdAt)
        if let counted = snapshot.completedTodayDay, !calendar.isDate(counted, inSameDayAs: day) {
            snapshot.completedTodayCount = 0
        }
        snapshot.completedTodayDay = day
        snapshot.completedTodayCount += 1
    }

    private static func reopen(_ action: WidgetAction, in snapshot: inout WidgetSnapshot, calendar: Calendar) {
        var reopened: WidgetSnapshot.Item?
        for index in snapshot.lists.indices {
            guard let row = snapshot.lists[index].doneItems.firstIndex(where: { matches($0.id, $0.occurrenceID, action) }) else { continue }
            var item = snapshot.lists[index].doneItems.remove(at: row)
            let completedAt = item.completedAt
            item.isCompleted = false
            item.completedAt = nil
            snapshot.lists[index].openItems.append(item)
            snapshot.lists[index].openCount += 1
            snapshot.lists[index].doneCount = max(0, snapshot.lists[index].doneCount - 1)
            if reopened == nil {
                reopened = item
                if let completedAt, let counted = snapshot.completedTodayDay, calendar.isDate(completedAt, inSameDayAs: counted) {
                    snapshot.completedTodayCount = max(0, snapshot.completedTodayCount - 1)
                }
            }
        }
        guard let item = reopened else { return }
        snapshot.totalOpenCount += 1
        if let due = item.dueDate {
            snapshot.countDue(on: due, by: 1, calendar: calendar)
            let tomorrowEnd = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: action.createdAt)) ?? due
            if due < tomorrowEnd { snapshot.todayItems.append(item) }
        }
    }
}
