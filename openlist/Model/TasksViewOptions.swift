import Foundation

/// Transient choices for a task list view; never written to synced models.
struct TasksViewOptions {
    var filter: TaskFilter = .open
    var grouping: TaskGrouping = .dueDate
    var listID: UUID?
    var titleQuery = ""
    var sorting: TaskSorting = .dueDate
    var ascending = true

    var normalizedTitleQuery: String {
        titleQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasCustomFilters: Bool {
        filter != .open || listID != nil || !titleQuery.isEmpty
    }

    var hasCustomSorting: Bool { sorting != .dueDate || !ascending }

    mutating func resetFilters() {
        filter = .open
        listID = nil
        titleQuery = ""
    }

    mutating func resetSorting() {
        sorting = .dueDate
        ascending = true
    }
}
