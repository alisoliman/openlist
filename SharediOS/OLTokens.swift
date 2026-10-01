//
//  OLTokens.swift
//  SharediOS
//

import CoreText
import SwiftUI
import UIKit

/// One colour token of the iPhone design, as its light and dark sRGB values
/// in docs/design/openlist-ios-companion/design-system.css.
///
/// The app draws with `color`, which follows the view's appearance. Widgets
/// and Live Activities resolve a pair for a scheme with `resolved(_:)`: an
/// archived widget view keeps no dynamic colour provider, and a Live Activity
/// is drawn on the dark palette whatever the phone's appearance.
nonisolated struct OLColorPair: Equatable, Hashable, Sendable {
    let light: UInt32
    let dark: UInt32

    init(light: UInt32, dark: UInt32) {
        self.light = light
        self.dark = dark
    }

    /// The same value in both appearances.
    init(_ both: UInt32) {
        self.init(light: both, dark: both)
    }

    func hex(for scheme: ColorScheme) -> UInt32 { scheme == .dark ? dark : light }

    /// Follows the appearance of whatever draws it.
    var color: Color { Color(uiColor: uiColor) }

    var uiColor: UIColor {
        let light = light, dark = dark
        return UIColor { traits in
            OLColorPair.uiColor(traits.userInterfaceStyle == .dark ? dark : light)
        }
    }

    /// Fixed to one appearance.
    func resolved(_ scheme: ColorScheme) -> Color { OLColorPair.color(hex(for: scheme)) }

    static func color(_ hex: UInt32, opacity: Double = 1) -> Color {
        Color(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }

    static func uiColor(_ hex: UInt32, alpha: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

/// The iPhone design's colour tokens (design-system.css), for the app, its
/// widgets and its Live Activity. `OL.x` follows the appearance; `OL.Pair.x`
/// holds the two values, for tests, widgets and a Live Activity's fixed dark.
///
/// The Mac's `NX` palette is a different, AppKit-bound set: only the card,
/// ink and dark canvas agree. List colours stay `ListAccent`'s, which are the
/// same everywhere; a list's soft band on the phone is `OL.tint(for:)`.
nonisolated enum OL {
    enum Pair {
        // Surfaces and text
        static let canvas = OLColorPair(light: 0xF2F0EC, dark: 0x1D1C21)
        static let surface = OLColorPair(light: 0xFFFFFF, dark: 0x2B2930)
        static let sunken = OLColorPair(light: 0xECEBE7, dark: 0x35333A)
        static let line = OLColorPair(light: 0xE7E5E0, dark: 0x3B3940)
        static let lineStrong = OLColorPair(light: 0x7D7A74, dark: 0x827F8A)
        static let ink = OLColorPair(light: 0x151417, dark: 0xF2F1F4)
        static let muted = OLColorPair(light: 0x6C6965, dark: 0xA09EA8)

        // Paper reference: neutral ink controls; semantic colors stay distinct.
        static let accent = OLColorPair(light: 0x151417, dark: 0xF2F1F4)
        static let onAccent = OLColorPair(light: 0xFFFFFF, dark: 0x151417)
        static let accentText = OLColorPair(light: 0x151417, dark: 0xF2F1F4)
        static let accentSoft = OLColorPair(light: 0xECEBE7, dark: 0x35333A)

        // Today
        static let today = OLColorPair(light: 0xCF7409, dark: 0xE8891A)
        static let onToday = OLColorPair(0x2A1800)
        static let todayText = OLColorPair(light: 0xA65700, dark: 0xF0A24A)
        static let todaySoft = OLColorPair(light: 0xFBEEDD, dark: 0x2B231E)

        // Danger
        static let danger = OLColorPair(light: 0xC23A28, dark: 0xFF7D6E)
        static let onDanger = OLColorPair(light: 0xFFFFFF, dark: 0x3A0F0A)
        static let dangerSoft = OLColorPair(light: 0xFBE5E1, dark: 0x3A2426)

        // Info, the Inbox's identity
        static let info = OLColorPair(light: 0x2F6FDC, dark: 0x76A6FF)
        /// Not in the CSS: `info` is 3.9:1 on the light canvas, short of AA
        /// for the 15 pt "6 to triage" eyebrow, so text takes a darker blue.
        static let infoText = OLColorPair(light: 0x2A60C0, dark: 0x76A6FF)
        static let onInfo = OLColorPair(light: 0xFFFFFF, dark: 0x10233F)

        // Success and teal
        static let success = OLColorPair(light: 0x2A9466, dark: 0x3A9772)
        static let successText = OLColorPair(light: 0x1C7750, dark: 0x5CC796)
        static let successSoft = OLColorPair(light: 0xE1F2E9, dark: 0x1F3329)
        static let teal = OLColorPair(light: 0x13786E, dark: 0x1C8F82)

        /// Not in the CSS: a medium-priority ring, since `today` orange already
        /// means due or starred. The Mac rings medium priority amber too.
        static let amber = OLColorPair(light: 0xC98A00, dark: 0xF2C14E)

        /// rgb(40, 30, 20), the warm shadow every light-mode elevation uses.
        static let warmShadow = OLColorPair(0x281E14)
    }

    static let canvas = Pair.canvas.color
    static let surface = Pair.surface.color
    static let sunken = Pair.sunken.color
    static let line = Pair.line.color
    static let lineStrong = Pair.lineStrong.color
    static let ink = Pair.ink.color
    static let muted = Pair.muted.color

    static let accent = Pair.accent.color
    static let onAccent = Pair.onAccent.color
    static let accentText = Pair.accentText.color
    static let accentSoft = Pair.accentSoft.color

    static let today = Pair.today.color
    static let onToday = Pair.onToday.color
    static let todayText = Pair.todayText.color
    static let todaySoft = Pair.todaySoft.color

    static let danger = Pair.danger.color
    static let onDanger = Pair.onDanger.color
    static let dangerSoft = Pair.dangerSoft.color

    static let info = Pair.info.color
    static let infoText = Pair.infoText.color
    static let onInfo = Pair.onInfo.color

    static let success = Pair.success.color
    static let successText = Pair.successText.color
    static let successSoft = Pair.successSoft.color
    static let teal = Pair.teal.color
    static let amber = Pair.amber.color

    // MARK: List tints

    /// The soft band behind a list's glyph: its card on Lists, its page header.
    enum Tint: String, CaseIterable, Sendable {
        case violet, green, amber, blue, rose, neutral

        var pair: OLColorPair {
            switch self {
            case .violet: OLColorPair(light: 0xE9E4F7, dark: 0x352D45)
            case .green: OLColorPair(light: 0xE1EEE6, dark: 0x2C3637)
            case .amber: OLColorPair(light: 0xF7EAD7, dark: 0x3A2F22)
            case .blue: OLColorPair(light: 0xDFE8F5, dark: 0x26303F)
            case .rose: OLColorPair(light: 0xF7E2E8, dark: 0x3A2630)
            case .neutral: OLColorPair(light: 0xEBE9E5, dark: 0x323037)
            }
        }

        var color: Color { pair.color }
    }

    /// The design draws six tints for the eleven list accents, so accents map
    /// to the tint of their colour family.
    static func tint(for accent: ListAccent) -> Tint {
        switch accent {
        case .violet, .indigo: .violet
        case .green, .teal: .green
        case .orange, .amber, .brown: .amber
        case .blue: .blue
        case .red, .pink: .rose
        case .graphite: .neutral
        }
    }

    // MARK: Heatmap

    /// A heatmap cell's fill for `ActivityBand.level` 0…4. Light is the
    /// mockup's accent at 0.2 / 0.4 / 0.65 / 1 over `sunken`. In dark, accent
    /// at 0.2 barely differs from `sunken`, so the steps lighten from the
    /// dark accent text over a slightly lifted empty cell instead.
    static func heat(_ level: Int) -> Color {
        let level = min(4, max(0, level))
        let light: (UInt32, Double) = [(Pair.sunken.light, 1), (Pair.accent.light, 0.2), (Pair.accent.light, 0.4),
                                       (Pair.accent.light, 0.65), (Pair.accent.light, 1)][level]
        let dark: (UInt32, Double) = [(0x3A3840, 1), (Pair.accentText.dark, 0.22), (Pair.accentText.dark, 0.42),
                                      (Pair.accentText.dark, 0.66), (Pair.accent.dark, 1)][level]
        return Color(uiColor: UIColor { traits in
            let (hex, alpha) = traits.userInterfaceStyle == .dark ? dark : light
            return OLColorPair.uiColor(hex, alpha: alpha)
        })
    }
}

/// Every token fixed to one appearance, for views that must not follow the
/// phone's: widget timelines, which are archived, and the Live Activity,
/// which the design draws on the dark palette in both.
nonisolated struct OLPalette: Sendable {
    let scheme: ColorScheme

    init(_ scheme: ColorScheme) { self.scheme = scheme }

    static let light = OLPalette(.light)
    static let dark = OLPalette(.dark)

    func color(_ pair: OLColorPair) -> Color { pair.resolved(scheme) }

    var canvas: Color { color(OL.Pair.canvas) }
    var surface: Color { color(OL.Pair.surface) }
    var sunken: Color { color(OL.Pair.sunken) }
    var line: Color { color(OL.Pair.line) }
    var lineStrong: Color { color(OL.Pair.lineStrong) }
    var ink: Color { color(OL.Pair.ink) }
    var muted: Color { color(OL.Pair.muted) }
    var accent: Color { color(OL.Pair.accent) }
    var onAccent: Color { color(OL.Pair.onAccent) }
    var accentText: Color { color(OL.Pair.accentText) }
    var accentSoft: Color { color(OL.Pair.accentSoft) }
    var today: Color { color(OL.Pair.today) }
    var todayText: Color { color(OL.Pair.todayText) }
    var danger: Color { color(OL.Pair.danger) }
    var dangerSoft: Color { color(OL.Pair.dangerSoft) }
    var info: Color { color(OL.Pair.info) }
    var infoText: Color { color(OL.Pair.infoText) }
    var onInfo: Color { color(OL.Pair.onInfo) }
    var success: Color { color(OL.Pair.success) }
    var successText: Color { color(OL.Pair.successText) }
    var successSoft: Color { color(OL.Pair.successSoft) }
    var teal: Color { color(OL.Pair.teal) }

    func tint(_ tint: OL.Tint) -> Color { color(tint.pair) }
}

/// The design's serif, Instrument Serif (OFL), bundled from Shared/Fonts and
/// listed under UIAppFonts in the app's and widget's Info.plist.
nonisolated enum OLSerif {
    static let fontName = "InstrumentSerif-Regular"

    /// Whether the face is installed. Registration from the bundle is the
    /// fallback for a process whose Info.plist didn't load it (a test host
    /// built without UIAppFonts, a preview).
    static let isAvailable: Bool = {
        if UIFont(name: fontName, size: 12) != nil { return true }
        guard let url = Bundle.main.url(forResource: fontName, withExtension: "ttf") else { return false }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        return UIFont(name: fontName, size: 12) != nil
    }()

    /// Instrument Serif at `size`, scaling with Dynamic Type from `style`,
    /// or the system serif when the face is missing.
    static func font(size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        isAvailable ? .custom(fontName, size: size, relativeTo: style) : .system(style, design: .serif)
    }

    /// At `size` and no other: widgets draw at their own fixed sizes.
    static func fixed(size: CGFloat) -> Font {
        isAvailable ? .custom(fontName, fixedSize: size) : .system(size: size, design: .serif)
    }
}
