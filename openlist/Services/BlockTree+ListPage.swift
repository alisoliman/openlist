//
//  BlockTree+ListPage.swift
//  openlist
//

import Foundation
import SwiftData

/// What a list page draws, read-only: its rows, the done tasks it lists
/// apart in its "N done" fold, and the open count its header names.
struct ListPageRows {
    /// The rows in display order, each with its depth, fold and children.
    var rows: [BlockRow]
    /// The done tasks the fold lists, most recently done first.
    var completed: [Block]
    /// Tasks not done, or still closing, subtasks included: "7 open".
    var openCount: Int
}

extension BlockTree {
    /// The rows a list page draws from `live`, its document's blocks: every
    /// row without the done top-level tasks, which the page lists apart,
    /// unless a task under one is still open, and without the sections of
    /// collapsed headings. Done subtasks stay where they were ticked, as in
    /// the design.
    ///
    /// Only tasks fold what's under them: what a heading, list item or text
    /// line has folded still shows, and a heading folds its section instead.
    /// `tasksOnly` is the Tasks presentation: only the tasks, each as deep as
    /// the tasks above it, a heading folding nothing, and done tasks going by
    /// their depth among the tasks.
    ///
    /// - Parameters:
    ///   - expanding: blocks shown open whatever their stored fold says, as
    ///     the ancestors of a revealed line.
    ///   - collapsing: tasks shown folded whatever their stored fold says, for
    ///     a viewer that keeps its folds to itself.
    ///   - keeping: done tasks that stay in place, as those just ticked.
    ///   - revealing: a line to show through the headings folding it away.
    static func visibleRows(of live: [Block], sorting: ListSorting, tasksOnly: Bool,
                            expanding: Set<UUID> = [], collapsing: Set<UUID> = [], keeping: Set<UUID> = [],
                            revealing revealedID: UUID? = nil) -> [BlockRow] {
        let unfolding = Set(live.lazy.filter { !OutlinePolicy.folds($0.kind) && $0.isCollapsed }.map(\.id))
        let folding = collapsing.isEmpty ? []
            : Set(live.lazy.filter { OutlinePolicy.folds($0.kind) && collapsing.contains($0.id) }.map(\.id))
        let rows = sortingTaskRuns(in: flatten(live, expanding: unfolding.union(expanding), collapsing: folding), by: sorting)
        if tasksOnly {
            return hidingCompletedTasks(in: taskOutline(rows), revealing: keeping
                .union(completedTasksHoldingOpenTasks(in: live, atTaskLevel: true)))
        }
        let unfolded = revealedID.map { Set(enclosingSections(of: $0, in: rows)) } ?? []
        return hidingCompletedTasks(in: hidingCollapsedSections(in: rows, revealing: unfolded),
                                    revealing: keeping.union(completedTasksHoldingOpenTasks(in: live)))
    }

    /// The done tasks a list page lists under its document once they've
    /// settled: those done at its top level, or in the Tasks presentation
    /// any with no task above it, most recently done first. A done task the
    /// page still `drawn`, with a task under it still open, isn't listed
    /// twice, and one still `closing` stays where it was ticked.
    static func completedFold(of tasks: [Block], drawn: Set<UUID> = [], closing: Set<UUID> = [], tasksOnly: Bool,
                              parent: (UUID) -> Block?) -> [Block] {
        tasks.filter {
            $0.isCompleted && !closing.contains($0.id) && !drawn.contains($0.id)
                && ($0.parentID == nil || tasksOnly && !hasTaskAncestor($0, parent: parent))
        }
            .sorted(by: Block.byCompletionDate)
    }

    /// A list page from its document's blocks, as a read-only viewer draws
    /// it, Tasks by default as the phone's: `visibleRows`, the fold under
    /// them, and the open count.
    static func listPage(_ blocks: [Block], sorting: ListSorting, tasksOnly: Bool = true,
                         expanding: Set<UUID> = [], collapsing: Set<UUID> = [], closing: Set<UUID> = []) -> ListPageRows {
        let live = blocks.filter { $0.modelContext != nil && !$0.isDeleted && $0.trashID == nil }
        let rows = visibleRows(of: live, sorting: sorting, tasksOnly: tasksOnly, expanding: expanding,
                               collapsing: collapsing, keeping: closing)
        let byID = Dictionary(live.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let tasks = live.filter(\.isTask)
        let completed = completedFold(of: tasks, drawn: Set(rows.lazy.map(\.id)), closing: closing, tasksOnly: tasksOnly) {
            byID[$0]
        }
        return ListPageRows(rows: rows, completed: completed,
                            openCount: tasks.count { !$0.isCompleted || closing.contains($0.id) })
    }
}
