import Foundation

/// Presentation order, independent of grouping and stored document positions.
/// Like the Lists gallery, visible titles use localized comparison, and ties
/// use creation time then identity without reversing when direction changes.
enum TaskSorting: String, CaseIterable, Identifiable {
    case dueDate, alphabetical, createdAt

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dueDate: "Due date"
        case .alphabetical: "Alphabetical"
        case .createdAt: "Creation date"
        }
    }

    func directionTitle(ascending: Bool) -> String {
        switch self {
        case .dueDate: ascending ? "Earliest first" : "Latest first"
        case .alphabetical: ascending ? "A to Z" : "Z to A"
        case .createdAt: ascending ? "Oldest first" : "Newest first"
        }
    }

    func summary(ascending: Bool) -> String {
        "\(title) · \(directionTitle(ascending: ascending))"
    }

    func sorted(_ tasks: [Block], ascending: Bool) -> [Block] {
        tasks.sorted { lhs, rhs in
            let comparison: ComparisonResult
            switch self {
            case .dueDate:
                switch (lhs.dueDate, rhs.dueDate) {
                case let (left?, right?): comparison = compare(left, right)
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): comparison = .orderedSame
                }
            case .alphabetical:
                comparison = lhs.displayTitle.localizedStandardCompare(rhs.displayTitle)
            case .createdAt:
                comparison = compare(lhs.createdAt, rhs.createdAt)
            }
            if comparison != .orderedSame {
                return comparison == (ascending ? .orderedAscending : .orderedDescending)
            }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func compare<Value: Comparable>(_ lhs: Value, _ rhs: Value) -> ComparisonResult {
        if lhs < rhs { return .orderedAscending }
        if lhs > rhs { return .orderedDescending }
        return .orderedSame
    }
}
