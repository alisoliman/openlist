import AppKit
import SwiftUI

/// The narrow gutter owns row gestures and drags. Native text views retain
/// their character selection, links, arrow keys and text drag handlers.
struct RowSelectionGutter: View {
    let id: UUID
    let title: String
    var isPrimaryAppearance = true
    var isRevealed = false
    var requiresSelectionMode = false

    @Environment(AppEnvironment.self) private var env
    @Environment(\.rowSelectionContext) private var scope
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var isHovering = false

    var body: some View {
        if let scope {
            RowSelectionControl(
                title: title,
                isSelected: (!requiresSelectionMode || env.navigator.isSelectingRows)
                    && env.navigator.selection.contains(id)
                    && (env.navigator.rowSelection.scopeID == nil || env.navigator.rowSelection.scopeID == scope.scopeID),
                isSelectionFocus: env.navigator.isSelectingRows
                    && env.navigator.rowSelection.scopeID == scope.scopeID
                    && env.navigator.rowSelection.focusID == id && isPrimaryAppearance,
                requestsKeyboardFocus: env.navigator.rowSelection.scopeID == scope.scopeID
                    && env.navigator.rowFocusRequest == id && isPrimaryAppearance,
                defersPlainClick: env.navigator.selection.count > 1 && env.navigator.selection.contains(id),
                isRevealed: isRevealed || isHovering || voiceOverEnabled
                    || (env.navigator.isSelectingRows && env.navigator.rowSelection.scopeID == scope.scopeID),
                onSelect: { gesture in
                    scope.activate()
                    env.navigator.selectRow(id, gesture: gesture, scope: scope.scopeID, visible: scope.visibleIDs)
                },
                onStep: { direction, extending in
                    scope.activate()
                    env.navigator.stepRowSelection(direction, extending: extending,
                        scope: scope.scopeID, visible: scope.visibleIDs)
                },
                onClear: env.navigator.clearSelection,
                onFocusRequestHandled: { env.navigator.finishRowFocusRequest(id) },
                onDrag: {
                    scope.activate()
                    return env.navigator.beginBlockDrag(id, scope: scope.scopeID, visible: scope.visibleIDs)
                },
                onDragEnd: { env.navigator.activeLegacyBlockDragID = nil }
            )
            .frame(width: 22, height: 26)
            .onHover { isHovering = $0 }
        }
    }
}
