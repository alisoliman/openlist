import Foundation
import SwiftData

/// A preferred or pinned placement belongs to one task occurrence. Generated
/// flexible plans remain derived, so separate Macs do not sync planner churn.
@Model
final class SchedulePlacement {
    var id: UUID = UUID()
    var taskID: UUID = UUID()
    var occurrenceID: UUID = UUID()
    var start: Date = Date.now
    var end: Date = Date.now
    var isPinned: Bool = false

    init(task: Block, start: Date, end: Date, isPinned: Bool = false) {
        taskID = task.id
        occurrenceID = task.occurrenceID
        self.start = start
        self.end = end
        self.isPinned = isPinned
    }
}
