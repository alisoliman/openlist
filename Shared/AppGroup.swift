//
//  AppGroup.swift
//  Shared between the app and the widget extension.
//

import Foundation
import Security

/// The App Group both processes share.
///
/// The app owns the SwiftData store inside it and publishes a small JSON
/// snapshot alongside. The widget reads the snapshot, and only ever writes to
/// the command queue (`widget-commands.json`) the app applies.
nonisolated enum AppGroup {
    #if OPENLIST_DEV
    static let identifier = "Y5UE64R7TQ.solimanali.openlist.dev"
    #else
    static let identifier = "Y5UE64R7TQ.solimanali.openlist"
    #endif

    /// Root of the shared container, or `nil` when the entitlement is missing.
    static var containerURL: URL? {
        // Review builds must never prompt for access to another app's protected
        // group, or touch its files, even when run with an ad-hoc signature.
        if let session = ReviewSession.identifier {
            let review = FileManager.default.temporaryDirectory
                .appendingPathComponent("OpenlistUIReviews/\(session)", isDirectory: true)
            try? FileManager.default.createDirectory(at: review, withIntermediateDirectories: true)
            return review
        }
        #if OPENLIST_DEV
        // Ad-hoc local builds have no authorized App Group. Never ask to open
        // the production group; keep their data in this app's private sandbox.
        if let task = SecTaskCreateFromSelf(nil),
           let groups = SecTaskCopyValueForEntitlement(task, "com.apple.security.application-groups" as CFString, nil) as? [String],
           groups.contains(identifier),
           let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return group
        }
        let development = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? .temporaryDirectory)
            .appendingPathComponent("Openlist Dev", isDirectory: true)
        try? FileManager.default.createDirectory(at: development, withIntermediateDirectories: true)
        return development
        #else
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
        #endif
    }

    /// Where the widget snapshot is written.
    static var snapshotURL: URL? {
        guard let containerURL else { return nil }
        return containerURL.appendingPathComponent("widget-snapshot.json")
    }
}
