//
//  NextListAppearance.swift
//  openlist
//

import SwiftUI

/// The list options' Icon & Colour…: the emoji and colour a list shows, in
/// the design's menu language. Each pick is one change the tray can undo.
struct ListAppearancePicker: View {
    let list: TaskList

    @Environment(AppEnvironment.self) private var env

    private static let emoji = [
        "📋", "✅", "🌱", "🏡", "💼", "📚", "🗻", "✈️", "🛒", "🎯",
        "💡", "🎨", "🎵", "🍳", "🏋️", "💰", "🐾", "🎁", "🧹", "📝",
        "🔧", "🌍", "☕️", "🌙", "🔥", "⭐️", "🧠", "🎬", "🚲", "🧺",
    ]

    var body: some View {
        let style = env.workbench.style
        VStack(alignment: .leading, spacing: 10) {
            NXCapsTitle(text: "Icon")
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 4), count: 10), spacing: 4) {
                ForEach(Self.emoji, id: \.self) { symbol in
                    let isOn = list.icon == symbol
                    Button { env.workbench.setAppearance(icon: symbol, for: list) } label: {
                        Text(symbol)
                            .font(.system(size: 17))
                            .frame(width: 30, height: 30)
                    }
                    // Chosen, the accent's faint fill, as the design's menus mark their pick.
                    .buttonStyle(NXHoverButtonStyle(hover: isOn ? style.accent.opacity(0.22) : NX.ink(0.06),
                                                    rest: isOn ? style.accent.opacity(0.15) : .clear, radius: 7,
                                                    padding: EdgeInsets()))
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            Rectangle().fill(NX.ink(0.07)).frame(height: 0.5)
                .padding(.vertical, 2)
            NXCapsTitle(text: "Colour")
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 2) {
                ForEach(ListAccent.allCases) { accent in
                    let isOn = list.accent == accent
                    Button { env.workbench.setAppearance(accent: accent, for: list) } label: {
                        Circle()
                            .fill(accent.color)
                            .frame(width: 20, height: 20)
                            .overlay(Circle().strokeBorder(NX.ink(isOn ? 0.62 : 0), lineWidth: 2).padding(-3))
                            .padding(5)
                    }
                    .buttonStyle(NXHoverButtonStyle(hover: NX.ink(0.06), radius: 8, padding: EdgeInsets()))
                    .help(accent.title)
                    .accessibilityLabel("\(accent.title) list colour")
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            .padding(.horizontal, -5)
        }
        .padding(14)
        .frame(width: 360)
        .presentationBackground(NX.card)
        .tint(style.accent)
        // Presented from the list options, outside the Next shell's style.
        .environment(\.nextStyle, style)
    }
}
