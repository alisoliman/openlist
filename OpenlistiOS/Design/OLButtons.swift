//
//  OLButtons.swift
//  OpenlistiOS
//

import SwiftUI

/// Every tappable surface's press: 0.94 and a touch lighter, over 150 ms,
/// or just the lightening under Reduce motion. The design defines no pressed
/// states; this is the iPhone's answer to the Mac's hover.
struct OLPressStyle: ButtonStyle {
    var scale: CGFloat = 0.94
    @Environment(\.olStyle) private var style

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !style.reduceMotion ? scale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(style.animation(OLStyle.press), value: configuration.isPressed)
    }
}

// MARK: - C9 Icon buttons

/// A round icon button (`.ib`): 44, or `lg` 56, `xl` 72.
struct OLIconButton: View {
    enum Kind: Equatable {
        /// `sunken` behind an `ink` icon.
        case plain
        /// No fill: top-bar icons.
        case bare
        /// `accent` behind `onAccent`, the Now card's play and Working's pause.
        case accent
        /// Already done: `successSoft` behind `successText`.
        case ok
        /// Delete: `dangerSoft` behind `danger`.
        case bad
        /// Working's Done: `success` behind white.
        case success
        /// On the canvas with a card shadow: Task detail's trash.
        case raised
    }

    enum Size: CGFloat {
        case regular = 44
        case large = 56
        case extraLarge = 72

        var icon: CGFloat {
            switch self {
            case .regular: 20
            case .large: 22
            case .extraLarge: 28
            }
        }
    }

    let symbol: String
    /// One of the mockups' own glyphs, drawn in place of `symbol`.
    var icon: OLIcon?
    let label: String
    var kind: Kind = .plain
    var size: Size = .regular
    /// The icon's point size, when not the size's own (22 in top bars).
    var iconSize: CGFloat?
    var tint: Color?
    let action: () -> Void

    init(_ symbol: String, label: String, kind: Kind = .plain, size: Size = .regular, iconSize: CGFloat? = nil,
         tint: Color? = nil, action: @escaping () -> Void) {
        self.symbol = symbol
        self.label = label
        self.kind = kind
        self.size = size
        self.iconSize = iconSize
        self.tint = tint
        self.action = action
    }

    /// A button drawing one of the mockups' own glyphs.
    init(icon: OLIcon, label: String, kind: Kind = .plain, size: Size = .regular, iconSize: CGFloat? = nil,
         tint: Color? = nil, action: @escaping () -> Void) {
        self.init("", label: label, kind: kind, size: size, iconSize: iconSize, tint: tint, action: action)
        self.icon = icon
    }

    var body: some View {
        Button(action: action) {
            glyph
                .foregroundStyle(tint ?? foreground)
                .frame(width: size.rawValue, height: size.rawValue)
                .background { background }
                .contentShape(.circle)
        }
        .buttonStyle(OLPressStyle())
        .accessibilityLabel(label)
    }

    @ViewBuilder private var glyph: some View {
        if let icon {
            OLIconView(icon: icon, size: iconSize ?? size.icon)
        } else {
            Image(systemName: symbol)
                .font(.system(size: iconSize ?? size.icon, weight: size == .regular ? .medium : .semibold))
        }
    }

    private var foreground: Color {
        switch kind {
        case .plain, .bare: OL.ink
        case .accent: OL.onAccent
        case .ok: OL.successText
        case .bad, .raised: OL.danger
        case .success: .white
        }
    }

    @ViewBuilder private var background: some View {
        switch kind {
        case .plain: Circle().fill(OL.sunken)
        case .bare: Color.clear
        case .accent:
            Circle().fill(OL.accent).olShadow(size == .regular ? .card : .fab)
        case .ok: Circle().fill(OL.successSoft)
        case .bad: Circle().fill(OL.dangerSoft)
        case .success: Circle().fill(OL.success)
        case .raised: Circle().fill(OL.surface).olShadow(.card)
        }
    }
}

// MARK: - C10 Buttons

/// A capsule button (`.btn`): 48 high, 16/20 semibold.
struct OLButtonStyle: ButtonStyle {
    enum Kind: Equatable {
        /// `sunken` and `ink`.
        case neutral
        /// `accent` and `onAccent`.
        case primary
        /// `ink` and `canvas`: Triage's Later. Light in dark mode, as the
        /// design's ink surfaces are.
        case ink
        /// `dangerSoft` and `danger`: Hold to empty Trash.
        case danger
    }

    enum Size: Equatable {
        /// 48 high, 22 pt sides.
        case regular
        /// 56 high, 17 pt: Start working, Later.
        case large
        /// 36 high, 15 pt: the capture sheet's Add.
        case small

        var height: CGFloat {
            switch self {
            case .regular: 48
            case .large: 56
            case .small: 36
            }
        }

        var padding: CGFloat {
            switch self {
            case .regular: 22
            case .large: 26
            case .small: 18
            }
        }

        var font: Font {
            switch self {
            case .regular: OLFont.button
            case .large: OLFont.buttonLarge
            case .small: OLFont.buttonSmall
            }
        }
    }

    var kind: Kind = .neutral
    var size: Size = .regular
    /// Full width (`.block`).
    var block = false
    /// The FAB's glow, for Start working.
    var glows = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.olStyle) private var style

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(size.font)
            .lineLimit(1)
            .fixedSize(horizontal: !block, vertical: false)
            .foregroundStyle(foreground)
            .padding(.horizontal, size.padding)
            .frame(maxWidth: block ? .infinity : nil)
            .frame(minHeight: size.height)
            .background {
                if glows && isEnabled {
                    Capsule(style: .continuous).fill(background).olShadow(.fab)
                } else {
                    Capsule(style: .continuous).fill(background)
                }
            }
            .contentShape(.capsule)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed && !style.reduceMotion ? 0.97 : 1)
            .animation(style.animation(OLStyle.press), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .neutral: OL.ink
        case .primary: OL.onAccent
        case .ink: OL.canvas
        case .danger: OL.danger
        }
    }

    private var background: Color {
        switch kind {
        case .neutral: OL.sunken
        case .primary: OL.accent
        case .ink: OL.ink
        case .danger: OL.dangerSoft
        }
    }
}

extension ButtonStyle where Self == OLButtonStyle {
    static func ol(_ kind: OLButtonStyle.Kind = .neutral, size: OLButtonStyle.Size = .regular,
                   block: Bool = false, glows: Bool = false) -> OLButtonStyle {
        OLButtonStyle(kind: kind, size: size, block: block, glows: glows)
    }
}

// MARK: - C11 Text link

/// A text button in the accent text (`.tlink`): Cancel, Done, Select all,
/// Look at tomorrow. 44 high, 17/22 medium, semibold when `strong`.
struct OLTextLinkStyle: ButtonStyle {
    var strong = false
    /// Restore in Trash's rows is 15 pt.
    var small = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(small ? OLFont.buttonSmall : strong ? OLFont.linkStrong : OLFont.link)
            .foregroundStyle(OL.accentText)
            .padding(.horizontal, 10)
            .frame(minHeight: 44)
            .contentShape(.rect)
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.4)
    }
}

extension ButtonStyle where Self == OLTextLinkStyle {
    static func olLink(strong: Bool = false, small: Bool = false) -> OLTextLinkStyle {
        OLTextLinkStyle(strong: strong, small: small)
    }
}
