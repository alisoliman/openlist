import Foundation

/// Row selection is distinct from a text editor's native character selection:
/// the line a document is writing, in the scope of the document editor that
/// shows it.
/// Callers supply the rows actually displayed.
nonisolated struct BlockSelection: Equatable {
    private(set) var scopeID: UUID?
    private(set) var visibleIDs: [UUID] = []

    /// Selects `id` alone, making `scope` the active document.
    mutating func select(_ id: UUID, in scope: UUID, visible: [UUID], selected: Set<UUID>) -> Set<UUID> {
        let current = reconcile(in: scope, visible: visible, selected: selected, activating: true)
        return visibleIDs.contains(id) ? [id] : current
    }

    /// An inactive document's editor, such as the one being replaced, cannot
    /// prune the active one's selection.
    mutating func reconcile(in scope: UUID, visible: [UUID], selected: Set<UUID>,
                            activating: Bool = false) -> Set<UUID> {
        guard activating || scopeID == scope else { return selected }
        scopeID = scope
        var seen = Set<UUID>()
        visibleIDs = visible.filter { seen.insert($0).inserted }
        return selected.intersection(visibleIDs)
    }

    mutating func clear() {
        scopeID = nil
        visibleIDs = []
    }
}
