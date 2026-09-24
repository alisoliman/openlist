import Foundation

nonisolated struct SearchOptions: Equatable, Sendable {
    enum Scope: String, Sendable {
        case everything, tasks, notes, lists
    }

    var query = ""
    var scope: Scope = .everything
    // Search has always included these records. Keep that access explicit.
    var includesCompleted = true
    var includesArchived = true
    var needle: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    static func matchRange(_ needle: String, in text: String) -> Range<String.Index>? {
        guard !needle.isEmpty else { return nil }
        return text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
    }
}
