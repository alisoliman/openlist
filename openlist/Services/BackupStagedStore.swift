import CoreData
import Foundation
import SwiftData

/// Builds only brand-new, isolated storage. It has no API that can overwrite
/// a live store, and never enables CloudKit or runs app bootstrap migrations.
enum BackupStagedStore {
    static func create(from snapshot: LibraryBackup, in directory: URL,
                       beforeSave: () throws -> Void = {}) throws -> URL {
        try create(from: snapshot, in: directory, using: BackupSnapshotReader(schema: AppPersistence.schema), beforeSave: beforeSave)
    }

    nonisolated static func create(from snapshot: LibraryBackup, in directory: URL,
                                   using reader: BackupSnapshotReader,
                                   beforeSave: () throws -> Void = {}) throws -> URL {
        try snapshot.validate()
        let manager = FileManager.default
        guard !manager.fileExists(atPath: directory.path) else {
            throw LibraryBackupError.invalid("Restore staging requires a new empty location.")
        }
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("Openlist.store")
        do {
            try beforeSave()
            try reader.createStore(from: snapshot, at: url)
            // No context/container remains open at this boundary. Full restore
            // adopts the original library's URL identity, not a new random one.
            var metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: url)
            metadata[NSStoreUUIDKey] = snapshot.libraryID.uuidString
            try NSPersistentStoreCoordinator.setMetadata(metadata, type: .sqlite, at: url)
            let reopened = try reader.read(at: url, settings: snapshot.settings, createdAt: snapshot.createdAt)
            guard reopened == snapshot else { throw LibraryBackupError.invalid("The restored store did not preserve every library record.") }
            return url
        } catch {
            try? manager.removeItem(at: directory)
            throw error
        }
    }

    static func read(at url: URL, settings: LibraryBackupSettings, createdAt: Date = .now) throws -> LibraryBackup {
        try autoreleasepool {
            let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: url)
            guard let raw = metadata[NSStoreUUIDKey] as? String, let libraryID = UUID(uuidString: raw) else {
                throw LibraryBackupError.invalid("The saved library identity could not be read.")
            }
            let container = try openLocal(at: url, allowsSave: false)
            container.mainContext.autosaveEnabled = false
            return try LibraryBackup(context: container.mainContext, libraryID: libraryID, settings: settings, createdAt: createdAt)
        }
    }

    private static func openLocal(at url: URL, allowsSave: Bool = true) throws -> ModelContainer {
        try ModelContainer(for: AppPersistence.schema, configurations: [
            ModelConfiguration(schema: AppPersistence.schema, url: url, allowsSave: allowsSave, cloudKitDatabase: .none)
        ])
    }
}
