import Foundation

enum TaskFilter: String, CaseIterable, Identifiable {
    case open, completed, all, starred, scheduled, unscheduled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .open: "Open"
        case .completed: "Completed"
        case .all: "All"
        case .starred: "Starred"
        case .scheduled: "Scheduled"
        case .unscheduled: "No date"
        }
    }

    func includes(_ task: Block) -> Bool {
        switch self {
        case .open: !task.isCompleted
        case .completed: task.isCompleted
        case .all: true
        case .starred: task.isStarred && !task.isCompleted
        case .scheduled: task.dueDate != nil && !task.isCompleted
        case .unscheduled: task.dueDate == nil && !task.isCompleted
        }
    }
}
