import Foundation

struct CalendarStartNudge: Equatable, Sendable {
    var taskID: UUID
    var occurrenceID: UUID
}

/// A heads-up that running work is about to reach its estimate. Work keeps
/// recording past it; the block then grows by itself.
struct CalendarOverrunNudge: Equatable, Sendable {
    var taskID: UUID
    var occurrenceID: UUID
    var estimatedEnd: Date
    var proposedEnd: Date
    var movedTaskCount: Int
}

struct CalendarRescheduleSummary: Identifiable, Equatable, Sendable {
    var id = UUID()
    var message: String
    var reason: String? = nil
}
