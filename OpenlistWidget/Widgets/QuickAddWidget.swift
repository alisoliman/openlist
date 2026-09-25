//
//  QuickAddWidget.swift
//  OpenlistWidget
//

import Foundation
import SwiftUI
import WidgetKit

/// One click to capture, and what is waiting in Inbox.
struct QuickAddWidget: Widget {
    static let kind = WidgetKind.quickAdd

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            WidgetEntryView(entry: entry) { family, style in
                QuickAddWidgetView(entry: entry, family: family, style: style)
            }
            // Widgets cannot hold a text field; the whole widget opens Quick Add.
            .widgetURL(WidgetLink.capture(listID: nil).url)
        }
        .configurationDisplayName("Quick Add")
        .description("One click to capture. Shows what’s waiting in Inbox.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

/// Small is the capture button alone, a single tap target. Medium puts the
/// Inbox beside it, with its own links to Inbox, triage and each capture.
struct QuickAddWidgetView: View {
    let entry: SnapshotEntry
    let family: WidgetFamily
    let style: WidgetStyle

    /// Rows the medium family fits under the Inbox header.
    private static let inboxRows = 4
    private static let hint: LocalizedStringKey = "Type it, Openlist sorts dates and labels"

    var body: some View {
        switch family {
        case .systemSmall:
            CapturePanel(detail: smallDetail, detailLines: 2)
                .accessibilityElement(children: .combine)
        default:
            HStack(alignment: .top, spacing: 14) {
                AppLink(.capture(listID: nil)) {
                    // SF sets the hint wider than the design's face, so it may
                    // need a third line in the narrow column.
                    CapturePanel(detail: Text(Self.hint), detailLines: 3)
                        .contentShape(Rectangle())
                }
                .frame(width: 118)
                .accessibilityLabel("New task")
                .accessibilityHint("Opens Quick Add")
                HStack(spacing: 0) {
                    Hairline(.vertical)
                    inbox.padding(.leading, 14)
                }
            }
        }
    }

    /// What is waiting in Inbox, or the hint when there is no snapshot to count.
    private var smallDetail: Text {
        let count = entry.state.snapshot.inboxCount
        if entry.isPlaceholder { return Text(Self.hint) }
        return count == 0 ? Text("Inbox zero") : Text("\(count) waiting in Inbox")
    }

    @ViewBuilder
    private var inbox: some View {
        let snapshot = entry.state.snapshot
        VStack(alignment: .leading, spacing: 9) {
            InboxHeader(count: entry.isPlaceholder ? 0 : snapshot.inboxCount)
            if entry.isPlaceholder {
                OpenAppPrompt()
            } else if snapshot.inboxCount == 0 {
                WidgetEmptyState(systemImage: "checkmark.circle.fill", title: "Inbox zero", message: "Nothing waiting to triage")
            } else {
                ForEach(snapshot.inboxItems.prefix(Self.inboxRows)) { item in
                    InboxRow(item: item, state: entry.state)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The accent "+" tile over "New task" and a line of detail: the whole small
/// widget, and the medium one's left column.
private struct CapturePanel: View {
    let detail: Text
    let detailLines: Int
    @Environment(\.widgetStyle) private var style

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CaptureTile()
            Spacer(minLength: 0)
            Text("New task")
                .foregroundStyle(style.ink)
                .lineLimit(1)
                .textStyle(14, .semibold, lineHeight: 1.2)
            detail
                .foregroundStyle(style.sub)
                .contentTransition(.numericText())
                .lineLimit(detailLines)
                .fixedSize(horizontal: false, vertical: true)
                .textStyle(11, .medium, lineHeight: 1.35)
                .padding(.top, 3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The 46-point accent tile with its soft glow.
private struct CaptureTile: View {
    @Environment(\.widgetStyle) private var style

    var body: some View {
        RoundedRectangle(cornerRadius: 15, style: .continuous)
            .fill(style.acc)
            // Only the tile is accentable: a tinted "+" would vanish into it.
            .widgetAccentable()
            .shadow(color: style.accShadow, radius: 9, y: 8)
            .overlay {
                Image(systemName: "plus")
                    .font(.system(size: 17.5, weight: .semibold))
                    .foregroundStyle(style.onAcc)
            }
            .frame(width: 46, height: 46)
            .accessibilityHidden(true)
    }
}

/// The tray, "Inbox" and its count, which open the Inbox, and the Triage chip.
private struct InboxHeader: View {
    let count: Int
    @Environment(\.widgetStyle) private var style

    var body: some View {
        HStack(spacing: 6) {
            AppLink(.inbox) {
                HStack(spacing: 6) {
                    Image(systemName: "tray.fill")
                        .font(.system(size: 9.5))
                        .foregroundStyle(style.blue)
                        .frame(width: 13, height: 13)
                    Text("Inbox")
                        .foregroundStyle(style.ink)
                        .lineLimit(1)
                        .textStyle(12, .bold, lineHeight: 1)
                    if count > 0 {
                        Text(count, format: .number)
                            .foregroundStyle(style.sub)
                            .contentTransition(.numericText())
                            .textStyle(11, .medium, lineHeight: 1)
                    }
                }
            }
            .accessibilityLabel(count > 0 ? Text("Inbox, \(count) waiting") : Text("Inbox"))
            Spacer(minLength: 0)
            // Nothing to triage, so no way into it.
            if count > 0 {
                AppLink(.triage) {
                    Text("Triage")
                        .foregroundStyle(style.blue)
                        .lineLimit(1)
                        .textStyle(10.5, .semibold, lineHeight: 1)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 8)
                        .background(style.blueChip, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .accessibilityLabel("Triage Inbox")
            }
        }
        // The chip's height, so the rows below never move when it hides.
        .frame(minHeight: 20.5)
    }
}

/// One capture: a quiet dot, the title and how long it has waited. Opens the
/// capture in the Inbox.
private struct InboxRow: View {
    let item: WidgetSnapshot.InboxItem
    let state: WidgetState
    @Environment(\.widgetStyle) private var style

    var body: some View {
        AppLink(.task(item.id)) {
            HStack(spacing: 8) {
                Circle()
                    .fill(style.faint)
                    .frame(width: 5, height: 5)
                Text(item.title)
                    .foregroundStyle(style.ink)
                    .lineLimit(1)
                    .textStyle(11.5, .medium, lineHeight: 1.3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(WidgetFormat.age(of: item.createdAt, now: state.now))
                    .foregroundStyle(style.faint)
                    .fixedSize()
                    .textStyle(10, .medium, lineHeight: 1)
            }
            .contentShape(Rectangle())
        }
        .accessibilityLabel("\(item.title), captured \(spokenAge)")
    }

    /// "2 hours ago": the row's "2h" is too terse to read aloud.
    private var spokenAge: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.calendar = state.calendar
        formatter.locale = state.calendar.locale ?? .current
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: item.createdAt, relativeTo: state.now)
    }
}

#if RENDER_QUICKADD
extension QuickAddWidget {
    static var renderCases: [RenderCase] {
        let empty: SnapshotEntry = {
            let full = SnapshotEntry.mockup()
            var snapshot = full.snapshot
            snapshot.inboxItems = []
            snapshot.inboxCount = 0
            return SnapshotEntry(date: full.date, snapshot: snapshot, calendar: full.state.calendar)
        }()
        let placeholder = SnapshotEntry(date: SnapshotEntry.mockup().date, snapshot: WidgetSnapshot(), isPlaceholder: true,
                                        calendar: RenderCalendar.current)
        return RenderCase.families("capture", [.systemSmall, .systemMedium]) { entry, family, style in
            QuickAddWidgetView(entry: entry, family: family, style: style)
        }
        + RenderCase.families("capture", [.systemSmall, .systemMedium], state: "empty", entry: empty) { entry, family, style in
            QuickAddWidgetView(entry: entry, family: family, style: style)
        }
        + RenderCase.families("capture", [.systemSmall, .systemMedium], state: "placeholder", entry: placeholder) { entry, family, style in
            QuickAddWidgetView(entry: entry, family: family, style: style)
        }
    }
}
#endif
