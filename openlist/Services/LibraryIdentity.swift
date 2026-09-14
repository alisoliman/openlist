import CoreData
import Foundation

/// The existing SQLite store UUID is this Mac's library identity. Reading it
/// through Core Data's public metadata API needs no schema or preference write.
/// A full store backup preserves it; a newly created store gets a different ID.
nonisolated enum LibraryIdentity {
    static func read(at storeURL: URL) throws -> UUID {
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: storeURL)
        guard let value = metadata[NSStoreUUIDKey] as? String, let id = UUID(uuidString: value) else {
            throw LocalLinkError.identityUnavailable
        }
        return id
    }
}
