import Foundation

@MainActor final class NotificationService {
    static let shared = NotificationService()
    let client = FakeReminderClient()
    lazy var reminders = ReminderRecovery(client: client)
    func reconcileReminders(_ intents: [ReminderIntent]) { reminders.reconcile(intents) }
    func reminderReadFailed(_ message: String) { reminders.recordReadFailure(message) }
}
enum EditorCommand: Equatable {
    case newTask, toggleCompletion, openDetails, setDueToday, pickDueDate, clearDueDate, pickLabel, clearLabels, toggleStar, indent, outdent, moveUp, moveDown, deleteSelection, expandAll, collapseAll
}
