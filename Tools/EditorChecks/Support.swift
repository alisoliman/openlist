import Foundation
// These checks exercise the real store, with notifications isolated from the OS.
final class NotificationService {
    static let shared = NotificationService()
    var scheduled = Set<UUID>()
    func cancelReminder(for id: UUID) { scheduled.remove(id) }
    func cancelAll() { scheduled.removeAll() }
    func scheduleReminder(id: UUID, title: String, listName: String, at date: Date) { scheduled.insert(id) }
}
enum EditorCommand: Equatable {
    case newTask, toggleCompletion, openDetails, setDueToday, pickDueDate, clearDueDate, pickLabel, clearLabels, moveToInbox, removeFromList, toggleStar, indent, outdent, moveUp, moveDown, deleteSelection, expandAll, collapseAll
}
