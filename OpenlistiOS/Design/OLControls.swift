//
//  OLControls.swift
//  OpenlistiOS
//

import SwiftUI

// MARK: - C12 Chips

/// A capsule chip (`.chip`): 36 high, 15/20 medium on `sunken`; `small` 30
/// and 13 pt. `on` is the picked one, in the accent; `ink` inverts.
struct OLChip: View {
    enum Style: Equatable {
        case plain
        case on
        case ink
        /// Inside a search field: 28 high on `surface`.
        case token
    }

    let label: String
    var symbol: String?
    /// A leading emoji or list glyph: a destination's "📥 Inbox".
    var glyph: String?
    var style: Style = .plain
    var small = false
    /// The text's colour when not `on`: a parsed date in `accentText`, a
    /// label in `teal`.
    var tint: Color?

    init(_ label: String, symbol: String? = nil, glyph: String? = nil, style: Style = .plain,
         small: Bool = false, tint: Color? = nil) {
        self.label = label
        self.symbol = symbol
        self.glyph = glyph
        self.style = style
        self.small = small
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 6) {
            if let glyph { Text(glyph).font(.system(size: small ? 14 : 17)) }
            if let symbol { Image(systemName: symbol).font(.system(size: small ? 14 : 17, weight: .medium)) }
            if !label.isEmpty { Text(label) }
        }
        .font(small || style == .token ? OLFont.chipSmall : OLFont.chip)
        .foregroundStyle(foreground)
        .lineLimit(1)
        .padding(.horizontal, label.isEmpty ? 0 : small || style == .token ? 12 : 14)
        .frame(minWidth: label.isEmpty ? height : nil, minHeight: height)
        .background(background, in: .capsule)
        .accessibilityAddTraits(style == .on ? .isSelected : [])
    }

    private var height: CGFloat {
        style == .token ? 28 : small ? 30 : 36
    }

    private var foreground: Color {
        switch style {
        case .on: OL.onAccent
        case .ink: OL.canvas
        case .plain, .token: tint ?? OL.ink
        }
    }

    private var background: Color {
        switch style {
        case .plain: OL.sunken
        case .on: OL.accent
        case .ink: OL.ink
        case .token: OL.surface
        }
    }
}

/// A chip that's a button: a destination, a filter, a triage choice.
struct OLChipButton: View {
    let chip: OLChip
    let action: () -> Void

    init(_ chip: OLChip, action: @escaping () -> Void) {
        self.chip = chip
        self.action = action
    }

    var body: some View {
        Button(action: action) { chip }
            .buttonStyle(OLPressStyle(scale: 0.96))
            .olFeedback(.selection, trigger: chip.style == .on)
    }
}

/// Chips that wrap onto more lines (`.chips`), 8 pt apart.
nonisolated struct OLFlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal: proposal, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(proposal: ProposedViewSize(width: bounds.width, height: nil), subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let limit = proposal.width ?? .infinity
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if needed > limit, !row.indices.isEmpty {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

/// Chips in one line that scroll sideways, edge to edge past the gutters:
/// the capture sheet's destinations.
struct OLChipScroller<Content: View>: View {
    @ViewBuilder var content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) { content }
                .padding(.horizontal, OLMetrics.gutter)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -OLMetrics.gutter)
    }
}

// MARK: - C13 Segmented

/// A segmented control (`.seg`): a `sunken` track, 32 pt segments, the
/// picked one on `surface`.
struct OLSegmented<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value
    @Environment(\.olStyle) private var style
    @Namespace private var namespace

    init(_ options: [(value: Value, title: String)], selection: Binding<Value>) {
        self.options = options
        _selection = selection
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let isOn = option.value == selection
                Button {
                    withAnimation(style.animation(.snappy(duration: 0.22))) { selection = option.value }
                } label: {
                    Text(option.title)
                        .font(OLFont.segment)
                        .foregroundStyle(isOn ? OL.ink : OL.muted)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background {
                            if isOn {
                                Capsule(style: .continuous).fill(OL.surface)
                                    .shadow(color: OL.Pair.warmShadow.resolved(.light).opacity(0.12), radius: 1.5, y: 1)
                                    .matchedGeometryEffect(id: "segment", in: namespace)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(3)
        .background(OL.sunken, in: .capsule)
        .olFeedback(.selection, trigger: selection)
    }
}

// MARK: - C14 Toggle

extension View {
    /// The design's switch is the system's, on in `success`.
    func olToggle() -> some View { tint(OL.success) }
}

// MARK: - C15 Stepper

/// The estimate stepper: − and + in 36 pt `sunken` circles around a 68 pt
/// value ("90 min"). VoiceOver adjusts it by swiping.
struct OLStepper: View {
    @Binding var value: Int
    var range: ClosedRange<Int> = 5...480
    var step = 5
    var label = "Estimate"
    var format: (Int) -> String = { "\($0) min" }

    var body: some View {
        HStack(spacing: 2) {
            button("minus", enabled: value > range.lowerBound) { change(-step) }
            Text(format(value))
                .font(OLFont.rowTitle.weight(.semibold).monospacedDigit())
                .frame(minWidth: 68)
                .contentTransition(.numericText(value: Double(value)))
            button("plus", enabled: value < range.upperBound) { change(step) }
        }
        .olFeedback(.selection, trigger: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(format(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: change(step)
            case .decrement: change(-step)
            @unknown default: break
            }
        }
    }

    private func change(_ delta: Int) {
        value = min(range.upperBound, max(range.lowerBound, value + delta))
    }

    private func button(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(OL.ink)
                .frame(width: 36, height: 36)
                .background(OL.sunken, in: .circle)
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .buttonStyle(OLPressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

// MARK: - C17 Progress

/// A 4 pt progress bar (`.prog`): `sunken` track, `accent` fill that turns
/// `success` when full. The fill eases over 560 ms.
struct OLProgressBar: View {
    let value: Double
    var tint: Color = OL.accent
    var track: Color = OL.sunken
    var height: CGFloat = 4
    var turnsGreenWhenFull = true
    @Environment(\.olStyle) private var style

    var body: some View {
        let fraction = min(1, max(0, value.isFinite ? value : 0))
        Capsule(style: .continuous)
            .fill(track)
            .frame(height: height)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule(style: .continuous)
                        .fill(fraction >= 1 && turnsGreenWhenFull ? OL.success : tint)
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .clipShape(.capsule)
            .animation(style.animation(OLStyle.progress), value: fraction)
            .accessibilityElement()
            .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
    }
}
