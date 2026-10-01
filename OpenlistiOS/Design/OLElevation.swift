//
//  OLElevation.swift
//  OpenlistiOS
//

import SwiftUI

/// The design's three shadows and the dark theme's card ring. A CSS blur is
/// about twice a SwiftUI radius; shadows go on the background shape, never
/// the content, so text doesn't cast one.
enum OLShadow {
    /// `--shadow-card`.
    case card
    /// `--shadow-float`: the dock, bulk bar and tray.
    case float
    /// `--shadow-fab`: the + and the primary work buttons.
    case fab
}

extension View {
    /// Casts one of the design's shadows, as each appearance draws it.
    func olShadow(_ shadow: OLShadow) -> some View {
        modifier(OLShadowModifier(shadow: shadow))
    }

    /// Casts one of the design's shadows around a Liquid Glass view in
    /// `shape`. `.shadow` never sees the glass, which the system draws in a
    /// layer of its own, so a copy of the shape in `fill` casts it from
    /// behind, cut away inside the shape so the glass still shows what
    /// scrolls under it.
    func olGlassShadow<S: Shape>(_ shadow: OLShadow, in shape: S, fill: Color) -> some View {
        background {
            shape.fill(fill)
                .olShadow(shadow)
                .mask { OLShadowCutout(shape: shape).fill(style: FillStyle(eoFill: true)) }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// The dark theme's 1 pt `line` ring round a raised shape (`--card-ring`):
    /// a disc, a tile, a raised button.
    func olDarkRing<S: InsettableShape>(_ shape: S) -> some View {
        modifier(OLDarkRing(shape: shape))
    }

    /// A card (`.card`): the surface, radius 20, the card shadow, and in dark
    /// a 1 pt ring in `line`, with the content clipped to the shape.
    func olCard(radius: CGFloat = 20, fill: Color = OL.surface) -> some View {
        modifier(OLCardModifier(radius: radius, fill: fill))
    }
}

/// Everything around `shape` out to the widest shadow's reach, and not the
/// shape itself (drawn even-odd).
nonisolated private struct OLShadowCutout<S: Shape>: Shape {
    let shape: S

    func path(in rect: CGRect) -> Path {
        var path = Path(rect.insetBy(dx: -64, dy: -64))
        path.addPath(shape.path(in: rect))
        return path
    }
}

private struct OLShadowModifier: ViewModifier {
    let shadow: OLShadow
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let warm = OL.Pair.warmShadow.resolved(.light)
        switch (shadow, scheme) {
        case (.card, .dark):
            content.shadow(color: .black.opacity(0.25), radius: 4, y: 2)
        case (.card, _):
            content
                .shadow(color: warm.opacity(0.05), radius: 1, y: 1)
                .shadow(color: warm.opacity(0.06), radius: 9, y: 6)
        case (.float, .dark):
            content.shadow(color: .black.opacity(0.5), radius: 14, y: 8)
        case (.float, _):
            content
                .shadow(color: warm.opacity(0.08), radius: 6, y: 4)
                .shadow(color: warm.opacity(0.12), radius: 20, y: 16)
        case (.fab, _):
            content.shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.20), radius: 12, y: 8)
        }
    }
}

private struct OLCardModifier: ViewModifier {
    let radius: CGFloat
    let fill: Color
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .clipShape(shape)
            .background { shape.fill(fill).olShadow(.card) }
            .overlay {
                if scheme == .dark { shape.strokeBorder(OL.line, lineWidth: 1) }
            }
    }
}

private struct OLDarkRing<S: InsettableShape>: ViewModifier {
    let shape: S
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content.overlay {
            if scheme == .dark { shape.strokeBorder(OL.line, lineWidth: 1) }
        }
    }
}
