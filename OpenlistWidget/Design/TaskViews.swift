//
//  TaskViews.swift
//  OpenlistWidget
//

import AppIntents
import SwiftUI
import WidgetKit

/// The 15-point checkbox. Tapping it ticks the task off (or reopens it)
/// through `ToggleTaskIntent`, without opening the app.
///
/// A toggle rather than a button, so the system draws it ticked the moment
/// it is tapped, while the intent runs in the app and until the reload after
/// it takes the row away. A tick queued for the app (`TaskCheck.closing`)
/// draws the same.
struct TaskCheckbox: View {
    let item: WidgetSnapshot.Item
    let check: TaskCheck
    private let isLate: Bool
    @Environment(\.widgetStyle) private var style

    init(item: WidgetSnapshot.Item, state: WidgetState) {
        self.item = item
        check = state.check(for: item)
        isLate = item.isOverdue(at: state.now, calendar: state.calendar)
    }

    var body: some View {
        Toggle(isOn: check != .open, intent: ToggleTaskIntent(taskID: item.id, occurrenceID: item.occurrenceID, completed: check == .open)) {
            Text(check == .open ? "Complete \(item.title)" : "Reopen \(item.title)")
        }
        .toggleStyle(TaskCheckStyle(ring: style.checkColor(for: item, isLate: isLate), isCompleted: item.isCompleted, style: style))
    }
}

/// The checkbox's circle: the ring while open, the accent disc a touch larger
/// while closing (ticked, but not yet completed in the snapshot), and the
/// green disc once done.
private struct TaskCheckStyle: ToggleStyle {
    let ring: Color
    /// Completed in the published snapshot.
    let isCompleted: Bool
    let style: WidgetStyle

    func makeBody(configuration: Configuration) -> some View {
        let closing = configuration.isOn && !isCompleted
        ZStack {
            if configuration.isOn {
                // Only the disc is accentable: a tinted checkmark would vanish
                // into the tinted disc behind it.
                Circle()
                    .fill(closing ? style.acc : style.green)
                    .widgetAccentable()
                Image(systemName: "checkmark")
                    .font(.system(size: 7.5, weight: .heavy))
                    .foregroundStyle(style.onAcc)
            } else {
                Circle()
                    .strokeBorder(ring, lineWidth: 1.5)
                    .widgetAccentable()
            }
        }
        .frame(width: 15, height: 15)
        .scaleEffect(closing ? 1.12 : 1)
        .contentShape(Circle())
    }
}

/// A task line: checkbox, title, list and due date. Tapping anywhere but the
/// checkbox opens the task in Openlist.
struct TaskRow: View {
    enum Layout {
        /// Title with the list underneath and the due date trailing.
        case standard
        /// The small family: a two-line title with the due date (or the list)
        /// underneath. Small widgets only support one tap target, so the row
        /// does not link to the task.
        case compact
    }

    let item: WidgetSnapshot.Item
    let state: WidgetState
    /// The list line under the title. Off in the List widget, where every row
    /// shares the header's list.
    var showsList = true
    var layout = Layout.standard
    @Environment(\.widgetStyle) private var style

    init(item: WidgetSnapshot.Item, state: WidgetState, showsList: Bool = true, layout: Layout = .standard) {
        self.item = item
        self.state = state
        self.showsList = showsList
        self.layout = layout
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            TaskCheckbox(item: item, state: state)
                .padding(.top, 1)
            Group {
                switch layout {
                case .standard:
                    AppLink(.task(item.id)) { standardDetails }
                        .accessibilityLabel(accessibilityText)
                case .compact:
                    compactDetails
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(accessibilityText)
                }
            }
            // While a tick's intent runs in the app, the system dims the row
            // beside its circle, until the reload that follows settles it out.
            .invalidatableContent()
        }
        // A tick queued for the app has no intent running, so the row fades
        // itself until the app applies it.
        .opacity(check == .closing ? 0.55 : 1)
    }

    private var standardDetails: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                title.lineLimit(1).textStyle(12, .medium, lineHeight: 1.3)
                if showsList, !item.listName.isEmpty {
                    listLine
                        .foregroundStyle(style.faint)
                        .lineLimit(1)
                        .textStyle(10, .medium, lineHeight: 1.2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if item.isStarred {
                Image(systemName: "star.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(style.amber)
                    .padding(.top, 2)
            }
            if !dueText.isEmpty {
                Text(dueText)
                    .monospacedDigit()
                    .foregroundStyle(dueColor)
                    .fixedSize()
                    .textStyle(10, .medium, lineHeight: 1.3)
                    .padding(.top, 1)
            }
        }
        .contentShape(Rectangle())
    }

    private var compactDetails: some View {
        VStack(alignment: .leading, spacing: 2) {
            title.lineLimit(2).textStyle(11.5, .medium, lineHeight: 1.3)
            if !dueText.isEmpty {
                Text(dueText)
                    .foregroundStyle(dueColor)
                    .lineLimit(1)
                    .textStyle(10, .medium, lineHeight: 1.2)
            } else if showsList, !item.listName.isEmpty {
                listLine
                    .foregroundStyle(style.faint)
                    .lineLimit(1)
                    .textStyle(10, .medium, lineHeight: 1.2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var title: Text {
        Text(item.title)
            .foregroundStyle(check == .open ? style.ink : check == .done ? style.faint : style.sub)
            .strikethrough(check != .open)
    }

    private var check: TaskCheck { state.check(for: item) }
    private var dueText: String { state.dueText(for: item) }
    private var listLine: Text {
        Text(listIcon: item.listIcon, name: item.listName, size: 10, includesIcon: !style.isVibrant)
    }

    /// A row being ticked off keeps its red "3d late" until it settles out.
    private var dueColor: Color {
        if check == .done { return style.faint }
        return item.isOverdue(at: state.now, calendar: state.calendar) ? style.red : style.sub
    }

    private var accessibilityText: String {
        var parts = [item.title]
        if showsList, !item.listName.isEmpty { parts.append(item.listName) }
        if !dueText.isEmpty { parts.append(dueText) }
        if item.isStarred { parts.append("starred") }
        return parts.joined(separator: ", ")
    }
}

extension Text {
    /// A list line, "🗻 Weekend in Kyoto", set at `size`, with the words
    /// `WidgetFormat.listLine` gives. The emoji is drawn as large as the
    /// design draws it at that size, not at Core Text's larger one (`EmojiSize`).
    init(listIcon icon: String, name: String, size: CGFloat, includesIcon: Bool) {
        guard WidgetFormat.listLine(icon: icon, name: name, includesIcon: includesIcon) != name else {
            self.init(verbatim: name)
            return
        }
        let emoji = Text(verbatim: icon).font(.system(size: EmojiSize.points(forDesign: size)))
        self = name.isEmpty ? emoji : Text("\(emoji) \(name)")
    }
}

/// Opens Openlist at `link` when tapped.
///
/// Use this instead of `Link`. `ImageRenderer` cannot draw a `Link` (it
/// renders a placeholder), so the render harness builds with `WIDGET_RENDER`
/// and draws only the label.
struct AppLink<Label: View>: View {
    let link: WidgetLink
    private let label: Label

    init(_ link: WidgetLink, @ViewBuilder label: () -> Label) {
        self.link = link
        self.label = label()
    }

    var body: some View {
        #if WIDGET_RENDER
        label
        #else
        Link(destination: link.url) { label }
        #endif
    }
}
