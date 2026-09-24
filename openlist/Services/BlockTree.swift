//
//  BlockTree.swift
//  openlist
//

import Foundation

/// A block paired with its computed position in the document outline.
struct BlockRow: Identifiable, Hashable {
    let id: UUID
    var block: Block
    /// Nesting depth, 0 at the document root.
    var depth: Int
    /// 1-based position among same-kind siblings, used to number ordered lists.
    var ordinal: Int
    /// `true` when this block has at least one child.
    var hasChildren: Bool
    /// `true` when the block's subtree is hidden.
    var isCollapsed: Bool

    init(block: Block, depth: Int, ordinal: Int, hasChildren: Bool, isCollapsed: Bool) {
        id = block.id
        self.block = block
        self.depth = depth
        self.ordinal = ordinal
        self.hasChildren = hasChildren
        self.isCollapsed = isCollapsed
    }

    static func == (lhs: BlockRow, rhs: BlockRow) -> Bool {
        lhs.id == rhs.id
            && lhs.depth == rhs.depth
            && lhs.ordinal == rhs.ordinal
            && lhs.hasChildren == rhs.hasChildren
            && lhs.isCollapsed == rhs.isCollapsed
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Pure functions that turn a flat array of blocks into an ordered outline.
///
/// Parentage lives in `Block.parentID` and ordering in `Block.sortIndex`, so
/// every view that renders a document runs the same flattening pass.
enum BlockTree {
    /// Reorders top-level blocks without disturbing their subtrees.
    ///
    /// Each depth-0 row travels with the deeper rows that follow it, so a
    /// sorted view still reads as a tree.
    static func sortingTaskRuns(in rows: [BlockRow], by sorting: ListSorting) -> [BlockRow] {
        guard sorting != .manual, !rows.isEmpty else { return rows }

        var chunks: [[BlockRow]] = []
        for row in rows {
            if row.depth == 0 || chunks.isEmpty {
                chunks.append([row])
            } else {
                chunks[chunks.count - 1].append(row)
            }
        }

        // Prose and headings define the reading order. Sort only contiguous
        // runs of top-level tasks, keeping each task's subtree with it.
        var result: [[BlockRow]] = []
        var taskRun: [[BlockRow]] = []
        func flush() {
            result += taskRun.enumerated().sorted {
                let left = $0.element[0].block, right = $1.element[0].block
                if sorting.precedes(left, right) { return true }
                if sorting.precedes(right, left) { return false }
                return $0.offset < $1.offset
            }.map(\.element)
            taskRun = []
        }
        for chunk in chunks {
            if chunk[0].block.isTask { taskRun.append(chunk) }
            else { flush(); result.append(chunk) }
        }
        flush()
        return result.flatMap { $0 }
    }

    /// Children of `parentID`, ordered by `sortIndex`.
    static func children(of parentID: UUID?, in blocks: [Block]) -> [Block] {
        childIndex(of: blocks, root: parentID)[parentID] ?? []
    }

    /// Depth-first flattening of the whole outline.
    ///
    /// - Parameters:
    ///   - blocks: every block in the container, at any depth.
    ///   - root: the parent to start from — `nil` for a list document, or a
    ///     task's id for the subtree under it.
    ///   - respectCollapse: when `true`, subtrees of collapsed blocks are skipped.
    static func flatten(
        _ blocks: [Block],
        root: UUID? = nil,
        respectCollapse: Bool = true,
        expanding: Set<UUID> = []
    ) -> [BlockRow] {
        // Bucket by parent once so the recursion is linear rather than O(n²).
        let byParent = childIndex(of: blocks, root: root)

        var rows: [BlockRow] = []
        rows.reserveCapacity(blocks.count)

        func visit(parent: UUID?, depth: Int) {
            let siblings = byParent[parent] ?? []
            var ordinal = 0
            var previousKind: BlockKind?

            for block in siblings {
                // Numbered lists restart whenever a different kind interrupts them.
                if block.kind == .numbered {
                    ordinal = previousKind == .numbered ? ordinal + 1 : 1
                } else {
                    ordinal = 0
                }
                previousKind = block.kind

                let kids = byParent[block.id] ?? []
                rows.append(
                    BlockRow(
                        block: block,
                        depth: depth,
                        ordinal: ordinal,
                        hasChildren: !kids.isEmpty,
                        isCollapsed: block.isCollapsed && !expanding.contains(block.id)
                    )
                )

                if !kids.isEmpty && !(respectCollapse && block.isCollapsed && !expanding.contains(block.id)) {
                    visit(parent: block.id, depth: depth + 1)
                }
            }
        }

        visit(parent: root, depth: 0)
        return rows
    }

    /// Hides the done tasks at depth 0, with their subtrees, keeping done
    /// subtasks where they were ticked. Revealed ancestors and targets stay
    /// visible without exposing every other done branch.
    static func hidingCompletedTasks(in rows: [BlockRow], revealing: Set<UUID> = []) -> [BlockRow] {
        var result: [BlockRow] = []
        var hidesBranch = false
        for row in rows {
            if row.depth == 0 {
                hidesBranch = row.block.isTask && row.block.isCompleted && !revealing.contains(row.id)
            }
            if !hidesBranch { result.append(row) }
        }
        return result
    }

    /// The done top-level tasks with a task still open somewhere below them,
    /// which a document hiding its done top-level tasks keeps on show, or
    /// that open task would go with it.
    static func completedTasksHoldingOpenTasks(in blocks: [Block]) -> Set<UUID> {
        let index = childIndex(of: blocks)
        var result: Set<UUID> = []
        for top in index[nil] ?? [] where top.isTask && top.isCompleted {
            if descendants(of: top.id, using: index).contains(where: { $0.isTask && !$0.isCompleted }) {
                result.insert(top.id)
            }
        }
        return result
    }

    // MARK: - Heading sections

    /// The level of a heading that bounds a section, `nil` for other kinds.
    static func sectionLevel(of kind: BlockKind) -> Int? {
        switch kind {
        case .heading1: 1
        case .heading2: 2
        case .heading3: 3
        default: nil
        }
    }

    /// Each top-level heading's section: the rows after it up to the next
    /// top-level heading of the same or a higher level, at any depth. Pass
    /// every row of the document, so a section counts what it hides too.
    static func sections(in rows: [BlockRow]) -> [UUID: ArraySlice<BlockRow>] {
        var sections: [UUID: ArraySlice<BlockRow>] = [:]
        for (index, row) in rows.enumerated() where row.depth == 0 {
            guard let level = sectionLevel(of: row.block.kind) else { continue }
            let rest = rows[(index + 1)...]
            let end = rest.firstIndex { $0.depth == 0 && (sectionLevel(of: $0.block.kind) ?? .max) <= level } ?? rows.endIndex
            sections[row.id] = rows[(index + 1)..<end]
        }
        return sections
    }

    /// The top-level headings whose sections hold `id`, nearest first: the
    /// heading above it, then each heading of a higher level above that one.
    static func enclosingSections(of id: UUID, in rows: [BlockRow]) -> [UUID] {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return [] }
        // A heading sits in the sections of higher-level headings only.
        var limit = rows[index].depth == 0 ? sectionLevel(of: rows[index].block.kind) ?? .max : .max
        var headings: [UUID] = []
        for row in rows[..<index].reversed() where row.depth == 0 {
            guard let level = sectionLevel(of: row.block.kind), level < limit else { continue }
            headings.append(row.id)
            limit = level
        }
        return headings
    }

    /// Hides a collapsed top-level heading's section, the way a collapsed
    /// task hides its subtree.
    static func hidingCollapsedSections(in rows: [BlockRow], revealing: Set<UUID> = []) -> [BlockRow] {
        var result: [BlockRow] = []
        var hiddenUntilLevel: Int?
        for row in rows {
            let level = row.depth == 0 ? sectionLevel(of: row.block.kind) : nil
            if let limit = hiddenUntilLevel {
                guard let level, level <= limit else { continue }
                hiddenUntilLevel = nil
            }
            result.append(row)
            if let level, row.block.isCollapsed, !revealing.contains(row.id) { hiddenUntilLevel = level }
        }
        return result
    }

    /// Buckets blocks by parent, sorted within each bucket.
    ///
    /// Callers that need more than one tree query should build this once and
    /// pass it in, rather than paying for it per lookup.
    static func childIndex(of blocks: [Block], root: UUID? = nil) -> [UUID?: [Block]] {
        let knownIDs = Set(blocks.map(\.id))
        var parents: [UUID: UUID] = [:]
        for block in blocks {
            if let parent = block.parentID, parent != block.id,
               knownIDs.contains(parent) || parent == root {
                parents[block.id] = parent
            }
        }
        // Concurrent moves can form a cycle even though each Mac validated its
        // own move. Break a deterministic edge in the projection, not in stored
        // data; incomplete imports must never cause destructive "repairs".
        var visited: Set<UUID> = []
        for block in blocks where !visited.contains(block.id) {
            var path: [UUID] = []
            var positions: [UUID: Int] = [:]
            var current: UUID? = block.id
            while let id = current, !visited.contains(id) {
                if let start = positions[id] {
                    if let anchor = path[start...].min(by: { $0.uuidString < $1.uuidString }) {
                        parents[anchor] = nil
                    }
                    break
                }
                positions[id] = path.count
                path.append(id)
                current = parents[id]
            }
            visited.formUnion(path)
        }
        var byParent: [UUID?: [Block]] = [:]
        for block in blocks {
            byParent[parents[block.id], default: []].append(block)
        }
        for key in byParent.keys {
            byParent[key]?.sort { lhs, rhs in
                if lhs.sortIndex != rhs.sortIndex { return lhs.sortIndex < rhs.sortIndex }
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        }
        return byParent
    }

    /// Every descendant of `blockID`, at any depth.
    ///
    /// Rebuilds the parent index on each call — fine for one-off use, but when
    /// walking many blocks hoist ``childIndex(of:)`` and use
    /// ``descendants(of:using:)``.
    static func descendants(of blockID: UUID, in blocks: [Block]) -> [Block] {
        descendants(of: blockID, using: childIndex(of: blocks, root: blockID))
    }

    /// Descendants resolved against a pre-built index.
    static func descendants(of blockID: UUID, using childIndex: [UUID?: [Block]]) -> [Block] {
        var result: [Block] = []
        var queue: [UUID] = [blockID]
        var visited: Set<UUID> = [blockID]
        while let current = queue.popLast() {
            let kids = (childIndex[current] ?? []).filter { visited.insert($0.id).inserted }
            result.append(contentsOf: kids)
            queue.append(contentsOf: kids.map(\.id))
        }
        return result
    }

    /// Walks up the parent chain, nearest ancestor first.
    static func ancestors(of block: Block, in blocks: [Block]) -> [Block] {
        var byID: [UUID: Block] = [:]
        for candidate in blocks { byID[candidate.id] = candidate }

        var result: [Block] = []
        var seen: Set<UUID> = [block.id]
        var current = block.parentID
        while let id = current, let parent = byID[id], !seen.contains(id) {
            result.append(parent)
            seen.insert(id)
            current = parent.parentID
        }
        return result
    }

    /// `true` when `candidateParent` sits inside `block`'s subtree, which would
    /// make a re-parent operation create a cycle.
    static func isDescendant(_ candidateParent: UUID, of block: UUID, in blocks: [Block]) -> Bool {
        descendants(of: block, in: blocks).contains { $0.id == candidateParent }
    }

    // MARK: - Fractional ordering

    /// The gap used when appending to the end of a sibling run.
    static let indexStep: Double = 1_024

    /// A sort index that places a new block immediately after `previous` and
    /// before `next`, without touching any existing row.
    static func index(after previous: Double?, before next: Double?) -> Double {
        switch (previous, next) {
        case let (.some(lower), .some(upper)):
            // Midpoint. If the gap has collapsed below representable precision
            // the caller is expected to renormalise the sibling run.
            let mid = (lower + upper) / 2
            return mid <= lower || mid >= upper ? lower + indexStep : mid
        case let (.some(lower), .none):
            return lower + indexStep
        case let (.none, .some(upper)):
            return upper - indexStep
        case (.none, .none):
            return 0
        }
    }

    /// `true` when neighbouring indices have converged and need respacing.
    static func needsRenormalisation<T: FractionallyOrdered>(_ siblings: [T]) -> Bool {
        guard siblings.count > 1 else { return false }
        for pair in zip(siblings, siblings.dropFirst())
        where pair.1.orderKey - pair.0.orderKey < 0.000_001 {
            return true
        }
        return false
    }

    /// Rewrites a sibling run onto clean, evenly spaced indices.
    static func renormalise<T: FractionallyOrdered>(_ siblings: [T]) {
        for (offset, item) in siblings.enumerated() {
            item.orderKey = Double(offset) * indexStep
        }
    }
}

/// Anything ordered by the fractional-index scheme above.
///
/// `TaskList` carries two independent orderings, so the conforming wrapper
/// picks which one participates rather than the model conforming twice.
protocol FractionallyOrdered: AnyObject {
    var orderKey: Double { get set }
}

extension Block: FractionallyOrdered {
    var orderKey: Double {
        get { sortIndex }
        set { sortIndex = newValue }
    }
}

extension SidebarSection: FractionallyOrdered {
    var orderKey: Double {
        get { sortIndex }
        set { sortIndex = newValue }
    }
}

/// Adapts a `TaskList`'s sidebar position to the ordering protocol.
final class SidebarOrdered: FractionallyOrdered {
    let list: TaskList

    init(_ list: TaskList) { self.list = list }

    var orderKey: Double {
        get { list.sidebarIndex }
        set { list.sidebarIndex = newValue }
    }
}

extension ListSorting {
    /// The same comparison serves both list presentations. Callers supply
    /// document order as a stable tie-breaker; no stored indices are changed.
    func precedes(_ lhs: Block, _ rhs: Block) -> Bool {
        switch self {
        case .manual: false
        case .dueDate: Block.byDueDate(lhs, rhs)
        case .createdAt: lhs.createdAt < rhs.createdAt
        case .alphabetical: lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
        case .priority: lhs.priorityRaw > rhs.priorityRaw
        }
    }

    func sortedTasks(_ tasks: [Block]) -> [Block] {
        guard self != .manual else { return tasks }
        return tasks.enumerated().sorted {
            if precedes($0.element, $1.element) { return true }
            if precedes($1.element, $0.element) { return false }
            return $0.offset < $1.offset
        }.map(\.element)
    }
}
