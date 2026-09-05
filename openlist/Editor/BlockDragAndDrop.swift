//
//  BlockDragAndDrop.swift
//  openlist
//

import SwiftUI
import UniformTypeIdentifiers

/// Where a dropped block should land relative to the row it was dropped on.
enum DropPosition {
    case before
    case after
    /// Nested as the target's first child.
    case inside
}

/// Makes a row draggable and turns it into a drop target with an insertion line.
struct BlockDragAndDrop: ViewModifier {
    let row: BlockRow
    /// Reordering is only offered while the stored order is what's on screen —
    /// a sorted view would put the block somewhere other than where it landed.
    var isEnabled: Bool = true
    let onMove: (UUID, DropPosition) -> Void
    let onDropText: (String) -> Void

    @State private var indicator: DropPosition?
    @State private var rowHeight: CGFloat = 28

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .overlay(alignment: .top) { indicatorLine(for: .before) }
                .overlay(alignment: .bottom) { indicatorLine(for: .after) }
                .overlay { nestingHighlight }
                .onGeometryChange(for: CGFloat.self) { geometry in
                    geometry.size.height
                } action: { height in
                    rowHeight = height
                }
                .onDrag {
                    NSItemProvider(object: DragPayload.block.encode(row.id) as NSString)
                }
                .onDrop(
                    of: [.text, .plainText, .utf8PlainText],
                    delegate: RowDropDelegate(
                        row: row,
                        rowHeight: rowHeight,
                        indicator: $indicator,
                        onMove: onMove,
                        onDropText: onDropText
                    )
                )
        } else {
            content
        }
    }

    @ViewBuilder
    private func indicatorLine(for position: DropPosition) -> some View {
        if indicator == position {
            Capsule()
                .fill(Theme.accent)
                .frame(height: 2)
                .padding(.leading, CGFloat(row.depth) * Theme.Spacing.indentStep + 20)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var nestingHighlight: some View {
        if indicator == .inside {
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .strokeBorder(Theme.accent, lineWidth: 1.5)
                .padding(.leading, CGFloat(row.depth) * Theme.Spacing.indentStep)
        }
    }
}

/// Resolves the drop position from the pointer's location within the row.
private struct RowDropDelegate: DropDelegate {
    let row: BlockRow
    let rowHeight: CGFloat
    @Binding var indicator: DropPosition?
    let onMove: (UUID, DropPosition) -> Void
    let onDropText: (String) -> Void

    func dropEntered(info: DropInfo) {
        indicator = position(for: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        indicator = position(for: info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        indicator = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        let target = position(for: info)
        indicator = nil

        guard let provider = info.itemProviders(for: [.text, .plainText, .utf8PlainText]).first else {
            return false
        }

        _ = provider.loadObject(ofClass: NSString.self) { value, _ in
            guard let string = value as? String else { return }
            Task { @MainActor in
                if let id = DragPayload.block.decode(string) {
                    onMove(id, target)
                } else {
                    onDropText(string)
                }
            }
        }
        return true
    }

    /// Top third inserts above, bottom third below, and the middle nests —
    /// but only when the target can actually hold children.
    private func position(for info: DropInfo) -> DropPosition {
        let height = max(1, rowHeight)
        let y = info.location.y

        if y < height * 0.3 { return .before }
        if y > height * 0.7 { return .after }
        return row.block.kind.acceptsChildren ? .inside : .after
    }

}
