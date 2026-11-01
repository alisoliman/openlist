//
//  NextListAppearance.swift
//  openlist
//

import AppKit
import SwiftUI

/// Icon & Colour, from the list's tile or its options' Icon & Colour…: the
/// emoji and colour a list shows, in the design's menu language. Past the
/// suggestions, any emoji typed, pasted or picked from Emoji & Symbols.
/// Each pick is one change the tray can undo.
struct ListAppearancePicker: View {
    let list: TaskList

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let style = env.workbench.style
        let glyph = list.glyph
        VStack(alignment: .leading, spacing: 10) {
            NXCapsTitle(text: "Icon")
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 4), count: 10), spacing: 4) {
                ForEach(ListIcon.suggestions, id: \.self) { symbol in
                    let isOn = glyph == symbol
                    Button { env.workbench.setAppearance(icon: symbol, for: list) } label: {
                        Self.cell(symbol)
                    }
                    // Chosen, the accent's faint fill, as the design's menus mark their pick.
                    .buttonStyle(NXHoverButtonStyle(hover: isOn ? style.accent.opacity(0.22) : NX.ink(0.06),
                                                    rest: isOn ? style.accent.opacity(0.15) : .clear, radius: 7,
                                                    padding: EdgeInsets()))
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            HStack(spacing: 4) {
                // An emoji of the list's own, marked as a suggestion would be.
                if !ListIcon.suggestions.contains(glyph), !ListIcon.isSymbolName(glyph) {
                    Self.cell(glyph)
                        .background(style.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .accessibilityAddTraits(.isSelected)
                }
                NXEmojiField { env.workbench.setAppearance(icon: $0, for: list) }
            }
            Rectangle().fill(NX.ink(0.07)).frame(height: 0.5)
                .padding(.vertical, 2)
            NXCapsTitle(text: "Colour")
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
                    .accessibilityLabel("\(accent.title) list colour")
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            .padding(.horizontal, -5)
        }
        .padding(14)
        // The ten emoji columns' width, which the field below them shares.
        .frame(width: 364)
        .presentationBackground(NX.card)
        .tint(style.accent)
        // Presented from the list's header, outside the Next shell's style.
        .environment(\.nextStyle, style)
    }

    private static func cell(_ emoji: String) -> some View {
        Text(emoji)
            .font(.system(size: 17))
            .frame(width: 30, height: 30)
    }
}

/// Icon & Colour's way to any other emoji: typed or pasted into its field,
/// or picked from Emoji & Symbols, which its button opens on the field. An
/// emoji is the list's icon at once and the field empties for the next;
/// whatever isn't one doesn't stay.
private struct NXEmojiField: View {
    let pick: (String) -> Void

    @Environment(\.nextStyle) private var style
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 4) {
            TextField("Any emoji", text: $text, prompt: Text("Type or paste any emoji"))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(NX.ink)
                .focused($focused)
                .accessibilityLabel("Any emoji")
                .onChange(of: text) { _, typed in
                    guard !typed.isEmpty else { return }
                    text = ""
                    if let emoji = ListIcon.emoji(in: typed) { pick(emoji) }
                }
            Button {
                focused = true
                NSApp.orderFrontCharacterPalette(nil)
            } label: {
                Image(systemName: "face.smiling").font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(NXHoverButtonStyle(hover: NX.ink(0.07), radius: 6,
                                            padding: EdgeInsets(top: 3, leading: 4, bottom: 3, trailing: 4),
                                            foreground: NX.textTertiary, hoverForeground: NX.ink))
            .help("Emoji & Symbols")
            .accessibilityLabel("Emoji & Symbols")
        }
        .padding(.leading, 9)
        .padding(.trailing, 3)
        .frame(height: 30)
        // NXPanelField's look, whose focus this field needs for the button.
        .background(NX.ink(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(focused ? style.accent.opacity(0.6) : NX.ink(0.08), lineWidth: focused ? 1 : 0.5))
        .animation(.easeOut(duration: 0.12), value: focused)
    }
}

/// A list header's tile, which opens the list's Icon & Colour beneath it.
struct ListAppearanceTile<Tile: View>: View {
    let list: TaskList
    @Binding var isPresented: Bool
    @ViewBuilder var tile: Tile

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Button { isPresented = true } label: { tile }
            // Over the tile's own fill, the hover deepens it.
            .buttonStyle(NXHoverButtonStyle(hover: NX.ink(0.05), radius: 12, padding: EdgeInsets()))
            .help("Icon & Colour")
            .accessibilityLabel("Icon & Colour")
            .accessibilityValue(list.glyph)
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                ListAppearancePicker(list: list).environment(env)
            }
    }
}
