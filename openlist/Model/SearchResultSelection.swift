import Foundation

/// Shared by pointer and keyboard navigation. Reconcile against current IDs
/// before opening, and grow the visible batch when arrows cross its boundary.
struct SearchResultSelection {
    static let batchSize = 80
    var selected: SearchDestination?
    private(set) var limit = batchSize

    mutating func reconcile(_ ids: [SearchDestination], reset: Bool = false) {
        if reset { limit = Self.batchSize; selected = ids.first }
        if selected.map({ !ids.contains($0) }) ?? true { selected = ids.first }
        if let selected, let index = ids.firstIndex(of: selected) { limit = max(limit, index + 1) }
    }

    mutating func move(_ offset: Int, in ids: [SearchDestination]) {
        guard !ids.isEmpty else { selected = nil; return }
        let index = selected.flatMap { ids.firstIndex(of: $0) }
        let next = index.map { min(ids.count - 1, max(0, $0 + offset)) } ?? (offset < 0 ? ids.count - 1 : 0)
        selected = ids[next]
        if next >= limit { limit = min(ids.count, max(next + 1, limit + Self.batchSize)) }
    }

    mutating func loadMore(total: Int) { limit = min(total, limit + Self.batchSize) }

    /// Return follows arrow selection even during the render that transfers
    /// native button focus from the previous row to the newly selected row.
    func keyboardDestination(focused: SearchDestination?) -> SearchDestination? { selected ?? focused }
}
