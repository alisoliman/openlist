import Foundation

struct CalendarStartNudge: Equatable, Sendable {
    var taskID: UUID
    var occurrenceID: UUID
    var scheduledStart: Date
    var graceEndsAt: Date
}

struct CalendarOverrunNudge: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case headsUp, needsConfirmation }
    var taskID: UUID
    var occurrenceID: UUID
    var kind: Kind
    var estimatedEnd: Date
    var proposedEnd: Date
    var movedTaskCount: Int
    var needsConfirmation: Bool { kind == .needsConfirmation }
}

struct CalendarRescheduleSummary: Identifiable, Equatable, Sendable {
    var id = UUID()
    var message: String
    var movedTaskCount: Int
    var taskIDs: [UUID]
    var reason: String? = nil
}
