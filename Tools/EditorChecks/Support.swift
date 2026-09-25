import Foundation
// These checks exercise the real store, with notifications isolated from the OS.
final class NotificationService {
    static let shared = NotificationService()
    var scheduled = Set<UUID>()
    func reconcileReminders(_ values: [ReminderIntent]) { scheduled = Set(values.filter { $0.isEligible(at: .now) }.map(\.id)) }
    func reminderReadFailed(_ message: String) {}
}
enum EditorCommand: Equatable {
    case toggleCompletion, openDetails, setDueToday, pickDueDate, clearDueDate, pickLabel, clearLabels, toggleStar, indent, outdent, moveUp, moveDown, deleteSelection, expandAll, collapseAll
}
