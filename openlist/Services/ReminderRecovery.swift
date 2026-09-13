import Foundation
import Observation

/// Serializes OS writes. A late add must settle before the newer desired state
/// is applied, so an old callback can never overwrite a newer request.
@Observable @MainActor
final class ReminderRecovery {
    private(set) var intents: [UUID: ReminderIntent] = [:]
    private(set) var statuses: [UUID: ReminderStatus] = [:]
    private(set) var authorization: ReminderAuthorization = .unknown
    private(set) var recoveryError: String?
    private(set) var libraryReadError: String?
    let isSimulated: Bool
    private(set) var authorizationError: String?
    private(set) var isRequestingAuthorization = false
    private(set) var isRefreshing = false
    @ObservationIgnored private let client: any ReminderNotificationClient
    @ObservationIgnored private let now: () -> Date
    private(set) var hasSnapshot = false
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var needsPass = false
    @ObservationIgnored private var retryIDs = Set<UUID>()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var expiryTask: Task<Void, Never>?

    init(client: any ReminderNotificationClient, isSimulated: Bool = false, now: @escaping () -> Date = Date.init) {
        self.client = client
        self.isSimulated = isSimulated
        self.now = now
    }

    func reconcile(_ values: [ReminderIntent]) {
        let recoveredLibraryRead = libraryReadError != nil
        libraryReadError = nil
        let updated = Dictionary(values.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        guard !hasSnapshot || updated != intents || recoveredLibraryRead else { return }
        hasSnapshot = true
        let changed = Set(updated.keys.filter { updated[$0] != intents[$0] })
        // Cancel immediately on a committed replacement, including delivered
        // requests absent from the pending inventory. The serial pass repeats
        // cleanup if an older add completes after this cancellation.
        let obsolete = Set(intents.keys.filter { intents[$0] != updated[$0] })
        client.remove(obsolete)
        retryIDs.formUnion(changed)
        if recoveredLibraryRead { retryIDs.formUnion(updated.keys) }
        intents = updated
        statuses = statuses.filter { updated[$0.key] != nil }
        for id in changed { statuses[id] = .checking }
        refresh()
    }

    func refresh(retryFailures: Bool = false) {
        if retryFailures { retryIDs.formUnion(intents.keys) }
        revision &+= 1
        needsPass = true
        startIfNeeded()
    }

    func title(for status: ReminderStatus) -> String {
        if isSimulated, status == .accepted { return "Simulated pending reminder" }
        return isSimulated ? "Simulated · \(status.title)" : status.title
    }

    func retry(_ id: UUID) {
        guard intents[id]?.isEligible(at: now()) == true else { refresh(); return }
        retryIDs.insert(id)
        refresh()
    }

    func recordReadFailure(_ message: String) {
        libraryReadError = message
        refresh()
    }

    /// Restore must invalidate callbacks before adopting a different library.
    /// The next pass removes old task requests, even if an earlier add completes.
    func resetForLibraryRestore() {
        hasSnapshot = true
        client.remove(Set(intents.keys))
        intents = [:]
        statuses = [:]
        retryIDs = []
        recoveryError = nil
        refresh()
    }

    @discardableResult
    func requestPermission() async -> Bool {
        guard !isRequestingAuthorization else { return false }
        isRequestingAuthorization = true
        revision &+= 1
        var granted = false
        do {
            granted = try await client.requestAuthorization()
            authorizationError = nil
        } catch {
            authorizationError = "Notification permission could not be requested. \(error.localizedDescription)"
        }
        isRequestingAuthorization = false
        refresh(retryFailures: true)
        return granted
    }

    /// Test/lifecycle boundary; does not sleep or assume callbacks completed.
    func waitUntilIdle() async { await task?.value }

    /// Do not make quitting depend forever on a noncooperative OS callback.
    /// This polls observable work, not a child task whose cancellation may be
    /// ignored. Timeout leaves intent/status unchanged for next-launch recovery.
    func drainForTermination(timeout: Duration = .seconds(5)) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while isRefreshing || isRequestingAuthorization {
            if clock.now >= deadline { return false }
            try? await Task.sleep(for: .milliseconds(20))
            if Task.isCancelled { return false }
        }
        return true
    }

    private func startIfNeeded() {
        guard task == nil, !isRequestingAuthorization else { return }
        isRefreshing = true
        task = Task { [weak self] in
            guard let self else { return }
            while needsPass, !isRequestingAuthorization {
                needsPass = false
                await runPass()
            }
            task = nil
            isRefreshing = false
            scheduleExpiryRefresh()
            if needsPass, !isRequestingAuthorization { startIfNeeded() }
        }
    }

    private func scheduleExpiryRefresh() {
        expiryTask?.cancel()
        guard let next = intents.values.filter({ $0.inactiveReason == nil && statuses[$0.id] != .expired }).map(\.date).min() else { return }
        let delay = min(86_400, max(0.05, next.timeIntervalSince(now()) + 0.05))
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    private func matches(_ pending: ReminderIntent, _ saved: ReminderIntent) -> Bool {
        pending.id == saved.id && pending.occurrenceID == saved.occurrenceID
            && pending.title == saved.title && pending.listName == saved.listName
            && abs(pending.date.timeIntervalSince(saved.date)) < 1
    }

    private func runPass() async {
        let generation = revision
        let saved = intents
        let retry = retryIDs
        let previousAuthorization = authorization
        do {
            let permission = try await client.authorization()
            guard generation == revision else { return }
            authorization = permission
            if permission == .authorized { authorizationError = nil }
            // A failed first library read is not an authoritative empty library.
            // Permission can be shown before storage is ready; no OS requests
            // may be canceled or recreated until a saved snapshot exists.
            guard hasSnapshot else { return }
            let pending = try await client.pending()
            guard generation == revision else { return }
            let delivered = await client.deliveredIDs()
            guard generation == revision else { return }
            recoveryError = nil
            let pendingByID = Dictionary(pending.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
            if let libraryReadError {
                // Inventory may confirm the last known saved request, but an
                // unread newer library must not recreate or remove OS work.
                for intent in saved.values {
                    if let reason = intent.inactiveReason { statuses[intent.id] = .inactive(reason) }
                    else if intent.date <= now() { statuses[intent.id] = .expired }
                    else if permission == .denied { statuses[intent.id] = .denied }
                    else if permission == .notDetermined { statuses[intent.id] = .permissionNeeded }
                    else if permission == .unavailable { statuses[intent.id] = .unavailable }
                    else if let existing = pendingByID[intent.id], matches(existing, intent) {
                        statuses[intent.id] = .accepted
                    } else {
                        statuses[intent.id] = .failed(libraryReadError)
                    }
                }
                return
            }
            let eligible = saved.filter { $0.value.isEligible(at: now()) }
            let stale = Set(pendingByID.keys.filter { id in
                guard permission == .authorized, let intent = eligible[id], let existing = pendingByID[id] else { return true }
                return !matches(existing, intent)
            })
            // Expired delivered reminders can remain useful in Notification
            // Center; completed/archived/deleted subjects cannot.
            let inactiveDelivered = delivered.filter { saved[$0] == nil || saved[$0]?.inactiveReason != nil }
            client.remove(stale.union(inactiveDelivered))
            for intent in saved.values.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
                guard generation == revision else { return }
                if let reason = intent.inactiveReason { statuses[intent.id] = .inactive(reason); continue }
                guard intent.date > now() else { statuses[intent.id] = .expired; continue }
                switch permission {
                case .notDetermined: statuses[intent.id] = .permissionNeeded; continue
                case .denied: statuses[intent.id] = .denied; continue
                case .unavailable: statuses[intent.id] = .unavailable; continue
                case .unknown: statuses[intent.id] = .failed("Notification authorization could not be determined."); continue
                case .authorized: break
                }
                if let existing = pendingByID[intent.id], matches(existing, intent) {
                    statuses[intent.id] = .accepted
                    continue
                }
                if case .failed = statuses[intent.id], !retry.contains(intent.id), previousAuthorization == permission { continue }
                statuses[intent.id] = .checking
                do {
                    try await client.add(intent)
                    guard generation == revision else { needsPass = true; return }
                    // Completion means OS acceptance, never proof of display.
                    // Query again so a missing/removed request isn't called pending.
                    let confirmed = try await client.pending()
                    guard generation == revision else { return }
                    if intent.date <= now() {
                        client.remove([intent.id])
                        statuses[intent.id] = .expired
                    } else if confirmed.contains(where: { matches($0, intent) }) {
                        statuses[intent.id] = .accepted
                    } else {
                        statuses[intent.id] = .failed("macOS did not report this reminder as a pending request. Retry while its time is still in the future.")
                    }
                } catch {
                    guard generation == revision else { needsPass = true; return }
                    client.remove([intent.id])
                    statuses[intent.id] = .failed(error.localizedDescription)
                }
            }
            // A later add can take long enough for an earlier request to fire,
            // or the OS can remove/evict a previously confirmed request. Publish
            // a coherent final inventory, not acceptance from earlier callbacks.
            let finalPending = try await client.pending()
            guard generation == revision else { return }
            for intent in saved.values where intent.inactiveReason == nil {
                if intent.date <= now() {
                    if finalPending.contains(where: { $0.id == intent.id }) { client.remove([intent.id]) }
                    statuses[intent.id] = .expired
                } else if statuses[intent.id] == .accepted,
                          !finalPending.contains(where: { matches($0, intent) }) {
                    statuses[intent.id] = .failed("macOS no longer reports this reminder as pending. Retry while its time is still in the future.")
                }
            }
            retryIDs.subtract(retry)
        } catch {
            guard generation == revision else { return }
            recoveryError = "Reminders could not be checked. \(error.localizedDescription)"
            for intent in saved.values where intent.isEligible(at: now()) {
                statuses[intent.id] = .failed(error.localizedDescription)
            }
        }
    }
}
