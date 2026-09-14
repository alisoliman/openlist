import Foundation
import SwiftData

/// Only immutable values cross to the search worker. Model reads happen on
/// MainActor inside the observed corpus view, including reads for non-matches.
nonisolated struct SearchCorpus: Equatable, Sendable {
    struct BlockRecord: Equatable, Sendable {
        let id: UUID
        let listID: UUID?
        let parentID: UUID?
        let text: String
        let note: String
        let displayTitle: String
        let isTask: Bool
        let isCompleted: Bool
        let updatedAt: Date
        let createdAt: Date
        let symbol: String
    }
    struct ListRecord: Equatable, Sendable {
        let id: UUID
        let title: String
        let displayTitle: String
        let summary: String
        let icon: String
        let accent: ListAccent
        let isArchived: Bool
        let mergedIntoID: UUID?
        let createdAt: Date
    }
    let blocks: [BlockRecord]
    let lists: [ListRecord]

    @MainActor
    init(blocks: [Block], lists: [TaskList]) {
        self.blocks = blocks.filter { !$0.isDeleted && !$0.isTrashed }.map {
            BlockRecord(id: $0.id, listID: $0.listID, parentID: $0.parentID,
                text: $0.text, note: $0.note, displayTitle: $0.displayTitle,
                isTask: $0.isTask, isCompleted: $0.isCompleted, updatedAt: $0.updatedAt,
                createdAt: $0.createdAt, symbol: $0.kind.symbol)
        }
        self.lists = lists.filter { !$0.isDeleted && !$0.isTrashed }.map {
            ListRecord(id: $0.id, title: $0.title, displayTitle: $0.displayTitle,
                summary: $0.summary, icon: $0.icon, accent: $0.accent,
                isArchived: $0.isArchived, mergedIntoID: $0.mergedIntoID, createdAt: $0.createdAt)
        }
    }
}
