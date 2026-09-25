//
//  ListAccent.swift
//  openlist
//

import SwiftUI

/// The fixed Next palette for lists and labels: list glyphs, tiles and
/// covers, label chips, calendar blocks and the widgets' list colours. Each
/// is one sRGB value, the same in light and dark appearance.
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

    /// The list's or label's colour.
    var color: Color {
        switch self {
        case .graphite: Color(hex: 0x6E6A73)
        case .red: Color(hex: 0xD8434B)
        case .orange: Color(hex: 0xE0861F)
        case .amber: Color(hex: 0xE8A917)
        case .green: Color(hex: 0x2F9E6E)
        case .teal: Color(hex: 0x12807F)
        case .blue: Color(hex: 0x2F6FE0)
        case .indigo: Color(hex: 0x5B5BD6)
        case .violet: Color(hex: 0x7C4DF0)
        case .pink: Color(hex: 0xB8479A)
        case .brown: Color(hex: 0xA0694B)
        }
    }
}

extension Color {
    /// An sRGB colour from 0xRRGGBB.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}
