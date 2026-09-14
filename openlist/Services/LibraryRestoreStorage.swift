import CoreData
import Foundation

/// File journal for selecting a library at process startup. A generation is a
/// new store plus its own media cache. The original store is never overwritten.
nonisolated struct LibraryRestoreStorage: Sendable {
    let originalStoreURL: URL
    let originalMediaURL: URL
    var root: URL { originalStoreURL.deletingLastPathComponent().appendingPathComponent("LibraryRecovery", isDirectory: true) }
    var recoveryDirectory: URL { root.appendingPathComponent("Backups", isDirectory: true) }
    private var stateURL: URL { root.appendingPathComponent("selection.json") }
    private var pendingURL: URL { root.appendingPathComponent("pending.json") }

    struct Selection: Codable, Sendable {
        var version = 1
        var id: UUID
        var generation: UUID?
        var libraryID: UUID
        var settings: LibraryBackupSettings
        var originalSettings: LibraryBackupSettings
        var recoveryName: String?
        var recoveryWarning: String?
    }
    struct Pending: Codable, Sendable {
        var version = 1
        var id: UUID
        var sourceGeneration: UUID?
        var destinationGeneration: UUID?
        var destinationSettings: LibraryBackupSettings
    }
    struct Prepared: Sendable {
        let generation: UUID
        let settings: LibraryBackupSettings
    }
    private struct Generation: Codable {
        /// Nil is the original version 1 staging contract.
        var formatVersion: Int?
        var createdAt: Date
        var fingerprint: String
    }
    struct Startup: Sendable {
        var selection: Selection?
        var storeURL: URL
        var mediaURL: URL
        var changed: Bool
        var isLocalRestore: Bool { selection?.generation != nil }
    }
    enum Checkpoint { case beforeSelection, afterSelection }

    func generationDirectory(_ id: UUID) -> URL {
        root.appendingPathComponent("Generations", isDirectory: true).appendingPathComponent(id.uuidString, isDirectory: true)
    }
    func storeURL(for generation: UUID?) -> URL {
        generation.map { generationDirectory($0).appendingPathComponent("Openlist.store") } ?? originalStoreURL
    }
    func mediaURL(for generation: UUID?) -> URL {
        generation.map { generationDirectory($0).appendingPathComponent("Media", isDirectory: true) } ?? originalMediaURL
    }

    func selection() throws -> Selection? {
        guard FileManager.default.fileExists(atPath: stateURL.path) else { return nil }
        let value = try JSONDecoder().decode(Selection.self, from: Data(contentsOf: stateURL))
        guard value.version == 1 else { throw LibraryBackupError.invalid("This library recovery selection requires a newer Openlist version.") }
        try value.settings.validate()
        try value.originalSettings.validate()
        return value
    }

    func pending() throws -> Pending? {
        guard FileManager.default.fileExists(atPath: pendingURL.path) else { return nil }
        let value = try JSONDecoder().decode(Pending.self, from: Data(contentsOf: pendingURL))
        guard value.version == 1 else { throw LibraryBackupError.invalid("This pending restore requires a newer Openlist version.") }
        try value.destinationSettings.validate()
        return value
    }

    /// Removing a post-commit journal only finishes replay; it cannot cancel
    /// the selection that has already been published. Recovery uses Return to
    /// Original in that state, so do not offer a misleading cancellation.
    func canCancelPending() throws -> Bool {
        guard let request = try pending() else { return false }
        return try selection()?.id != request.id
    }

    func prepare(_ snapshot: LibraryBackup, using reader: BackupSnapshotReader) throws -> Prepared {
        let id = UUID()
        var complete = false
        defer { if !complete { try? FileManager.default.removeItem(at: generationDirectory(id)) } }
        var restored = snapshot
        // An open historical record cannot imply that work continued while
        // this backup was absent. Retain its last recorded instant and pause it.
        for index in restored.workSessions.indices where restored.workSessions[index].endedAt == nil {
            restored.workSessions[index].endedAt = max(restored.workSessions[index].startedAt,
                min(restored.workSessions[index].lastHeartbeatAt, snapshot.createdAt))
            restored.workSessions[index].pauseReason = "Library restored; paused at last recorded time"
        }
        _ = try BackupStagedStore.create(from: restored, in: generationDirectory(id), using: reader)
        // Cached media are separate from the original library. Record bytes are
        // authoritative; ordinary materialization rebuilds files when needed.
        try FileManager.default.createDirectory(at: mediaURL(for: id), withIntermediateDirectories: true)
        let manifest = Generation(formatVersion: LibraryBackup.currentVersion, createdAt: restored.createdAt, fingerprint: try LibraryBackupPackage.fingerprint(restored))
        try JSONEncoder().encode(manifest).write(to: generationDirectory(id).appendingPathComponent("verification.json"), options: .atomic)
        complete = true
        return Prepared(generation: id, settings: restored.settings)
    }

    /// Called only after the in-product replace confirmation. Staging and a
    /// pending journal do not change the active library or its preferences.
    func queue(_ prepared: Prepared) throws {
        let selected = try selection()
        let request = Pending(id: UUID(), sourceGeneration: selected?.generation,
            destinationGeneration: prepared.generation, destinationSettings: prepared.settings)
        do { try write(request, to: pendingURL) }
        catch {
            if selected?.generation != prepared.generation {
                try? FileManager.default.removeItem(at: generationDirectory(prepared.generation))
            }
            throw error
        }
    }

    func queueReturnToOriginal() throws {
        guard let selected = try selection(), selected.generation != nil else {
            throw LibraryBackupError.invalid("The original library is already selected.")
        }
        try write(Pending(id: UUID(), sourceGeneration: selected.generation,
            destinationGeneration: nil, destinationSettings: selected.originalSettings), to: pendingURL)
    }

    func cancelPending() throws {
        if FileManager.default.fileExists(atPath: pendingURL.path) { try FileManager.default.removeItem(at: pendingURL) }
    }

    /// Runs before any app container, CloudKit integration, media service or
    /// widget/reminder publisher starts. Replay is idempotent on either side of
    /// the atomic selection write. Old storage and logical recovery stay intact.
    func activatePending(currentSettings: LibraryBackupSettings, using reader: BackupSnapshotReader,
                         checkpoint: (Checkpoint) throws -> Void = { _ in }) throws -> Startup {
        let selected = try selection()
        guard let request = try pending() else {
            if let selected { try validateSelectedStore(selected) }
            return Startup(selection: selected, storeURL: storeURL(for: selected?.generation),
                mediaURL: mediaURL(for: selected?.generation), changed: false)
        }
        if selected?.id == request.id {
            if let selected { try validateSelectedStore(selected) }
            // The process stopped after publishing the complete selection.
            try cancelPending()
            return Startup(selection: selected, storeURL: storeURL(for: selected?.generation),
                mediaURL: mediaURL(for: selected?.generation), changed: true)
        }
        guard request.sourceGeneration == selected?.generation else {
            throw LibraryBackupError.invalid("The selected library changed after this restore was prepared. Cancel the pending restore and try again.")
        }
        let destinationURL = storeURL(for: request.destinationGeneration)
        // Reopen and validate staging before creating recovery or committing a
        // pointer. No bootstrap, migration, notification or sync runs here.
        let destinationLibraryID: UUID
        if let generation = request.destinationGeneration {
            let verification = try JSONDecoder().decode(Generation.self,
                from: Data(contentsOf: generationDirectory(generation).appendingPathComponent("verification.json")))
            guard verification.formatVersion == LibraryBackup.currentVersion else {
                throw LibraryBackupError.invalid("This restore was prepared by an older or incompatible Openlist version. Your current library and staged files have been kept. Cancel the pending restore and select the original backup again; version 1, version 2, and version 3 backup packages can be upgraded safely.")
            }
            let destination = try reader.readClosedStore(at: destinationURL, settings: request.destinationSettings, createdAt: verification.createdAt)
            guard try LibraryBackupPackage.fingerprint(destination) == verification.fingerprint else {
                throw LibraryBackupError.invalid("The staged library changed after validation. Cancel this restore and select the backup again.")
            }
            destinationLibraryID = destination.libraryID
        } else {
            destinationLibraryID = try reader.readClosedStore(at: destinationURL, settings: request.destinationSettings).libraryID
        }
        let sourceURL = storeURL(for: selected?.generation)
        let name = "Before restore \(request.id.uuidString).\(LibraryBackupPackage.fileExtension)"
        let recovery = recoveryDirectory.appendingPathComponent(name, isDirectory: true)
        var recoveryName: String? = name
        var recoveryWarning: String?
        do {
            let source = try reader.readClosedStore(at: sourceURL, settings: currentSettings)
            try FileManager.default.createDirectory(at: recoveryDirectory, withIntermediateDirectories: true)
            // A stopped pre-commit attempt may already have published this copy.
            if FileManager.default.fileExists(atPath: recovery.path) {
                _ = try LibraryBackupPackage.read(at: recovery)
            } else {
                let sourceMedia = mediaURL(for: selected?.generation)
                try LibraryBackupPackage.write(source, to: recovery) { filename in
                    try LibraryBackupPackage.validateFilename(filename)
                    return try Data(contentsOf: sourceMedia.appendingPathComponent(filename))
                }
            }
        } catch {
            // Explicit recovery must remain available when the selected restore
            // is unreadable. Its files are retained verbatim for later recovery.
            guard request.destinationGeneration == nil else { throw error }
            recoveryName = nil
            recoveryWarning = "Returned to the original library. A new backup of the restored library could not be created; its files remain in LibraryRecovery/Generations. \(error.localizedDescription)"
        }
        let next = Selection(id: request.id, generation: request.destinationGeneration, libraryID: destinationLibraryID,
            settings: request.destinationSettings,
            originalSettings: selected?.generation == nil ? currentSettings : (selected?.originalSettings ?? currentSettings),
            recoveryName: recoveryName, recoveryWarning: recoveryWarning)
        try checkpoint(.beforeSelection)
        try write(next, to: stateURL)
        try checkpoint(.afterSelection)
        try cancelPending()
        return Startup(selection: next, storeURL: destinationURL,
            mediaURL: mediaURL(for: next.generation), changed: true)
    }

    func validateSelectedStore(_ selected: Selection) throws {
        let url = storeURL(for: selected.generation)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LibraryBackupError.invalid("The selected library store is missing. It has not been replaced with an empty library. Return to the original library or recover its retained files.")
        }
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: url)
        guard let raw = metadata[NSStoreUUIDKey] as? String, UUID(uuidString: raw) == selected.libraryID else {
            throw LibraryBackupError.invalid("The selected library identity could not be verified. Its files have been kept for recovery.")
        }
    }

    /// Preferences are replayed only for a new selection, before constructing
    /// observers. The marker is written last so interruption retries all keys.
    @MainActor func applySettings(_ startup: Startup, to defaults: UserDefaults) throws {
        guard let selection = startup.selection,
              defaults.string(forKey: "libraryRestore.appliedSelection") != selection.id.uuidString else { return }
        try selection.settings.apply(to: defaults)
        defaults.set(selection.id.uuidString, forKey: "libraryRestore.appliedSelection")
    }

    /// Journal cleanup can precede an interrupted bootstrap. Selection identity,
    /// rather than Startup.changed, makes the derived reset safely replayable.
    @MainActor func needsDerivedReset(_ startup: Startup, defaults: UserDefaults) -> Bool {
        guard let selection = startup.selection else { return false }
        return defaults.string(forKey: "libraryRestore.derivedSelection") != selection.id.uuidString
    }

    /// Called only after the reset and saved-state reconciliation have drained.
    /// A failed read/recovery leaves the marker absent for the next launch.
    @MainActor func finishDerivedReset(_ startup: Startup, defaults: UserDefaults, succeeded: Bool) {
        guard succeeded, let selection = startup.selection else { return }
        defaults.set(selection.id.uuidString, forKey: "libraryRestore.derivedSelection")
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}

extension AppPersistence {
    /// Recheck immediately at the real container factory as well as journal
    /// resolution, so a missing selected store never becomes an empty library.
    static func openSelected(_ startup: LibraryRestoreStorage.Startup, storage: LibraryRestoreStorage,
                             iCloudUnavailableReason: String?) throws -> LoadedStore {
        guard startup.storeURL == storage.storeURL(for: startup.selection?.generation),
              startup.mediaURL == storage.mediaURL(for: startup.selection?.generation) else {
            throw LibraryBackupError.invalid("The selected library location could not be verified.")
        }
        if let selected = startup.selection { try storage.validateSelectedStore(selected) }
        return try open(at: startup.storeURL, iCloudUnavailableReason: startup.isLocalRestore
            ? "This restored library is local only. Your original iCloud library is retained separately. Return to it in Settings > Data when ready."
            : iCloudUnavailableReason)
    }
}
