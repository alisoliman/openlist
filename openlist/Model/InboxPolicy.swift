import Foundation

/// One projection for the queue, sidebar, menu and widget. Document ownership
/// and completion are independent; archived/missing sources retain selection.
struct InboxPolicy {
    let activeListIDs: Set<UUID>

    init(lists: [TaskList]) {
        self.init(hierarchy: ListHierarchy(lists))
    }

    init(hierarchy: ListHierarchy) {
        activeListIDs = hierarchy.activeIDs
    }

    static func selection(_ task: Block) -> InboxMembership? {
        guard !task.isTrashed, task.isTask, let data = task.inboxMembershipData,
              let value = try? InboxMembership.decode(data), value.included,
              value.occurrenceID == task.occurrenceID else { return nil }
        return value
    }

    func includes(_ task: Block) -> Bool {
        guard let listID = task.listID, activeListIDs.contains(listID) else { return false }
        return Self.selection(task) != nil
    }

    func ordered(_ tasks: [Block], showsCompleted: Bool = true) -> [Block] {
        tasks.compactMap { task -> (task: Block, order: Double)? in
            guard let listID = task.listID, activeListIDs.contains(listID),
                  showsCompleted || !task.isCompleted, let value = Self.selection(task), let order = value.order else { return nil }
            return (task, order)
        }.sorted {
            $0.order == $1.order ? $0.task.id.uuidString < $1.task.id.uuidString : $0.order < $1.order
        }.map(\.task)
    }

    func openCount(_ tasks: [Block]) -> Int {
        tasks.reduce(0) { $0 + (includes($1) && !$1.isCompleted ? 1 : 0) }
    }

    static func issue(in tasks: [Block]) -> String? {
        for task in tasks where task.isTask {
            guard let data = task.inboxMembershipData else { continue }
            do { _ = try InboxMembership.decode(data) }
            catch { return error.localizedDescription }
        }
        return nil
    }
}
