import Foundation

/// Row selection is distinct from a text editor's native character selection.
/// Callers supply the rows actually displayed, including their display order.
nonisolated struct BlockSelection: Equatable {
    enum Gesture { case replace, toggle, range, addingRange }

    private(set) var scopeID: UUID?
    private(set) var anchorID: UUID?
    private(set) var focusID: UUID?
    private(set) var visibleIDs: [UUID] = []

    mutating func select(_ id: UUID, gesture: Gesture, in scope: UUID,
                         visible: [UUID], selected: Set<UUID>) -> Set<UUID> {
        let current = reconcile(in: scope, visible: visible, selected: selected, activating: true)
        guard let index = visibleIDs.firstIndex(of: id) else { return current }
        focusID = id
        switch gesture {
        case .replace:
            anchorID = id
            return [id]
        case .toggle:
            anchorID = id
            var result = current
            if !result.insert(id).inserted { result.remove(id) }
            return result
        case .range, .addingRange:
            let anchor = anchorID.flatMap { visibleIDs.firstIndex(of: $0) } ?? index
            if anchorID == nil { anchorID = id }
            let range = Set(visibleIDs[min(anchor, index)...max(anchor, index)])
            return gesture == .addingRange ? current.union(range) : range
        }
    }

    mutating func step(_ direction: Int, extending: Bool, in scope: UUID,
                       visible: [UUID], selected: Set<UUID>) -> Set<UUID> {
        let current = reconcile(in: scope, visible: visible, selected: selected, activating: true)
        guard !visibleIDs.isEmpty else { return [] }
        let focused = focusID.flatMap { visibleIDs.firstIndex(of: $0) }
        let next: Int
        if let focused {
            next = min(visibleIDs.count - 1, max(0, focused + (direction < 0 ? -1 : 1)))
        } else {
            next = direction < 0 ? visibleIDs.count - 1 : 0
        }
        return select(visibleIDs[next], gesture: extending ? .range : .replace,
                      in: scope, visible: visibleIDs, selected: current)
    }

    /// An inactive inspector/list cannot prune another pane's selection.
    mutating func reconcile(in scope: UUID, visible: [UUID], selected: Set<UUID>,
                            activating: Bool = false) -> Set<UUID> {
        guard activating || scopeID == scope else { return selected }
        if scopeID != scope {
            scopeID = scope
            anchorID = nil
            focusID = nil
        }
        var seen = Set<UUID>()
        visibleIDs = visible.filter { seen.insert($0).inserted }
        let allowed = Set(visibleIDs)
        let result = selected.intersection(allowed)
        if let anchorID, !allowed.contains(anchorID) { self.anchorID = nil }
        if let focusID, !allowed.contains(focusID) { self.focusID = nil }
        return result
    }

    mutating func clear() {
        scopeID = nil
        anchorID = nil
        focusID = nil
        visibleIDs = []
    }

    func ordered(_ selected: Set<UUID>) -> [UUID] {
        visibleIDs.filter { selected.contains($0) }
    }
}
