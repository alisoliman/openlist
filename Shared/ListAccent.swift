//
//  ListAccent.swift
//  openlist
//

import SwiftUI

/// The fixed palette used for list tints, label chips and activity markers.
///
/// Each accent resolves through `Color` so it adapts automatically between
/// light and dark appearance.
enum ListAccent: String, Codable, CaseIterable, Sendable, Identifiable {
    case graphite
    case red
    case orange
    case amber
    case green
    case teal
    case blue
    case indigo
    case violet
    case pink
    case brown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .graphite: "Graphite"
        case .red: "Red"
        case .orange: "Orange"
        case .amber: "Amber"
        case .green: "Green"
        case .teal: "Teal"
        case .blue: "Blue"
        case .indigo: "Indigo"
        case .violet: "Violet"
        case .pink: "Pink"
        case .brown: "Brown"
        }
    }

    /// Saturated fill used for checkboxes, chips and icon backgrounds.
    var color: Color {
        switch self {
        case .graphite: Self.rgb(0x6E6A73)
        case .red: Self.rgb(0xD8434B)
        case .orange: Self.rgb(0xE0861F)
        case .amber: Self.rgb(0xE8A917)
        case .green: Self.rgb(0x2F9E6E)
        case .teal: Self.rgb(0x12807F)
        case .blue: Self.rgb(0x2F6FE0)
        case .indigo: Self.rgb(0x5B5BD6)
        case .violet: Self.rgb(0x7C4DF0)
        case .pink: Self.rgb(0xB8479A)
        case .brown: Self.rgb(0xA0694B)
        }
    }

    private static func rgb(_ hex: UInt32) -> Color {
        Color(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255)
    }

    /// Tinted background for chips and soft badges.
    var softBackground: Color { color.opacity(0.14) }

    /// Readable text colour when drawn on `softBackground`.
    var textColor: Color { color }
}
