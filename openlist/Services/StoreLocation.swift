//
//  StoreLocation.swift
//  openlist
//

import Foundation

/// Decides where the SwiftData store file lives.
///
/// Retains the original App Group location across the iCloud upgrade. Only the
/// app opens this database, including MCP operations; widgets read a separate
/// JSON snapshot. If the group is unavailable, the existing private Application
/// Support path is used.
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
