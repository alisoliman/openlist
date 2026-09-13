import AppKit
import Foundation
import SwiftData

/// The user-visible manual workflow. Bulk work uses immutable values and an
/// owned Core Data queue; only draft commits and UI state run on the main actor.
@Observable @MainActor
final class LibraryMaintenance {
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

    func chooseBackup() async {
        let panel = NSOpenPanel()
        panel.title = "Choose an Openlist backup"
        panel.message = "Select an .openlistbackup package to validate and preview. Selecting it does not replace your library."
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
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
            self.preview = nil
            self.status = "Restore is prepared. Open Openlist again after it quits to finish."
            NSApplication.shared.terminate(nil)
        }
    }

    func returnToOriginal() async {
        await perform {
            try await self.commitDrafts()
            try self.storage.queueReturnToOriginal()
            self.hasPendingRestore = true
            self.status = "Return is prepared. Open Openlist again after it quits."
            NSApplication.shared.terminate(nil)
        }
    }

    func cancelPending() {
        do {
            try storage.cancelPending()
            hasPendingRestore = false
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
