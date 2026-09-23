//
//  NextKit.swift
//  openlist
//

import SwiftUI

// MARK: - Chips

/// The tint families a chip can use.
enum NXTone: Equatable {
    case neutral, accent, over, green, amber
    case label(Color)
}

struct NXChipModel: Identifiable {
    var id: String
    var label: String
    var icon: String?
    var tone: NXTone = .neutral
    var fill = false
}

struct NXChip: View {
    @Environment(\.nextStyle) private var style
    let chip: NXChipModel
    var fresh = false
    /// Tasks-screen chips: text only, colour only when it means something.
    var quiet = false
    @State private var appeared = true

    var body: some View {
        let (fg, bg) = colors
        HStack(spacing: quiet ? 3 : 4) {
            if let icon = chip.icon {
                Image(systemName: icon).font(.system(size: 9.5, weight: chip.fill ? .bold : .semibold))
            }
            if !chip.label.isEmpty {
                Text(quiet && isLabel ? "#" + chip.label : chip.label)
                    .font(.system(size: quiet ? 11.5 : 11, weight: quiet ? .medium : .semibold))
            }
        }
        .lineLimit(1)
        .foregroundStyle(quiet ? quietColor(fg) : fg)
        .padding(.horizontal, quiet ? 0 : 7)
        .padding(.vertical, quiet ? 0 : 3)
        .background(quiet ? Color.clear : bg, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .fixedSize()
        .scaleEffect(appeared ? 1 : 0.85)
        .offset(y: appeared ? 0 : 3)
        .opacity(appeared ? 1 : 0)
        .onChange(of: fresh) { _, isFresh in if isFresh { pop() } }
        .onAppear { if fresh { pop() } }
    }

    private var isLabel: Bool { if case .label = chip.tone { true } else { false } }

    private func quietColor(_ fg: Color) -> Color {
        switch chip.tone {
        case .over, .accent, .amber, .label: fg
        default: NX.ink(0.42)
        }
    }

    private func pop() {
        guard style.lively else { return }
        appeared = false
        withAnimation(style.ease(280)) { appeared = true }
    }

    private var colors: (Color, Color) {
        switch chip.tone {
        case .neutral: (NX.ink(0.58), NX.ink(0.06))
        case .accent: (style.accent, style.accent.opacity(0.12))
        case .over: (NX.redText, NX.red.opacity(0.13))
        case .green: (NX.greenText, NX.green.opacity(0.14))
        case .amber: (NX.amberText, NX.amber.opacity(0.18))
        case let .label(color): (color, color.opacity(0.12))
        }
    }
}

// MARK: - Keys & small controls

/// A monospaced key hint such as `N`, `⌘K` or `↩`.
struct NXKey: View {
    let text: String
    var opacity: Double = 0.6
    var size: CGFloat = 10

    init(_ text: String, opacity: Double = 0.6, size: CGFloat = 10) {
        self.text = text
        self.opacity = opacity
        self.size = size
    }

    var body: some View {
        Text(text).font(NX.mono(size)).opacity(opacity)
    }
}

/// A 16px key badge used by triage and the add row.
struct NXKeyBadge: View {
    let text: String
    var body: some View {
        Text(text)
            .font(NX.mono(10, weight: .semibold))
            .foregroundStyle(NX.ink(0.5))
            .frame(minWidth: 16, minHeight: 16)
            .padding(.horizontal, text.count > 1 ? 3 : 0)
            .background(NX.ink(0.06), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

/// The design's 34×20 switch.
struct NXToggle: View {
    @Environment(\.nextStyle) private var style
    let isOn: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? style.accent : NX.ink(0.16))
                Circle().fill(.white)
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.2), radius: 1.5, y: 1)
                    .padding(2)
            }
            .frame(width: 34, height: 20)
            .animation(style.spring(200), value: isOn)
        }
        .buttonStyle(.plain)
    }
}

/// Rounded pill used for inspector options, capture destinations and filters.
struct NXPill<Label: View>: View {
    @Environment(\.nextStyle) private var style
    var isOn: Bool
    var onColor: Color?
    var action: () -> Void
    @ViewBuilder var label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .font(.system(size: 11.5, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .foregroundStyle(isOn ? Color.white : NX.ink(0.66))
                .background(isOn ? (onColor ?? style.accent) : NX.ink(0.05),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
                .animation(style.ease(140), value: isOn)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Hover

/// A plain button whose background appears on hover.
struct NXHoverButtonStyle: ButtonStyle {
    var hover: Color = NX.ink(0.06)
    var radius: CGFloat = 7
    var padding: EdgeInsets = EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8)
    var foreground: Color = NX.ink(0.6)
    var hoverForeground: Color?

    func makeBody(configuration: Configuration) -> some View {
        HoverBody(configuration: configuration, style: self)
    }

    private struct HoverBody: View {
        let configuration: Configuration
        let style: NXHoverButtonStyle
        @State private var hovering = false

        var body: some View {
            configuration.label
                .padding(style.padding)
                .foregroundStyle(hovering ? (style.hoverForeground ?? style.foreground) : style.foreground)
                .background(hovering || configuration.isPressed ? style.hover : .clear,
                            in: RoundedRectangle(cornerRadius: style.radius, style: .continuous))
                .opacity(configuration.isPressed ? 0.8 : 1)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}

extension View {
    /// The design's warm card shadow: hairline plus a soft drop.
    func nxCardShadow(radius: CGFloat = 12, hairline: Double = 0.12, drop: Double = 0.09, y: CGFloat = 14, blur: CGFloat = 40) -> some View {
        self
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(NX.ink(hairline), lineWidth: 0.5))
            .shadow(color: NX.shadowWarm.opacity(drop), radius: blur / 2, y: y)
    }

    func nxSectionTitle() -> some View {
        self.font(.system(size: 10.5, weight: .semibold))
            .kerning(0.5)
            .textCase(.uppercase)
            .foregroundStyle(NX.ink(0.42))
    }
}

/// Tracks hover for custom rows.
struct NXHover: ViewModifier {
    @Binding var isHovering: Bool
    func body(content: Content) -> some View {
        content.onHover { isHovering = $0 }
    }
}

// MARK: - Screen header

struct NXScreenHeader<Trailing: View>: View {
    @Environment(\.nextStyle) private var style
    enum Tile { case icon(String), emoji(String), list(TaskList) }
    let tile: Tile
    let color: Color
    let title: String
    let subtitle: String
    var progress: (done: Int, total: Int)?
    /// Sits after the subtitle, like the list header's hours menu.
    var accessory: AnyView?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(color.opacity(0.12))
                switch tile {
                case let .icon(name):
                    Image(systemName: name).font(.system(size: 19, weight: .semibold)).foregroundStyle(color)
                case let .emoji(emoji):
                    Text(emoji).font(.system(size: 24))
                case let .list(list):
                    NXListGlyph(list: list, size: 24)
                }
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(style.serifTitles ? NX.serif(34) : .system(size: 27, weight: .bold))
                    .kerning(style.serifTitles ? 0 : -0.27)
                    .foregroundStyle(NX.ink)
                    .lineLimit(1)
                // The accessory's hover padding stands in for the space after the subtitle.
                HStack(spacing: -1) {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(NX.ink(0.48))
                        .lineLimit(1)
                        .contentTransition(.numericText())
                    accessory
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 12)
            if let progress, progress.total > 0 {
                NXProgress(done: progress.done, total: progress.total)
            }
            trailing()
        }
        .padding(.bottom, 18)
    }
}

extension NXScreenHeader where Trailing == EmptyView {
    init(tile: Tile, color: Color, title: String, subtitle: String, progress: (done: Int, total: Int)? = nil,
         accessory: AnyView? = nil) {
        self.init(tile: tile, color: color, title: title, subtitle: subtitle, progress: progress, accessory: accessory) { EmptyView() }
    }
}

struct NXProgress: View {
    @Environment(\.nextStyle) private var style
    let done: Int
    let total: Int

    var body: some View {
        // Narrow windows drop the count, then the bar, before the title truncates.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                Text("\(done) of \(total) done")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(NX.ink(0.5))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .fixedSize()
                bar
            }
            bar
            Color.clear.frame(width: 0, height: 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(done) of \(total) done")
    }

    private var bar: some View {
        let fraction = total > 0 ? Double(done) / Double(total) : 0
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3).fill(NX.ink(0.08))
            RoundedRectangle(cornerRadius: 3).fill(fraction >= 1 ? NX.green : style.accent)
                .frame(width: 110 * fraction)
        }
        .frame(width: 110, height: 4)
        .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.56), value: fraction)
    }
}

/// Segmented control used by Calendar's range picker.
struct NXSegmented<Value: Hashable>: View {
    @Environment(\.nextStyle) private var style
    let options: [(Value, String)]
    let selection: Value
    var onSelect: (Value) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.0) { value, label in
                Button { onSelect(value) } label: {
                    Text(label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(selection == value ? NX.ink : NX.ink(0.55))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background {
                            if selection == value {
                                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(NX.card)
                                    .shadow(color: NX.ink(0.12), radius: 1, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(NX.ink(0.06), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .animation(style.ease(140), value: selection)
    }
}

/// Breathing dot used by the notch and the "Planned now" banner.
struct NXBreathingDot: View {
    var color: Color
    var active = true
    var size: CGFloat = 7
    @State private var dim = false

    var body: some View {
        Circle().fill(color)
            .frame(width: size, height: size)
            .opacity(active && dim ? 0.45 : 1)
            .scaleEffect(active && dim ? 0.8 : 1)
            .onAppear { restart() }
            .onChange(of: active) { _, _ in restart() }
    }

    private func restart() {
        dim = false
        guard active else { return }
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { dim = true }
    }
}

/// Modifiers for current keyboard state.
enum NXModifiers {
    static var command: Bool { NSEvent.modifierFlags.contains(.command) }
    static var shift: Bool { NSEvent.modifierFlags.contains(.shift) }
}
