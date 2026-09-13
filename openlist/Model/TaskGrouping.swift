import Foundation

enum TaskGrouping: String, CaseIterable, Identifiable {
    case dueDate, list, label, priority, none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dueDate: "Due date"
        case .list: "List"
        case .label: "Label"
        case .priority: "Priority"
        case .none: "Flat"
        }
    }
}
