import SwiftUI

/// Asks before a list goes to Trash, for those who keep Settings' "Confirm
/// before deleting a list" on. The design asks nothing, as Undo covers it;
/// either way the tray then offers Undo and Open Trash. So here, unlike
/// Settings' confirmations, Return confirms.
struct DeleteListSheet: View {
    let list: TaskList
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        NXConfirmationSheet(
            title: "Move “\(list.displayTitle)” to Trash?",
            message: "Its nested lists, tasks, notes and files go with it, as one item you can restore from Trash.",
            detail: env.sync.state.isEnabled ? "Undo (⌘Z) brings it straight back. With iCloud on, this also syncs to your other Macs."
                                             : "Undo (⌘Z) brings it straight back.",
            confirm: "Move to Trash",
            returnConfirms: true
        ) {
            env.performDeleteList(list)
        }
    }
}
