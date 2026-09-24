import Foundation

/// A list document's multi-line selection takes structural commands only.
/// Task commands must never toggle mixed states, delete a multi-selection or
/// borrow its first line.
enum SelectionCommandPolicy {
    static func reject(_ command: EditorCommand, selectedCount: Int, store: Store) -> Bool {
        guard selectedCount > 1 else { return false }
        switch command {
        case .newTask, .expandAll, .collapseAll:
            return false
        default:
            store.editorNotice = "Select one line for task actions."
            return true
        }
    }
}
