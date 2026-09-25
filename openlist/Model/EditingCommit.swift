import Foundation

extension Notification.Name {
    /// The inspector's title and note drafts must reach the Store before the
    /// app resigns or quits, a backup or restore runs, or a trash or move
    /// becomes its own step.
    static let commitPendingEditorDrafts = Notification.Name("openlist.commitPendingEditorDrafts")
}
