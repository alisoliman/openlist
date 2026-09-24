//
//  BlockDragAndDrop.swift
//  openlist
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Where a dropped block should land relative to the row it was dropped on.
enum DropPosition {
    case before
    case after
    /// Nested as the target's first child.
    case inside
}

/// A positional drop target. Dragging starts only at a line's grip, leaving
/// native text drags and selected-character copy untouched.
struct BlockDragAndDrop: ViewModifier {
    let row: BlockRow
    /// Reordering is only offered while the stored order is what's on screen —
    /// a sorted view would put the block somewhere other than where it landed.
    var isEnabled: Bool = true
    /// Whether the middle of the row nests a drop inside it.
    let holdsDrops: Bool
    /// The indicators' colour, the document's indent step, their inset past
    /// the indent, and their corner.
    let accent: Color
    var indentStep: CGFloat = 26
    let indicatorInset: CGFloat
    let radius: CGFloat
    let onMove: ([UUID], DropPosition) -> Void
    let onDropText: (String) -> Void

    @Environment(AppEnvironment.self) private var env

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
                .onDrop(
                    of: [UTType(exportedAs: DragPayload.blockTypeIdentifier), .text, .plainText, .utf8PlainText],
                    delegate: RowDropDelegate(
                        row: row,
                        holdsDrops: holdsDrops,
                        rowHeight: rowHeight,
                        indicator: $indicator,
                        sessionID: env.navigator.blockDragSessionID,
                        onMove: onMove,
                        onDropText: onDropText,
                        onInvalid: { env.store.refuse("This internal drag is invalid or belongs to another library. No rows were changed.") },
                        onList: { env.store.refuse("Lists can't be dropped into a document. No rows were changed.") },
                        onUnavailable: { env.store.refuse("The drop target is no longer available. No rows were changed.") }
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
                .fill(accent)
                .frame(height: 2)
                .padding(.leading, CGFloat(row.depth) * indentStep + indicatorInset)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var nestingHighlight: some View {
        if indicator == .inside {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(accent, lineWidth: 1.5)
                .padding(.leading, CGFloat(row.depth) * indentStep)
        }
    }
}

/// Resolves the drop position from the pointer's location within the row.
private struct RowDropDelegate: DropDelegate {
    let row: BlockRow
    let holdsDrops: Bool
    let rowHeight: CGFloat
    @Binding var indicator: DropPosition?
    let sessionID: UUID
    let onMove: ([UUID], DropPosition) -> Void
    let onDropText: (String) -> Void
    let onInvalid: () -> Void
    /// A sidebar list, which travels on the rows' own type.
    let onList: () -> Void
    let onUnavailable: () -> Void

    private var targetIsAvailable: Bool {
        row.block.modelContext != nil && !row.block.isDeleted && !row.block.isTrashed
    }

    func dropEntered(info: DropInfo) {
        guard targetIsAvailable else { indicator = nil; return }
        indicator = position(for: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard targetIsAvailable else { indicator = nil; return DropProposal(operation: .cancel) }
        indicator = position(for: info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        indicator = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        guard targetIsAvailable else { indicator = nil; onUnavailable(); return false }
        let target = position(for: info)
        indicator = nil

        guard let provider = info.itemProviders(for: [UTType(exportedAs: DragPayload.blockTypeIdentifier), .text, .plainText, .utf8PlainText]).first else {
            return false
        }

        if provider.hasItemConformingToTypeIdentifier(DragPayload.blockTypeIdentifier) {
            provider.loadDataRepresentation(forTypeIdentifier: DragPayload.blockTypeIdentifier) { data, _ in
                Task { @MainActor in
                    // The target may disappear while the provider loads. Do
                    // not inspect its kind, ID or position after deletion.
                    guard targetIsAvailable else { onUnavailable(); return }
                    guard let data, let value = String(data: data, encoding: .utf8) else { onInvalid(); return }
                    if DragPayload.list.decode(value) != nil { onList(); return }
                    guard case .blocks(let ids) = DragPayload.blockDrop(value, session: sessionID) else {
                        onInvalid()
                        return
                    }
                    onMove(ids, target)
                }
            }
            return true
        }
        _ = provider.loadObject(ofClass: NSString.self) { value, _ in
            guard let string = value as? String else { return }
            Task { @MainActor in
                guard targetIsAvailable else { onUnavailable(); return }
                switch DragPayload.blockDrop(string, session: sessionID) {
                case .blocks(let ids): onMove(ids, target)
                case .text(let text): onDropText(text)
                case .invalid: onInvalid()
                }
            }
        }
        return true
    }

    /// Top third inserts above, bottom third below, and the middle nests —
    /// but only when the target holds drops.
    private func position(for info: DropInfo) -> DropPosition {
        let height = max(1, rowHeight)
        let y = info.location.y

        if y < height * 0.3 { return .before }
        if y > height * 0.7 { return .after }
        return holdsDrops ? .inside : .after
    }

}
