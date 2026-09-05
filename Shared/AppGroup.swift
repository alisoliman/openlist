//
//  AppGroup.swift
//  Shared between the app and the widget extension.
//

import Foundation

/// The App Group both processes share.
///
/// The app owns the SwiftData store inside it and publishes a small JSON
/// snapshot alongside; the widget only ever reads the snapshot.
nonisolated enum AppGroup {
    static let identifier = "Y5UE64R7TQ.solimanali.openlist"

    /// Root of the shared container, or `nil` when the entitlement is missing.
    static var containerURL: URL? {
        guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else { return nil }
        if let session = ReviewSession.identifier {
            let review = root.appendingPathComponent("UIReviews/\(session)", isDirectory: true)
            try? FileManager.default.createDirectory(at: review, withIntermediateDirectories: true)
            return review
        }
        return root
    }

    /// Where the widget snapshot is written.
    static var snapshotURL: URL? {
        guard let containerURL else { return nil }
        return containerURL.appendingPathComponent("widget-snapshot.json")
    }
}
