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

    /// A task snoozed from triage, or deferred to a later day, waits out of
    /// triage's queue and its counts until that day begins, then comes back
    /// by itself, on every device (`Block.deferredUntil`).
    static func isSnoozed(_ block: Block, now: Date, calendar: Calendar = .current) -> Bool {
        guard let day = block.deferredUntil else { return false }
        return calendar.startOfDay(for: day) > calendar.startOfDay(for: now)
    }
}
