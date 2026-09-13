import Foundation

/// Creation is an explicit fallback after existing destinations and commands.
enum CommandMatchRank {
    static func rank(title: String, query: String, isCreation: Bool = false, isTask: Bool = false) -> Int {
        if isCreation { return 4 }
        let name = title.hasPrefix("Go to ") ? String(title.dropFirst(6)) : title
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.localizedCaseInsensitiveCompare(query) == .orderedSame
            || title.localizedCaseInsensitiveCompare(query) == .orderedSame { return 0 }
        if name.lowercased().hasPrefix(query.lowercased()) { return 1 }
        return isTask ? 3 : 2
    }
}
