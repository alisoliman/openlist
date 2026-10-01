//
//  DesignTokenTests.swift
//  OpenlistiOSTests
//

import SwiftUI
import Testing
import UIKit
@testable import OpenlistiOS

/// The tokens are design-system.css's values, in both appearances.
struct DesignTokenTests {
    /// Every CSS custom property the app draws with, light and dark.
    static let css: [(String, OLColorPair, UInt32, UInt32)] = [
        ("canvas", OL.Pair.canvas, 0xF2F0EC, 0x1D1C21),
        ("surface", OL.Pair.surface, 0xFFFFFF, 0x2B2930),
        ("sunken", OL.Pair.sunken, 0xECEBE7, 0x35333A),
        ("line", OL.Pair.line, 0xE7E5E0, 0x3B3940),
        ("line-strong", OL.Pair.lineStrong, 0x7D7A74, 0x827F8A),
        ("ink", OL.Pair.ink, 0x151417, 0xF2F1F4),
        ("muted", OL.Pair.muted, 0x6C6965, 0xA09EA8),
        ("accent", OL.Pair.accent, 0x151417, 0xF2F1F4),
        ("on-accent", OL.Pair.onAccent, 0xFFFFFF, 0x151417),
        ("accent-text", OL.Pair.accentText, 0x151417, 0xF2F1F4),
        ("accent-soft", OL.Pair.accentSoft, 0xECEBE7, 0x35333A),
        ("today", OL.Pair.today, 0xCF7409, 0xE8891A),
        ("on-today", OL.Pair.onToday, 0x2A1800, 0x2A1800),
        ("today-text", OL.Pair.todayText, 0xA65700, 0xF0A24A),
        ("today-soft", OL.Pair.todaySoft, 0xFBEEDD, 0x2B231E),
        ("danger", OL.Pair.danger, 0xC23A28, 0xFF7D6E),
        ("on-danger", OL.Pair.onDanger, 0xFFFFFF, 0x3A0F0A),
        ("danger-soft", OL.Pair.dangerSoft, 0xFBE5E1, 0x3A2426),
        ("info", OL.Pair.info, 0x2F6FDC, 0x76A6FF),
        ("on-info", OL.Pair.onInfo, 0xFFFFFF, 0x10233F),
        ("success", OL.Pair.success, 0x2A9466, 0x3A9772),
        ("success-text", OL.Pair.successText, 0x1C7750, 0x5CC796),
        ("success-soft", OL.Pair.successSoft, 0xE1F2E9, 0x1F3329),
        ("teal", OL.Pair.teal, 0x13786E, 0x1C8F82),
        ("tint-violet", OL.Tint.violet.pair, 0xE9E4F7, 0x352D45),
        ("tint-green", OL.Tint.green.pair, 0xE1EEE6, 0x2C3637),
        ("tint-amber", OL.Tint.amber.pair, 0xF7EAD7, 0x3A2F22),
        ("tint-blue", OL.Tint.blue.pair, 0xDFE8F5, 0x26303F),
        ("tint-rose", OL.Tint.rose.pair, 0xF7E2E8, 0x3A2630),
        ("tint-neutral", OL.Tint.neutral.pair, 0xEBE9E5, 0x323037),
    ]

    @Test func pairsHoldTheCSSValues() {
        for (name, pair, light, dark) in Self.css {
            #expect(pair.light == light, "\(name) light")
            #expect(pair.dark == dark, "\(name) dark")
        }
    }

    /// The colours views draw with follow the trait collection.
    @Test func dynamicColoursResolvePerAppearance() {
        for (name, pair, light, dark) in Self.css {
            #expect(Self.hex(pair.uiColor, .light) == light, "\(name) light")
            #expect(Self.hex(pair.uiColor, .dark) == dark, "\(name) dark")
        }
        #expect(Self.hex(UIColor(OL.canvas), .dark) == 0x1D1C21)
        #expect(Self.hex(UIColor(OL.canvas), .light) == 0xF2F0EC)
    }

    /// Widgets and the Live Activity draw one appearance whatever the phone's.
    @Test func palettesAreFixed() {
        #expect(Self.hex(UIColor(OLPalette.dark.surface), .light) == 0x2B2930)
        #expect(Self.hex(UIColor(OLPalette.light.ink), .dark) == 0x151417)
    }

    @Test func listAccentsMapToTheirTintFamily() {
        #expect(OL.tint(for: .violet) == .violet)
        #expect(OL.tint(for: .indigo) == .violet)
        #expect(OL.tint(for: .green) == .green)
        #expect(OL.tint(for: .teal) == .green)
        #expect(OL.tint(for: .blue) == .blue)
        #expect(OL.tint(for: .pink) == .rose)
        #expect(OL.tint(for: .red) == .rose)
        #expect(OL.tint(for: .amber) == .amber)
        #expect(OL.tint(for: .graphite) == .neutral)
        #expect(Set(ListAccent.allCases.map(OL.tint(for:))) == Set(OL.Tint.allCases))
    }

    /// The Inbox's eyebrow needs AA contrast on the canvas, which `info` misses.
    @Test func infoTextMeetsAAOnTheCanvas() {
        #expect(Self.contrast(OL.Pair.info.light, OL.Pair.canvas.light) < 4.5)
        #expect(Self.contrast(OL.Pair.infoText.light, OL.Pair.canvas.light) >= 4.5)
        #expect(Self.contrast(OL.Pair.infoText.dark, OL.Pair.canvas.dark) >= 4.5)
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
