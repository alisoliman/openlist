import Foundation

/// The same ownership rule powers Inbox, its badge, the menu bar and widgets.
/// Legacy queue selections never pull filed content back into Inbox.
struct InboxPolicy {
    let inboxIDs: Set<UUID>

    init(lists: [TaskList]) { self.init(hierarchy: ListHierarchy(lists)) }

    init(hierarchy: ListHierarchy) {
        inboxIDs = hierarchy.inboxIDs
    }

    func includes(_ block: Block) -> Bool {
        !block.isTrashed && block.listID.map(inboxIDs.contains) == true
    }

    func openCount(_ blocks: [Block]) -> Int {
        blocks.filter { includes($0) && $0.isTask && !$0.isCompleted }.count
    }
}
