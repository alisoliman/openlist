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
    /// One of the mockups' own glyphs, in place of `symbol`.
    var icon: OLIcon?
    /// A leading emoji or list glyph: a destination's "📥 Inbox".
    var glyph: String?
    var style: Style = .plain
    var small = false
    /// The text's colour when not `on`: a parsed date in `accentText`, a
    /// label in `teal`.
    var tint: Color?

    init(_ label: String, symbol: String? = nil, icon: OLIcon? = nil, glyph: String? = nil, style: Style = .plain,
         small: Bool = false, tint: Color? = nil) {
        self.label = label
        self.symbol = symbol
        self.icon = icon
        self.glyph = glyph
        self.style = style
        self.small = small
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 6) {
            if let glyph { Text(glyph).font(.system(size: small ? 14 : 17)) }
            if let icon { OLIconView(icon: icon, size: small ? 16 : 18) }
            else if let symbol { Image(systemName: symbol).font(.system(size: small ? 14 : 17, weight: .medium)) }
            if !label.isEmpty { Text(label) }
        }
        .font(small || style == .token ? OLFont.chipSmall : OLFont.chip)
        .foregroundStyle(foreground)
        .lineLimit(1)
        // A glyph alone keeps the chip's own sides, as the design's calendar chip.
        .padding(.horizontal, small || style == .token ? 12 : 14)
        .frame(minHeight: height)
        .background(background, in: .capsule)
        .accessibilityAddTraits(style == .on ? .isSelected : [])
    }

    var height: CGFloat {
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
        // A 44 pt target around the 28–36 pt capsule, which keeps its own
        // height in the layout, as `OLGroupAction` does.
        let slack = max(0, (44 - chip.height) / 2)
        Button(action: action) {
            chip
                .padding(.vertical, slack)
                .contentShape(.rect)
        }
        .buttonStyle(OLPressStyle(scale: 0.96))
        .padding(.vertical, -slack)
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

// MARK: - View toggle

/// A page's two views, List and Calendar: their glyphs in a `sunken`
/// capsule, the one on show on a raised pill. A page that has just taken
/// over from the other view (`from`) draws the pill there and slides it
/// across as it appears.
struct OLViewToggle: View {
    enum Mode: Hashable { case list, calendar }

    let selection: Mode
    var listIdentifier: String?
    var calendarIdentifier: String?
    /// Called as it appears, to mark the switch read.
    var arrived: () -> Void
    let select: (Mode) -> Void
    @State private var pill: Mode
    @State private var taps = 0
    @Environment(\.olStyle) private var style
    @Namespace private var namespace

    init(selection: Mode, from: Mode? = nil, listIdentifier: String? = nil, calendarIdentifier: String? = nil,
         arrived: @escaping () -> Void = {}, select: @escaping (Mode) -> Void) {
        self.selection = selection
        self.listIdentifier = listIdentifier
        self.calendarIdentifier = calendarIdentifier
        self.arrived = arrived
        self.select = select
        _pill = State(initialValue: from ?? selection)
    }

    var body: some View {
        HStack(spacing: 2) {
            segment(.list, label: "List", identifier: listIdentifier) {
                Image(systemName: "list.bullet").font(.system(size: 16, weight: .semibold))
            }
            segment(.calendar, label: "Calendar", identifier: calendarIdentifier) {
                OLIconView(icon: .calendar, size: 18)
            }
        }
        .padding(3)
        .background(OL.sunken, in: .capsule)
        .olFeedback(.selection, trigger: taps)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("View")
        .onAppear {
            arrived()
            guard pill != selection else { return }
            // A turn after the first frame, so the slide is drawn.
            Task { @MainActor in
                withAnimation(style.animation(.snappy(duration: 0.32))) { pill = selection }
            }
        }
        .onChange(of: selection) { _, new in
            withAnimation(style.animation(.snappy(duration: 0.32))) { pill = new }
        }
    }

    private func segment(_ mode: Mode, label: String, identifier: String?,
                         @ViewBuilder glyph: () -> some View) -> some View {
        let on = pill == mode
        return Button {
            guard mode != selection else { return }
            taps += 1
            withAnimation(style.animation(.snappy(duration: 0.32))) { pill = mode }
            select(mode)
        } label: {
            glyph()
                .foregroundStyle(on ? OL.accentText : OL.muted)
                .frame(width: 44, height: 32)
                .background {
                    if on {
                        Capsule(style: .continuous)
                            .fill(OL.surface)
                            .olShadow(.card)
                            .olDarkRing(Capsule(style: .continuous))
                            .matchedGeometryEffect(id: "pill", in: namespace)
                    }
                }
                .contentShape(.capsule)
        }
        .buttonStyle(OLPressStyle(scale: 0.94))
        .accessibilityLabel(label)
        .accessibilityAddTraits(mode == selection ? .isSelected : [])
        .accessibilityIdentifier(identifier ?? "view.\(label.lowercased())")
    }
}

// MARK: - C15 Estimate

/// The estimate as a slider over friendly stops, 5 min to 8 h, closer
/// together where estimates usually fall. The value beside its label follows
/// the thumb with a tick at each stop, and the change is made once, on
/// letting go. VoiceOver, or a keyboard, moves it a stop at a time, each
/// made at once.
struct OLEstimateSlider: View {
    let value: Int
    var identifier: String?
    let commit: (Int) -> Void
    @State private var sliding: Double?
    @State private var isDragging = false

    static let stops = [5, 10, 15, 20, 25, 30, 40, 45, 50, 60, 75, 90, 105, 120, 150, 180, 210, 240, 300, 360, 420, 480]

    /// The stops, with an estimate between them (one made on the Mac) in
    /// its place, so the thumb starts where it is.
    private var stops: [Int] {
        Self.stops.contains(value) || value <= 0 ? Self.stops : (Self.stops + [value]).sorted()
    }

    var body: some View {
        let stops = stops
        let current = Double(stops.firstIndex(of: value) ?? 0)
        let shown = stops[min(stops.count - 1, max(0, Int((sliding ?? current).rounded())))]
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Estimate").font(OLFont.rowTitle).foregroundStyle(OL.ink)
                Spacer(minLength: 8)
                Text(Self.label(shown))
                    .font(OLFont.rowTitle.weight(.semibold).monospacedDigit())
                    .foregroundStyle(sliding == nil ? OL.ink : OL.accentText)
                    .contentTransition(.numericText(value: Double(shown)))
            }
            .accessibilityHidden(true)
            Slider(value: Binding(get: { sliding ?? current }, set: { position in
                // Moved without a drag, by VoiceOver or a keyboard: made at once.
                guard isDragging else { return settle(position, stops: stops) }
                sliding = position
            }), in: 0...Double(stops.count - 1), step: 1) { editing in
                isDragging = editing
                guard !editing, let sliding else { return }
                settle(sliding, stops: stops)
            }
            .tint(OL.accent)
            .accessibilityLabel("Estimate")
            .accessibilityValue(Self.spoken(shown))
            .accessibilityIdentifier(identifier ?? "estimate")
            HStack {
                Text(Self.label(stops[0]))
                Spacer()
                Text(Self.label(stops[stops.count - 1]))
            }
            .font(OLFont.meta)
            .foregroundStyle(OL.muted)
            .accessibilityHidden(true)
        }
        .olFeedback(.selection, trigger: shown)
    }

    private func settle(_ position: Double, stops: [Int]) {
        sliding = nil
        let picked = stops[min(stops.count - 1, max(0, Int(position.rounded())))]
        if picked != value { commit(picked) }
    }

    /// "45 minutes", "1 hour 30 minutes", for VoiceOver.
    static func spoken(_ minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        let parts = [hours > 0 ? "\(hours) \(hours == 1 ? "hour" : "hours")" : nil,
                     rest > 0 ? "\(rest) \(rest == 1 ? "minute" : "minutes")" : nil]
        return parts.compactMap(\.self).joined(separator: " ")
    }

    /// "45 min", "1 h", "1 h 30 min".
    static func label(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes) min" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
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
