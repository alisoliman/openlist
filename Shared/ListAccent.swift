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

    /// The Inbox's own blue, which it wears instead of a list accent.
    nonisolated static let inboxHex: UInt32 = 0x3A7BD8

    /// The accent as 0xRRGGBB, for places that carry colours as data, such as
    /// the widget snapshot. Nonisolated so widget timelines and intents can
    /// read it off the main actor.
    nonisolated var hex: UInt32 {
        switch self {
        case .graphite: 0x6E6A73
        case .red: 0xD8434B
        case .orange: 0xE0861F
        case .amber: 0xE8A917
        case .green: 0x2F9E6E
        case .teal: 0x12807F
        case .blue: 0x2F6FE0
        case .indigo: 0x5B5BD6
        case .violet: 0x7C4DF0
        case .pink: 0xB8479A
        case .brown: 0xA0694B
        }
    }

    /// The list's or label's colour.
    var color: Color { Color(hex: hex) }
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
