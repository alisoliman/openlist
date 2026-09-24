import SwiftUI

/// Asks before a list goes to Trash, for those who keep Settings' "Confirm
/// before deleting a list" on. The design asks nothing, as Undo covers it;
/// either way the tray then offers Undo and Open Trash.
struct DeleteListSheet: View {
    let list: TaskList
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let style = env.workbench.style
        VStack(alignment: .leading, spacing: 16) {
            NXPanelTitle("Move “\(list.displayTitle)” to Trash?")
            VStack(alignment: .leading, spacing: 8) {
                Text("Its nested lists, tasks, notes and files go with it, as one item you can restore from Trash.")
                    .foregroundStyle(NX.ink(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                Text(env.sync.state.isEnabled ? "Undo (⌘Z) brings it straight back. With iCloud on, this also syncs to your other Macs."
                                              : "Undo (⌘Z) brings it straight back.")
                    .foregroundStyle(NX.ink(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 12.5))
            .lineSpacing(2)
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(NXPanelButtonStyle(kind: .secondary))
                Button("Move to Trash", role: .destructive) {
                    dismiss()
                    env.performDeleteList(list)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(NXPanelButtonStyle(kind: .destructive))
            }
        }
        .padding(24)
        .frame(width: 430)
        .presentationBackground(NX.card)
        .tint(style.accent)
        // Presented from the window, outside the Next shell's style.
        .environment(\.nextStyle, style)
    }
}
