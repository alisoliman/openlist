import Foundation

/// A self-contained clipboard value. IDs are local references inside this
/// envelope, never identities to adopt in the destination library.
nonisolated struct DocumentFragment: Codable, Equatable, Sendable {
    static let currentVersion = 1
    static let maximumBytes = 64 * 1_024 * 1_024
    static let maximumAssetBytes = 32 * 1_024 * 1_024
    static let maximumMediaBytes = 40 * 1_024 * 1_024
    var version = currentVersion
    var roots: [UUID]
    var blocks: [FragmentBlock]
    var labels: [FragmentLabel]

    func encoded() throws -> Data {
        try validate()
        let data = try JSONEncoder().encode(self)
        guard data.count <= Self.maximumBytes else { throw FragmentError.tooLarge }
        return data
    }

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumBytes else { throw FragmentError.tooLarge }
        let value: Self
        do { value = try JSONDecoder().decode(Self.self, from: data) }
        catch { throw FragmentError.invalid("The clipboard data is incomplete or malformed.") }
        try value.validate()
        return value
    }

    func validate() throws {
        guard version == Self.currentVersion else { throw FragmentError.version(version) }
        guard !blocks.isEmpty, blocks.count <= 10_000, !roots.isEmpty,
              labels.count <= 10_000 else { throw FragmentError.invalid("The fragment has an invalid item count.") }
        let ids = Set(blocks.map(\.id)), labelIDs = Set(labels.map(\.id))
        guard ids.count == blocks.count, labelIDs.count == labels.count,
              Set(roots).count == roots.count, Set(roots).isSubset(of: ids) else {
            throw FragmentError.invalid("The fragment has duplicate or missing identities.")
        }
        let byID = Dictionary(uniqueKeysWithValues: blocks.map { ($0.id, $0) })
        guard Set(blocks.filter { $0.parentID == nil }.map(\.id)) == Set(roots) else {
            throw FragmentError.invalid("The fragment roots do not match its structure.")
        }
        var mediaBytes = 0
        for block in blocks {
            try block.validate(labelIDs: labelIDs)
            var seen: Set<UUID> = [block.id]
            var parent = block.parentID
            while let id = parent {
                guard let ancestor = byID[id], seen.insert(id).inserted, seen.count <= 512 else {
                    throw FragmentError.invalid("The fragment has a missing parent, cycle, or more than 512 levels.")
                }
                parent = ancestor.parentID
            }
            for asset in block.attachments.map(\.media) + [block.image].compactMap({ $0 }) {
                try asset.validate()
                mediaBytes += asset.data.count
                guard mediaBytes <= Self.maximumMediaBytes else { throw FragmentError.tooLarge }
            }
        }
        for label in labels {
            guard !label.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  label.name.utf8.count <= 1_024 else { throw FragmentError.invalid("A label has no usable name.") }
        }
    }
}

nonisolated enum FragmentError: LocalizedError {
    case version(Int), invalid(String), tooLarge, destination, clipboard
    var errorDescription: String? {
        switch self {
        case .version(let version): "This content uses Openlist fragment version \(version), which this app cannot paste. Update Openlist or paste its text instead."
        case .invalid(let reason): "Content was not pasted. \(reason)"
        case .tooLarge: "This fragment is too large. Copy a smaller subtree (64 MB clipboard data, 40 MB total media, and 32 MB per file)."
        case .destination: "The destination is no longer available. Choose an existing document and try again."
        case .clipboard: "Openlist could not write the content to the clipboard."
        }
    }
}
