//
//  WidgetStyle.swift
//  OpenlistWidget
//

import SwiftUI
import WidgetKit

/// The resolved colours and fonts every widget draws with.
///
/// Built once per render from the colour scheme, the rendering mode and the
/// app's accent, so views never branch on appearance themselves. Colours are
/// resolved here rather than through dynamic `NSColor`s because a widget's view
/// is archived and redrawn by the system, and plain values survive that.
nonisolated struct WidgetStyle: Equatable, Sendable {
    enum Mode: String, CaseIterable, Sendable {
        case light
        case dark
        /// The desktop's in-background look (and tinted widgets): the system
        /// strips colour, so every accent collapses to white and only shape and
        /// weight tell parts apart.
        case vibrant
    }

    let mode: Mode
    let serifTitles: Bool
    /// `false` when the system has removed the widget's background (for
    /// example on the desktop in vibrant mode), so views never paint a plate
    /// of their own in its place.
    let showsBackground: Bool

    // Surfaces and text.
    let bg: Color
    let ink: Color
    let sub: Color
    let faint: Color
    let line: Color
    let chip: Color
    let track: Color

    // Accents.
    let acc: Color
    let orange: Color
    let red: Color
    let green: Color
    let amber: Color
    let blue: Color
    let blueChip: Color
    /// Icons and checks drawn on an accent fill.
    let onAcc: Color
    let accShadow: Color
    /// Meeting blocks in the agenda.
    let meet: Color

    var isVibrant: Bool { mode == .vibrant }

    init(mode: Mode, accentHex: UInt32 = 0x7C4DF0, serifTitles: Bool = true, showsBackground: Bool = true) {
        self.mode = mode
        self.serifTitles = serifTitles
        self.showsBackground = showsBackground
        switch mode {
        case .light:
            let ink: UInt32 = 0x17161A
            bg = Self.rgb(0xFFFFFF)
            self.ink = Self.rgb(ink)
            sub = Self.rgb(ink, 0.58)
            faint = Self.rgb(ink, 0.36)
            line = Self.rgb(ink, 0.09)
            chip = Self.rgb(ink, 0.05)
            track = Self.rgb(ink, 0.08)
            acc = Self.rgb(accentHex)
            orange = Self.rgb(0xE0861F)
            red = Self.rgb(0xD8434B)
            green = Self.rgb(0x2F9E6E)
            amber = Self.rgb(0xE8A917)
            blue = Self.rgb(ListAccent.inboxHex)
            blueChip = Self.rgb(ListAccent.inboxHex, 0.12)
            onAcc = Self.rgb(0xFFFFFF)
            accShadow = Self.rgb(accentHex, 0.32)
            meet = Self.rgb(ink, 0.055)
        case .dark:
            let ink: UInt32 = 0xF4F2F7
            let accent = Self.darkAccent(accentHex)
            bg = Self.rgb(0x232128)
            self.ink = Self.rgb(ink)
            sub = Self.rgb(ink, 0.6)
            faint = Self.rgb(ink, 0.36)
            line = Self.rgb(ink, 0.1)
            chip = Self.rgb(ink, 0.08)
            track = Self.rgb(ink, 0.12)
            acc = Self.rgb(accent)
            orange = Self.rgb(0xF0A04B)
            red = Self.rgb(0xFF6B72)
            green = Self.rgb(0x4CC08A)
            amber = Self.rgb(0xF2C14E)
            blue = Self.rgb(0x6AA1F0)
            blueChip = Self.rgb(0x6AA1F0, 0.16)
            onAcc = Self.rgb(0xFFFFFF)
            accShadow = Self.rgb(accent, 0.3)
            meet = Self.rgb(ink, 0.08)
        case .vibrant:
            let white: UInt32 = 0xFFFFFF
            let accent = Self.rgb(white, 0.95)
            bg = Self.rgb(white, 0.18)
            ink = Self.rgb(white, 0.97)
            sub = Self.rgb(white, 0.74)
            faint = Self.rgb(white, 0.52)
            line = Self.rgb(white, 0.2)
            chip = Self.rgb(white, 0.14)
            track = Self.rgb(white, 0.24)
            acc = accent
            orange = accent
            red = accent
            green = accent
            amber = accent
            blue = accent
            blueChip = Self.rgb(white, 0.18)
            onAcc = Self.rgb(0x24202E, 0.82)
            accShadow = .clear
            meet = Self.rgb(white, 0.13)
        }
    }

    /// The style for the current render environment.
    ///
    /// Accented (tinted) and vibrant rendering both discard colour, so both use
    /// the white palette; full colour follows the light or dark appearance.
    init(colorScheme: ColorScheme, renderingMode: WidgetRenderingMode, showsBackground: Bool, snapshot: WidgetSnapshot) {
        let mode: Mode = if renderingMode == .vibrant || renderingMode == .accented {
            .vibrant
        } else {
            colorScheme == .dark ? .dark : .light
        }
        self.init(mode: mode, accentHex: snapshot.accentHex, serifTitles: snapshot.serifTitles, showsBackground: showsBackground)
    }

    static let light = WidgetStyle(mode: .light)
    static let dark = WidgetStyle(mode: .dark)
    static let vibrant = WidgetStyle(mode: .vibrant)

    // MARK: - List colours

    /// A list's own colour: checkbox rings, bars and progress. List colours
    /// are saturated enough to read on both backgrounds, so only vibrant
    /// rendering changes them.
    func listColor(_ hex: UInt32) -> Color {
        isVibrant ? Self.rgb(0xFFFFFF, 0.92) : Self.rgb(hex)
    }

    /// The soft fill behind a list's glyph and its agenda blocks.
    func listTint(_ hex: UInt32) -> Color {
        switch mode {
        case .light: Self.rgb(hex, 0.14)
        case .dark: Self.rgb(hex, 0.24)
        case .vibrant: Self.rgb(0xFFFFFF, 0.16)
        }
    }

    /// The ring colour for an open task: late or high-priority work is red,
    /// medium priority is amber, as the app's rows draw it (`NX.priorityStroke`),
    /// anything else wears its list's colour. Orange is Today's colour, so
    /// a medium task in orange would read as due rather than as a priority.
    func checkColor(for item: WidgetSnapshot.Item, isLate: Bool) -> Color {
        if isLate || item.priority >= 3 { return red }
        if item.priority == 2 { return amber }
        return listColor(item.accentHex)
    }

    /// Fill opacity for the activity heatmap's bands 1...4; band 0 draws
    /// `track` instead.
    static let heatOpacities: [Double] = [0, 0.28, 0.5, 0.75, 1]

    // MARK: - Fonts

    /// Instrument Serif, the app's display face, or the system serif when the
    /// font could not be registered.
    func serif(_ size: CGFloat) -> Font {
        WidgetFonts.hasSerif ? .custom(WidgetFonts.serifName, size: size) : .system(size: size, design: .serif)
    }

    /// Titles and big numbers. Follows the app's serif-titles setting: with it
    /// off, the app sets headers in bold system type about a fifth smaller,
    /// and so do widgets.
    func display(_ size: CGFloat) -> Font {
        serifTitles ? serif(size) : .system(size: size * 0.8, weight: .bold)
    }

    /// `ui-monospace` in the design: times, ranges and hour labels.
    func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    // MARK: - Colour maths

    static func rgb(_ hex: UInt32, _ opacity: Double = 1) -> Color {
        Color(.sRGB,
              red: Double((hex >> 16) & 0xFF) / 255,
              green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255,
              opacity: opacity)
    }

    /// The accent lifted for dark backgrounds. The default violet uses the
    /// design's hand-picked value; other accents are brightened and slightly
    /// desaturated the same way, which keeps them readable on #232128
    /// without glowing.
    static func darkAccent(_ hex: UInt32) -> UInt32 {
        if hex == 0x7C4DF0 { return 0x9B78FF }
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        let high = max(r, g, b), low = min(r, g, b)
        guard high > 0 else { return 0x9B9A9F }
        let brightness = min(1, high + 0.13)
        let saturation = (high - low) / high * 0.78
        // Rescale each channel from the old value range into the new one,
        // which keeps the hue.
        func channel(_ value: Double) -> UInt32 {
            let position = high > low ? (value - low) / (high - low) : 1
            let newLow = brightness * (1 - saturation)
            return UInt32(((newLow + (brightness - newLow) * position) * 255).rounded())
        }
        return channel(r) << 16 | channel(g) << 8 | channel(b)
    }
}

extension EnvironmentValues {
    /// Set by `WidgetCanvas`, so shared components pick up the widget's style
    /// without every call site passing it along.
    @Entry var widgetStyle: WidgetStyle = .light
}
