//
//  SnapshotEntry.swift
//  OpenlistWidget
//

import Foundation
import WidgetKit

/// One moment on a widget's timeline.
nonisolated struct SnapshotEntry: TimelineEntry {
    let date: Date
    /// The snapshot as the app published it.
    let snapshot: WidgetSnapshot
    /// Taps the app has not applied yet, oldest first.
    let pending: [WidgetCommand]
    /// `true` when the app has never published a snapshot (or the widget
    /// cannot see it), so there is nothing real to show and views should
    /// invite the user to open Openlist instead.
    let isPlaceholder: Bool
    /// The List widget's configuration; `nil` for every other kind.
    let list: ListSelection?
    /// What views should draw: the snapshot with `pending` and the passage of
    /// time applied. Computed once here rather than in every view.
    let state: WidgetState

    init(
        date: Date,
        snapshot: WidgetSnapshot,
        pending: [WidgetCommand] = [],
        isPlaceholder: Bool = false,
        list: ListSelection? = nil,
        calendar: Calendar = .current
    ) {
        self.date = date
        self.snapshot = snapshot
        self.pending = pending
        self.isPlaceholder = isPlaceholder
        self.list = list
        state = WidgetState(snapshot: snapshot, pending: pending, now: date, calendar: calendar)
    }

    /// The same data at another moment, for timelines that step through the day.
    func at(_ date: Date) -> SnapshotEntry {
        SnapshotEntry(date: date, snapshot: snapshot, pending: pending, isPlaceholder: isPlaceholder, list: list, calendar: state.calendar)
    }

    /// The list the List widget shows: the configured one, or the first real
    /// list when none is chosen or the chosen one has gone.
    var selectedList: WidgetSnapshot.ListSummary? {
        state.snapshot.list(id: list?.listID)
    }
}

/// What the List widget was configured to show.
nonisolated struct ListSelection: Equatable, Sendable {
    var listID: UUID?
    var showsCompleted = false
}

extension WidgetSnapshot {
    /// The Mac's calendar with the first weekday chosen in Openlist, so weeks
    /// in widgets start on the same day as in the app.
    nonisolated func calendar(base: Calendar = .current) -> Calendar {
        var calendar = base
        if (1...7).contains(firstWeekday) { calendar.firstWeekday = firstWeekday }
        return calendar
    }
}
