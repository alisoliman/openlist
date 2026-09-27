//
//  OLRows.swift
//  OpenlistiOS
//

import SwiftUI

// MARK: - C18 Tiles and list glyphs

/// A list's icon: its emoji, or, from older or synced data, an SF Symbol
/// name drawn as the symbol in the list's colour, never as its name.
struct OLListGlyph: View {
    let icon: String
    var accent: Color = OL.muted
    /// The design's size: 20 in a tile, 30 on a list card's band, 32 on a page.
    var size: CGFloat = 20

    var body: some View {
        Group {
            if ListIcon.isSymbolName(icon) {
                Image(systemName: icon)
                    .font(.system(size: size * 0.8, weight: .medium))
                    .foregroundStyle(accent)
            } else {
                Text(icon.isEmpty ? "📋" : icon)
                    .font(.system(size: size))
            }
        }
        .accessibilityHidden(true)
    }
}

/// A rounded square holding a glyph (`.tile`): 40 pt, radius 12; the list
/// page's is 60, radius 16, on `surface` with the card shadow.
struct OLTile: View {
    let icon: String
    var accent: Color = OL.muted
    var size: CGFloat = 40
    var fill: Color = OL.surface
    var raised = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size >= 60 ? 16 : 12, style: .continuous)
        OLListGlyph(icon: icon, accent: accent, size: size >= 60 ? 32 : 20)
            .frame(width: size, height: size)
            .background {
                if raised { shape.fill(fill).olShadow(.card) } else { shape.fill(fill) }
            }
    }
}

/// A settings row's coloured square (`.stile`): 30 pt, radius 8, an 18 pt
/// symbol in white or the tile colour's own ink.
struct OLSettingsTile: View {
    let symbol: String
    var fill: Color = OL.accent
    var ink: Color = .white

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(ink)
            .frame(width: 30, height: 30)
            .background(fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityHidden(true)
    }

    /// The design's tile colours by section (mockup 15).
    static func accent(_ symbol: String) -> OLSettingsTile { OLSettingsTile(symbol: symbol) }
    static func today(_ symbol: String) -> OLSettingsTile { OLSettingsTile(symbol: symbol, fill: OL.today, ink: OL.onToday) }
    static func teal(_ symbol: String) -> OLSettingsTile { OLSettingsTile(symbol: symbol, fill: OL.teal) }
    static func info(_ symbol: String) -> OLSettingsTile { OLSettingsTile(symbol: symbol, fill: OL.info, ink: OL.onInfo) }
    static func danger(_ symbol: String) -> OLSettingsTile { OLSettingsTile(symbol: symbol, fill: OL.danger, ink: OL.onDanger) }
}

// MARK: - C16 Settings rows

/// A settings row (`.srow`): tile, label, and a trailing value with a
/// chevron, a toggle or anything else. 52 pt at least, 16/22.
struct OLSettingsRow<Trailing: View>: View {
    var tile: OLSettingsTile?
    let title: String
    var separator: OLSeparator = .none
    @ViewBuilder var trailing: Trailing

    init(_ title: String, tile: OLSettingsTile? = nil, separator: OLSeparator = .none,
         @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.tile = tile
        self.separator = separator
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            if let tile { tile }
            Text(title)
                .font(OLFont.rowTitle)
                .foregroundStyle(OL.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .overlay(alignment: .top) { OLSeparatorLine(separator: separator) }
    }
}

/// A settings row's value and chevron (`.val`): "Monday ›", "5 s ›".
struct OLRowValue: View {
    let text: String?
    var color: Color = OL.muted
    var showsChevron = true

    init(_ text: String?, color: Color = OL.muted, showsChevron: Bool = true) {
        self.text = text
        self.color = color
        self.showsChevron = showsChevron
    }

    var body: some View {
        HStack(spacing: 4) {
            if let text { Text(text).foregroundStyle(color) }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(OL.muted)
            }
        }
        .font(OLFont.rowTitle)
        .lineLimit(1)
    }
}

/// Task detail's field rows: a 76 pt muted label, the value, a chevron.
struct OLFieldRow<Value: View>: View {
    let label: String
    var separator: OLSeparator = .none
    var showsChevron = true
    @ViewBuilder var value: Value

    init(_ label: String, separator: OLSeparator = .none, showsChevron: Bool = true, @ViewBuilder value: () -> Value) {
        self.label = label
        self.separator = separator
        self.showsChevron = showsChevron
        self.value = value()
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(OLFont.note)
                .foregroundStyle(OL.muted)
                .frame(width: 76, alignment: .leading)
            value
                .font(OLFont.rowTitle)
                .frame(maxWidth: .infinity, alignment: .leading)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(OL.muted)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .overlay(alignment: .top) { OLSeparatorLine(separator: separator) }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - C19 Search field

/// The search field (`.field`): a 44 pt `sunken` capsule with a magnifier.
/// On Lists it's a button to Find; on Find, a live field with token chips.
struct OLSearchField<Tokens: View>: View {
    @Binding var text: String
    var prompt = "Find a task, note or #label"
    @ViewBuilder var tokens: Tokens
    var focus: FocusState<Bool>.Binding?

    init(text: Binding<String>, prompt: String = "Find a task, note or #label", focus: FocusState<Bool>.Binding? = nil,
         @ViewBuilder tokens: () -> Tokens) {
        _text = text
        self.prompt = prompt
        self.focus = focus
        self.tokens = tokens()
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(OL.muted)
                .accessibilityHidden(true)
            tokens
            field
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .background(OL.sunken, in: .capsule)
    }

    @ViewBuilder private var field: some View {
        let field = TextField(prompt, text: $text, prompt: Text(prompt).foregroundStyle(OL.muted))
            .font(OLFont.rowTitle)
            .foregroundStyle(OL.ink)
            .submitLabel(.search)
            .autocorrectionDisabled()
        if let focus { field.focused(focus) } else { field }
    }
}

extension OLSearchField where Tokens == EmptyView {
    init(text: Binding<String>, prompt: String = "Find a task, note or #label", focus: FocusState<Bool>.Binding? = nil) {
        self.init(text: text, prompt: prompt, focus: focus, tokens: { EmptyView() })
    }
}

/// The search field drawn as a button, as Lists shows it.
struct OLSearchLink: View {
    var prompt = "Find a task, note or #label"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                Text(prompt)
                    .font(OLFont.rowTitle)
                Spacer(minLength: 0)
            }
            .foregroundStyle(OL.muted)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(OL.sunken, in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(OLRowPressStyle())
        .accessibilityLabel("Find")
        .accessibilityHint(prompt)
        .accessibilityAddTraits(.isSearchField)
    }
}
