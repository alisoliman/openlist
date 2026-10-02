//
//  OLTaskRow.swift
//  OpenlistiOS
//

import SwiftUI

// MARK: - C7 Checkbox

/// What a task's checkbox shows (`.cb`).
enum OLCheck: Equatable {
    case open
    /// Due on an earlier day: a `danger` ring.
    case late
    /// A `success` fill with a white tick.
    case done
    /// Picked in Select: an `accent` fill.
    case selected
    /// An open task's priority as its ring: high `danger`, medium `amber`,
    /// low `info`. Late wins over priority, as in the widgets.
    case priority(TaskPriority)

    var isFilled: Bool { self == .done || self == .selected }
}

/// A round checkbox: 22 pt with a 1.8 pt ring, or 28 on Task detail, inside
/// a 44 pt target. The tick fills in over 200 ms.
struct OLCheckbox: View {
    let state: OLCheck
    var size: CGFloat = 22
    /// The task's title, for VoiceOver: "Complete Pay the ryokan deposit".
    var title = ""
    let action: () -> Void

    init(_ state: OLCheck, size: CGFloat = 22, title: String = "", action: @escaping () -> Void) {
        self.state = state
        self.size = size
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            OLCheckmark(state: state, size: size)
                .frame(width: max(44, size + 22), height: max(44, size + 22))
                .contentShape(.circle)
        }
        .buttonStyle(OLPressStyle(scale: 0.9))
        .frame(width: size, height: size)
        .accessibilityLabel(state == .done ? "Reopen \(title)" : state == .selected ? "Deselect \(title)" : "Complete \(title)")
        .accessibilityValue(state == .done ? "Completed" : state == .selected ? "Selected" : "Open")
    }
}

/// The checkbox's drawing alone, for rows that aren't buttons (Activity's
/// done rows) and for the checkbox itself.
struct OLCheckmark: View {
    let state: OLCheck
    var size: CGFloat = 22
    @Environment(\.olStyle) private var style

    var body: some View {
        ZStack {
            Circle().fill(fill)
            Circle().strokeBorder(ring, lineWidth: 1.8)
            OLTick()
                .trim(from: 0, to: state.isFilled ? 1 : 0)
                .stroke(state == .selected ? OL.onAccent : .white,
                        style: StrokeStyle(lineWidth: 2.4 * tickSize / 24, lineCap: .round, lineJoin: .round))
                .frame(width: tickSize, height: tickSize)
                .opacity(state.isFilled ? 1 : 0)
        }
        .frame(width: size, height: size)
        .animation(style.animation(OLStyle.checkbox), value: state)
        .accessibilityHidden(true)
    }

    /// 14 of 22, 17 of 28: the design's tick on a 24-unit square.
    private var tickSize: CGFloat { size >= 28 ? size * 17 / 28 : size * 14 / 22 }

    private var fill: Color {
        switch state {
        case .done: OL.success
        case .selected: OL.accent
        default: .clear
        }
    }

    private var ring: Color {
        switch state {
        case .open: OL.lineStrong
        case .late: OL.danger
        case .done: OL.success
        case .selected: OL.accent
        case let .priority(priority):
            switch priority {
            case .high: OL.danger
            case .medium: OL.amber
            case .low: OL.info
            case .none: OL.lineStrong
            }
        }
    }
}

/// The design's tick: `M5 12.5 l4.5 4.5 L19 7.5` on a 24-unit square.
nonisolated struct OLTick: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale) }
        var path = Path()
        path.move(to: point(5, 12.5))
        path.addLine(to: point(9.5, 17))
        path.addLine(to: point(19, 7.5))
        return path
    }
}

// MARK: - C8 Trailing meta

/// The one value a row shows at its end (`.tr`): "3d late", "11:30", "Sat",
/// a star, "1 of 3", "2h".
struct OLTrailing: Equatable {
    enum Tone: Equatable {
        case muted
        /// Due today, or a time today: `accentText`.
        case due
        /// Late: `danger`.
        case late
        /// A star: `today`.
        case star
        /// When a task was done, on an earlier day: `successText`.
        case done
    }

    var text: String?
    var symbol: String?
    var tone: Tone = .muted
    /// Read instead of the text: "Repeats every Wednesday", "Starred".
    var accessibilityLabel: String?

    static func text(_ text: String, tone: Tone = .muted) -> OLTrailing { OLTrailing(text: text, tone: tone) }
    static let star = OLTrailing(symbol: "star.fill", tone: .star, accessibilityLabel: "Starred")
    static func repeats(_ label: String, text: String? = nil, tone: Tone = .muted) -> OLTrailing {
        OLTrailing(text: text, symbol: "repeat", tone: tone, accessibilityLabel: text.map { "\(label), \($0)" } ?? label)
    }

    /// A due date as `CompactText` words it: late in `danger`, today in the
    /// accent, later days muted (the Mac's rule).
    static func due(_ due: CompactText.Due, repeats: String? = nil) -> OLTrailing {
        let tone: Tone = switch due.tone {
        case .late: .late
        case .today: .due
        case .upcoming: .muted
        }
        if let repeats { return .repeats(repeats, text: due.text, tone: tone) }
        return OLTrailing(text: due.text, tone: tone)
    }
}

struct OLTrailingView: View {
    let trailing: OLTrailing

    init(_ trailing: OLTrailing) { self.trailing = trailing }

    var body: some View {
        HStack(spacing: 4) {
            if let symbol = trailing.symbol {
                // A star alone fills the design's 16 pt box (a glyph of about
                // 11 pt, which SF draws from a 10 pt star); a repeat alone 15;
                // beside a date, 13.
                if trailing.tone == .star && trailing.text == nil {
                    Image(systemName: symbol)
                        .font(.system(size: 10, weight: .medium))
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: trailing.text == nil ? 15 : 13, weight: .medium))
                }
            }
            if let text = trailing.text { Text(text) }
        }
        .font(OLFont.trailing)
        .foregroundStyle(color)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(trailing.accessibilityLabel ?? trailing.text ?? "")
    }

    private var color: Color {
        switch trailing.tone {
        case .muted: OL.muted
        case .due: OL.accentText
        case .late: OL.danger
        case .star: OL.today
        case .done: OL.successText
        }
    }
}

// MARK: - C6 Task row

/// A task in a card (`.li`): checkbox, title up to two lines, one trailing
/// value. 52 pt at least, 16 pt sides, 14 pt between. A subtask (`depth` 1)
/// sits 36 pt in. With a subtitle (`.two`) it's 62 pt, the subtitle 13/18.
///
/// The checkbox and the title are separate targets: the checkbox acts, the
/// rest of the row opens the task.
struct OLTaskRow: View {
    let title: String
    var state: OLCheck = .open
    var depth = 0
    var subtitle: String?
    var subtitleIcon: String?
    var subtitleAccent: Color = OL.muted
    var trailing: OLTrailing?
    /// Draws the hairline above, from the checkbox's right edge.
    var separator: OLSeparator = .none
    /// Picked in Select: the `accentSoft` row.
    var isHighlighted = false
    var onToggle: () -> Void = {}
    var onOpen: (() -> Void)?

    @ScaledMetric(relativeTo: .callout) private var minHeight: CGFloat = 52
    @ScaledMetric(relativeTo: .callout) private var twoLineHeight: CGFloat = 62
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 14) {
            OLCheckbox(state, title: title, action: onToggle)
            content
        }
        .padding(.vertical, subtitle == nil && trailing == nil ? 13 : 11)
        .padding(.leading, 16 + (depth > 0 ? 36 : 0))
        .padding(.trailing, 16)
        .frame(maxWidth: .infinity, minHeight: subtitle == nil && trailing == nil ? minHeight : twoLineHeight, alignment: .leading)
        .background(isHighlighted ? OL.accentSoft : .clear)
        .overlay(alignment: .top) { OLSeparatorLine(separator: separator) }
    }

    @ViewBuilder private var content: some View {
        let label = VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(OLFont.rowTitle)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .strikethrough(state == .done, color: OL.muted)
                .foregroundStyle(state == .done ? OL.muted : OL.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            if subtitle != nil || trailing != nil {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 3) {
                            sourceLabel.fixedSize(horizontal: false, vertical: true)
                            if let trailing { OLTrailingView(trailing) }
                        }
                    } else {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 6) {
                                sourceLabel.lineLimit(1)
                                if let trailing { OLTrailingView(trailing) }
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                sourceLabel.lineLimit(2)
                                if let trailing { OLTrailingView(trailing) }
                            }
                        }
                    }
                }
                .font(OLFont.meta)
                .foregroundStyle(OL.muted)
            }
        }
        .contentShape(.rect)
        if let onOpen {
            Button(action: onOpen) { label }
                .buttonStyle(OLRowPressStyle())
                .accessibilityLabel(title)
                .accessibilityValue([subtitle, trailing.map { $0.accessibilityLabel ?? $0.text ?? "" }]
                    .compactMap(\.self).filter { !$0.isEmpty }.joined(separator: ", "))
                .accessibilityHint("Opens the task")
        } else {
            label.accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder private var sourceLabel: some View {
        if let subtitle {
            HStack(spacing: 4) {
                if let subtitleIcon {
                    OLListGlyph(icon: subtitleIcon, accent: subtitleAccent, size: 13)
                }
                Text(subtitle)
            }
        }
    }
}

/// The hairline between rows in a card: from `inset`, to the card's edge.
enum OLSeparator: Equatable {
    case none
    /// After a task row's checkbox: 52, or 88 beside a subtask.
    case task(nested: Bool)
    /// A plain card's rows (Recent changes, Trash): 16.
    case plain
    /// A settings row, after its tile: 58.
    case settings
    case inset(CGFloat)

    var inset: CGFloat? {
        switch self {
        case .none: nil
        case let .task(nested): nested ? 88 : 52
        case .plain: 16
        case .settings: 58
        case let .inset(value): value
        }
    }

    /// Between a row at `depth` and the one above it at `previous`, as
    /// `.li.nest + .li` and `.li + .li.nest` set it.
    static func task(depth: Int, previousDepth: Int?) -> OLSeparator {
        guard let previousDepth else { return .none }
        return .task(nested: depth > 0 || previousDepth > 0)
    }
}

struct OLSeparatorLine: View {
    let separator: OLSeparator

    var body: some View {
        if let inset = separator.inset {
            Rectangle()
                .fill(OL.line)
                .frame(height: 1)
                .padding(.leading, inset)
                .accessibilityHidden(true)
        }
    }
}

/// A row's press: it dims, and doesn't shrink.
struct OLRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Rows in a card, each separated from the one above as the design draws it.
struct OLCardRows<Item: Identifiable, Row: View>: View {
    let items: [Item]
    @ViewBuilder var row: (Item, _ separator: OLSeparator) -> Row
    var depth: (Item) -> Int = { _ in 0 }
    /// Builds only the rows on screen, for cards that can hold every open
    /// task (Lists' Tasks view, Find, Select). A screen of short cards, as
    /// Today's, stays eager, so its first layout is exact and the page opens
    /// at its top.
    var lazy = false

    init(_ items: [Item], lazy: Bool = false, depth: @escaping (Item) -> Int = { _ in 0 },
         @ViewBuilder row: @escaping (Item, _ separator: OLSeparator) -> Row) {
        self.items = items
        self.lazy = lazy
        self.depth = depth
        self.row = row
    }

    var body: some View {
        Group {
            if lazy {
                LazyVStack(spacing: 0) { rows }
            } else {
                VStack(spacing: 0) { rows }
            }
        }
        .olCard()
    }

    private var rows: some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            row(item, .task(depth: depth(item), previousDepth: index > 0 ? depth(items[index - 1]) : nil))
        }
    }
}
