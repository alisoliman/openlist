import AppKit
import CloudKit
import CoreData
import Foundation
import OSLog

@Observable
@MainActor
final class ICloudSyncMonitor {
    var state: ICloudSyncState
    var pushRegistrationError: String?
    var startupWarning: String?
    @ObservationIgnored var onRemoteChange: (() -> Void)? {
        didSet { if needsRefresh { scheduleRemoteRefresh() } }
    }
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var accountTask: Task<Void, Never>?
    private var needsRefresh = false
    private var accountChangedAt: Date?
    private let logger = Logger(subsystem: "solimanali.openlist", category: "iCloud")

    init(unavailableReason: String?) {
        state = ICloudSyncState(unavailableReason: unavailableReason)
        observers.append(NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event,
                  let snapshot = CloudEventSnapshot(event) else { return }
            MainActor.assumeIsolated {
                guard let self, self.state.isEnabled else { return }
                self.receive(snapshot)
            }
        })
        observe(.NSPersistentStoreRemoteChange) { monitor in
            monitor.scheduleRemoteRefresh()
        }
        observe(.CKAccountChanged) { monitor in
            monitor.accountChangedAt = .now
            monitor.state.accountChanged()
            monitor.checkAccount()
        }
        observe(NSApplication.didBecomeActiveNotification) { monitor in
            monitor.checkAccount()
            monitor.scheduleRemoteRefresh()
        }
    }

    isolated deinit {
        refreshTask?.cancel()
        accountTask?.cancel()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    private func observe(
        _ name: Notification.Name,
        handler: @escaping @MainActor (ICloudSyncMonitor) -> Void
    ) {
        observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.state.isEnabled else { return }
                handler(self)
            }
        })
    }

    func checkAccount() {
        guard state.isEnabled else { return }
        accountTask?.cancel()
        accountTask = Task { [weak self] in
            do {
                let status = try await CKContainer(identifier: ICloudConfiguration.containerIdentifier).accountStatus()
                guard !Task.isCancelled, let self else { return }
                switch status {
                case .available: state.account = .available
                case .noAccount: state.account = .signedOut
                case .restricted: state.account = .restricted
                case .temporarilyUnavailable: state.account = .temporarilyUnavailable
                case .couldNotDetermine: state.account = .failed("Try checking again when you are online.")
                @unknown default: state.account = .failed("This version of macOS returned an unknown account status.")
                }
            } catch {
                guard !Task.isCancelled, let self else { return }
                state.account = .failed(ICloudError.message(for: error))
                logger.error("iCloud account check failed: \(error.localizedDescription)")
            }
        }
    }

    private func receive(_ event: CloudEventSnapshot) {
        if let accountChangedAt, event.startDate < accountChangedAt { return }
        guard let endDate = event.endDate else {
            state.begin(event.operation, id: event.identifier)
            return
        }
        state.finish(event.operation, id: event.identifier, at: endDate, error: event.error)
        if let error = event.error { logger.error("iCloud operation failed: \(error)") }
        if event.operation == .download, event.error == nil { scheduleRemoteRefresh() }
    }

    private nonisolated struct CloudEventSnapshot: Sendable {
        let operation: ICloudSyncState.Operation
        let identifier: UUID
        let startDate: Date
        let endDate: Date?
        let error: String?

        init?(_ event: NSPersistentCloudKitContainer.Event) {
            switch event.type {
            case .setup: operation = .setup
            case .import: operation = .download
            case .export: operation = .upload
            @unknown default: return nil
            }
            identifier = event.identifier
            startDate = event.startDate
            endDate = event.endDate
            error = event.succeeded || event.endDate == nil
                ? nil : (event.error.map { ICloudError.message(for: $0) } ?? "The iCloud operation did not finish successfully.")
        }
    }

    private func scheduleRemoteRefresh() {
        needsRefresh = true
        guard onRemoteChange != nil else { return }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            needsRefresh = false
            onRemoteChange?()
        }
    }
}

@MainActor
final class OpenlistApplicationDelegate: NSObject, NSApplicationDelegate {
    var sync: ICloudSyncMonitor?
    var onDidLaunch: (() -> Void)?
    var persistPendingChanges: (() throws -> Void)?
    var finishPendingNotifications: (() async -> Bool)?
    var hasPendingNotifications: (() -> Bool)?
    private var isTerminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        onDidLaunch?()
    }

    func applicationDidResignActive(_ notification: Notification) {
        guard !isTerminating else { return }
        commitEditingDrafts()
        Task { @MainActor in
            await Task.yield()
            try? persistPendingChanges?()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard persistPendingChanges != nil else { return .terminateNow }
        guard !isTerminating else { return .terminateLater }
        isTerminating = true
        commitEditingDrafts()
        Task { @MainActor in
            do {
                try await TerminationDrain.run(commitDrafts: commitEditingDrafts,
                    persist: { try self.persistPendingChanges?() },
                    wait: { await self.finishPendingNotifications?() ?? true },
                    hasPendingWork: { self.hasPendingNotifications?() ?? false },
                    finish: { sender.reply(toApplicationShouldTerminate: true) })
            } catch {
                // Preserve retryable edits and show the Store's save error.
                isTerminating = false
                sender.reply(toApplicationShouldTerminate: false)
            }
        }
        return .terminateLater
    }

    private func commitEditingDrafts() {
        NotificationCenter.default.post(name: .commitPendingEditorDrafts, object: nil)
        for window in NSApplication.shared.windows { window.makeFirstResponder(nil) }
    }

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        sync?.pushRegistrationError = nil
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        sync?.pushRegistrationError = "Background change notifications are unavailable. \(error.localizedDescription)"
        Logger(subsystem: "solimanali.openlist", category: "iCloud")
            .error("Remote notification registration failed: \(error.localizedDescription)")
    }
}
