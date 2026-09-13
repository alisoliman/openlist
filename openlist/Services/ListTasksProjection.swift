import Foundation
import SwiftData

/// A read-only queue of original tasks, in outline order before applying the
/// list's sort. Every descendant appears once, even beneath collapsed prose or
/// a completed parent. Completion visibility applies to each task separately.
struct ListTasksProjection {
    let tasks: [Block]
    let completedCount: Int
    let hiddenContentCount: Int

    init(blocks: [Block], listID: UUID, sorting: ListSorting, showsCompleted: Bool) {
        var seen: Set<UUID> = []
        let owned = blocks.filter { $0.listID == listID && !$0.isDeleted && seen.insert($0.id).inserted }
        let outlined = BlockTree.flatten(owned, respectCollapse: false).map(\.block)
        let allTasks = outlined.filter(\.isTask)
        completedCount = allTasks.filter(\.isCompleted).count
        hiddenContentCount = owned.count - allTasks.count
        tasks = sorting.sortedTasks(allTasks.filter { showsCompleted || !$0.isCompleted })
    }
}
