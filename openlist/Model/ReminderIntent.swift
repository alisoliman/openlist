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

    var title: String {
        switch self {
        case .checking: "Checking reminder…"
        case .accepted: "Accepted by macOS"
        case .permissionNeeded: "Saved · notification permission needed"
        case .denied: "Saved · notifications turned off"
        case .expired: "Expired · will not be replayed"
        case .inactive(let reason): "Not scheduled · \(reason)"
        case .failed: "Saved · scheduling failed"
        case .unavailable: "Saved · reminders disabled in this review build"
        }
    }
    var needsRecovery: Bool {
        switch self {
        case .permissionNeeded, .denied, .failed: true
        default: false
        }
    }
}
