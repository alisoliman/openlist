import SwiftData
import SwiftUI

/// A context menu or inspector can outlive the model deleted by structural
/// Undo. Guard before all payload reads and again when a retained action fires.
struct InboxMembershipButton: View {
    let block: Block
    @Environment(AppEnvironment.self) private var env
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        if block.modelContext != nil, !block.isDeleted {
            let selected = InboxPolicy.selection(block) != nil
            Button(selected ? "Remove from Inbox" : "Add to Inbox", systemImage: selected ? "tray.and.arrow.up" : "tray.and.arrow.down") {
                guard block.modelContext != nil, !block.isDeleted else { return }
                env.store.setInboxMembership(InboxPolicy.selection(block) == nil, taskIDs: [block.id],
                    undoManager: undoManager ?? NSApp.keyWindow?.undoManager)
            }
            .help(selected ? "Keep this task in its source, and remove it from the Inbox queue (⇧⌘R)" : "Select this task for Inbox without moving its content (⇧⌘I)")
        }
    }
}
