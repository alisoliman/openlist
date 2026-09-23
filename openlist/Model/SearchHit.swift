import Foundation

nonisolated enum SearchDestination: Hashable, Sendable {
    case list(UUID)
    case block(UUID)
}

nonisolated enum SearchField: Equatable, Sendable {
    case text, note, summary
}

/// Values, not retained SwiftData models: a hit is re-resolved when activated.
nonisolated struct SearchHit: Identifiable, Equatable, Sendable {
    let id: SearchDestination
    let title: String
    let context: String
    let snippet: String
    let symbol: String?
    let emoji: String?
    let accent: ListAccent
    let field: SearchField
    /// When an open task is due, for its subtitle.
    var dueDate: Date? = nil
}
