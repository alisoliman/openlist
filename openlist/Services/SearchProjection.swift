import Foundation

/// One current projection of the local corpus. Selection and pagination live
/// in a child view, so moving through results does not repeat this scan.
nonisolated struct SearchProjection: Sendable {
    let hits: [SearchHit]

    init(corpus: SearchCorpus, options: SearchOptions) throws {
        let needle = options.needle
        guard !needle.isEmpty else { hits = []; return }
        try Task.checkCancellation()
        let blocks = corpus.blocks
        let lists = corpus.lists
        let listsByID = Dictionary(lists.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let blocksByID = Dictionary(blocks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [SearchHit] = []

        if options.scope == .everything || options.scope == .lists {
            let matching = try lists.enumerated().filter { offset, list in
                if offset.isMultiple(of: 128) { try Task.checkCancellation() }
                return list.mergedIntoID == nil && (options.includesArchived || !list.isArchived)
                    && (Self.matches(list.title, needle) || Self.matches(list.summary, needle))
            }.map(\.element).sorted {
                let order = $0.displayTitle.localizedStandardCompare($1.displayTitle)
                if order != .orderedSame { return order == .orderedAscending }
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return $0.id.uuidString < $1.id.uuidString
            }
            result += matching.map { list in
                let field: SearchField = Self.matches(list.title, needle) ? .text : .summary
                return SearchHit(id: .list(list.id), title: list.displayTitle,
                    context: (list.isArchived ? "Archived · " : "") + list.path,
                    snippet: list.summary.isEmpty ? "" : Self.snippet(list.summary, matching: needle),
                    symbol: nil, emoji: list.icon, accent: list.accent, field: field)
            }
        }

        if options.scope != .lists {
            let matching = try blocks.enumerated().filter { offset, block in
                if offset.isMultiple(of: 128) { try Task.checkCancellation() }
                if options.scope == .tasks && !block.isTask { return false }
                if options.scope == .notes && block.isTask { return false }
                if !options.includesArchived, block.listID.flatMap({ listsByID[$0] })?.isArchived == true { return false }
                if !options.includesCompleted && block.isCompleted { return false }
                return Self.matches(block.text, needle) || Self.matches(block.note, needle)
            }.map(\.element).sorted {
                if $0.isCompleted != $1.isCompleted { return !$0.isCompleted }
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
                return $0.id.uuidString < $1.id.uuidString
            }
            for (offset, block) in matching.enumerated() {
                if offset.isMultiple(of: 256) { try Task.checkCancellation() }
                let ancestors = Self.ancestors(of: block, byID: blocksByID)
                let completed = block.isCompleted || ancestors.contains { $0.isTask && $0.isCompleted }
                if !options.includesCompleted && completed { continue }
                let list = block.listID.flatMap { listsByID[$0] }
                let field: SearchField = Self.matches(block.text, needle) ? .text : .note
                var context = [list.map { "\($0.icon) \($0.path)" } ?? "Unavailable list"]
                context += ancestors.reversed().map(\.displayTitle)
                if list?.isArchived == true { context.append("Archived") }
                if completed { context.append("Completed") }
                result.append(SearchHit(id: .block(block.id), title: block.displayTitle,
                    context: context.joined(separator: " › "),
                    snippet: field == .text && block.text.utf8.count <= 160 && !block.text.contains("\n")
                        ? "" : Self.snippet(field == .note ? block.note : block.text, matching: needle),
                    symbol: block.isTask ? (block.isCompleted ? "checkmark.circle.fill" : "circle") : block.symbol,
                    emoji: nil, accent: list?.accent ?? .graphite, field: field))
            }
        }
        try Task.checkCancellation()
        hits = result
    }

    static func range(of needle: String, in text: String) -> Range<String.Index>? {
        SearchOptions.matchRange(needle, in: text)
    }

    static func matches(_ text: String, _ needle: String) -> Bool { range(of: needle, in: text) != nil }

    /// A grapheme-safe excerpt around the match, including note-only matches
    /// deep inside a long note, rather than always showing its opening words.
    static func snippet(_ text: String, matching needle: String) -> String {
        let match = range(of: needle, in: text)
        let start = text.index(match?.lowerBound ?? text.startIndex, offsetBy: -45, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(match?.upperBound ?? start, offsetBy: 110, limitedBy: text.endIndex) ?? text.endIndex
        let excerpt = text[start..<end].split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return (start == text.startIndex ? "" : "…") + excerpt + (end == text.endIndex ? "" : "…")
    }

    static func ancestors(of block: SearchCorpus.BlockRecord, byID: [UUID: SearchCorpus.BlockRecord]) -> [SearchCorpus.BlockRecord] {
        var result: [SearchCorpus.BlockRecord] = []
        var seen: Set<UUID> = [block.id]
        var parentID = block.parentID
        while let id = parentID, seen.insert(id).inserted, let parent = byID[id], parent.listID == block.listID {
            result.append(parent)
            parentID = parent.parentID
        }
        return result
    }
}
