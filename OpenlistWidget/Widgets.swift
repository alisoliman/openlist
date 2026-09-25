//
//  Widgets.swift
//  OpenlistWidget
//

import AppIntents
import SwiftUI
import WidgetKit

/// Every Openlist widget. The kinds of the three original widgets are kept, so
/// widgets already on a desktop upgrade in place; List reuses Lists'.
enum OpenlistWidgetKind: String, CaseIterable, Sendable {
    case today = "OpenlistToday"
    case upNext = "OpenlistUpNext"
    case capture = "OpenlistCapture"
    case list = "OpenlistLists"
    case agenda = "OpenlistAgenda"
    case summary = "OpenlistSummary"
    case activity = "OpenlistActivity"

    var name: String {
        switch self {
        case .today: "Today"
        case .upNext: "Up Next"
        case .capture: "Quick Add"
        case .list: "List"
        case .agenda: "Agenda"
        case .summary: "Summary"
        case .activity: "Activity"
        }
    }

    var summary: String {
        switch self {
        case .today: "What’s due and overdue. Tick tasks off without opening the app."
        case .upNext: "The block you should be on now, with Start, Pause and Done."
        case .capture: "One click to capture. Shows what’s waiting in Inbox."
        case .list: "Any list you pick, with progress and tickable tasks."
        case .agenda: "Today’s plan around your meetings, or the whole week."
        case .summary: "Due, overdue, Inbox and done, plus this week."
        case .activity: "Your completion streak as a heatmap."
        }
    }

    var families: [WidgetFamily] {
        switch self {
        case .today: [.systemSmall, .systemMedium, .systemLarge]
        case .upNext, .capture, .summary, .activity: [.systemSmall, .systemMedium]
        case .list: [.systemMedium, .systemLarge]
        case .agenda: [.systemLarge, .systemExtraLarge]
        }
    }

    var sizes: [WidgetSize] { families.map(WidgetSize.init) }

    var cadence: WidgetCadence {
        switch self {
        case .today, .list, .summary, .activity: .daily
        case .capture: .inboxAges
        case .agenda: .quarterHourly
        case .upNext: .upNext
        }
    }
}

/// A widget's content at the size it's drawn at, on its own background.
struct OpenlistWidgetContent: View {
    let kind: OpenlistWidgetKind
    let entry: WidgetEntry
    let size: WidgetSize

    var body: some View {
        WidgetPaletteReader { palette in
            content
                .padding(size.padding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .containerBackground(for: .widget) { palette.bg }
                .widgetURL(url)
        }
    }

    private var clock: WidgetClock { SnapshotSource.clock(entry.snapshot, at: entry.date) }

    /// The chosen list, or the first, as for a widget nobody chose one for,
    /// once the chosen one is gone: deleted, archived or merged away.
    private var list: WidgetSnapshot.ListSummary? {
        guard let lists = entry.snapshot?.lists else { return nil }
        return entry.listID.flatMap { id in lists.first { $0.id == id } } ?? lists.first
    }

    @ViewBuilder private var content: some View {
        if let snapshot = entry.snapshot {
            switch kind {
            case .today: TodayWidgetView(model: TodayModel(snapshot, clock: clock), size: size, libraryID: snapshot.libraryID)
            case .upNext:
                UpNextWidgetView(model: UpNextModel(snapshot, clock: clock, heartbeatLimit: entry.heartbeatLimit), size: size, date: entry.date)
            case .capture: CaptureWidgetView(model: CaptureModel(snapshot, clock: clock), size: size)
            case .list:
                if let list {
                    ListWidgetView(model: ListModel(list, showsCompleted: entry.showsCompleted, clock: clock), size: size,
                                   libraryID: snapshot.libraryID)
                } else {
                    NoListsView()
                }
            case .agenda: AgendaWidgetView(model: AgendaModel(snapshot, clock: clock), size: size)
            case .summary: SummaryWidgetView(model: SummaryModel(snapshot, clock: clock), size: size)
            case .activity: ActivityWidgetView(model: ActivityModel(snapshot, clock: clock, weeks: size == .small ? 10 : 21), size: size)
            }
        } else {
            OpenOpenlistView()
        }
    }

    private var url: URL {
        switch kind {
        case .today, .summary: WidgetRoute.today.url
        case .upNext, .agenda: WidgetRoute.calendar.url
        case .activity: WidgetRoute.activity.url
        case .capture: size == .small ? WidgetRoute.capture(listID: nil, forToday: false).url : WidgetRoute.inbox.url
        // "No lists" opens Lists; "Open Openlist", before any snapshot, Today.
        case .list:
            list.map { WidgetRoute.listURL(libraryID: entry.snapshot?.libraryID, listID: $0.id) }
                ?? (entry.snapshot == nil ? WidgetRoute.today.url : WidgetRoute.lists.url)
        }
    }
}

/// Reads the family the system is drawing.
private struct OpenlistWidgetEntryView: View {
    let kind: OpenlistWidgetKind
    let entry: WidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        OpenlistWidgetContent(kind: kind, entry: entry, size: WidgetSize(family))
    }
}

private extension WidgetConfiguration {
    func openlist(_ kind: OpenlistWidgetKind) -> some WidgetConfiguration {
        configurationDisplayName(kind.name)
            .description(kind.summary)
            .supportedFamilies(kind.families)
            // The design pads each widget itself.
            .contentMarginsDisabled()
    }
}

private func staticWidget(_ kind: OpenlistWidgetKind) -> some WidgetConfiguration {
    StaticConfiguration(kind: kind.rawValue, provider: SnapshotTimelineProvider(cadence: kind.cadence)) { entry in
        OpenlistWidgetEntryView(kind: kind, entry: entry)
    }
    .openlist(kind)
}

/// Replaces the original Today widget.
struct TodayWidget: Widget {
    var body: some WidgetConfiguration { staticWidget(.today) }
}

struct UpNextWidget: Widget {
    var body: some WidgetConfiguration { staticWidget(.upNext) }
}

struct CaptureWidget: Widget {
    var body: some WidgetConfiguration { staticWidget(.capture) }
}

/// Replaces Lists: one list, chosen in Edit Widget.
struct ListWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: OpenlistWidgetKind.list.rawValue, intent: SelectListIntent.self, provider: ListProvider()) { entry in
            OpenlistWidgetEntryView(kind: .list, entry: entry)
        }
        .openlist(.list)
    }
}

struct AgendaWidget: Widget {
    var body: some WidgetConfiguration { staticWidget(.agenda) }
}

struct SummaryWidget: Widget {
    var body: some WidgetConfiguration { staticWidget(.summary) }
}

struct ActivityWidget: Widget {
    var body: some WidgetConfiguration { staticWidget(.activity) }
}
