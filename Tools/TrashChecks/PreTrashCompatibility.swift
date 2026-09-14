import Foundation

// These computed adapters let the current logical DTO describe the fixture.
// They are outside @Model and add no persisted fields to the prior schema.
extension Block {
    var isTrashed: Bool { false }
    var trashID: UUID? { get { nil } set {} }
    var trashMetadataData: Data? { get { nil } set {} }
}
extension TaskList {
    var trashID: UUID? { get { nil } set {} }
    var trashMetadataData: Data? { get { nil } set {} }
}
