//
//  SlashMenuView.swift
//  openlist
//

import SwiftUI

/// The block picker summoned by typing `/`.
struct SlashMenuView: View {
    let query: String
    let selectedIndex: Int
    var menuSize = CGSize(width: 260, height: 264)
    let onSelect: (BlockKind) -> Void
    let onHover: (Int) -> Void
    let onDismiss: () -> Void
    var onContentHeight: (CGFloat) -> Void = { _ in }

    /// Kinds offered by the menu, in presentation order.
    private static let offered: [BlockKind] = [
        .task, .paragraph, .heading1, .heading2, .heading3,
        .bullet, .numbered, .quote, .code, .divider, .image,
    ]

    /// Filters the menu by a fuzzy-ish prefix match on title, shorthand and
    /// keywords, so "h2", "head" and "sub" all find Heading 2.
    static func matches(query: String) -> [BlockKind] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return offered }

        return offered.filter { kind in
            if kind.title.lowercased().contains(needle) { return true }
            if let shorthand = kind.shorthand, shorthand.hasPrefix(needle) { return true }
            return kind.searchTerms.contains { $0.hasPrefix(needle) }
        }
    }

    private var results: [BlockKind] { Self.matches(query: query) }

    var body: some View {
        Group {
            if results.isEmpty {
                Text("No blocks match “\(query)”")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.tertiaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(Array(results.enumerated()), id: \.element) { index, kind in
                                row(for: kind, index: index)
                                    .id(kind)
                            }
                        }
                        .padding(4)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onContentHeight($0) }
                    }
                    .frame(height: menuSize.height)
                    .onChange(of: selectedIndex) { _, newValue in
                        guard results.indices.contains(newValue) else { return }
                        proxy.scrollTo(results[newValue], anchor: .center)
                    }
                }
            }
        }
        .frame(width: menuSize.width, height: menuSize.height, alignment: .leading)
        .background(SlashMenuDismissal(onDismiss: onDismiss))
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                .strokeBorder(Theme.separator, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
    }

    private func row(for kind: BlockKind, index: Int) -> some View {
        let isSelected = index == selectedIndex

        return Button {
            onSelect(kind)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 12))
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(isSelected ? Color.white.opacity(0.22) : Theme.chipFill)
                    )
                    .foregroundStyle(isSelected ? Color.white : Theme.secondaryText)

                Text(kind.title)
                    .font(.system(size: 12.5, weight: .medium))

                Spacer(minLength: 4)

                if let shorthand = kind.shorthand {
                    Text(shorthand)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.7) : Theme.tertiaryText)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(isSelected ? Color.white.opacity(0.15) : Theme.chipFill)
                        )
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Theme.accent : Color.clear)
            )
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(kind.subtitle)
        .help(kind.subtitle)
        .onHover { hovering in
            if hovering { onHover(index) }
        }
    }
}
