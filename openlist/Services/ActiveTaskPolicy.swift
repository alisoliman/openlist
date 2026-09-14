import Foundation

/// Archived lists retain their documents, but stop contributing to active
/// work, badges, reminders and widgets. Keep every cross-list surface on the
/// same membership rule so archiving cannot leave a task behind elsewhere.
struct ActiveTaskPolicy {
    let activeListIDs: Set<UUID>

    init(lists: [TaskList]) {
        self.init(hierarchy: ListHierarchy(lists))
    }

    init(hierarchy: ListHierarchy) {
        activeListIDs = hierarchy.activeIDs
    }

    func includes(_ task: Block) -> Bool {
        guard !task.isTrashed, task.isTask, let listID = task.listID else { return false }
        return activeListIDs.contains(listID)
    }

    func tasks(in tasks: [Block]) -> [Block] {
        tasks.filter(includes)
    }
}
