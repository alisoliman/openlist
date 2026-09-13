import Foundation

struct TaskCaptureRequest: Identifiable {
    let id = UUID()
    var text = ""
    var suggestedListID: UUID?
    var plansForToday = false
    /// A list's Tasks view starts in that list and appends at the document root.
    /// A user-selected destination still wins; display position is never used.
    var appendsToSuggestedList = false
}
