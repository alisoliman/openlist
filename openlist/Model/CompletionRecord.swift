import Foundation
import SwiftData

struct CompletionCalendarInterval: Codable, Equatable, Sendable {
    var start: Date
    var end: Date
}

/// Completion is an append-only occurrence record, independent of a live task.
@Model
final class CompletionRecord {
    var id: UUID = UUID()
    var taskID: UUID = UUID()
    var occurrenceID: UUID = UUID()
    var listID: UUID?
    var title: String = ""
    var completedAt: Date = Date.now
    var dueDate: Date?
    var estimateMinutes: Int = 30
    var wasRecurring: Bool = false
    /// Displayed planning slots are history, never recorded work or future busy time.
    /// Optional data adds safely to existing local and CloudKit stores.
    var plannedIntervalsData: Data?

    var plannedIntervals: [CompletionCalendarInterval] {
        get {
            guard let plannedIntervalsData,
                  let intervals = try? JSONDecoder().decode([CompletionCalendarInterval].self, from: plannedIntervalsData)
            else { return [] }
            return intervals.filter { $0.start.timeIntervalSinceReferenceDate.isFinite && $0.end.timeIntervalSinceReferenceDate.isFinite && $0.end >= $0.start }
        }
        set { plannedIntervalsData = try? JSONEncoder().encode(newValue) }
    }

    init(task: Block, completedAt: Date = .now, estimateMinutes: Int = 30) {
        taskID = task.id
        occurrenceID = task.occurrenceID
        listID = task.listID
        title = task.displayTitle
        self.completedAt = completedAt
        dueDate = task.dueDate
        self.estimateMinutes = estimateMinutes
        wasRecurring = task.recurrence != nil
    }
}
