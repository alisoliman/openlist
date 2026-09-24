//
//  NextPanels.swift
//  openlist
//

import SwiftUI

// MARK: - Buttons

/// Buttons for popovers, sheets and notices. `primary` is the design's accent
/// "Start working" button, `secondary` its grey "Review kept tasks" one, whose
/// hover deepens only the fill, and `destructive` Trash's red. `link` is a
/// quiet action in the accent and `quiet` a grey one that darkens on hover,
/// like the Tasks query's clear ×. Hover swaps the fill at once, with no
/// pressed dim, as the design's style-hover; unlike `NXHoverButtonStyle`, a
/// disabled button dims.
struct NXPanelButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, destructive, link, quiet }
    /// `regular` is the design's 8/12 button, `small` its 5/9 pill-sized one,
    /// `icon` a square around a symbol.
    enum Size { case regular, small, icon }

    var kind: Kind = .secondary
    var size: Size = .regular

    func makeBody(configuration: Configuration) -> some View {
        PanelButton(configuration: configuration, kind: kind, size: size)
    }

    private struct PanelButton: View {
        @Environment(\.nextStyle) private var style
        @Environment(\.isEnabled) private var isEnabled
        let configuration: Configuration
        let kind: Kind
        let size: Size
        @State private var hovering = false

        var body: some View {
            let hot = isEnabled && (hovering || configuration.isPressed)
            configuration.label
                .font(.system(size: size == .small ? 11.5 : 12, weight: isText ? .medium : .semibold))
                .lineLimit(1)
                .foregroundStyle(foreground(hot))
                .padding(padding)
                .background(fill(hot), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                // The design's `0 1px 2px` accent glow under its filled capture button.
                .shadow(color: kind == .primary && isEnabled ? style.accent.opacity(0.4) : .clear, radius: 1, y: 1)
                .contentShape(Rectangle())
                .opacity(isEnabled ? 1 : 0.45)
                .onHover { hovering = $0 }
        }

        private var isText: Bool { kind == .link || kind == .quiet }

        private var padding: EdgeInsets {
            switch (size, isText) {
            case (.icon, _): EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)
            case (.regular, false): EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
            case (.small, false): EdgeInsets(top: 5, leading: 9, bottom: 5, trailing: 9)
            case (.regular, true): EdgeInsets(top: 3, leading: 5, bottom: 3, trailing: 5)
            case (.small, true): EdgeInsets(top: 2, leading: 5, bottom: 2, trailing: 5)
            }
        }

        private var radius: CGFloat {
            switch (size, isText) {
            case (.regular, false): 8
            case (.small, false): 7
            case (.small, true): 5
            default: 6
            }
        }

        private func foreground(_ hot: Bool) -> Color {
            switch kind {
            case .primary: .white
            case .secondary: NX.ink(0.7)
            case .destructive: NX.redText
            case .link: style.accent
            case .quiet: hot ? NX.ink : NX.ink(0.55)
            }
        }

        private func fill(_ hot: Bool) -> Color {
            switch kind {
            case .primary: hot ? style.accentHover : style.accent
            case .secondary: NX.ink(hot ? 0.1 : 0.06)
            case .destructive: NX.red.opacity(hot ? 0.16 : 0.1)
            case .link: hot ? style.accent.opacity(0.1) : .clear
            case .quiet: hot ? NX.ink(0.06) : .clear
            }
        }
    }
}

/// A quiet chevron that shows or hides the part below it, as the design's
/// carets do: right while closed, down once open. The inspector's More
/// options and Full history, Work history's Originally planned and a
/// matched note's Full note share it. Its text lines up with the column.
struct NXDisclosureButton: View {
    @Environment(\.nextStyle) private var style
    let title: String
    @Binding var isExpanded: Bool

    init(_ title: String, isExpanded: Binding<Bool>) {
        self.title = title
        _isExpanded = isExpanded
    }

    var body: some View {
        Button { withAnimation(style.ease(220)) { isExpanded.toggle() } } label: {
            HStack(spacing: 5) {
                Text(title)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8.5, weight: .bold))
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(NXPanelButtonStyle(kind: .quiet, size: .small))
        .padding(.leading, -5)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }
}

/// A row in the design's small menus, like the Tasks sentence menus and the
/// label picker: 8/9 padding on a 7pt radius, the accent's faint fill and a
/// check when chosen, grey on hover. It is a real button, so the keyboard and
/// VoiceOver can choose it.
struct NXPanelRowStyle: ButtonStyle {
    var isOn: Bool
    /// Whether it's the row Return picks, in a menu that keeps one. Given, it
    /// alone draws the grey, as in the design's palette: the pointer moves
    /// that one highlight rather than greying a second row.
    var isHighlighted: Bool?

    func makeBody(configuration: Configuration) -> some View {
        PanelRow(configuration: configuration, isOn: isOn, isHighlighted: isHighlighted)
    }

    /// Whether a row takes the grey: its highlight when the menu keeps one,
    /// else the pointer, and while pressed.
    static func greys(highlighted: Bool?, hovering: Bool, pressed: Bool) -> Bool {
        (highlighted ?? hovering) || pressed
    }

    private struct PanelRow: View {
        @Environment(\.nextStyle) private var style
        let configuration: Configuration
        let isOn: Bool
        let isHighlighted: Bool?
        @State private var hovering = false

        var body: some View {
            HStack(spacing: 9) {
                configuration.label
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "checkmark")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(style.accent)
                    .opacity(isOn ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(NX.ink)
            .padding(.vertical, 8)
            .padding(.horizontal, 9)
            .background(NXPanelRowStyle.greys(highlighted: isHighlighted, hovering: hovering, pressed: configuration.isPressed)
                            ? NX.ink(0.05) : isOn ? style.accent.opacity(0.06) : .clear,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: isOn)
        }
    }
}

// MARK: - Titles & fields

/// A sheet's display title, set in Instrument Serif like the design's
/// "Inbox triaged", or in bold when the settings turn serif titles off.
struct NXPanelTitle: View {
    @Environment(\.nextStyle) private var style
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(style.serifTitles ? NX.serif(26) : .system(size: 21, weight: .bold))
            .foregroundStyle(NX.ink)
            .fixedSize(horizontal: false, vertical: true)
            // The design's 26px/1.1 line box, not the serif's taller metrics.
            .padding(.vertical, style.serifTitles ? NX.serifLeading(26, lineHeight: 1.1) : 0)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A text field on a faint fill, with an optional leading symbol, like the
/// Tasks screen's title filter. The plain field has no focus ring, so the
/// border turns to the accent while it has focus.
struct NXPanelField<Field: View>: View {
    @Environment(\.nextStyle) private var style
    var icon: String?
    @ViewBuilder var field: () -> Field
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 7) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NX.ink(0.38))
                    .accessibilityHidden(true)
            }
            field()
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(NX.ink)
                .focused($focused)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 9)
        .background(NX.ink(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(focused ? style.accent.opacity(0.6) : NX.ink(0.08), lineWidth: focused ? 1 : 0.5))
        .animation(.easeOut(duration: 0.12), value: focused)
    }
}

// MARK: - Notices

/// The banner the window's notices share, from its failures and sync
/// warnings to its link and reminder notices: an untitled card with a
/// hairline, a tinted symbol, 12.5pt text and quiet link buttons.
struct NXNoticeCard<Actions: View>: View {
    enum Tone { case info, warning, error }

    let icon: String
    var tone: Tone = .info
    let message: String
    /// Long messages stop here, with the whole text as the tooltip.
    var lineLimit: Int?
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 16)
                .accessibilityHidden(true)
            let text = Text(message)
                .font(.system(size: 12.5))
                .foregroundStyle(NX.ink(0.7))
                .lineLimit(lineLimit)
                .fixedSize(horizontal: false, vertical: true)
            Group { if lineLimit != nil { text.help(message) } else { text } }
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 2) { actions() }
                .fixedSize()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(NX.card, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(NX.ink(0.12), lineWidth: 0.5))
        .accessibilityElement(children: .contain)
    }

    private var iconColor: Color {
        switch tone {
        case .info: NX.ink(0.45)
        case .warning: NX.amberText
        case .error: NX.redText
        }
    }
}

/// Why an action inside a sheet failed, where the sheet stays open to try
/// again: the notice cards' warning triangle beside red 12.5pt text, heard
/// as one line. Use as template, Merge labels and Move planned work share it.
struct NXSheetError: View {
    let message: String

    init(_ message: String) { self.message = message }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 12, weight: .medium))
            Text(message).fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 12.5))
        .foregroundStyle(NX.redText)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// Where the window's notices sit: under the toolbar, in line with the
    /// screen's content column.
    func nxNoticePlacement() -> some View {
        frame(maxWidth: 880, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.top, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
