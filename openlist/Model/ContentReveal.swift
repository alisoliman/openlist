import Foundation
import SwiftData

/// A temporary display request; none of these values are persisted on a block.
struct ContentReveal: Identifiable, Equatable {
    enum Anchor: Hashable { case pageHeader, taskTitle(UUID), taskNote(UUID), blockNote(UUID), listSummary(UUID) }
    let id = UUID()
    let destination: SearchDestination
    let listID: UUID
    let taskID: UUID?
    let ancestorIDs: Set<UUID>
    let field: SearchField
    let query: String

    var blockID: UUID? {
        if case let .block(id) = destination { return id }
        return nil
    }
    var visiblePath: Set<UUID> { ancestorIDs.union(blockID.map { [$0] } ?? []) }

    func revealsSummary(for id: UUID) -> Bool { destination == .list(id) && field == .summary }

    enum Unavailable: LocalizedError {
        case deleted, missingList, changed
        var errorDescription: String? {
            switch self {
            case .deleted: "This result is no longer available. It may have been deleted. Search again to see current results."
            case .missingList: "This result’s list is no longer available. Search again after the library finishes updating."
            case .changed: "This result changed and no longer matches your search. Search again to see current results."
            }
        }
    }

    static func resolve(_ destination: SearchDestination, field: SearchField = .text, query: String = "",
                        blocks: [Block], lists: [TaskList]) throws -> ContentReveal {
        let list: TaskList?
        let block: Block?
        switch destination {
        case let .list(id):
            list = lists.first { $0.id == id && !$0.isTrashed && $0.mergedIntoID == nil }
            block = nil
            guard list != nil else { throw Unavailable.deleted }
        case let .block(id):
            block = blocks.first { $0.id == id && !$0.isTrashed && !$0.isDeleted }
            guard let block else { throw Unavailable.deleted }
            list = lists.first { $0.id == block.listID && !$0.isTrashed && $0.mergedIntoID == nil }
        }
        guard let list, !list.isDeleted else { throw Unavailable.missingList }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var currentField = field
        if !needle.isEmpty {
            let text = block?.text ?? list.title
            let supporting = block?.note ?? list.summary
            if field != .text, SearchOptions.matchRange(needle, in: supporting) != nil {
                currentField = block == nil ? .summary : .note
            } else if SearchOptions.matchRange(needle, in: text) != nil { currentField = .text }
            else if SearchOptions.matchRange(needle, in: supporting) != nil { currentField = block == nil ? .summary : .note }
            else { throw Unavailable.changed }
        }
        let ancestors = block.map { BlockTree.ancestors(of: $0, in: blocks.filter { $0.listID == list.id }) } ?? []
        return ContentReveal(destination: destination, listID: list.id,
            taskID: block.flatMap { $0.isTask ? $0.id : nil }, ancestorIDs: Set(ancestors.map(\.id)), field: currentField, query: needle)
    }
}
