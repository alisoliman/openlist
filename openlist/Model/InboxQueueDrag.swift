import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Inbox order is independent of outline ownership. Its private transfer type
/// cannot interpret a multi-row content move as a queue reorder or native text.
nonisolated struct InboxQueueDrag: Codable, Transferable {
    let taskID: UUID
    let sessionID: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: UTType(exportedAs: "app.openlist.inbox-order"))
    }
}
