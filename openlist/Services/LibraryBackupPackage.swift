import CryptoKit
import Darwin
import Foundation

/// All package paths are owned by this format. User-supplied filenames are
/// metadata only; bytes use SHA-256 names inside one fixed Media directory.
nonisolated enum LibraryBackupPackage {
    static let fileExtension = "openlistbackup"
    static let maximumJSONBytes = 64 * 1_024 * 1_024
    static let maximumMediaBytes = 128 * 1_024 * 1_024
    static let maximumTotalMediaBytes = 256 * 1_024 * 1_024

    struct Asset: Codable, Equatable, Sendable {
        var filename: String
        var digest: String
        var byteCount: Int
    }

    struct Manifest: Codable, Equatable, Sendable {
        var format = "Openlist Library Backup"
        var version = LibraryBackup.currentVersion
        var libraryID: UUID
        var createdAt: Date
        var libraryDigest: String
        var assets: [Asset]
    }

    struct Validated: Sendable {
        var snapshot: LibraryBackup
        var manifest: Manifest
        var mediaBytes: Int { manifest.assets.reduce(0) { $0 + $1.byteCount } }
    }

    /// Writes a new package and publishes it only after a full read/validation.
    /// An existing destination is never removed or replaced, including failure.
    static func write(_ original: LibraryBackup, to destination: URL,
                      readMedia: (String) throws -> Data,
                      beforePublish: () throws -> Void = {}) throws {
        try original.validate()
        let manager = FileManager.default
        guard !manager.fileExists(atPath: destination.path) else {
            throw LibraryBackupError.invalid("A backup already exists at this location. Choose a new name.")
        }
        // A save-panel grant covers the chosen destination, not arbitrary
        // siblings. Foundation supplies an authorized staging directory on
        // the destination volume so publication can remain a single rename.
        let replacement = try manager.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                          appropriateFor: destination, create: true)
        defer { try? manager.removeItem(at: replacement) }
        let temporary = replacement.appendingPathComponent("Backup.openlistbackup", isDirectory: true)
        try manager.createDirectory(at: temporary.appendingPathComponent("Media"), withIntermediateDirectories: true)
        var snapshot = original
        var assets: [String: Asset] = [:]
        var totalBytes = 0
        func add(_ filename: String, data inline: Data?) throws {
            try validateFilename(filename)
            let bytes = try inline ?? readMedia(filename)
            guard bytes.count <= maximumMediaBytes else { throw LibraryBackupError.invalid("A media file exceeds the supported 128 MB limit.") }
            let hash = digest(bytes)
            let asset = Asset(filename: filename, digest: hash, byteCount: bytes.count)
            if let prior = assets[filename], prior != asset {
                throw LibraryBackupError.invalid("Different media records use the same filename: \(filename).")
            }
            if assets[filename] == nil { totalBytes += asset.byteCount }
            guard totalBytes <= maximumTotalMediaBytes else { throw LibraryBackupError.invalid("This backup exceeds the supported 256 MB media limit.") }
            assets[filename] = asset
            let path = temporary.appendingPathComponent("Media").appendingPathComponent(hash)
            if !manager.fileExists(atPath: path.path) { try bytes.write(to: path, options: .atomic) }
        }
        for index in snapshot.blocks.indices {
            if let filename = snapshot.blocks[index].mediaFilename {
                try add(filename, data: snapshot.blocks[index].mediaData)
                snapshot.blocks[index].mediaData = nil
            }
        }
        for index in snapshot.attachments.indices {
            try add(snapshot.attachments[index].filename, data: snapshot.attachments[index].contentData)
            snapshot.attachments[index].contentData = nil
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(snapshot)
        guard bytes.count <= maximumJSONBytes else { throw LibraryBackupError.invalid("The library exceeds the supported 64 MB metadata limit.") }
        try bytes.write(to: temporary.appendingPathComponent("library.json"), options: .atomic)
        let manifest = Manifest(libraryID: snapshot.libraryID, createdAt: snapshot.createdAt,
            libraryDigest: digest(bytes), assets: assets.values.sorted { $0.filename < $1.filename })
        try encoder.encode(manifest).write(to: temporary.appendingPathComponent("manifest.json"), options: .atomic)
        _ = try read(at: temporary)
        try beforePublish()
        // Coordinate the selected URL, then rename exclusively: even a new
        // destination created during validation must remain untouched. A
        // cross-volume error fails rather than falling back to a partial copy.
        var coordinationError: NSError?
        var publicationError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: destination, options: [],
                                                         error: &coordinationError) { target in
            if renamex_np(temporary.path, target.path, UInt32(RENAME_EXCL)) != 0 {
                publicationError = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        }
        if let coordinationError { throw coordinationError }
        if let publicationError { throw publicationError }
    }

    static func read(at package: URL) throws -> Validated {
        let directory = try CheckedDirectory(package)
        let decoder = JSONDecoder()
        let manifest = try decoder.decode(Manifest.self,
            from: directory.read("manifest.json", maximumBytes: maximumJSONBytes))
        guard manifest.format == "Openlist Library Backup" else { throw LibraryBackupError.invalid("This is not an Openlist library backup.") }
        guard LibraryBackup.readableVersions.contains(manifest.version) else { throw LibraryBackupError.unsupportedVersion(manifest.version) }
        let bytes = try directory.read("library.json", maximumBytes: maximumJSONBytes)
        guard digest(bytes) == manifest.libraryDigest else { throw LibraryBackupError.invalid("The library checksum does not match. The backup is damaged or has changed.") }
        var snapshot = try decoder.decode(LibraryBackup.self, from: bytes)
        guard snapshot.libraryID == manifest.libraryID, snapshot.createdAt == manifest.createdAt,
              snapshot.version == manifest.version else { throw LibraryBackupError.invalid("The backup manifest does not match its library.") }
        try snapshot.upgradeToCurrentVersion()
        try snapshot.validate()
        guard manifest.assets.count <= 1_000_000, Set(manifest.assets.map(\.filename)).count == manifest.assets.count else {
            throw LibraryBackupError.invalid("Duplicate or excessive media entries.")
        }
        let required = Set(snapshot.blocks.compactMap(\.mediaFilename) + snapshot.attachments.map(\.filename))
        guard required == Set(manifest.assets.map(\.filename)) else { throw LibraryBackupError.invalid("The media manifest does not match the library's references.") }
        let media = try directory.subdirectory("Media")
        var assets: [String: Data] = [:]
        var totalBytes = 0
        for asset in manifest.assets {
            try validateFilename(asset.filename)
            guard isDigest(asset.digest), asset.byteCount >= 0, asset.byteCount <= maximumMediaBytes else {
                throw LibraryBackupError.invalid("Invalid media checksum, path or size.")
            }
            totalBytes += asset.byteCount
            guard totalBytes <= maximumTotalMediaBytes else { throw LibraryBackupError.invalid("This backup exceeds the supported 256 MB media limit.") }
            let data = try media.read(asset.digest, maximumBytes: maximumMediaBytes)
            guard data.count == asset.byteCount, digest(data) == asset.digest else {
                throw LibraryBackupError.invalid("A media file is missing, damaged or has changed: \(asset.filename).")
            }
            assets[asset.filename] = data
        }
        for index in snapshot.blocks.indices {
            if let filename = snapshot.blocks[index].mediaFilename {
                guard snapshot.blocks[index].mediaData == nil else { throw LibraryBackupError.invalid("Media bytes must use the package media manifest.") }
                snapshot.blocks[index].mediaData = assets[filename]
            }
        }
        for index in snapshot.attachments.indices {
            guard snapshot.attachments[index].contentData == nil else { throw LibraryBackupError.invalid("Attachment bytes must use the package media manifest.") }
            let data = assets[snapshot.attachments[index].filename]
            guard data?.count == snapshot.attachments[index].byteCount else {
                throw LibraryBackupError.invalid("An attachment's recorded size does not match its bytes: \(snapshot.attachments[index].displayName).")
            }
            snapshot.attachments[index].contentData = data
        }
        return Validated(snapshot: snapshot, manifest: manifest)
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Verification for a staged database without base64-encoding its entire
    /// media corpus into a second large JSON buffer.
    static func fingerprint(_ original: LibraryBackup) throws -> String {
        var snapshot = original
        var media: [String] = []
        for index in snapshot.blocks.indices {
            if let bytes = snapshot.blocks[index].mediaData {
                media.append("block|\(snapshot.blocks[index].id)|\(bytes.count)|\(digest(bytes))")
                snapshot.blocks[index].mediaData = nil
            }
        }
        for index in snapshot.attachments.indices {
            if let bytes = snapshot.attachments[index].contentData {
                media.append("attachment|\(snapshot.attachments[index].id)|\(bytes.count)|\(digest(bytes))")
                snapshot.attachments[index].contentData = nil
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var hash = SHA256()
        hash.update(data: try encoder.encode(snapshot))
        hash.update(data: Data(media.sorted().joined(separator: "\n").utf8))
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func isDigest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    static func validateFilename(_ value: String) throws {
        guard !value.isEmpty, value != ".", value != "..", !value.contains("/"), !value.contains("\\"),
              !value.contains("\0"), value.utf8.count <= 255 else {
            throw LibraryBackupError.invalid("Invalid media filename.")
        }
    }

    /// openat + O_NOFOLLOW keeps all reads below an already-open directory,
    /// including when another process substitutes a symlink during validation.
    private final class CheckedDirectory {
        private let descriptor: Int32
        init(_ url: URL) throws {
            descriptor = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        }
        private init(descriptor: Int32) { self.descriptor = descriptor }
        deinit { close(descriptor) }

        func subdirectory(_ name: String) throws -> CheckedDirectory {
            try LibraryBackupPackage.validateFilename(name)
            let child = openat(descriptor, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard child >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            return CheckedDirectory(descriptor: child)
        }

        func read(_ name: String, maximumBytes: Int) throws -> Data {
            try LibraryBackupPackage.validateFilename(name)
            let file = openat(descriptor, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
            guard file >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            let handle = FileHandle(fileDescriptor: file, closeOnDealloc: true)
            var status = stat()
            guard fstat(file, &status) == 0, (status.st_mode & S_IFMT) == S_IFREG,
                  status.st_size >= 0, status.st_size <= maximumBytes else {
                throw LibraryBackupError.invalid("Invalid or oversized backup file.")
            }
            let result = try handle.read(upToCount: maximumBytes + 1) ?? Data()
            guard result.count <= maximumBytes, result.count == status.st_size else {
                throw LibraryBackupError.invalid("A backup file changed while it was being read.")
            }
            return result
        }
    }
}
