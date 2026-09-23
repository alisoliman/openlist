import AppKit
import Foundation
import SwiftData
import UniformTypeIdentifiers

/// The user-visible manual workflow and the automatic daily snapshots. Bulk
/// work uses immutable values and an owned Core Data queue; only draft commits
/// and UI state run on the main actor.
@Observable @MainActor
final class LibraryMaintenance {
    private static let backupType = UTType(exportedAs: "solimanali.openlist.library-backup", conformingTo: .package)
    private let store: Store
    let storage: LibraryRestoreStorage
    let startup: LibraryRestoreStorage.Startup
    private let defaults: UserDefaults
    var isBusy = false
    var error: String?
    var status: String?
    var preview: LibraryBackupPackage.Validated?
    var lastBackupURL: URL?
    var hasPendingRestore = false
    var isLocalRestore: Bool { startup.isLocalRestore }
    var pendingQuitError: String? { hasPendingRestore ? store.persistenceError : nil }
    let snapshots = LibrarySnapshots(directory: LibrarySnapshots.defaultDirectory)
    /// Why the last daily snapshot failed, until one is written.
    var snapshotError: String?
    @ObservationIgnored private var quitsAfterPreviewDismissal = false
    @ObservationIgnored private var quitTask: Task<Void, Never>?
    @ObservationIgnored private weak var settings: AppSettings?
    @ObservationIgnored private var isSnapshotting = false
    @ObservationIgnored private var dayObserver: NSObjectProtocol?

    init(store: Store, storage: LibraryRestoreStorage, startup: LibraryRestoreStorage.Startup,
         defaults: UserDefaults = ReviewSession.defaults) {
        self.store = store
        self.storage = storage
        self.startup = startup
        self.defaults = defaults
        hasPendingRestore = (try? storage.pending()) != nil
        status = startup.selection?.recoveryWarning
    }

    func exportBackup() async {
        let panel = NSSavePanel()
        panel.title = "Back up library"
        panel.nameFieldStringValue = "Openlist \(Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash))) \(UUID().uuidString.prefix(6)).openlistbackup"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [Self.backupType]
        panel.allowsOtherFileTypes = false
        panel.message = "This unencrypted package contains your private library and files. Choose a new backup name."
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        let access = destination.startAccessingSecurityScopedResource()
        defer { if access { destination.stopAccessingSecurityScopedResource() } }
        await perform {
            try await self.commitDrafts()
            let settings = LibraryBackupSettings(defaults: self.defaults)
            let reader = try BackupSnapshotReader(schema: AppPersistence.schema)
            let sourceURL = self.startup.storeURL
            try await Task.detached(priority: .userInitiated) {
                let snapshot = try reader.read(at: sourceURL, settings: settings)
                try LibraryBackupPackage.write(snapshot, to: destination) { try MediaStore.shared.readFile(filename: $0) }
            }.value
            self.lastBackupURL = destination
            self.status = "Backup created: \(destination.lastPathComponent)"
        }
    }

    /// Takes today's snapshot soon after launch if it's due, and again as each
    /// new day starts while Openlist runs.
    func startDailySnapshots(settings: AppSettings) {
        guard self.settings == nil else { return }
        self.settings = settings
        dayObserver = NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.snapshotIfDue() }
            }
        }
        Task { [weak self] in
            // Launch opens the library, sync and reminders first.
            try? await Task.sleep(for: .seconds(10))
            await self?.snapshotIfDue()
        }
    }

    /// Writes a snapshot of the saved library when Daily is on and today has
    /// none yet, then keeps the newest fourteen. It never takes the focus or
    /// commits a draft, so it can run while you type.
    func snapshotIfDue(now: Date = .now) async {
        guard settings?.takesDailySnapshots == true, !isSnapshotting, !isBusy, !hasPendingRestore,
              snapshots.isDue(at: now) else { return }
        isSnapshotting = true
        defer { isSnapshotting = false }
        do {
            let settings = LibraryBackupSettings(defaults: defaults)
            let reader = try BackupSnapshotReader(schema: AppPersistence.schema)
            let sourceURL = startup.storeURL
            let snapshots = snapshots
            try await Task.detached(priority: .utility) {
                try FileManager.default.createDirectory(at: snapshots.directory, withIntermediateDirectories: true)
                let snapshot = try reader.read(at: sourceURL, settings: settings, createdAt: now)
                try LibraryBackupPackage.write(snapshot, to: snapshots.destination(at: now)) { try MediaStore.shared.readFile(filename: $0) }
                try snapshots.prune()
            }.value
            snapshotError = nil
        } catch {
            snapshotError = "The daily snapshot could not be written. \(error.localizedDescription)"
        }
    }

    func showSnapshots() {
        do {
            try FileManager.default.createDirectory(at: snapshots.directory, withIntermediateDirectories: true)
            NSWorkspace.shared.open(snapshots.directory)
        } catch { self.error = error.localizedDescription }
    }

    func chooseBackup() async {
        let panel = NSOpenPanel()
        panel.title = "Choose an Openlist backup"
        panel.message = "Select an .openlistbackup package to validate and preview. Selecting it does not replace your library."
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = [Self.backupType]
        panel.allowsMultipleSelection = false
        panel.prompt = "Preview Backup"
        guard panel.runModal() == .OK, let source = panel.url else { return }
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        await perform {
            self.preview = try await Task.detached(priority: .userInitiated) {
                try LibraryBackupPackage.read(at: source)
            }.value
        }
    }

    func confirmRestore() async {
        guard let preview else { return }
        await perform {
            try await self.commitDrafts()
            let reader = try BackupSnapshotReader(schema: AppPersistence.schema)
            let storage = self.storage
            let prepared = try await Task.detached(priority: .userInitiated) {
                try storage.prepare(preview.snapshot, using: reader)
            }.value
            try storage.queue(prepared)
            self.hasPendingRestore = true
            self.quitsAfterPreviewDismissal = true
            self.preview = nil
            self.status = "Restore is prepared. Open Openlist again after it quits to finish."
        }
    }

    /// A nil binding starts sheet dismissal; only onDismiss confirms that the
    /// presentation has closed. A cancelled preview must never request quit.
    func previewDidDismiss() {
        guard quitsAfterPreviewDismissal else { return }
        quitsAfterPreviewDismissal = false
        requestQuit()
    }

    func returnToOriginal() async {
        await perform {
            try await self.commitDrafts()
            try self.storage.queueReturnToOriginal()
            self.hasPendingRestore = true
            self.status = "Return is prepared. Open Openlist again after it quits."
            self.requestQuit()
        }
    }

    /// AppKit can decline terminate while a sheet or alert is still closing.
    /// Wait for the actual presentation boundary, not an animation-duration
    /// guess; leave a clear retry action if another dialog remains open.
    func requestQuit() {
        guard hasPendingRestore, quitTask == nil else { return }
        quitTask = Task { [weak self] in
            guard let self else { return }
            defer { quitTask = nil }
            await Task.yield()
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while NSApplication.shared.modalWindow != nil
                || NSApplication.shared.windows.contains(where: { $0.attachedSheet != nil }) {
                guard !Task.isCancelled, hasPendingRestore else { return }
                guard ContinuousClock.now < deadline else {
                    error = "Close any open dialogs, then choose Quit Openlist to finish the prepared restore."
                    return
                }
                do { try await Task.sleep(for: .milliseconds(50)) }
                catch { return }
            }
            guard !Task.isCancelled, hasPendingRestore else { return }
            error = nil
            ApplicationQuit.request { [weak self] in self?.hasPendingRestore == true }
        }
    }

    func cancelPending() {
        do {
            try storage.cancelPending()
            hasPendingRestore = false
            quitsAfterPreviewDismissal = false
            quitTask?.cancel()
            status = "Pending restore cancelled. Your current library is still selected."
        } catch { self.error = error.localizedDescription }
    }

    func showRecoveryFiles() {
        do {
            try FileManager.default.createDirectory(at: storage.root, withIntermediateDirectories: true)
            NSWorkspace.shared.open(storage.root)
        } catch { self.error = error.localizedDescription }
    }

    private func commitDrafts() async throws {
        NotificationCenter.default.post(name: .commitPendingTaskTitles, object: nil)
        for window in NSApplication.shared.windows { window.makeFirstResponder(nil) }
        await Task.yield()
        try store.persistChanges()
    }

    private func perform(_ operation: () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        error = nil
        defer { isBusy = false }
        do { try await operation() }
        catch { self.error = error.localizedDescription }
    }
}
