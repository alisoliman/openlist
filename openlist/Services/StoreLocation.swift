//
//  StoreLocation.swift
//  openlist
//

import Foundation

/// Decides where the SwiftData store file lives.
///
/// The app owns the store in its App Group; widgets consume only a JSON
/// snapshot, and agent operations run inside the app. If the group container
/// is unavailable for any reason, the app falls back to its
/// private Application Support directory rather than failing to launch.
nonisolated enum StoreLocation {
    /// Directory holding `Openlist.store`, creating it if needed.
    static var directory: URL {
        if let group = AppGroup.containerURL {
            let url = group.appendingPathComponent("Store", isDirectory: true)
            if ensureDirectory(url) { return url }
        }

        let base = (FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL.temporaryDirectory)
        let fallback = (ReviewSession.identifier.map { base.appendingPathComponent("Openlist-Review-\($0)") } ?? base)
            .appendingPathComponent("Openlist", isDirectory: true)
        _ = ensureDirectory(fallback)
        return fallback
    }

    static var storeURL: URL {
        directory.appendingPathComponent("Openlist.store")
    }

    private static func ensureDirectory(_ url: URL) -> Bool {
        if FileManager.default.fileExists(atPath: url.path) { return true }
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return true
        } catch {
            return false
        }
    }
}
