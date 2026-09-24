import Foundation

/// A list document's multi-line selection, which a fragment paste can leave
/// behind until one of its lines takes the caret, takes New Task, Expand All
/// and Collapse All only. Task and structural commands must never toggle mixed
/// states, delete or move a multi-selection, or borrow its first line; the
/// tray says so, as for any other refused change.
enum SelectionCommandPolicy {
    static func reject(_ command: EditorCommand, selectedCount: Int, store: Store) -> Bool {
        guard selectedCount > 1 else { return false }
        switch command {
        case .newTask, .expandAll, .collapseAll:
            return false
        default:
            store.refuse("Select one line first.")
            return true
        }
    }
}
