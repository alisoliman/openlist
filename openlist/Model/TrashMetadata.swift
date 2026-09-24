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
    /// The tasks under a trashed task, which restore and erase with it.
    var subtaskCount: Int = 0

    /// What a block's entry holds besides itself, for its Trash row: "with 2
    /// subtasks", "with 1 nested item", "with 2 subtasks and 1 more item".
    /// Nil for a list, which counts its items, and for a block on its own.
    var nestedSummary: String? {
        guard !isList, blockCount > 1 else { return nil }
        let others = blockCount - 1 - subtaskCount
        var parts: [String] = []
        if subtaskCount > 0 { parts.append(subtaskCount == 1 ? "1 subtask" : "\(subtaskCount) subtasks") }
        if others > 0 {
            let noun = subtaskCount > 0 ? "more" : "nested"
            parts.append("\(others) \(noun) \(others == 1 ? "item" : "items")")
        }
        return "with " + parts.joined(separator: " and ")
    }
}

nonisolated struct TrashLabel: Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var accentRaw: String
    var sortIndex: Double
    var createdAt: Date
}
