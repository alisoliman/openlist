import Foundation

extension Notification.Name {
    /// Local row drafts must reach the Store before lifecycle persistence.
    static let commitPendingTaskTitles = Notification.Name("openlist.commitPendingTaskTitles")
}
