import Foundation

@MainActor
final class FakeReminderClient: ReminderNotificationClient {
    var permission: ReminderAuthorization = .authorized
    var permissionFailure = false
    var readFailure = false
    var addFailures = 0
    var requests: [UUID: ReminderIntent] = [:]
    var delivered = Set<UUID>()
    var adds: [ReminderIntent] = []
    var removals: [Set<UUID>] = []
    var holdNextAdd = false
    var addContinuation: CheckedContinuation<Void, Never>?
    var holdAuthorization = false
    var authorizationContinuation: CheckedContinuation<Void, Never>?
    func authorization() async throws -> ReminderAuthorization {
        let captured = permission
        if holdAuthorization {
            holdAuthorization = false
            await withCheckedContinuation { authorizationContinuation = $0 }
        }
        if readFailure { throw CocoaError(.fileReadUnknown) }
        return captured
    }
    func requestAuthorization() async throws -> Bool {
        if permissionFailure { throw CocoaError(.featureUnsupported) }
        permission = .authorized
        return true
    }
    func pending() async throws -> [ReminderIntent] {
        if readFailure { throw CocoaError(.fileReadUnknown) }
        return Array(requests.values)
    }
    func deliveredIDs() async -> Set<UUID> { delivered }
    func add(_ intent: ReminderIntent) async throws {
        adds.append(intent)
        // Deliberately apply the request after a delayed completion too: this
        // is the worst ordering a canceled task must recover from.
        if holdNextAdd {
            holdNextAdd = false
            await withCheckedContinuation { addContinuation = $0 }
        }
        if addFailures > 0 { addFailures -= 1; throw CocoaError(.fileWriteUnknown) }
        requests[intent.id] = intent
    }
    func remove(_ ids: Set<UUID>) {
        removals.append(ids)
        for id in ids { requests[id] = nil; delivered.remove(id) }
    }
    func releaseAdd() { addContinuation?.resume(); addContinuation = nil }
    func releaseAuthorization() { authorizationContinuation?.resume(); authorizationContinuation = nil }
}
