import Foundation
import SwiftData

/// Actual work starts only through an explicit Start action. Snapshot fields
/// preserve useful history when a task is renamed, repeated, moved or deleted.
@Model
final class WorkSession {
    var id: UUID = UUID()
    var taskID: UUID = UUID()
    var occurrenceID: UUID = UUID()
    var listID: UUID?
    var title: String = ""
    var startedAt: Date = Date.now
    var endedAt: Date?
    var lastHeartbeatAt: Date = Date.now
    var deviceID: String = ""
    /// A correction overrides elapsed time without destroying the original.
    var correctedMinutes: Double?
    var pauseReason: String?
    /// The original displayed slots, captured before explicit Start replans the
    /// active block. This is planning history, never a recorded duration.
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

    init(task: Block, deviceID: String, startedAt: Date = .now) {
        taskID = task.id
        occurrenceID = task.occurrenceID
        listID = task.listID
        title = task.displayTitle
        self.deviceID = deviceID
        self.startedAt = startedAt
        lastHeartbeatAt = startedAt
    }

    func durationMinutes(at now: Date = .now) -> Double {
        if let correctedMinutes { return max(0, correctedMinutes) }
        return max(0, (endedAt ?? now).timeIntervalSince(startedAt) / 60)
    }
}
