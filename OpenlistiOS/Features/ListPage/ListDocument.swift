import Foundation
import SwiftData

/// The phone's document projection shares the Mac's heading boundaries,
/// task folds and completed-task rules, without mutating any stored blocks.
@MainActor
struct ListDocument {
    let page: ListPageRows
    let selectableTasks: [Block]
    private let sections: Set<UUID>
    private let children: [UUID?: [Block]]
    private let closing: Set<UUID>

    init(blocks: [Block], sorting: ListSorting, closing: Set<UUID> = []) {
        let live = blocks.filter { $0.modelContext != nil && !$0.isDeleted && $0.trashID == nil }
        let children = BlockTree.childIndex(of: live)
        var page = BlockTree.listPage(live, sorting: sorting, tasksOnly: false, closing: closing)
        // An incomplete import can leave a missing parent or a cycle. The
        // outline promotes a stable root without changing stored ancestry;
        // the done fold must use those same roots or a done orphan vanishes.
        let drawn = Set(page.rows.map(\.id))
        page.completed = (children[nil] ?? []).filter {
            $0.isTask && $0.isCompleted && !closing.contains($0.id) && !drawn.contains($0.id)
        }.sorted(by: Block.byCompletionDate)
        self.page = page
        selectableTasks = page.rows.map(\.block).filter { $0.isTask && !$0.isCompleted && !closing.contains($0.id) }
        let outline = BlockTree.flatten(live, respectCollapse: false)
        sections = Set(BlockTree.sections(in: outline).filter { !$0.value.isEmpty }.keys)
        self.children = children
        self.closing = closing
    }

    func canDisclose(_ row: BlockRow) -> Bool {
        row.block.isTask ? row.hasChildren : sections.contains(row.id)
    }

    /// Immediate child tasks, matching the count in Task detail. Prose does
    /// not count as work, and a completed task still in its dwell counts done.
    func progress(for task: Block) -> (done: Int, total: Int)? {
        let tasks = (children[task.id] ?? []).filter(\.isTask)
        guard !tasks.isEmpty else { return nil }
        return (tasks.count { $0.isCompleted || closing.contains($0.id) }, tasks.count)
    }
}
