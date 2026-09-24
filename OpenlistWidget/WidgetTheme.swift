//
//  WidgetTheme.swift
//  OpenlistWidget
//

import AppKit
import CoreText
import SwiftUI
import WidgetKit

/// The widget design's palette (`pal(mode)` in `docs/design/openlist-next-v2/widgets/widget.jsx`).
///
/// The widget can't import the app's Next tokens, and its dark palette differs
/// from them anyway, so the design's values live here literally.
struct WidgetPalette {
    enum Mode: String, CaseIterable, Sendable {
        case light, dark
        /// The desktop's in-background (vibrant) and tinted renderings: whites at
        /// several strengths, every accent collapsed to white.
        case dimmed
    }

    let mode: Mode
    let bg, ink, sub, faint, line, chip, track: Color
    let acc, orange, red, green, amber, blue, bluechip: Color
    let onacc, accshadow, meet: Color
    /// `sub` and `faint` are one solid colour at these opacities. The browser
    /// draws emoji in a text's alpha too, so lines that carry a list's emoji use
    /// the solid colour and fade as a whole.
    let solid: Color
    let subOpacity, faintOpacity: Double

    var isDimmed: Bool { mode == .dimmed }

    init(_ mode: Mode) {
        self.mode = mode
        switch mode {
        case .light: solid = Color(hex: 0x17161A); subOpacity = 0.58; faintOpacity = 0.36
        case .dark: solid = Color(hex: 0xF4F2F7); subOpacity = 0.6; faintOpacity = 0.36
        case .dimmed: solid = Color(hex: 0xFFFFFF); subOpacity = 0.74; faintOpacity = 0.52
        }
        switch mode {
        case .light:
            bg = Color(hex: 0xFFFFFF); ink = Color(hex: 0x17161A)
            sub = Color(hex: 0x17161A, opacity: 0.58); faint = Color(hex: 0x17161A, opacity: 0.36)
            line = Color(hex: 0x17161A, opacity: 0.09); chip = Color(hex: 0x17161A, opacity: 0.05)
            track = Color(hex: 0x17161A, opacity: 0.08)
            acc = Color(hex: 0x7C4DF0); orange = Color(hex: 0xE0861F); red = Color(hex: 0xD8434B)
            green = Color(hex: 0x2F9E6E); amber = Color(hex: 0xE8A917); blue = Color(hex: 0x3A7BD8)
            bluechip = Color(hex: 0x3A7BD8, opacity: 0.12); onacc = Color(hex: 0xFFFFFF)
            accshadow = Color(hex: 0x7C4DF0, opacity: 0.32); meet = Color(hex: 0x17161A, opacity: 0.055)
        case .dark:
            bg = Color(hex: 0x232128); ink = Color(hex: 0xF4F2F7)
            sub = Color(hex: 0xF4F2F7, opacity: 0.6); faint = Color(hex: 0xF4F2F7, opacity: 0.36)
            line = Color(hex: 0xF4F2F7, opacity: 0.1); chip = Color(hex: 0xF4F2F7, opacity: 0.08)
            track = Color(hex: 0xF4F2F7, opacity: 0.12)
            acc = Color(hex: 0x9B78FF); orange = Color(hex: 0xF0A04B); red = Color(hex: 0xFF6B72)
            green = Color(hex: 0x4CC08A); amber = Color(hex: 0xF2C14E); blue = Color(hex: 0x6AA1F0)
            bluechip = Color(hex: 0x6AA1F0, opacity: 0.16); onacc = Color(hex: 0xFFFFFF)
            accshadow = Color(hex: 0x9B78FF, opacity: 0.3); meet = Color(hex: 0xF4F2F7, opacity: 0.08)
        case .dimmed:
            let white = Color(hex: 0xFFFFFF, opacity: 0.95)
            bg = Color(hex: 0xFFFFFF, opacity: 0.18); ink = Color(hex: 0xFFFFFF, opacity: 0.97)
            sub = Color(hex: 0xFFFFFF, opacity: 0.74); faint = Color(hex: 0xFFFFFF, opacity: 0.52)
            line = Color(hex: 0xFFFFFF, opacity: 0.2); chip = Color(hex: 0xFFFFFF, opacity: 0.14)
            track = Color(hex: 0xFFFFFF, opacity: 0.24)
            acc = white; orange = white; red = white; green = white; amber = white; blue = white
            bluechip = Color(hex: 0xFFFFFF, opacity: 0.18); onacc = Color(hex: 0x24202E, opacity: 0.82)
            accshadow = .clear; meet = Color(hex: 0xFFFFFF, opacity: 0.13)
        }
    }

    /// Full colour follows the appearance; the desktop's in-background and
    /// tinted renderings get the design's dimmed palette.
    static func resolve(colorScheme: ColorScheme, renderingMode: WidgetRenderingMode) -> WidgetPalette {
        if renderingMode == .fullColor { return WidgetPalette(colorScheme == .dark ? .dark : .light) }
        return WidgetPalette(.dimmed)
    }

    /// A list's own colour (`col(c)`): white once dimmed.
    func col(_ accent: String?) -> Color {
        isDimmed ? Color(hex: 0xFFFFFF, opacity: 0.92) : accent.map(Self.listColor) ?? sub
    }

    /// A list's soft fill (`tint(c)`): its colour at 0x24 in light, 0x3D in dark.
    func tint(_ accent: String?) -> Color {
        if isDimmed { return Color(hex: 0xFFFFFF, opacity: 0.16) }
        return Self.listColor(accent ?? "graphite").opacity(mode == .dark ? 0x3D / 255 : 0x24 / 255)
    }

    /// A `ListAccent` raw value, or an exact `#RRGGBB` the design samples use.
    static func listColor(_ accent: String) -> Color {
        if let named = ListAccent(rawValue: accent) { return named.color }
        if accent.hasPrefix("#"), let hex = UInt32(accent.dropFirst(), radix: 16) { return Color(hex: hex) }
        return ListAccent.graphite.color
    }
}

extension EnvironmentValues {
    @Entry var widgetPalette = WidgetPalette(.light)
    /// Previews outside WidgetKit: the running clock stops at the entry's date,
    /// and links draw as their labels, which an offscreen renderer can't host.
    @Entry var widgetIsPreview = false
}

/// A `Link`, or its label alone in previews.
struct WidgetLink<Label: View>: View {
    let destination: URL
    @ViewBuilder var label: Label
    @Environment(\.widgetIsPreview) private var isPreview

    var body: some View {
        if isPreview { label } else { Link(destination: destination) { label } }
    }
}

/// Resolves the palette for the rendering the system asked for.
struct WidgetPaletteReader<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetRenderingMode) private var renderingMode
    @ViewBuilder var content: (WidgetPalette) -> Content

    var body: some View {
        let palette = WidgetPalette.resolve(colorScheme: colorScheme, renderingMode: renderingMode)
        content(palette).environment(\.widgetPalette, palette)
    }
}

// MARK: - Type

/// A face from the design's CSS: `-apple-system`, `ui-monospace` or the
/// display serif, at a CSS weight taken literally (500 medium, 600 semibold,
/// 700 bold).
struct WidgetFace {
    enum Family { case sans, mono, serif }

    var family: Family
    var size: CGFloat
    var weight: Font.Weight

    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Self { Self(family: .sans, size: size, weight: weight) }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Self { Self(family: .mono, size: size, weight: weight) }
    static func serif(_ size: CGFloat) -> Self { Self(family: .serif, size: size, weight: .regular) }

    static let serifName = "InstrumentSerif-Regular"
    /// Checked on each use: the font is registered when the bundle loads.
    static var hasSerif: Bool { NSFont(name: serifName, size: 12) != nil }

    var font: Font {
        switch family {
        case .sans: .system(size: size, weight: weight)
        case .mono: .system(size: size, weight: weight, design: .monospaced)
        case .serif: Self.hasSerif ? .custom(Self.serifName, size: size) : .system(size: size, design: .serif)
        }
    }

    /// The distance SwiftUI puts between wrapped lines of this face, before any
    /// line spacing: the system face's whole-point line heights.
    var linePitch: CGFloat {
        guard family != .serif else { return size * 1.3 }
        let measured: [CGFloat: CGFloat] = [9: 11, 9.5: 12, 10: 13, 10.5: 13, 11: 14, 11.5: 14, 12: 15, 13: 16, 14: 17, 15: 19]
        return measured[size] ?? (size * 1.2).rounded(.up)
    }

    /// The whole-point ascent and descent the design's browser lays this face
    /// out with. The system face's differ from the ones AppKit reports, so the
    /// sizes the design uses are measured; others follow their proportions.
    var metrics: (ascent: CGFloat, descent: CGFloat) {
        switch family {
        case .sans:
            let measured: [CGFloat: (CGFloat, CGFloat)] = [9: (8, 2), 9.5: (8, 2), 10: (10, 3), 10.5: (10, 3), 11: (10, 3),
                                                           11.5: (11, 3), 12: (11, 3), 13: (12, 3), 14: (13, 4), 15: (13, 4)]
            return measured[size] ?? ((size * 0.9).rounded(), (size * 0.25).rounded())
        case .mono:
            let measured: [CGFloat: (CGFloat, CGFloat)] = [9: (8, 2), 9.5: (9, 2), 10: (9, 2), 19: (18, 4)]
            return measured[size] ?? ((size * 0.93).rounded(), (size * 0.24).rounded())
        case .serif:
            guard let font = NSFont(name: Self.serifName, size: size) else { return ((size * 0.99).rounded(), (size * 0.31).rounded()) }
            return (font.ascender.rounded(), (-font.descender).rounded())
        }
    }
}

extension View {
    /// Sets `face` and lays the text out in the CSS line box `size × lineHeight`,
    /// its first baseline where the browser puts it, so stacked gaps match.
    func css(_ face: WidgetFace, line lineHeight: CGFloat) -> some View {
        let box = face.size * lineHeight
        let metrics = face.metrics
        // The browser splits the leading around the face's ascent and descent,
        // giving the top half its floor.
        let baseline = metrics.ascent + ((box - metrics.ascent - metrics.descent) / 2).rounded(.down)
        // Wrapped lines step by the line box, not SwiftUI's own pitch.
        let spacing = max(0, box - face.linePitch)
        return CSSLineBox(box: box, baseline: baseline).callAsFunction { self.font(face.font).lineSpacing(spacing) }
    }
}

/// One text in its CSS line box, its first baseline at `baseline`; wrapped
/// lines follow at the pitch `css` sets.
private struct CSSLineBox: Layout {
    var box: CGFloat
    var baseline: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let text = subviews.first else { return .zero }
        let d = text.dimensions(in: ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: d.width, height: box + d[.lastTextBaseline] - d[.firstTextBaseline])
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let text = subviews.first else { return }
        let size = ProposedViewSize(width: bounds.width, height: nil)
        let d = text.dimensions(in: size)
        text.place(at: CGPoint(x: bounds.minX, y: bounds.minY + baseline - d[.firstTextBaseline]), anchor: .topLeading, proposal: size)
    }

    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: Subviews, cache: inout ()) -> CGFloat? {
        if guide == .firstTextBaseline { return bounds.minY + baseline }
        if guide == .lastTextBaseline { return bounds.maxY - (box - baseline) }
        return nil
    }
}

// MARK: - Fonts

enum WidgetFonts {
    /// Registers the bundled display serif for this process. The Info.plist's
    /// `ATSApplicationFontsPath` makes it available to the renderer as well.
    static func register(bundle: Bundle = .main) {
        guard !WidgetFace.hasSerif,
              let url = bundle.url(forResource: WidgetFace.serifName, withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

// MARK: - Sizes

/// The design's sizes, and the width and height it draws each at.
enum WidgetSize: String, CaseIterable, Sendable {
    case small, medium, large, xl

    init(_ family: WidgetFamily) {
        switch family {
        case .systemSmall: self = .small
        case .systemLarge: self = .large
        case .systemExtraLarge: self = .xl
        default: self = .medium
        }
    }

    /// `DIMS` in the design.
    var designSize: CGSize {
        switch self {
        case .small: CGSize(width: 170, height: 170)
        case .medium: CGSize(width: 358, height: 170)
        case .large: CGSize(width: 358, height: 358)
        case .xl: CGSize(width: 734, height: 358)
        }
    }

    /// The root padding: 14 pt at small size, 15 by 16 otherwise.
    var padding: EdgeInsets {
        self == .small ? EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
            : EdgeInsets(top: 15, leading: 16, bottom: 15, trailing: 16)
    }
}
