//
//  TaskViews.swift
//  OpenlistWidget
//

import AppIntents
import SwiftUI
import WidgetKit

/// The 15-point checkbox. Tapping it ticks the task off (or reopens it)
/// through `ToggleTaskIntent`, without opening the app.
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
        Button(intent: ToggleTaskIntent(taskID: item.id, occurrenceID: item.occurrenceID, completed: check == .open)) {
            mark
        }
        .buttonStyle(.plain)
        .accessibilityLabel(check == .open ? "Complete \(item.title)" : "Reopen \(item.title)")
    }

    private var mark: some View {
        ZStack {
            switch check {
            case .open:
                Circle()
                    .strokeBorder(style.checkColor(for: item, isLate: isLate), lineWidth: 1.5)
                    .widgetAccentable()
            case .closing, .done:
                // Only the disc is accentable: a tinted checkmark would vanish
                // into the tinted disc behind it.
                Circle()
                    .fill(check == .closing ? style.acc : style.green)
                    .widgetAccentable()
                Image(systemName: "checkmark")
                    .font(.system(size: 7.5, weight: .heavy))
                    .foregroundStyle(style.onAcc)
            }
        }
        .frame(width: 15, height: 15)
        .scaleEffect(check == .closing ? 1.12 : 1)
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
        .opacity(check == .closing ? 0.55 : 1)
    }

    private var standardDetails: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                title.lineLimit(1).textStyle(12, .medium, lineHeight: 1.3)
                if showsList, !item.listName.isEmpty {
                    Text(listLine)
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
                Text(listLine)
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
    private var listLine: String {
        WidgetFormat.listLine(icon: item.listIcon, name: item.listName, includesIcon: !style.isVibrant)
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
