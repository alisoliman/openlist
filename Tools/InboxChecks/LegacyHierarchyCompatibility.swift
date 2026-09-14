import Foundation

// Current read-only projections can compile against the exact pre-Inbox model.
// These adapters are outside @Model and add no fields to its persisted schema.
extension TaskList {
    var parentListID: UUID? { nil }
    var trashID: UUID? { nil }
}
