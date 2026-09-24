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
