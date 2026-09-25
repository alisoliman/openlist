import Foundation

nonisolated struct SearchOptions: Equatable, Sendable {
    var query = ""
    /// Search's Include completed; archived lists and their content always show.
    var includesCompleted = true
    var needle: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    static func matchRange(_ needle: String, in text: String) -> Range<String.Index>? {
        guard !needle.isEmpty else { return nil }
        return text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
    }
}
