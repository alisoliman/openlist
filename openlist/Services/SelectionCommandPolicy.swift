import Foundation

/// Bulk actions are explicit toolbar operations. Legacy task commands must
/// never toggle mixed states, delete a multi-selection or borrow its first row.
enum SelectionCommandPolicy {
    static func reject(_ command: EditorCommand, selectedCount: Int, store: Store) -> Bool {
        guard selectedCount > 1 else { return false }
        switch command {
        case .newTask, .expandAll, .collapseAll:
            return false
        default:
            store.editorNotice = "Use Complete, Reopen or Move in the selection bar. Select one row for other task actions."
            return true
        }
    }
}
