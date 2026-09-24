//
//  NextTheme.swift
//  openlist
//

import AppKit
import CoreText
import SwiftUI

/// Tokens for the Openlist Next interface: warm paper surfaces, one ink colour
/// used at several strengths, and a small semantic palette.
enum NX {
    // MARK: Surfaces

    static let paper = dynamic(light: 0xFCFBFA, dark: 0x1D1C20)
    static let sidebar = dynamic(light: 0xF1EEEA, dark: 0x252328)
    static let inspector = dynamic(light: 0xF7F5F2, dark: 0x222025)
    /// Raised cards, focused rows, popovers.
    static let card = dynamic(light: 0xFFFFFF, dark: 0x2B292F)
    /// Ink — every text and hairline colour is this at some opacity.
    static let ink = dynamic(light: 0x17161A, dark: 0xF1EFEC)
    /// The tray and other inverted surfaces.
    static let inverse = dynamic(light: 0x17161A, dark: 0x3A3740)
    /// Filled primary buttons, like triage's "Keep for later".
    static let primaryButton = dynamic(light: 0x17161A, dark: 0x3A3740)
    static let primaryButtonHover = dynamic(light: 0x2C2A31, dark: 0x46434C)

    static func ink(_ opacity: Double) -> Color { ink.opacity(opacity) }

    // MARK: Semantic

    static let green = Color(hex: 0x2F9E6E)
    /// The text variants: the design's chip text hexes in light mode, lighter
    /// in dark mode so they stay legible on their own tinted chip fill.
    static let greenText = dynamic(light: 0x23865B, dark: 0x5CC596)
    static let red = Color(hex: 0xD8434B)
    static let redText = dynamic(light: 0xC03A42, dark: 0xF07A80)
    static let amber = Color(hex: 0xE8A917)
    static let amberText = dynamic(light: 0xA87A06, dark: 0xE8B84A)
    static let inbox = Color(hex: 0x3A7BD8)
    static let today = Color(hex: 0xE0861F)
    static let lists = Color(hex: 0x5B5BD6)
    static let grey = Color(hex: 0x6E6A73)

    static func priorityStroke(_ priority: TaskPriority) -> Color? {
        switch priority {
        case .high: red
        case .medium: amber
        case .low: inbox
        case .none: nil
        }
    }

    // MARK: Type

    /// Looked up once, after `registerFonts()` has run at launch.
    private static let hasSerif = NSFont(name: "InstrumentSerif-Regular", size: 12) != nil

    static func serif(_ size: CGFloat) -> Font {
        hasSerif ? .custom("InstrumentSerif-Regular", size: size) : .system(size: size, design: .serif)
    }

    /// Half the difference between the design's CSS line box (`size × lineHeight`)
    /// and the serif's own ascent and descent, which SwiftUI uses for its line.
    /// Negative: the design packs Instrument Serif tighter than its metrics.
    static func serifLeading(_ size: CGFloat, lineHeight: CGFloat) -> CGFloat {
        guard let font = NSFont(name: "InstrumentSerif-Regular", size: size) else { return 0 }
        return (size * lineHeight - (font.ascender - font.descender)) / 2
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// Registers the bundled display face once per process.
    static func registerFonts() {
        guard let url = Bundle.main.url(forResource: "InstrumentSerif-Regular", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    // MARK: Motion

    /// `cubic-bezier(0.2, 0.9, 0.2, 1)` — the house ease-out.
    static func ease(_ ms: Double) -> Animation { .timingCurve(0.2, 0.9, 0.2, 1, duration: ms / 1000) }
    /// `cubic-bezier(0.34, 1.56, 0.64, 1)` — the overshooting spring.
    static func spring(_ ms: Double) -> Animation { .timingCurve(0.34, 1.56, 0.64, 1, duration: ms / 1000) }
    static func standard(_ ms: Double) -> Animation { .timingCurve(0.4, 0, 0.2, 1, duration: ms / 1000) }
    /// CSS's plain `ease`, `cubic-bezier(0.25, 0.1, 0.25, 1)`.
    static func cssEase(_ ms: Double) -> Animation { .timingCurve(0.25, 0.1, 0.25, 1, duration: ms / 1000) }

    // MARK: Shadows

    static let shadowWarm = Color(red: 40 / 255, green: 30 / 255, blue: 20 / 255)

    // MARK: Helpers

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

/// Per-window style resolved from settings and the system reduce-motion flag.
struct NextStyle: Equatable {
    var accent: Color = NextAccent.violet.color
    /// Multiplies animation durations: 0.6 restrained, 1 expressive, 1.2 playful, 0.4 reduced.
    var motion: Double = 1
    /// Whether bounces, rings and pops play.
    var lively = true
    /// Whether the inspector, notch, bottom bars and overlay cards slide in.
    /// Reduce Motion fades them instead, as its hint promises.
    var slides = true
    var dwell: Double = 5
    var compact = false
    var serifTitles = true

    var rowVerticalPadding: CGFloat { compact ? 3 : 5 }
    func ms(_ base: Double) -> Double { (base * motion).rounded() }
    func ease(_ base: Double) -> Animation { NX.ease(ms(base)) }
    func spring(_ base: Double) -> Animation { lively ? NX.spring(ms(base)) : NX.ease(ms(base)) }
    func standard(_ base: Double) -> Animation { NX.standard(ms(base)) }
    func cssEase(_ base: Double) -> Animation { NX.cssEase(ms(base)) }
    /// `transition`, or a fade where the style doesn't slide.
    func slide(_ transition: AnyTransition) -> AnyTransition { slides ? transition : .opacity }
}

private struct NextStyleKey: EnvironmentKey {
    static let defaultValue = NextStyle()
}

extension EnvironmentValues {
    var nextStyle: NextStyle {
        get { self[NextStyleKey.self] }
        set { self[NextStyleKey.self] = newValue }
    }
}

extension NextAccent {
    /// The accent as one of the editor's shared colours. It stays the same
    /// instance across renders, so it can be a `BlockTextView.strikeColor`
    /// where `NSColor(style.accent)` would restyle the text on every update.
    var editorColor: NSColor {
        switch self {
        case .violet: Theme.Editor.accentViolet
        case .blue: Theme.Editor.accentBlue
        case .green: Theme.Editor.accentGreen
        case .orange: Theme.Editor.accentOrange
        }
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}
