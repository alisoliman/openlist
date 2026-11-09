//
//  NextTheme.swift
//  openlist
//

import AppKit
import CoreText
import SwiftUI

/// Tokens for the Openlist Next interface: near-neutral paper surfaces, one
/// ink colour used at several strengths, grey states, and a small semantic
/// palette kept for what colour means: overdue, done and priority.
enum NX {
    // MARK: Surfaces

    // Close to neutral in both appearances, so no surface carries a hue: the
    // dark ones lost their violet cast, the light sidebar its beige.
    static let paper = dynamic(light: 0xFCFCFB, dark: 0x1C1C1E)
    static let sidebar = dynamic(light: 0xF4F4F2, dark: 0x232325)
    static let inspector = dynamic(light: 0xF8F8F7, dark: 0x202022)
    /// Raised cards, focused rows, popovers.
    static let card = dynamic(light: 0xFFFFFF, dark: 0x2A2A2D)
    /// Ink — every text and hairline colour is this at some opacity.
    static let ink = dynamic(light: 0x17161A, dark: 0xF1EFEC)
    /// The tray and other inverted surfaces.
    static let inverse = dynamic(light: 0x17161A, dark: 0x39393C)
    /// The one filled primary action on a surface, like triage's "Keep for
    /// later": solid ink, inverted in either appearance, with `onPrimary`
    /// words. It's the neutral accent's fill too.
    static let primaryButton = ink
    static let primaryButtonHover = dynamic(light: 0x34333A, dark: 0xD9D7D3)
    static let onPrimary = paper

    static func ink(_ opacity: Double) -> Color { ink.opacity(opacity) }

    // MARK: States

    // Grey in every accent: selection, hover, chips and highlights never
    // take the accent's hue, so colour is left to what it means.

    /// The pointer's wash on rows, menu items and quiet buttons.
    static let hoverFill = ink(0.05)
    /// A selected row or tile.
    static let selectedFill = ink(0.075)
    /// A chip or pill that's on, a step darker than the grey chips at rest,
    /// like capture's destination.
    static let chosenFill = ink(0.12)
    /// Where something just landed, like a fresh row or a search hit, as it
    /// eases out.
    static let highlightFill = ink(0.065)
    /// The quiet ring around a focused row or a chosen tile.
    static let selectedRing = ink(0.14)
    /// Where a drag would land: a list, the inspector, a calendar column.
    static let dropRing = ink(0.35)
    /// Native switches and sliders while the accent is Neutral: the ink in
    /// light mode, a lighter grey in dark mode, where a white knob on white
    /// ink would disappear.
    static let controlTint = dynamic(light: 0x2E2D33, dark: 0x8F8C95)

    // MARK: Text

    // Text below full ink comes in three strengths, each tuned per
    // appearance so it keeps its contrast on paper, cards and the sidebar.
    // Use these for words; `ink(_:)` stays for fills, hairlines and symbols.

    /// Reading text under a title: notes, text lines, descriptions, a
    /// sidebar's unselected names. About 7:1 on paper.
    static let textSecondary = Color(nsColor: NXEditor.secondaryInk)
    /// Metadata: subtitles, crumbs, chip and field labels, times, counts
    /// beside a title, section labels. At least 4.5:1 on paper.
    static let textTertiary = Color(nsColor: NXEditor.inkColor(light: 0.62, dark: 0.56))
    /// Placeholders, hints, key caps' labels and disabled words: legible
    /// but out of the way. About 3:1 on paper.
    static let textQuaternary = Color(nsColor: NXEditor.placeholderInk)

    // MARK: Semantic

    static let green = Color(hex: 0x2F9E6E)
    /// The text variants: the design's chip text hexes in light mode, lighter
    /// in dark mode so they stay legible on their own tinted chip fill.
    static let greenText = dynamic(light: 0x23865B, dark: 0x5CC596)
    static let red = Color(hex: 0xD8434B)
    static let redText = dynamic(light: 0xC03A42, dark: 0xF07A80)
    static let amber = Color(hex: 0xE8A917)
    static let amberText = dynamic(light: 0xA87A06, dark: 0xE8B84A)
    /// The Inbox's own colour, which its glyph wears as a list's does.
    static let inbox = Color(hex: ListAccent.inboxHex)

    /// A checkbox's ring by priority: softened, so a list of prioritised
    /// tasks reads as titles first and a column of colour second.
    static func priorityStroke(_ priority: TaskPriority) -> Color? {
        switch priority {
        case .high: red.opacity(0.85)
        case .medium: amber.opacity(0.7)
        case .low: inbox.opacity(0.7)
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
    /// and the serif's line as SwiftUI lays it out (`serifLineHeight`).
    /// Negative: the design packs Instrument Serif tighter than its metrics.
    static func serifLeading(_ size: CGFloat, lineHeight: CGFloat) -> CGFloat {
        guard let line = serifLineHeight(size) else { return 0 }
        return (size * lineHeight - line) / 2
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

// MARK: - Hairlines

/// A rule one device pixel thick: half a point on a Retina display and a
/// whole point on a 1x one, where a half-point line falls between pixels and
/// fades to nothing, as the calendar's hour lines and the toolbar's foot did.
struct NXHairline: View {
    let color: Color
    var axis: Axis = .horizontal
    @Environment(\.displayScale) private var displayScale

    init(_ color: Color, axis: Axis = .horizontal) {
        self.color = color
        self.axis = axis
    }

    var body: some View {
        let thickness = 1 / displayScale
        Rectangle().fill(color)
            .frame(width: axis == .vertical ? thickness : nil, height: axis == .horizontal ? thickness : nil)
    }
}

/// A shape's border one device pixel thick, as `NXHairline` draws a rule.
struct NXHairlineBorder<S: InsettableShape>: View {
    let shape: S
    let color: Color
    @Environment(\.displayScale) private var displayScale

    init(_ shape: S, _ color: Color) {
        self.shape = shape
        self.color = color
    }

    var body: some View {
        shape.strokeBorder(color, lineWidth: 1 / displayScale)
    }
}

/// Per-window style resolved from settings and the system reduce-motion flag.
struct NextStyle: Equatable {
    /// The accent the settings choose. It marks only the caret and focus,
    /// primary buttons, progress, links and on-states; selection, hover,
    /// chips and icons stay grey whatever it is.
    var accentChoice: NextAccent = .neutral
    /// Multiplies the durations the design paces with ms() (rows, screens,
    /// triage, the inspector): 0.6 restrained, 1 expressive, 1.2 playful, 0.4
    /// reduced. Its fixed timings go through `NX` instead.
    var motion: Double = 1
    /// Whether the checkbox's bounce and ring play, as the design's lively().
    var lively = true
    /// Whether the inspector, notch, bottom bars and overlay cards slide in,
    /// Trash's restored row slides out, chips, the selection check and lifted
    /// cards rise into place, and the tick and switch knob overshoot. Reduce
    /// Motion fades and eases them instead, as its hint promises.
    var slides = true
    var dwell: Double = 5
    var compact = false
    var serifTitles = true

    var rowVerticalPadding: CGFloat { compact ? 3 : 5 }
    /// The accent's colour: the ink while it's Neutral, else its hue.
    var accent: Color { accentChoice.color }
    /// Words and symbols on a filled accent: the paper on ink, white on a hue.
    var onAccent: Color { accentChoice == .neutral ? NX.onPrimary : .white }
    /// A filled accent button under the pointer. The ink lifts a step toward
    /// the paper; a hue takes 0x12 off each sRGB channel, as the design's
    /// Planned now Start goes from #7C4DF0 to #6A3BDE.
    var accentHover: Color {
        guard accentChoice != .neutral, let rgb = NSColor(accent).usingColorSpace(.sRGB) else { return NX.primaryButtonHover }
        let shade = { (value: CGFloat) in max(0, value - 0x12 / 255) }
        return Color(.sRGB, red: shade(rgb.redComponent), green: shade(rgb.greenComponent),
                     blue: shade(rgb.blueComponent), opacity: rgb.alphaComponent)
    }
    /// The tint native controls take, a switch's or slider's on-state: a
    /// grey that keeps their white knob in sight while the accent is Neutral.
    var controlTint: Color { accentChoice == .neutral ? NX.controlTint : accent }
    /// A text field's border while it has focus.
    var focusRing: Color { accent.opacity(accentChoice == .neutral ? 0.38 : 0.6) }
    func ms(_ base: Double) -> Double { (base * motion).rounded() }
    func ease(_ base: Double) -> Animation { NX.ease(ms(base)) }
    func spring(_ base: Double) -> Animation { lively ? NX.spring(ms(base)) : NX.ease(ms(base)) }
    func standard(_ base: Double) -> Animation { NX.standard(ms(base)) }
    func cssEase(_ base: Double) -> Animation { NX.cssEase(ms(base)) }
    /// The design's fixed overshooting spring, like its tick's and switch
    /// knob's, whatever the Motion setting. Reduce Motion eases instead.
    func bounce(_ ms: Double) -> Animation { slides ? NX.spring(ms) : NX.ease(ms) }
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
    /// instance across renders, so as a `BlockTextView.accentColor` it's set
    /// on the text view only when it changes, where `NSColor(style.accent)`
    /// would be a new colour on every update.
    var editorColor: NSColor {
        switch self {
        case .neutral: NXEditor.ink
        case .violet: NXEditor.accentViolet
        case .blue: NXEditor.accentBlue
        case .green: NXEditor.accentGreen
        case .orange: NXEditor.accentOrange
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
