//
//  NextNoteSlashCard.swift
//  openlist
//

import SwiftUI

/// The note's `/` menu, as the list document's card draws it: each block
/// with its symbol, and the shortcut that makes it as it's typed.
struct NXNoteSlashCard: View {
    let slash: NXNoteSlash
    let apply: (NoteMarkdown.Block) -> Void
    let dismiss: () -> Void
    @State private var shown = false
    @Environment(\.nextStyle) private var style

    var body: some View {
        let blocks = slash.blocks
        VStack(alignment: .leading, spacing: 1) {
            Text("Blocks")
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.8)
                .textCase(.uppercase)
                .foregroundStyle(NX.textTertiary)
                .padding(.vertical, (10 - NX.lineHeight(10)) / 2)
                .padding(EdgeInsets(top: 7, leading: 9, bottom: 6, trailing: 9))
            if blocks.isEmpty {
                Text("No blocks match")
                    .font(.system(size: 13))
                    .foregroundStyle(NX.textQuaternary)
                    .padding(EdgeInsets(top: 6, leading: 9, bottom: 8, trailing: 9))
            }
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                item(block, selected: index == slash.selected)
            }
        }
        .padding(5)
        .frame(width: 250, alignment: .leading)
        .background(NX.card, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .nxCardShadow(radius: 11, hairline: 0.14, drop: 0.18, y: 16, blur: 40)
        .background(SlashMenuDismissal(onDismiss: dismiss))
        .scaleEffect(shown || !style.slides ? 1 : 0.97, anchor: .topLeading)
        .opacity(shown ? 1 : 0)
        .onAppear { withAnimation(NX.ease(160)) { shown = true } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Blocks")
    }

    private func item(_ block: NoteMarkdown.Block, selected: Bool) -> some View {
        Button { apply(block) } label: {
            HStack(spacing: 10) {
                Image(systemName: block.symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(selected ? NX.ink(0.75) : NX.ink(0.5))
                    .frame(width: 16, height: 16)
                Text(block.label)
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !block.shortcut.isEmpty {
                    Text(block.shortcut).font(NX.mono(10.5)).foregroundStyle(NX.textQuaternary)
                }
            }
            .foregroundStyle(NX.ink)
            .padding(.vertical, 7)
            .padding(.horizontal, 9)
            // A grey highlight, as the page's other menus draw theirs.
            .background(selected ? NX.selectedFill : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
