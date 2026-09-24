import Foundation

/// Only facts captured at a successful commit. This is explanatory history,
/// not a restorable document version.
nonisolated struct TaskActivityState: Codable, Equatable, Sendable {
    var title: String
    var dueDate: Date?
    var includesTime: Bool
    var isCompleted: Bool
    var listID: UUID?
    var listTitle: String
    var listIcon: String
    var occurrenceID: UUID

}

nonisolated struct TaskActivityChange: Codable, Equatable, Sendable {
    var before: TaskActivityState?
    var after: TaskActivityState?
    var completionID: UUID?
    var completedAt: Date?
    var completedDueDate: Date?
    var advancesOccurrence = false
    /// Captured from the completed occurrence, never from today's task state.
    /// Optional for compatibility with existing history and library backups.
    var completedOccurrenceID: UUID?
    var completionWasRecurring: Bool?
    /// A recurring ancestor's cycle is stable when a child is reopened.
    /// For a task with its own rule this is its completed occurrence UUID.
    var completionCycleID: UUID?
    /// A list document line left empty and taken out as its edit ended, which
    /// the design logs as "Removed an empty line", not as a task moved to
    /// Trash. Optional for compatibility with existing history.
    var removedEmptyLine: Bool?
}

/// A staged legacy event retains its action time across retries. Each attempt
/// uses a fresh model identity so a failed SwiftData insertion stays quarantined.
struct ActivityDraft {
    var timestamp = Date.now
    var kind: ActivityKind
    var title: String
    var detail: String
    var blockID: UUID?
    var listID: UUID?
    var listTitle: String
    var listIcon: String

    func model() -> ActivityEvent {
        let event = ActivityEvent(kind: kind, title: title, detail: detail, blockID: blockID,
                                  listID: listID, listTitle: listTitle, listIcon: listIcon)
        event.timestamp = timestamp
        return event
    }
}
