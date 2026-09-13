import Foundation
import UserNotifications

/// Value-only boundary lets failure and callback ordering checks avoid OS access.
@MainActor
protocol ReminderNotificationClient {
    func authorization() async throws -> ReminderAuthorization
    func requestAuthorization() async throws -> Bool
    func pending() async throws -> [ReminderIntent]
    func deliveredIDs() async -> Set<UUID>
    func add(_ intent: ReminderIntent) async throws
    func remove(_ ids: Set<UUID>)
}

@MainActor
struct SystemReminderNotificationClient: ReminderNotificationClient {
    let center: UNUserNotificationCenter?
    let isEnabled: Bool

    func authorization() async throws -> ReminderAuthorization {
        guard isEnabled, let center else { return .unavailable }
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .authorized
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .unknown
        }
    }

    func requestAuthorization() async throws -> Bool {
        guard isEnabled, let center else { return false }
        return try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func pending() async throws -> [ReminderIntent] {
        guard isEnabled, let center else { return [] }
        return await center.pendingNotificationRequests().compactMap { request in
            guard let id = UUID(uuidString: request.identifier) else { return nil }
            let info = request.content.userInfo
            let occurrence = (info["occurrenceID"] as? String).flatMap(UUID.init(uuidString:)) ?? id
            // Legacy UUID requests are included, so they can be replaced or
            // canceled without touching calendar nudges or unrelated requests.
            let date = (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() ?? .distantPast
            return ReminderIntent(id: id, occurrenceID: occurrence, title: request.content.title,
                listName: info["listName"] as? String ?? "", date: date, inactiveReason: nil)
        }
    }

    func deliveredIDs() async -> Set<UUID> {
        guard isEnabled, let center else { return [] }
        return Set(await center.deliveredNotifications().compactMap { UUID(uuidString: $0.request.identifier) })
    }

    func add(_ intent: ReminderIntent) async throws {
        guard isEnabled, let center else { throw CocoaError(.featureUnsupported) }
        try await center.add(Self.request(for: intent))
    }

    static func request(for intent: ReminderIntent) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = intent.title
        content.body = intent.body
        content.sound = .default
        content.userInfo = ["blockID": intent.id.uuidString, "occurrenceID": intent.occurrenceID.uuidString, "listName": intent.listName]
        // Persisted Date is an absolute instant, including across travel/DST.
        // An explicit UTC calendar avoids reinterpretation in a new time zone.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: intent.date)
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        return UNNotificationRequest(identifier: intent.id.uuidString, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
    }

    func remove(_ ids: Set<UUID>) {
        guard isEnabled, let center, !ids.isEmpty else { return }
        let identifiers = ids.map(\.uuidString)
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}
