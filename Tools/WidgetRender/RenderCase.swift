//
//  RenderCase.swift
//  Widget render harness
//

import SwiftUI
import WidgetKit

/// One widget picture to draw, in every mode.
///
/// Widget files list theirs under `#if RENDER_<KIND>`, so the harness only
/// ever compiles the kinds it was asked for.
struct RenderCase {
    /// The file name prefix, matching the design crops: "today", "upnext",
    /// "capture", "list", "agenda", "summary", "activity".
    let kind: String
    let family: WidgetFamily
    /// An extra state ("closing", "working", "paused"), or `nil`.
    let state: String?
    let entry: SnapshotEntry
    let draw: (SnapshotEntry, WidgetFamily, WidgetStyle) -> AnyView

    init<V: View>(
        _ kind: String,
        _ family: WidgetFamily,
        state: String? = nil,
        entry: SnapshotEntry = .mockup(),
        @ViewBuilder view: @escaping (SnapshotEntry, WidgetFamily, WidgetStyle) -> V
    ) {
        self.kind = kind
        self.family = family
        self.state = state
        self.entry = entry
        draw = { AnyView(view($0, $1, $2)) }
    }

    /// The same entry in several families.
    static func families<V: View>(
        _ kind: String,
        _ families: [WidgetFamily],
        state: String? = nil,
        entry: SnapshotEntry = .mockup(),
        @ViewBuilder view: @escaping (SnapshotEntry, WidgetFamily, WidgetStyle) -> V
    ) -> [RenderCase] {
        families.map { RenderCase(kind, $0, state: state, entry: entry, view: view) }
    }

    /// "today-medium-closing", before the mode is appended, as the design
    /// crops in /tmp/olw/spec are named. At the measured size the size gains
    /// a "-real" suffix, "today-medium-real-closing", so the design-size file
    /// names still match the crops.
    func name(canvas: RenderCanvas) -> String {
        let size = switch family {
        case .systemSmall: "small"
        case .systemMedium: "medium"
        case .systemLarge: "large"
        default: "xl"
        }
        return [kind, canvas == .measured ? size + "-real" : size, state].compactMap(\.self).joined(separator: "-")
    }
}

/// The sizes every case is drawn at.
enum RenderCanvas: CaseIterable {
    /// The design's, for comparing with its crops.
    case design
    /// The smaller ones macOS actually gives widgets, where fixed columns
    /// squeeze whatever shares the row with them.
    case measured

    func size(for family: WidgetFamily) -> CGSize {
        switch self {
        case .design: WidgetMetrics.size(for: family)
        case .measured: WidgetMetrics.measuredSize(for: family)
        }
    }
}

extension SnapshotEntry {
    /// The sample data at the mockup's "now", 10:40 on Wednesday 23 September 2026.
    static func mockup(work: WidgetSnapshot.Work.State? = nil, pending: [WidgetCommand] = [], list: ListSelection? = nil) -> SnapshotEntry {
        let calendar = RenderCalendar.current
        return .sample(now: WidgetSnapshot.mockupNow(calendar: calendar), work: work, pending: pending, list: list, calendar: calendar)
    }
}

extension WidgetCommand {
    /// A tick on one of the sample tasks ("q4"), issued a moment before the
    /// mockup's "now" and still waiting for the app.
    static func completing(_ key: String) -> WidgetCommand {
        WidgetCommand(action: .complete, taskID: WidgetSnapshot.sampleTaskID(key),
                      occurrenceID: WidgetSnapshot.sampleOccurrenceID(key), issuedAt: WidgetSnapshot.mockupNow(calendar: RenderCalendar.current).addingTimeInterval(-2))
    }
}

/// English names, whatever this Mac's language, so renders compare cleanly
/// with the design.
enum RenderCalendar {
    static var current: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_GB")
        calendar.timeZone = .current
        return calendar
    }
}
