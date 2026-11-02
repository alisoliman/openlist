//
//  SharedCaptures.swift
//  Shared between the iPhone app and its share extension.
//

import Foundation

/// What the Share sheet's Add to Openlist hands the app: the words, and a
/// link or other note to go with them.
nonisolated struct SharedCapture: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var text: String
    var note = ""
    var sharedAt = Date.now
}

/// The shares waiting in the App Group for the app to file. The extension
/// can't reach the library, which is the app's alone, so it only appends;
/// the next time the app comes forward it takes them all and empties the
/// file, each step coordinated with the other process.
nonisolated enum SharedCaptures {
    static let fileName = "shared-captures.json"

    /// Why a share can't be left for the app: a build without the App Group,
    /// as an unsigned one is, has nowhere both can reach.
    struct Unavailable: LocalizedError {
        var errorDescription: String? { "This build of Openlist can’t take shares. Open Openlist and add it there." }
    }

    /// The file in `container`, the App Group's unless a test says otherwise.
    static func url(in container: URL? = AppGroup.containerURL) -> URL? {
        container?.appendingPathComponent(fileName)
    }

    /// Adds shares to the file, after those already waiting.
    static func append(_ captures: [SharedCapture], container: URL? = AppGroup.containerURL) throws {
        guard let url = url(in: container) else { throw Unavailable() }
        var failure: Error?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forMerging, error: &coordinationError) { url in
            do {
                let waiting = read(url)
                try JSONEncoder().encode(waiting + captures).write(to: url, options: .atomic)
            } catch {
                failure = error
            }
        }
        if let error = coordinationError ?? failure { throw error }
    }

    /// Every share waiting, oldest first, with the file emptied in the same step.
    static func takeAll(container: URL? = AppGroup.containerURL) -> [SharedCapture] {
        guard let url = url(in: container), FileManager.default.fileExists(atPath: url.path) else { return [] }
        var taken: [SharedCapture] = []
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { url in
            taken = read(url)
            try? FileManager.default.removeItem(at: url)
        }
        return taken
    }

    private static func read(_ url: URL) -> [SharedCapture] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([SharedCapture].self, from: data)) ?? []
    }
}
