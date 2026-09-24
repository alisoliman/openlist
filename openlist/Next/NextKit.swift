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
    /// A list chip's list, whose glyph leads the label.
    var glyph: TaskList?
}

struct NXChip: View {
    @Environment(\.nextStyle) private var style
    let chip: NXChipModel
    var fresh = false
    /// Tasks-screen chips: text only, colour only when it means something.
    var quiet = false
    /// Starts hidden when the chip arrives fresh, so chipIn has somewhere to play from.
    @State private var appeared: Bool

    init(chip: NXChipModel, fresh: Bool = false, quiet: Bool = false) {
        self.chip = chip
        self.fresh = fresh
        self.quiet = quiet
        _appeared = State(initialValue: !fresh)
    }

    var body: some View {
        let (fg, bg) = colors
        HStack(spacing: quiet ? 3 : 4) {
            if let icon = chip.icon {
                Image(systemName: icon).font(.system(size: 9.5, weight: chip.fill ? .bold : .semibold))
            }
            if !chip.label.isEmpty {
                let size: CGFloat = quiet ? 11.5 : 11
                Group {
                    if let list = chip.glyph {
                        // One run, as the design's `emoji + " " + name`, the emoji at the design's size.
                        Text("\(NXListGlyph.text(list, size: size)) \(chip.label)")
                            .accessibilityLabel(chip.label)
                    } else {
                        Text(quiet && isLabel ? "#" + chip.label : chip.label)
                    }
                }
                .font(.system(size: size, weight: quiet ? .medium : .semibold))
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
        .onChange(of: fresh, initial: true) { _, isFresh in if isFresh { pop() } }
    }

    private var isLabel: Bool { if case .label = chip.tone { true } else { false } }

    private func quietColor(_ fg: Color) -> Color {
        switch chip.tone {
        case .over, .accent, .amber, .label: fg
        default: NX.ink(0.42)
        }
    }

    private func pop() {
        guard style.lively else { appeared = true; return }
        withTransaction(\.disablesAnimations, true) { appeared = false }
        // Showing again on the next update keeps the two changes from
        // merging into none, which would skip chipIn.
        Task { @MainActor in withAnimation(style.ease(280)) { appeared = true } }
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

/// The design's 34×20 switch.
struct NXToggle: View {
    @Environment(\.nextStyle) private var style
    let isOn: Bool
    /// What VoiceOver announces; the visible label sits beside the switch.
    var label: String = ""
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
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}

// MARK: - Hover

/// A plain button whose background appears on hover. `rest` is the fill at
/// rest; the hover fill replaces it, as the design's style-hover does.
struct NXHoverButtonStyle: ButtonStyle {
    var hover: Color = NX.ink(0.06)
    var rest: Color = .clear
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
                .background(hovering || configuration.isPressed ? style.hover : style.rest,
                            in: RoundedRectangle(cornerRadius: style.radius, style: .continuous))
                .opacity(configuration.isPressed ? 0.8 : 1)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}

/// The grey minus or plus of the inspector's estimate stepper. `label` is
/// what VoiceOver reads for it, not the symbol's name.
struct NXStepButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 11, weight: .medium)).frame(width: 15, height: 15)
        }
        .buttonStyle(NXHoverButtonStyle(hover: NX.ink(0.1), rest: NX.ink(0.05), radius: 6,
                                        padding: EdgeInsets(top: 3, leading: 3, bottom: 3, trailing: 3),
                                        foreground: NX.ink(0.6)))
        .accessibilityLabel(label)
    }
}

extension View {
    /// The design's warm card shadow: hairline plus a soft drop.
    func nxCardShadow(radius: CGFloat = 12, hairline: Double = 0.12, drop: Double = 0.09, y: CGFloat = 14, blur: CGFloat = 40) -> some View {
        self
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(NX.ink(hairline), lineWidth: 0.5))
            .shadow(color: NX.shadowWarm.opacity(drop), radius: blur / 2, y: y)
    }
}

// MARK: - Screen header

/// A screen title renamed in place, like a list's: a click on it starts,
/// Return or clicking away commits, Esc cancels.
struct NXTitleRename {
    var isEditing: Binding<Bool>
    /// What the field starts from, all selected: the title as stored, or
    /// nothing for a title still to be given.
    var value: String
    var placeholder: String
    var commit: (String) -> Void
}

struct NXScreenHeader<Trailing: View>: View {
    @Environment(\.nextStyle) private var style
    enum Tile { case icon(String), emoji(String), list(TaskList) }
    let tile: Tile
    let color: Color
    let title: String
    let subtitle: String
    var progress: (done: Int, total: Int)?
    /// Makes the title editable in place.
    var rename: NXTitleRename?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
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
                if let rename {
                    NXHeaderTitleField(title: title, rename: rename)
                } else {
                    NXHeaderTitle(text: title)
                }
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NX.ink(0.48))
                    .lineLimit(1)
                    .contentTransition(.numericText())
            }
            .layoutPriority(1)
            // The design's flex spacer: the row's gaps alone keep the title
            // and what trails it apart.
            Spacer(minLength: 0)
            if let progress, progress.total > 0 {
                NXProgress(done: progress.done, total: progress.total)
            }
            trailing()
        }
    }
}

/// A screen header's title: serif 34 on the design's 1.05 line box, or bold
/// 27 without serif titles.
struct NXHeaderTitle: View {
    @Environment(\.nextStyle) private var style
    let text: String

    var body: some View {
        Text(text)
            .modifier(NXHeaderTitleType())
            // Long names wrap, as the design's header does, rather than truncate.
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            // The design's 34px/1.05 line box, not the serif's taller metrics.
            .padding(.vertical, style.serifTitles ? NX.serifLeading(34, lineHeight: 1.05) : 0)
    }
}

/// The header title's face, shared by the title and the field renaming it.
private struct NXHeaderTitleType: ViewModifier {
    @Environment(\.nextStyle) private var style

    func body(content: Content) -> some View {
        content
            .font(style.serifTitles ? NX.serif(34) : .system(size: 27, weight: .bold))
            .kerning(style.serifTitles ? 0 : -0.27)
            .foregroundStyle(NX.ink)
    }
}

/// The header's title renamed in place. The field sits on the title's own
/// line box, which keeps laying out what's typed, so the header keeps its
/// metrics while the title is written.
private struct NXHeaderTitleField: View {
    let title: String
    let rename: NXTitleRename
    @State private var draft = ""
    @State private var selection: TextSelection?
    @FocusState private var focused: Bool

    var body: some View {
        if rename.isEditing.wrappedValue {
            NXHeaderTitle(text: draft.isEmpty ? rename.placeholder : draft)
                .opacity(0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .leading) {
                    TextField(rename.placeholder, text: $draft, selection: $selection, axis: .vertical)
                        .textFieldStyle(.plain)
                        .modifier(NXHeaderTitleType())
                        .lineLimit(1...2)
                        .focused($focused)
                        .onSubmit(commit)
                        .onExitCommand { rename.isEditing.wrappedValue = false }
                        .accessibilityLabel("Title")
                }
                .onAppear {
                    draft = rename.value
                    selection = TextSelection(range: draft.startIndex..<draft.endIndex)
                    // Once the field is on screen, or the focus can miss it.
                    DispatchQueue.main.async { focused = true }
                }
                .onChange(of: focused) { _, now in if !now { commit() } }
        } else {
            NXHeaderTitle(text: title)
                .contentShape(Rectangle())
                .onTapGesture { rename.isEditing.wrappedValue = true }
                .pointerStyle(.horizontalText)
                .help("Rename")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(named: "Rename") { rename.isEditing.wrappedValue = true }
        }
    }

    /// Return or clicking away: a name that isn't empty, and has changed, is kept.
    private func commit() {
        guard rename.isEditing.wrappedValue else { return }
        rename.isEditing.wrappedValue = false
        let name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty, name != rename.value { rename.commit(name) }
    }
}

extension NXScreenHeader where Trailing == EmptyView {
    init(tile: Tile, color: Color, title: String, subtitle: String, progress: (done: Int, total: Int)? = nil) {
        self.init(tile: tile, color: color, title: title, subtitle: subtitle, progress: progress) { EmptyView() }
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
        HStack(spacing: 2) {
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
