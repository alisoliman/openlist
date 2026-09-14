import Foundation

// DTO-only adapters do not add persisted fields to the actual prior model.
extension TaskList {
    var coverFilename: String? { get { nil } set {} }
    var coverData: Data? { get { nil } set {} }
    var coverMetadataData: Data? { get { nil } set {} }
    var coverPresentationRaw: String? { get { nil } set {} }
}

extension TaskList {
    var parentListID: UUID? { get { nil } set {} }
}
