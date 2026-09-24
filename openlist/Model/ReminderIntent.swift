import Foundation

/// Saved reminder intent is portable. Scheduling results belong to this Mac.
nonisolated struct ReminderIntent: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let occurrenceID: UUID
    let title: String
    let listName: String
    let date: Date
    let inactiveReason: String?

    var body: String { listName.isEmpty ? "Task reminder" : "Task reminder in \(listName)" }
    func isEligible(at now: Date) -> Bool { inactiveReason == nil && date > now }
}

/// How far a reminder is from its task's due time: whole days on the
/// calendar, so "1 day before" keeps the clock time across a daylight-saving
/// change, then elapsed seconds, as "10 minutes before" counts them.
nonisolated struct ReminderOffset: Equatable, Sendable {
    var days = 0
    var seconds: TimeInterval = 0

    init(days: Int = 0, minutes: Int = 0) {
        self.days = days
        seconds = TimeInterval(minutes * 60)
    }

    /// The offset of `reminder` from `due`.
    init(from due: Date, to reminder: Date, calendar: Calendar) {
        days = calendar.dateComponents([.day], from: due, to: reminder).day ?? 0
        seconds = reminder.timeIntervalSince(Self.moving(due, days: days, calendar: calendar))
    }

    /// The reminder this far from `due`.
    func date(from due: Date, calendar: Calendar) -> Date {
        Self.moving(due, days: days, calendar: calendar).addingTimeInterval(seconds)
    }

    private static func moving(_ date: Date, days: Int, calendar: Calendar) -> Date {
        days == 0 ? date : calendar.date(byAdding: .day, value: days, to: date) ?? date.addingTimeInterval(TimeInterval(days) * 86_400)
    }
}

nonisolated enum ReminderAuthorization: Equatable, Sendable {
    case unknown, notDetermined, denied, authorized, unavailable

    var title: String {
        switch self {
        case .unknown: "Checking…"
        case .notDetermined: "Permission needed"
        case .denied: "Turned off in System Settings"
        case .authorized: "Allowed by macOS"
        case .unavailable: "Disabled in this review build"
        }
    }
}

nonisolated enum ReminderStatus: Equatable, Sendable {
    case checking, accepted, permissionNeeded, denied, expired, inactive(String), failed(String), unavailable

    /// In plain words, as the app speaks elsewhere, not the scheduler's. The
    /// ones that need the user read whole wherever they show, beside a task's
    /// title in Settings too; the others show only under the Reminder tab's.
    var title: String {
        switch self {
        case .checking: "Checking reminder…"
        case .accepted: "Reminder set"
        case .permissionNeeded: "Notifications aren’t allowed yet"
        case .denied: "Notifications are off for Openlist"
        case .expired: "Already passed"
        case .inactive(let reason): Self.offTitle(reason)
        case .failed: "The reminder couldn’t be scheduled"
        case .unavailable: "Reminders are off in this review build"
        }
    }

    /// Why a saved reminder waits, from the reason the Store gives.
    private static func offTitle(_ reason: String) -> String {
        switch reason {
        case "task completed": "Off while the task is done"
        case "list archived": "Off while the list is archived"
        case "list unavailable": "Off while its list can’t be found"
        case "in Trash": "Off while it’s in Trash"
        default: "Off · \(reason)"
        }
    }
    var needsRecovery: Bool {
        switch self {
        case .permissionNeeded, .denied, .failed: true
        default: false
        }
    }
}
