import Foundation
// These checks exercise the real store, with notifications isolated from the OS.
final class NotificationService {
    static let shared = NotificationService()
    var scheduled = Set<UUID>()
    func cancelReminder(for id: UUID) { scheduled.remove(id) }
    func cancelAll() { scheduled.removeAll() }
    func scheduleReminder(id: UUID, title: String, listName: String, at date: Date) { scheduled.insert(id) }
    func reconcileReminders(_ values: [ReminderIntent]) { scheduled = Set(values.filter { $0.isEligible(at: .now) }.map(\.id)) }
    func reminderReadFailed(_ message: String) {}
}
enum EditorCommand: Equatable {
    case newTask, toggleCompletion, openDetails, setDueToday, pickDueDate, clearDueDate, pickLabel, clearLabels, addToInbox, removeFromInbox, toggleStar, indent, outdent, moveUp, moveDown, deleteSelection, expandAll, collapseAll
}
