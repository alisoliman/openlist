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
    let field: SearchField
    /// When an open task is due, for its subtitle.
    var dueDate: Date? = nil
    /// The icon of the list a block is in, an emoji or an SF Symbol name,
    /// drawn before `context`, which starts with the list's path.
    var listIcon: String? = nil
}
