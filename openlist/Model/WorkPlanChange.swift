import Foundation

struct WorkPlanChange: Identifiable, Equatable, Sendable {
    let taskID: UUID
    let occurrenceID: UUID
    let title: String
    let previousStart: Date
    let proposedStart: Date?
    var id: UUID { occurrenceID }
}
