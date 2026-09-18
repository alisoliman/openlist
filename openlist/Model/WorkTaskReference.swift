import Foundation

/// Actions bind to an occurrence, never just a title or a recurring task ID.
struct WorkTaskReference: Equatable, Hashable, Identifiable, Sendable {
    let taskID: UUID
    let occurrenceID: UUID
    var id: UUID { occurrenceID }

    init(_ task: Block) {
        taskID = task.id
        occurrenceID = task.occurrenceID
    }
}
