//
//  MediaStore.swift
//  openlist
//

import AppKit
import Foundation
import UniformTypeIdentifiers

/// Owns the on-disk copies of images and attachments referenced by blocks.
///
/// Files are copied into Application Support so a note keeps working after the
/// user moves or deletes the original. `nonisolated` because model objects
/// resolve attachment URLs from outside the main actor.
nonisolated final class MediaStore: @unchecked Sendable {
    static let shared = MediaStore()

    private let originalDirectory: URL
    private var selectedDirectory: URL?
    private let locationLock = NSLock()
    private var directory: URL { locationLock.withLock { selectedDirectory ?? originalDirectory } }
    private let queue = DispatchQueue(label: "com.openlist.mediastore")

    static var defaultDirectory: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL.temporaryDirectory
        #if OPENLIST_DEV
        let defaultBase = AppGroup.containerURL ?? base.appendingPathComponent("Openlist Dev", isDirectory: true)
        #else
        let defaultBase = base
        #endif
        let mediaBase = ReviewSession.identifier.map { base.appendingPathComponent("Openlist-Review-\($0)", isDirectory: true) } ?? defaultBase
        return mediaBase
            .appendingPathComponent("Openlist", isDirectory: true)
            .appendingPathComponent("Media", isDirectory: true)
    }

    private init() {
        originalDirectory = Self.defaultDirectory
        try? FileManager.default.createDirectory(at: originalDirectory, withIntermediateDirectories: true)
    }

    /// Called once at startup, before model bootstrap or any media operation.
    /// A running app never switches libraries underneath pending file writes.
    func selectStartupDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        locationLock.withLock { selectedDirectory = url }
    }

    func url(for filename: String) -> URL {
        directory.appendingPathComponent(filename)
    }

    /// Copies an external file in and returns the generated storage filename.
    @discardableResult
    func importFile(at source: URL) throws -> ImportedMedia {
        let needsScope = source.startAccessingSecurityScopedResource()
        defer { if needsScope { source.stopAccessingSecurityScopedResource() } }

        let ext = source.pathExtension.isEmpty ? "dat" : source.pathExtension
        let filename = "\(UUID().uuidString).\(ext)"
        let destination = url(for: filename)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try Data(contentsOf: source)
        try data.write(to: destination, options: .atomic)

        let values = try? destination.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
        let type = values?.contentType ?? UTType(filenameExtension: ext) ?? .data

        var pixelSize = CGSize.zero
        if type.conforms(to: .image), let image = NSImage(contentsOf: destination) {
            pixelSize = Self.pixelSize(of: image)
        }

        return ImportedMedia(
            filename: filename,
            displayName: source.lastPathComponent,
            contentType: type.preferredMIMEType ?? "application/octet-stream",
            byteCount: data.count,
            pixelSize: pixelSize,
            data: data
        )
    }

    func delete(filename: String) {
        queue.async { [directory] in
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(filename))
        }
    }

    func fileContents(filename: String) -> Data? {
        queue.sync { try? Data(contentsOf: url(for: filename)) }
    }

    func readFile(filename: String) throws -> Data {
        try queue.sync { try Data(contentsOf: checkedURL(for: filename)) }
    }

    /// Recreates a downloaded asset's local cache on demand. Cached files are
    /// immutable imports; opening an external editor does not update the record.
    func materialize(filename: String, data: Data?) throws -> URL {
        try queue.sync {
            let destination = try checkedURL(for: filename)
            if let data {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                if (try? Data(contentsOf: destination)) != data {
                    try data.write(to: destination, options: .atomic)
                }
            } else if !FileManager.default.fileExists(atPath: destination.path) {
                throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: destination.path])
            }
            return destination
        }
    }

    private func checkedURL(for filename: String) throws -> URL {
        guard !filename.isEmpty, filename != ".", filename != "..",
              (filename as NSString).lastPathComponent == filename else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        return url(for: filename)
    }

    func restoreFile(_ data: Data, filename: String) throws {
        try queue.sync {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: checkedURL(for: filename), options: .atomic)
        }
    }

    /// Copies a stored file under a fresh name.
    ///
    /// Duplicating a list must not leave two blocks pointing at one asset, or
    /// deleting either would blank the other.
    func duplicate(filename: String) -> String? {
        let source = url(for: filename)
        guard FileManager.default.fileExists(atPath: source.path) else { return nil }

        let ext = source.pathExtension
        let copyName = ext.isEmpty ? UUID().uuidString : "\(UUID().uuidString).\(ext)"
        do {
            try FileManager.default.copyItem(at: source, to: url(for: copyName))
            return copyName
        } catch {
            return nil
        }
    }

    func image(named filename: String, data: Data? = nil) -> NSImage? {
        if let data { return NSImage(data: data) }
        return NSImage(contentsOf: url(for: filename))
    }

    private static func pixelSize(of image: NSImage) -> CGSize {
        if let rep = image.representations.first {
            return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        return image.size
    }
}

struct ImportedMedia: Sendable {
    var filename: String
    var displayName: String
    var contentType: String
    var byteCount: Int
    var pixelSize: CGSize
    var data: Data
}
