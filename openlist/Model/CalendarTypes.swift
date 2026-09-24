import Foundation

/// Availability is inherited from the containing list; tasks can override it.
enum AvailabilityCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case work, personal
    var id: String { rawValue }
    var title: String { self == .work ? "Work" : "Personal" }
}

nonisolated struct AvailabilityWindow: Codable, Hashable, Sendable {
    var startMinute: Int
    var endMinute: Int

    init(startMinute: Int, endMinute: Int) {
        self.startMinute = startMinute
        self.endMinute = endMinute
    }
}

nonisolated struct AvailabilityOverride: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var date: Date
    /// An empty array explicitly makes the date unavailable.
    var windows: [AvailabilityWindow]
    var breaks: [AvailabilityWindow] = []
}

nonisolated struct AvailabilityProfile: Codable, Equatable, Sendable {
    /// Calendar weekday numbers: Sunday = 1, Monday = 2, … Saturday = 7.
    var weekly: [Int: [AvailabilityWindow]]
    var breaks: [Int: [AvailabilityWindow]] = [:]
    var overrides: [AvailabilityOverride] = []

    static var workDefault: AvailabilityProfile {
        AvailabilityProfile(
            weekly: Dictionary(uniqueKeysWithValues: (2...6).map {
                ($0, [AvailabilityWindow(startMinute: 9 * 60, endMinute: 17 * 60)])
            }),
            breaks: Dictionary(uniqueKeysWithValues: (2...6).map {
                ($0, [AvailabilityWindow(startMinute: 12 * 60, endMinute: 13 * 60)])
            })
        )
    }

    static var personalDefault: AvailabilityProfile {
        AvailabilityProfile(weekly: Dictionary(uniqueKeysWithValues: (1...7).map {
            ($0, [AvailabilityWindow(startMinute: 18 * 60, endMinute: 21 * 60)])
        }))
    }

    /// The date's own hours, when an override sets them; the latest one wins.
    func override(on day: Date, calendar: Calendar) -> AvailabilityOverride? {
        overrides.last { calendar.isDate($0.date, inSameDayAs: day) }
    }

    /// The hours available on `day`: its override's, else its weekday's.
    func windows(on day: Date, calendar: Calendar) -> [AvailabilityWindow] {
        override(on: day, calendar: calendar)?.windows ?? weekly[calendar.component(.weekday, from: day), default: []]
    }

    /// The breaks on `day`: its override's, else its weekday's.
    func breaks(on day: Date, calendar: Calendar) -> [AvailabilityWindow] {
        override(on: day, calendar: calendar)?.breaks ?? breaks[calendar.component(.weekday, from: day), default: []]
    }
}

nonisolated struct CalendarPreferences: Codable, Equatable, Sendable {
    var defaultEstimateMinutes: Double = 30
    var minimumSessionMinutes: Int = 25
    var horizonDays: Int = 28
    var work: AvailabilityProfile = .workDefault
    var personal: AvailabilityProfile = .personalDefault

    func profile(for category: AvailabilityCategory) -> AvailabilityProfile {
        category == .work ? work : personal
    }
}

struct ScheduleTask: Identifiable, Sendable {
    /// An occurrence remains stable while a recurring task rolls forward.
    var id: UUID { occurrenceID }
    var taskID: UUID
    var occurrenceID: UUID
    var title: String
    var category: AvailabilityCategory
    var remainingMinutes: Double
    /// Exclusive cutoff. Date-only due dates should be normalized to next midnight by the caller.
    var dueDate: Date?
    var selectedForToday: Bool
    var earliestStart: Date?
    /// Larger numbers represent higher priority.
    var priority: Int
    var keepTogether: Bool

    init(taskID: UUID, occurrenceID: UUID, title: String, category: AvailabilityCategory = .work,
         remainingMinutes: Double = 30, dueDate: Date? = nil, selectedForToday: Bool = false,
         earliestStart: Date? = nil, priority: Int = 0, keepTogether: Bool = false) {
        self.taskID = taskID
        self.occurrenceID = occurrenceID
        self.title = title
        self.category = category
        self.remainingMinutes = remainingMinutes
        self.dueDate = dueDate
        self.selectedForToday = selectedForToday
        self.earliestStart = earliestStart
        self.priority = priority
        self.keepTogether = keepTogether
    }
}

struct FixedBusyTime: Identifiable, Sendable {
    var id: String
    var title: String
    var start: Date
    var end: Date
}

struct PlacementInput: Identifiable, Sendable {
    var id: UUID
    var taskID: UUID
    var occurrenceID: UUID
    var start: Date
    var end: Date
    var isPinned: Bool
}

struct ActiveScheduleInput: Sendable {
    var taskID: UUID
    var occurrenceID: UUID
    var start: Date
    var end: Date
}

struct PlannedBlock: Identifiable, Sendable {
    var id: String
    var taskID: UUID
    var occurrenceID: UUID
    var start: Date
    var end: Date
    var isPinned: Bool
    var placementID: UUID?
    var conflicts: [String]
    var isActive: Bool = false
    var completionID: UUID? = nil
    var titleSnapshot: String? = nil
    var isTimeTracked: Bool = false
    /// A done block drawn at the slot it was planned in, stretched to any
    /// work past its ends, as the design's done placement, rather than where
    /// recorded work happened.
    var keepsSlot: Bool = false
    var isCompleted: Bool { completionID != nil }
    var durationMinutes: Double { max(0, end.timeIntervalSince(start) / 60) }
}

enum TaskScheduleStatus: String, Codable, Sendable {
    case scheduled
    case cannotFitBeforeDeadline
    case outsidePlanningHorizon

    var title: String {
        switch self {
        case .scheduled: "Scheduled"
        case .cannotFitBeforeDeadline: "Cannot fit before deadline"
        case .outsidePlanningHorizon: "Outside planning horizon"
        }
    }
}

struct TaskScheduleAssessment: Identifiable, Sendable {
    var id: UUID { occurrenceID }
    var taskID: UUID
    var occurrenceID: UUID
    var status: TaskScheduleStatus
    var requiredMinutes: Double
    var scheduledMinutes: Double
    /// Time with no fixed-placement conflict that falls before the task's cutoff.
    var beforeDeadlineMinutes: Double
    var reason: String
    var conflicts: [String] = []
}

struct CalendarPlan: Sendable {
    var start: Date
    var end: Date
    var blocks: [PlannedBlock]
    var assessments: [TaskScheduleAssessment]

    static var empty: CalendarPlan {
        CalendarPlan(start: .distantPast, end: .distantPast, blocks: [], assessments: [])
    }
}
