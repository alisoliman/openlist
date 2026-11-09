//
//  DesignTokenTests.swift
//  OpenlistiOSTests
//

import SwiftUI
import Testing
import UIKit
@testable import OpenlistiOS

/// The tokens' values, in both appearances: monochrome, as the Mac's.
struct DesignTokenTests {
    /// Every colour token the app draws with, light and dark.
    static let tokens: [(String, OLColorPair, UInt32, UInt32)] = [
        ("canvas", OL.Pair.canvas, 0xF4F4F2, 0x1C1C1E),
        ("surface", OL.Pair.surface, 0xFFFFFF, 0x2A2A2D),
        ("sunken", OL.Pair.sunken, 0xECECEA, 0x343437),
        ("line", OL.Pair.line, 0xE7E7E5, 0x3A3A3D),
        ("line-strong", OL.Pair.lineStrong, 0x7C7C7A, 0x818184),
        ("ink", OL.Pair.ink, 0x151417, 0xF2F1F4),
        ("muted", OL.Pair.muted, 0x6B6B69, 0x9F9FA2),
        ("accent", OL.Pair.accent, 0x151417, 0xF2F1F4),
        ("on-accent", OL.Pair.onAccent, 0xFFFFFF, 0x151417),
        ("accent-text", OL.Pair.accentText, 0x151417, 0xF2F1F4),
        ("accent-soft", OL.Pair.accentSoft, 0xECECEA, 0x343437),
        ("control-tint", OL.Pair.controlTint, 0x2E2E31, 0x8F8F92),
        ("star", OL.Pair.star, 0xCF7409, 0xE8891A),
        ("star-text", OL.Pair.starText, 0xA65700, 0xF0A24A),
        ("danger", OL.Pair.danger, 0xC23A28, 0xFF7D6E),
        ("on-danger", OL.Pair.onDanger, 0xFFFFFF, 0x3A0F0A),
        ("danger-soft", OL.Pair.dangerSoft, 0xFBE5E1, 0x3A2426),
        ("info", OL.Pair.info, 0x2F6FDC, 0x76A6FF),
        ("success", OL.Pair.success, 0x2A9466, 0x3A9772),
        ("success-text", OL.Pair.successText, 0x1C7750, 0x5CC796),
        ("success-soft", OL.Pair.successSoft, 0xE1F2E9, 0x1F3329),
        ("amber", OL.Pair.amber, 0xC98A00, 0xF2C14E),
    ]

    /// The surfaces, greys and the accent: no hue in either appearance.
    static let neutrals: [(String, OLColorPair)] = [
        ("canvas", OL.Pair.canvas), ("surface", OL.Pair.surface), ("sunken", OL.Pair.sunken),
        ("line", OL.Pair.line), ("line-strong", OL.Pair.lineStrong), ("ink", OL.Pair.ink),
        ("muted", OL.Pair.muted), ("accent", OL.Pair.accent), ("on-accent", OL.Pair.onAccent),
        ("accent-text", OL.Pair.accentText), ("accent-soft", OL.Pair.accentSoft),
        ("control-tint", OL.Pair.controlTint),
    ]

    @Test func pairsHoldTheirValues() {
        for (name, pair, light, dark) in Self.tokens {
            #expect(pair.light == light, "\(name) light")
            #expect(pair.dark == dark, "\(name) dark")
        }
    }

    /// The colours views draw with follow the trait collection.
    @Test func dynamicColoursResolvePerAppearance() {
        for (name, pair, light, dark) in Self.tokens {
            #expect(Self.hex(pair.uiColor, .light) == light, "\(name) light")
            #expect(Self.hex(pair.uiColor, .dark) == dark, "\(name) dark")
        }
        #expect(Self.hex(UIColor(OL.canvas), .dark) == 0x1C1C1E)
        #expect(Self.hex(UIColor(OL.canvas), .light) == 0xF4F4F2)
        #expect(Self.hex(UIColor(OL.band), .light) == OL.Pair.sunken.light)
        #expect(Self.hex(UIColor(OL.band), .dark) == OL.Pair.sunken.dark)
    }

    /// Widgets and the Live Activity draw one appearance whatever the phone's.
    @Test func palettesAreFixed() {
        #expect(Self.hex(UIColor(OLPalette.dark.surface), .light) == 0x2A2A2D)
        #expect(Self.hex(UIColor(OLPalette.light.ink), .dark) == 0x151417)
    }

    /// The surfaces lost their warm and violet casts, as the Mac's did: no
    /// channel strays more than 3 from the others, as the Mac's cool dark
    /// greys (`NX.card`'s 0x2A2A2D) at most.
    @Test func neutralTokensCarryNoHue() {
        for (name, pair) in Self.neutrals {
            for (appearance, hex) in [("light", pair.light), ("dark", pair.dark)] {
                let channels = [hex >> 16 & 0xFF, hex >> 8 & 0xFF, hex & 0xFF]
                #expect(channels.max()! - channels.min()! <= 3, "\(name) \(appearance) has a hue")
            }
        }
    }

    /// Muted words stay AA on every surface they sit on, and an open
    /// checkbox's ring stays 3:1 on a card.
    @Test func greysKeepTheirContrast() {
        for background in [OL.Pair.canvas, OL.Pair.surface, OL.Pair.sunken] {
            #expect(Self.contrast(OL.Pair.muted.light, background.light) >= 4.5)
            #expect(Self.contrast(OL.Pair.muted.dark, background.dark) >= 4.5)
        }
        #expect(Self.contrast(OL.Pair.lineStrong.light, OL.Pair.surface.light) >= 3)
        #expect(Self.contrast(OL.Pair.lineStrong.dark, OL.Pair.surface.dark) >= 3)
    }

    /// The serif is bundled and registered through UIAppFonts.
    @Test func theSerifIsInstalled() {
        #expect(OLSerif.isAvailable)
        #expect(UIFont(name: OLSerif.fontName, size: 36) != nil)
    }

    // MARK: Helpers

    static func hex(_ color: UIColor, _ style: UIUserInterfaceStyle) -> UInt32 {
        let resolved = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func byte(_ value: CGFloat) -> UInt32 { UInt32((min(1, max(0, value)) * 255).rounded()) }
        return byte(red) << 16 | byte(green) << 8 | byte(blue)
    }

    static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        func luminance(_ hex: UInt32) -> Double {
            func channel(_ value: UInt32) -> Double {
                let c = Double(value) / 255
                return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(hex >> 16 & 0xFF) + 0.7152 * channel(hex >> 8 & 0xFF) + 0.0722 * channel(hex & 0xFF)
        }
        let (l1, l2) = (luminance(a), luminance(b))
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }
}
