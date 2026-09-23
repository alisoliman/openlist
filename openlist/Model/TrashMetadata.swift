import Foundation

/// Immutable provenance belongs to the deletion root, never to editor transforms.
nonisolated struct TrashMetadata: Codable, Equatable, Sendable {
    var deletedAt: Date
    var listTitle: String
    /// The list's icon at deletion; nil for items deleted before it was recorded.
    var listIcon: String?
    var parentTitle: String?
    var labels: [TrashLabel]
    var recoveryNote: String?

    var formerLocation: String {
        parentTitle.map { "\(listTitle) › \($0)" } ?? listTitle
    }
}

struct TrashEntry: Identifiable {
    var id: UUID
    var title: String
    var isList: Bool
    var metadata: TrashMetadata?
    var blockCount: Int
    var byteCount: Int
    var listCount: Int = 0
}

nonisolated struct TrashLabel: Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var accentRaw: String
    var sortIndex: Double
    var createdAt: Date
}
