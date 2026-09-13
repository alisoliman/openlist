import Foundation

/// A local display preference; sorting Today never rewrites a list document.
enum TodaySorting: String, CaseIterable, Identifiable {
    case `default`
    case priority
    case dueDate
    case alphabetical
    case createdAt
    case listOrder

    static let preferenceKey = "today.sorting"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .default: "Default"
        case .priority: "Priority"
        case .dueDate: "Due date"
        case .alphabetical: "Alphabetical"
        case .createdAt: "Creation date"
        case .listOrder: "List order"
        }
    }

    var explanation: String {
        switch self {
        case .default: "Original order within each Today section"
        case .priority: "Highest priority first within each section"
        case .dueDate: "Earliest due first; undated tasks last in each section"
        case .alphabetical: "A to Z within each section"
        case .createdAt: "Oldest created first within each section"
        case .listOrder: "List position, then stored document order within each section"
        }
    }
}
