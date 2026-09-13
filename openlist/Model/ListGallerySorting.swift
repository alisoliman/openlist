import Foundation

/// Local presentation of the gallery; never changes a list's saved position.
enum ListGallerySorting: String, CaseIterable, Identifiable {
    case existing
    case alphabetical
    case creationDate

    static let preferenceKey = "listsGallery.sorting"
    static let ascendingPreferenceKey = "listsGallery.sortAscending"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .existing: "Existing order"
        case .alphabetical: "Alphabetical"
        case .creationDate: "Creation date"
        }
    }

    func directionTitle(ascending: Bool) -> String {
        switch self {
        case .existing: "Existing order"
        case .alphabetical: ascending ? "A to Z" : "Z to A"
        case .creationDate: ascending ? "Oldest first" : "Newest first"
        }
    }

    func summary(ascending: Bool) -> String {
        self == .existing ? title : "\(title) · \(directionTitle(ascending: ascending))"
    }

    func visibleLists(from lists: [TaskList], includingArchived: Bool, ascending: Bool) -> [TaskList] {
        lists.filter { !$0.isTrashed && $0.mergedIntoID == nil && (includingArchived || !$0.isArchived) }
            .sorted { left, right in
                let comparison: ComparisonResult
                switch self {
                case .existing:
                    comparison = compare(left.sortIndex, right.sortIndex)
                case .alphabetical:
                    comparison = left.displayTitle.localizedStandardCompare(right.displayTitle)
                case .creationDate:
                    comparison = compare(left.createdAt, right.createdAt)
                }

                if comparison != .orderedSame {
                    return self == .existing || ascending
                        ? comparison == .orderedAscending
                        : comparison == .orderedDescending
                }

                // A direction change reverses the selected key, not ties. UUID
                // keeps duplicate names and timestamps stable across fetches.
                if left.createdAt != right.createdAt { return left.createdAt < right.createdAt }
                return left.id.uuidString < right.id.uuidString
            }
    }

    private func compare<Value: Comparable>(_ left: Value, _ right: Value) -> ComparisonResult {
        if left < right { return .orderedAscending }
        if left > right { return .orderedDescending }
        return .orderedSame
    }
}
