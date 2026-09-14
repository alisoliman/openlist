import Foundation

// DTO adapter only; the preceding persisted schema has no ownership field.
extension TaskList {
    var parentListID: UUID? { get { nil } set {} }
}
