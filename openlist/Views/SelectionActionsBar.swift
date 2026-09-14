import AppKit
import SwiftUI

struct SelectionActionsBar: View {
    let scopeID: UUID?
    @Environment(AppEnvironment.self) private var env
    @Environment(\.undoManager) private var undoManager

    private var ids: [UUID] {
        guard env.navigator.isSelectingRows, env.navigator.rowSelection.scopeID == scopeID else { return [] }
        return env.navigator.orderedSelection
    }

    var body: some View {
        if !ids.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    count
                    Spacer(minLength: 8)
                    actions
                }
                VStack(alignment: .leading, spacing: 8) {
                    count
                    HStack(spacing: 8) { actions }
                }
            }
            .padding(12)
            .background(.bar)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Selected rows actions")
        }
    }

    private var count: some View {
        Text("\(ids.count) selected")
            .font(Theme.Font.body)
            .monospacedDigit()
    }

    private var actions: some View {
        Group {
            Button("Complete") { setCompletion(true) }
                .disabled(!ids.contains { env.store.block(id: $0).map { $0.isTask && !$0.isCompleted } ?? false })
            Button("Reopen") { setCompletion(false) }
                .disabled(!ids.contains { env.store.block(id: $0).map { $0.isTask && $0.isCompleted } ?? false })
            Menu("Move", systemImage: "folder") {
                ForEach(env.store.allLists().filter { !$0.isEffectivelyArchived && $0.mergedIntoID == nil }) { list in
                    Button(list.isSystemInbox ? "Unfiled content" : list.displayTitle) { move(to: list.id) }
                }
            }
            .help("Move selected rows and their descendants to a list")
            Button("Delete", systemImage: "trash", role: .destructive, action: deleteSelection)
                .help("Move selected rows and their descendants to Trash. Restore them from Trash or Undo.")
            Button("Clear selection", systemImage: "xmark", action: env.navigator.clearSelection)
                .labelStyle(.iconOnly)
                .help("Clear selection (Escape in the selection gutter)")
        }
        .controlSize(.small)
    }

    private func setCompletion(_ completed: Bool) {
        let selected = ids
        NotificationCenter.default.post(name: .commitPendingTaskTitles, object: nil)
        do { _ = try env.store.setBulkCompletion(completed, ids: selected) }
        catch { env.store.editorNotice = error.localizedDescription }
    }

    private func move(to listID: UUID) {
        let selected = ids
        NotificationCenter.default.post(name: .commitPendingTaskTitles, object: nil)
        do {
            _ = try env.store.moveSelection(selected, to: listID,
                undoManager: undoManager ?? NSApp.keyWindow?.undoManager)
        } catch { env.store.editorNotice = error.localizedDescription }
    }

    private func deleteSelection() {
        let selected = ids
        NotificationCenter.default.post(name: .commitPendingTaskTitles, object: nil)
        do {
            if try env.store.trashSelection(selected, undoManager: undoManager ?? NSApp.keyWindow?.undoManager) {
                env.navigator.clearSelection()
            } else {
                env.store.editorNotice = env.store.trashError
            }
        } catch { env.store.editorNotice = error.localizedDescription }
    }
}
