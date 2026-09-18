import Foundation

struct WorkCompletionSummary {
    let task: WorkTaskReference
    let title: String
    let recordedMinutes: Double
    let nextDate: Date?
    let undoID: UUID?
}
