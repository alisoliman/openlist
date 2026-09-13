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
