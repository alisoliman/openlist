//
//  Providers.swift
//  OpenlistWidget
//

import Foundation
import WidgetKit

/// What the extension reads for every timeline: the published snapshot and
/// any taps still waiting for the app.
nonisolated enum WidgetData {
    static func entry(at now: Date, list: ListSelection? = nil) -> SnapshotEntry {
        guard let snapshot = WidgetSnapshotStore.read() else {
            return SnapshotEntry(date: now, snapshot: WidgetSnapshot(), isPlaceholder: true, list: list)
        }
        return SnapshotEntry(date: now, snapshot: snapshot, pending: WidgetCommandQueue.pending(now: now), list: list)
    }

    /// One entry per date over the same data.
    static func timeline(_ entry: SnapshotEntry, dates: [Date], reload: Date) -> Timeline<SnapshotEntry> {
        let entries = entry.isPlaceholder ? [entry] : dates.map(entry.at)
        return Timeline(entries: entries.isEmpty ? [entry] : entries, policy: .after(reload))
    }
}

/// Today, Quick Add, Summary and Activity: the day's data, with extra entries
/// only where a task turns late, an Inbox capture's age changes or a waiting
/// tap expires.
nonisolated struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        .sample(now: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (SnapshotEntry) -> Void) {
        completion(context.isPreview ? .sample(now: .now) : WidgetData.entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<SnapshotEntry>) -> Void) {
        let entry = WidgetData.entry(at: .now)
        let calendar = entry.state.calendar
        let dates = TimelineSchedule.snapshotDates(for: entry.state.snapshot, pending: entry.pending, now: entry.date, calendar: calendar)
        completion(WidgetData.timeline(entry, dates: dates, reload: TimelineSchedule.reload(after: dates, now: entry.date, calendar: calendar)))
    }
}

/// Up Next: minute steps while a block counts down or recording fills the
/// bar. The running clock itself ticks on its own and needs no entries.
nonisolated struct UpNextProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        .sample(now: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (SnapshotEntry) -> Void) {
        completion(context.isPreview ? .sample(now: .now) : WidgetData.entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<SnapshotEntry>) -> Void) {
        let entry = WidgetData.entry(at: .now)
        let calendar = entry.state.calendar
        let dates = TimelineSchedule.upNextDates(for: entry.state.snapshot, pending: entry.pending, now: entry.date, calendar: calendar)
        completion(WidgetData.timeline(entry, dates: dates, reload: TimelineSchedule.upNextReload(after: dates, now: entry.date, calendar: calendar)))
    }
}

/// Agenda: a quarter-hour step until midnight so the now line moves.
nonisolated struct AgendaProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        .sample(now: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (SnapshotEntry) -> Void) {
        completion(context.isPreview ? .sample(now: .now) : WidgetData.entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<SnapshotEntry>) -> Void) {
        let entry = WidgetData.entry(at: .now)
        let calendar = entry.state.calendar
        let dates = TimelineSchedule.agendaDates(for: entry.state.snapshot, pending: entry.pending, now: entry.date, calendar: calendar)
        completion(WidgetData.timeline(entry, dates: dates, reload: TimelineSchedule.reload(after: dates, now: entry.date, calendar: calendar)))
    }
}

/// The List widget, configured with a list and the Show completed switch.
nonisolated struct ListProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        .sample(now: .now, list: ListSelection())
    }

    func snapshot(for configuration: ListWidgetIntent, in context: Context) async -> SnapshotEntry {
        let selection = ListSelection(configuration)
        return context.isPreview ? .sample(now: .now, list: selection) : WidgetData.entry(at: .now, list: selection)
    }

    func timeline(for configuration: ListWidgetIntent, in context: Context) async -> Timeline<SnapshotEntry> {
        let entry = WidgetData.entry(at: .now, list: ListSelection(configuration))
        let calendar = entry.state.calendar
        let dates = TimelineSchedule.snapshotDates(for: entry.state.snapshot, pending: entry.pending, now: entry.date, calendar: calendar)
        return WidgetData.timeline(entry, dates: dates, reload: TimelineSchedule.reload(after: dates, now: entry.date, calendar: calendar))
    }
}
