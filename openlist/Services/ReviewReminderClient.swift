import Foundation

/// Opt-in disposable native-fixture backend. No UserNotifications center is
/// created. Its pending inventory survives review-app relaunch in that fixture's
/// isolated defaults, and every task's first add is rejected to exercise Retry.
@MainActor
final class ReviewReminderClient: ReminderNotificationClient {
    private let defaults: UserDefaults
    private var requests: [UUID: ReminderIntent]
    private var attempted: Set<UUID>
    private static let pendingKey = "review.reminders.pending"
    private static let attemptedKey = "review.reminders.attempted"

    init(defaults: UserDefaults) {
        self.defaults = defaults
        let saved = defaults.data(forKey: Self.pendingKey).flatMap { try? JSONDecoder().decode([ReminderIntent].self, from: $0) } ?? []
        requests = Dictionary(saved.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        attempted = Set((defaults.stringArray(forKey: Self.attemptedKey) ?? []).compactMap(UUID.init(uuidString:)))
    }
    func authorization() async throws -> ReminderAuthorization { .authorized }
    func requestAuthorization() async throws -> Bool { true }
    func pending() async throws -> [ReminderIntent] {
        requests = requests.filter { $0.value.date > .now }
        save()
        return Array(requests.values)
    }
    func deliveredIDs() async -> Set<UUID> { [] }
    func add(_ intent: ReminderIntent) async throws {
        if attempted.insert(intent.id).inserted {
            save()
            throw SimulationError.firstAttempt
        }
        requests[intent.id] = intent
        save()
    }
    func remove(_ ids: Set<UUID>) {
        for id in ids { requests[id] = nil }
        save()
    }
    private func save() {
        defaults.set(try? JSONEncoder().encode(Array(requests.values)), forKey: Self.pendingKey)
        defaults.set(attempted.map(\.uuidString), forKey: Self.attemptedKey)
    }
    private enum SimulationError: LocalizedError {
        case firstAttempt
        var errorDescription: String? { "Simulated scheduling rejection. Retry this future reminder to test recovery without sending a notification." }
    }
}
