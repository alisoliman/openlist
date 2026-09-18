import SwiftUI
import SwiftData

/// Quiet at rest, discoverable on hover, selection, keyboard focus and VoiceOver.
/// Menus keep native keyboard navigation; every glyph has a help tag and label.
struct InboxRowActions: View {
    let block: Block
    let isRevealed: Bool
    let actions: BlockRowActions

    @Environment(AppEnvironment.self) private var env
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @FocusState private var focusedAction: String?

    private var revealed: Bool { isRevealed || focusedAction != nil || voiceOverEnabled }

    var body: some View {
        if block.modelContext != nil, !block.isDeleted {
            HStack(spacing: 0) {
                Menu {
                    let destinations = env.store.allLists().filter { !$0.isSystemInbox }
                    if destinations.isEmpty {
                        Text("Create a list in the sidebar to file this item")
                    }
                    ForEach(destinations) { list in
                        Button(ListHierarchy(destinations).path(for: list.id)) { file(to: list.id) }
                    }
                } label: { glyph("folder") }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .focused($focusedAction, equals: "file")
                .help("File into a list — removes this item from Inbox")
                .accessibilityLabel("File \(block.displayTitle) into a list")

                if block.isTask {
                    Menu {
                        Button("Today") { setDate { env.store.setDueToday($0) } }
                        Button("Tomorrow") { setDate { env.store.setDueTomorrow($0) } }
                        Button("Next week") { setDate { env.store.setDueNextWeek($0) } }
                        Button("Choose date…", action: actions.onOpenDetails)
                        if block.dueDate != nil {
                            Divider()
                            Button("Clear date") { setDate { env.store.setDueDate(nil, for: $0) } }
                        }
                    } label: { glyph("calendar") }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .focused($focusedAction, equals: "date")
                    .help("Set a due date — keeps this task in Inbox")
                    .accessibilityLabel("Set due date for \(block.displayTitle)")

                    Button(action: actions.onOpenDetails) { glyph("arrow.up.forward.square") }
                        .buttonStyle(.plain)
                        .focused($focusedAction, equals: "details")
                        .help("Open details (⌘↩)")
                        .accessibilityLabel("Open details for \(block.displayTitle)")
                }

                Button(role: .destructive) {
                    guard let current = env.store.block(id: block.id) else { return }
                    _ = env.store.trashBlocks([current], undoManager: undoManager ?? NSApp.keyWindow?.undoManager)
                } label: { glyph("trash") }
                .buttonStyle(.plain)
                .focused($focusedAction, equals: "trash")
                .help("Move to Trash")
                .accessibilityLabel("Move \(block.displayTitle) to Trash")
            }
            .opacity(revealed ? 1 : 0)
            .accessibilityHidden(false)
        }
    }

    private func glyph(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 12))
            .foregroundStyle(Theme.secondaryText)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
    }

    private func file(to destinationID: UUID) {
        guard let current = env.store.block(id: block.id),
              let destination = env.store.list(id: destinationID) else { return }
        do {
            _ = try env.store.moveSelection([current.id], to: destination.id,
                undoManager: undoManager ?? NSApp.keyWindow?.undoManager)
        } catch { env.store.editorNotice = error.localizedDescription }
    }

    private func setDate(_ mutation: (Block) -> Void) {
        guard let current = env.store.block(id: block.id), let listID = current.listID else { return }
        env.store.undoableEditorEdit(in: listID, name: "Set due date",
            undoManager: undoManager ?? NSApp.keyWindow?.undoManager) {
                mutation(current)
            }
    }
}
