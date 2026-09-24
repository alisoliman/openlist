//
//  Providers.swift
//  OpenlistWidget
//

import AppIntents
import WidgetKit

/// One moment of a widget: the snapshot to draw and the date to draw it at.
struct WidgetEntry: TimelineEntry {
    var date: Date
    /// Nil until the app has published a snapshot this widget can read.
    var snapshot: WidgetSnapshot?
    /// Running work whose heartbeat is older than this is shown paused.
    var heartbeatLimit: Date?
    /// The List widget's configuration; nil picks the first list.
    var listID: UUID?
    var showsCompleted = false

    /// The design's data, at the design's time of day, for the gallery and
    /// the placeholder.
    static func sample(on day: Date = .now) -> WidgetEntry {
        let calendar = Calendar.current
        let moment = calendar.date(bySettingHour: 10, minute: 40, second: 0, of: day) ?? day
        return WidgetEntry(date: moment, snapshot: WidgetSampleData.snapshot(now: moment))
    }
}

enum SnapshotSource {
    /// The published snapshot, with actions still queued for the app laid over it.
    static func current() -> WidgetSnapshot? {
        guard let snapshot = WidgetSnapshotStore.read() else { return nil }
        let pending = WidgetActionQueue.pending().map(\.action)
        guard !pending.isEmpty else { return snapshot }
        return SnapshotOverlay.apply(pending, to: snapshot, calendar: clock(snapshot, at: .now).calendar)
    }

    static func clock(_ snapshot: WidgetSnapshot?, at date: Date) -> WidgetClock {
        WidgetClock(now: date, firstWeekday: snapshot?.firstWeekday ?? 1)
    }
}

/// When each kind needs drawing again without the app's help.
enum WidgetCadence {
    /// Today, List, Summary and Activity: the day rolling over.
    case daily
    /// Quick Add: Inbox ages move by the hour.
    case hourly
    /// Agenda: the now line, every quarter of an hour until midnight.
    case quarterHourly
    /// Up Next: "N min left", its bar and the next block, by the minute.
    case upNext

    func timeline(now: Date, snapshot: WidgetSnapshot?, configure: (inout WidgetEntry) -> Void = { _ in }) -> Timeline<WidgetEntry> {
        let calendar = SnapshotSource.clock(snapshot, at: now).calendar
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
        var dates: [Date] = [now]
        switch self {
        case .daily:
            dates += [midnight, calendar.date(byAdding: .day, value: 1, to: midnight) ?? midnight]
        case .hourly:
            dates += (1...24).map { now.addingTimeInterval(Double($0) * 3600) }
        case .quarterHourly:
            let quarter: TimeInterval = 15 * 60
            var next = Date(timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate / quarter).rounded(.down) * quarter + quarter)
            while next < midnight {
                dates.append(next)
                next = next.addingTimeInterval(quarter)
            }
            dates.append(midnight)
        case .upNext:
            dates += Self.upNextDates(now: now, midnight: midnight, snapshot: snapshot, calendar: calendar)
        }
        let limit = now.addingTimeInterval(-180)
        let entries = dates.map { date -> WidgetEntry in
            var entry = WidgetEntry(date: date, snapshot: snapshot, heartbeatLimit: limit)
            configure(&entry)
            return entry
        }
        return Timeline(entries: entries, policy: .atEnd)
    }

    /// A minute at a time while something is on or coming up today, so the
    /// countdown, the bar and the next block keep moving. A running timer ticks
    /// by itself; its entries stop sooner so a timer the app stopped feeding is
    /// caught within half an hour.
    private static func upNextDates(now: Date, midnight: Date, snapshot: WidgetSnapshot?, calendar: Calendar) -> [Date] {
        guard let snapshot else { return [midnight] }
        let today = snapshot.agenda.first { calendar.isDate($0.day, inSameDayAs: now) }?.items ?? []
        let upcoming = today.contains { $0.kind == .task && !$0.isCompleted && $0.end > now }
        guard snapshot.work != nil || upcoming else { return [midnight] }
        let horizon = snapshot.work?.isRunning == true ? 30 : 90
        let minute = (now.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60
        return (1...horizon).map { Date(timeIntervalSinceReferenceDate: minute + Double($0) * 60) }.filter { $0 <= midnight }
    }
}

/// Today, Up Next, Quick Add, Agenda, Summary and Activity.
struct SnapshotTimelineProvider: TimelineProvider {
    let cadence: WidgetCadence

    func placeholder(in context: Context) -> WidgetEntry { .sample() }

    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        if context.isPreview {
            completion(.sample())
        } else {
            completion(WidgetEntry(date: .now, snapshot: SnapshotSource.current(), heartbeatLimit: Date.now.addingTimeInterval(-180)))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        completion(cadence.timeline(now: .now, snapshot: SnapshotSource.current()))
    }
}

/// The List widget, configured with a list and whether completed tasks show.
struct ListProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry { .sample() }

    func snapshot(for configuration: SelectListIntent, in context: Context) async -> WidgetEntry {
        if context.isPreview { return .sample() }
        var entry = WidgetEntry(date: .now, snapshot: SnapshotSource.current())
        apply(configuration, to: &entry)
        return entry
    }

    func timeline(for configuration: SelectListIntent, in context: Context) async -> Timeline<WidgetEntry> {
        WidgetCadence.daily.timeline(now: .now, snapshot: SnapshotSource.current()) { apply(configuration, to: &$0) }
    }

    private func apply(_ configuration: SelectListIntent, to entry: inout WidgetEntry) {
        entry.listID = configuration.list.flatMap { UUID(uuidString: $0.id) }
        entry.showsCompleted = configuration.showsCompleted
    }
}
