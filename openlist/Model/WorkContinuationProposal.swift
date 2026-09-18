import Foundation

struct WorkContinuationProposal: Equatable, Sendable {
    let task: WorkTaskReference
    let pausedAt: Date
    let proposedEnd: Date
    let boundary: Date
    let changes: [WorkPlanChange]
}
