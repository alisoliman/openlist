//
//  OpenlistiOSWidgetBundle.swift
//  OpenlistiOSWidget
//

import SwiftUI
import WidgetKit

/// The iPhone widget extension (mockup 05). It reads the snapshot the app
/// publishes to the App Group through the Mac widget's providers and model,
/// which it compiles from OpenlistWidget/, and draws the phone's design.
@main
struct OpenlistiOSWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        InboxWidget()
        UpNextWidget()
        WorkLiveActivity()
    }
}

/// Today: the day's progress and what's on (small), the day's tasks to tick
/// off (medium), and a ring of how much is done (Lock Screen).
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.today, provider: TodayPlanProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("Today")
        .description("How much of today is done, and what’s next.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
    }
}

/// Today's timeline: the snapshot's own dates, and each start and end of
/// the day's blocks, for the small size's "next".
nonisolated struct TodayPlanProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        .sample(now: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (SnapshotEntry) -> Void) {
        completion(context.isPreview ? .sample(now: .now) : WidgetData.entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<SnapshotEntry>) -> Void) {
        let entry = WidgetData.entry(at: .now)
        let calendar = entry.state.calendar
        let dates = TimelineSchedule.todayPlanDates(for: entry.state.snapshot, pending: entry.pending, now: entry.date,
                                                    calendar: calendar)
        completion(WidgetData.timeline(entry, dates: dates, reload: TimelineSchedule.reload(after: dates, now: entry.date,
                                                                                           calendar: calendar)))
    }
}

/// Inbox: what's waiting to triage, and Capture.
struct InboxWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.quickAdd, provider: SnapshotProvider()) { entry in
            InboxWidgetView(entry: entry)
        }
        .configurationDisplayName("Inbox")
        .description("What’s waiting to triage, and a quick capture.")
        .supportedFamilies([.systemSmall])
    }
}

/// Up next, on the Lock Screen: what the day holds after the work in hand.
struct UpNextWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.upNext, provider: UpNextProvider()) { entry in
            UpNextWidgetView(entry: entry)
        }
        .configurationDisplayName("Up next")
        .description("The next thing on today’s plan.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
    }
}
