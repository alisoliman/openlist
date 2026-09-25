//
//  ListWidget.swift
//  OpenlistWidget
//

import SwiftUI
import WidgetKit

/// Any list the user picks, with its progress and tickable tasks.
struct ListWidget: Widget {
    static let kind = WidgetKind.lists

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: ListWidgetIntent.self, provider: ListProvider()) { entry in
            WidgetEntryView(entry: entry) { family, style in
                ListWidgetView(entry: entry, family: family, style: style)
            }
            .widgetURL((entry.selectedList.map { WidgetLink.list($0.id) } ?? .today).url)
        }
        .configurationDisplayName("List")
        .description("Any list you pick, with progress and tickable tasks.")
        .supportedFamilies([.systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

/// The configured list's header and progress, then its open tasks (and its
/// completed ones, when the widget is set to show them). Large adds a footer
/// for adding to the list.
struct ListWidgetView: View {
    let entry: SnapshotEntry
    let family: WidgetFamily
    let style: WidgetStyle

    var body: some View {
        if entry.isPlaceholder {
            OpenAppPrompt()
        } else if let list = entry.selectedList {
            let isLarge = family == .systemLarge
            let rows = ListRows(list: list, state: entry.state, showsCompleted: entry.list?.showsCompleted ?? false, isLarge: isLarge)
            VStack(alignment: .leading, spacing: 0) {
                ListHeader(list: list)
                if rows.visible.isEmpty {
                    ListEmptyState(list: list)
                } else {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(rows.visible, id: \.occurrenceID) { item in
                            TaskRow(item: item, state: entry.state, showsList: isLarge)
                        }
                        if rows.hiddenCount > 0 {
                            MoreLabel(count: rows.hiddenCount)
                        }
                    }
                    .padding(.top, 13)
                }
                if isLarge {
                    Spacer(minLength: 0)
                    ListFooter(list: list)
                }
            }
        } else {
            // Only reachable with a snapshot that has no lists at all, not
            // even the Inbox.
            WidgetEmptyState(systemImage: "checklist", title: "No lists yet", message: "Lists you make in Openlist show up here.", tint: style.acc)
        }
    }
}

/// Which rows fit, and how many of the list's tasks that leaves out.
private struct ListRows {
    let visible: [WidgetSnapshot.Item]
    /// Open tasks not drawn, plus completed ones when they are shown. Counted
    /// against the list's totals rather than the rows, because the snapshot
    /// carries only the first few of each.
    let hiddenCount: Int

    init(list: WidgetSnapshot.ListSummary, state: WidgetState, showsCompleted: Bool, isLarge: Bool) {
        // A row ticked off in the widget stays among the open rows until the
        // next reload, so it settles out where it was tapped.
        let rows = list.openItems + (showsCompleted ? list.doneItems : [])
        func hidden(_ visible: ArraySlice<WidgetSnapshot.Item>) -> Int {
            let shownOpen = visible.count { state.check(for: $0) == .open }
            // Ticked rows already count as done in the overlaid totals.
            let shownDone = visible.count - shownOpen
            return max(0, list.openCount - shownOpen) + (showsCompleted ? max(0, list.doneCount - shownDone) : 0)
        }
        // Large fits six two-line rows and the label above its footer.
        // Medium fits four single-line rows, or three and the label.
        var visible = rows.prefix(isLarge ? 6 : 4)
        if !isLarge, hidden(visible) > 0 { visible = rows.prefix(3) }
        self.visible = Array(visible)
        hiddenCount = hidden(visible)
    }
}

/// The list's glyph, name and open count over a bar of its progress.
private struct ListHeader: View {
    let list: WidgetSnapshot.ListSummary
    @Environment(\.widgetStyle) private var style

    var body: some View {
        HStack(spacing: 10) {
            ListGlyph(icon: list.icon, accentHex: list.accentHex)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(list.title)
                        .foregroundStyle(style.ink)
                        .lineLimit(1)
                        .textStyle(13, .bold, lineHeight: 1.1)
                    Spacer(minLength: 0)
                    Text("\(list.openCount) open")
                        .monospacedDigit()
                        .foregroundStyle(style.sub)
                        .contentTransition(.numericText(value: Double(list.openCount)))
                        .invalidatableContent()
                        .fixedSize()
                        .textStyle(10.5, .medium, lineHeight: 1)
                }
                ProgressLine(fraction: progress, color: style.listColor(list.accentHex))
                    .invalidatableContent()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel(list.title)
        .accessibilityValue("\(list.openCount) open, \(list.doneCount) done")
    }

    private var progress: Double {
        let total = list.openCount + list.doneCount
        return total > 0 ? Double(list.doneCount) / Double(total) : 0
    }
}

/// Large only: the chip that opens Quick Add filing into this list, and the
/// done count.
private struct ListFooter: View {
    let list: WidgetSnapshot.ListSummary
    @Environment(\.widgetStyle) private var style

    var body: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: 8) {
                // The app has no short names for lists, so the chip names the
                // whole list and truncates a long one.
                ChipLink("Add to \(list.title)", link: .capture(listID: list.id))
                Spacer(minLength: 0)
                // "0 done" says nothing the empty bar doesn't.
                if list.doneCount > 0 {
                    Text("\(list.doneCount) done")
                        .monospacedDigit()
                        .foregroundStyle(style.sub)
                        .contentTransition(.numericText(value: Double(list.doneCount)))
                        .invalidatableContent()
                        .fixedSize()
                        .textStyle(10.5, .medium, lineHeight: 1)
                }
            }
            .padding(.top, 9)
        }
    }
}

/// Nothing left to show: a small celebration once everything is ticked off,
/// or a nudge for a list with no tasks yet.
private struct ListEmptyState: View {
    let list: WidgetSnapshot.ListSummary
    @Environment(\.widgetStyle) private var style

    var body: some View {
        Group {
            if list.doneCount > 0 {
                WidgetEmptyState(systemImage: "checkmark.circle.fill", title: "All done", message: "Nothing left on this list.")
            } else {
                WidgetEmptyState(systemImage: "checklist", title: "No tasks yet", message: "Tasks you add to this list show up here.",
                                 tint: style.listColor(list.accentHex))
            }
        }
        .padding(.top, 8)
    }
}

#if RENDER_LIST
extension ListWidget {
    static var renderCases: [RenderCase] {
        let kyoto = ListSelection(listID: WidgetSnapshot.sampleListID("kyoto"))
        let families: [WidgetFamily] = [.systemMedium, .systemLarge]
        let view = { (entry: SnapshotEntry, family: WidgetFamily, style: WidgetStyle) in
            ListWidgetView(entry: entry, family: family, style: style)
        }
        return RenderCase.families("list", families, entry: .mockup(list: kyoto), view: view)
            + RenderCase.families("list", families, state: "closing", entry: .mockup(pending: [.completing("k3")], list: kyoto), view: view)
            + RenderCase.families("list", families, state: "completed",
                                  entry: .mockup(list: ListSelection(listID: kyoto.listID, showsCompleted: true)), view: view)
            + RenderCase.families("list", families, state: "q3",
                                  entry: .mockup(list: ListSelection(listID: WidgetSnapshot.sampleListID("q3"))), view: view)
            + RenderCase.families("list", families, state: "alldone", entry: .editingKyoto { list in
                list.openItems = []
                list.openCount = 0
            }, view: view)
            + RenderCase.families("list", families, state: "empty", entry: .editingKyoto { list in
                (list.openItems, list.doneItems) = ([], [])
                (list.openCount, list.doneCount) = (0, 0)
            }, view: view)
            // A medium-priority task wears the app's amber ring, not Today's orange.
            + RenderCase.families("list", families, state: "priority", entry: .editingKyoto { list in
                list.openItems[1].priority = 2
            }, view: view)
            + RenderCase.families("list", families, state: "long", entry: .editingKyoto { list in
                list.title = "Weekend in Kyoto, Nara and the Kumano Kodo trail"
                list.openItems[1].title = "Ask Mika to water the planters and take in the post while we are away"
            }, view: view)
    }
}

private extension SnapshotEntry {
    /// The mockup showing Kyoto after `edit`.
    static func editingKyoto(_ edit: (inout WidgetSnapshot.ListSummary) -> Void) -> SnapshotEntry {
        let calendar = RenderCalendar.current
        let now = WidgetSnapshot.mockupNow(calendar: calendar)
        let id = WidgetSnapshot.sampleListID("kyoto")
        var snapshot = WidgetSnapshot.sample(now: now, calendar: calendar)
        if let index = snapshot.lists.firstIndex(where: { $0.id == id }) {
            edit(&snapshot.lists[index])
        }
        return SnapshotEntry(date: now, snapshot: snapshot, list: ListSelection(listID: id), calendar: calendar)
    }
}
#endif
