//
//  BlockTree.swift
//  openlist
//

import Foundation

/// A block paired with its computed position in the document outline.
struct BlockRow: Identifiable, Hashable {
    var block: Block
    /// Nesting depth, 0 at the document root.
    var depth: Int
    /// 1-based position among same-kind siblings, used to number ordered lists.
    var ordinal: Int
    /// `true` when this block has at least one child.
    var hasChildren: Bool
    /// `true` when the block's subtree is hidden.
    var isCollapsed: Bool

    var id: UUID { block.id }

    static func == (lhs: BlockRow, rhs: BlockRow) -> Bool {
        lhs.block.id == rhs.block.id
            && lhs.depth == rhs.depth
            && lhs.ordinal == rhs.ordinal
            && lhs.hasChildren == rhs.hasChildren
            && lhs.isCollapsed == rhs.isCollapsed
    }

    func hash(into hasher: inout Hasher) { hasher.combine(block.id) }
}

/// Pure functions that turn a flat array of blocks into an ordered outline.
///
/// Parentage lives in `Block.parentID` and ordering in `Block.sortIndex`, so
/// every view that renders a document runs the same flattening pass.
enum BlockTree {
    /// A display projection: completed tasks settle below pending siblings,
    /// carrying their entire subtree. Stored manual order is untouched, so
    /// reopening a task restores its position and exports keep document order.
    static func prioritizingPendingTasks(in rows: [BlockRow]) -> [BlockRow] {
        var index = 0
        func siblings(at depth: Int) -> [BlockRow] {
            var pending: [[BlockRow]] = []
            var completed: [[BlockRow]] = []
            while index < rows.count, rows[index].depth == depth {
                let row = rows[index]
                index += 1
                var branch = [row]
                if index < rows.count, rows[index].depth > depth {
                    branch += siblings(at: rows[index].depth)
                }
                if row.block.isTask && row.block.isCompleted {
                    completed.append(branch)
                } else {
                    pending.append(branch)
                }
            }
            return (pending + completed).flatMap { $0 }
        }
        guard let first = rows.first else { return [] }
        return siblings(at: first.depth)
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
    ///     task's id when rendering its detail page.
    ///   - respectCollapse: when `true`, subtrees of collapsed blocks are skipped.
    static func flatten(
        _ blocks: [Block],
        root: UUID? = nil,
        respectCollapse: Bool = true
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
                        isCollapsed: block.isCollapsed
                    )
                )

                if !kids.isEmpty && !(respectCollapse && block.isCollapsed) {
                    visit(parent: block.id, depth: depth + 1)
                }
            }
        }

        visit(parent: root, depth: 0)
        return rows
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
    /// walking many blocks prefer ``subtaskCounts(in:)`` or hoist
    /// ``childIndex(of:)`` and use ``descendants(of:using:)``.
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

    /// Completed/total subtask counts for **every** block, in one pass.
    ///
    /// Computing these individually is quadratic: each `descendants` call
    /// rebuilds the whole index. A document view needs the number for every
    /// row, so it wants the whole table at once.
    static func subtaskCounts(in blocks: [Block]) -> [UUID: (done: Int, total: Int)] {
        let index = childIndex(of: blocks)
        var counts: [UUID: (done: Int, total: Int)] = [:]
        counts.reserveCapacity(blocks.count)

        // Post-order: a block's totals are its children's totals plus the
        // children themselves, so each block is visited exactly once.
        func visit(_ block: Block) -> (done: Int, total: Int) {
            if let cached = counts[block.id] { return cached }

            var done = 0
            var total = 0
            for child in index[block.id] ?? [] {
                let sub = visit(child)
                if child.isTask {
                    total += 1
                    if child.isCompleted { done += 1 }
                }
                done += sub.done
                total += sub.total
            }

            let result = (done, total)
            counts[block.id] = result
            return result
        }

        for block in blocks where counts[block.id] == nil {
            _ = visit(block)
        }
        return counts
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
