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
        case .graphite: Color(red: 0.44, green: 0.46, blue: 0.51)
        case .red: Color(red: 0.90, green: 0.28, blue: 0.31)
        case .orange: Color(red: 0.96, green: 0.53, blue: 0.20)
        case .amber: Color(red: 0.95, green: 0.72, blue: 0.16)
        case .green: Color(red: 0.24, green: 0.71, blue: 0.44)
        case .teal: Color(red: 0.16, green: 0.68, blue: 0.68)
        case .blue: Color(red: 0.20, green: 0.55, blue: 0.95)
        case .indigo: Color(red: 0.36, green: 0.40, blue: 0.90)
        case .violet: Color(red: 0.55, green: 0.36, blue: 0.93)
        case .pink: Color(red: 0.92, green: 0.35, blue: 0.62)
        case .brown: Color(red: 0.60, green: 0.45, blue: 0.34)
        }
    }

    /// Tinted background for chips and soft badges.
    var softBackground: Color { color.opacity(0.14) }

    /// Readable text colour when drawn on `softBackground`.
    var textColor: Color { color }
}
