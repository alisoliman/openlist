import Foundation

/// A task's independent place in the focus queue. One optional persisted blob
/// keeps the decision, order and occurrence together during synchronization.
nonisolated struct InboxMembership: Codable, Equatable, Sendable {
    static let currentVersion = 1
    static let excludedData = Data(#"{"version":1,"included":false}"#.utf8)

    var version = currentVersion
    var included: Bool
    var order: Double?
    var occurrenceID: UUID?
    /// Explicit decisions remain distinguishable from recurrence/default clears.
    var decisionID: UUID?

    static func included(order: Double, occurrenceID: UUID) -> Self {
        Self(included: true, order: order, occurrenceID: occurrenceID)
    }

    static func decode(_ data: Data) throws -> Self {
        let value = try JSONDecoder().decode(Self.self, from: data)
        try value.validate()
        return value
    }

    func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    private func validate() throws {
        guard version == Self.currentVersion else { throw InboxMembershipError.unsupportedVersion(version) }
        guard order?.isFinite != false, !included || (order != nil && occurrenceID != nil) else {
            throw InboxMembershipError.invalid
        }
    }
}

nonisolated enum InboxMembershipError: LocalizedError {
    case unsupportedVersion(Int), invalid, unavailable, ordering

    var errorDescription: String? {
        switch self {
        case let .unsupportedVersion(version):
            "This task's Inbox selection uses version \(version), which requires a newer Openlist. Its saved selection was kept."
        case .invalid:
            "This task's saved Inbox selection could not be read. Its data was kept; restore a backup or use a compatible Openlist version."
        case .unavailable:
            "This task or its source could not be read. No Inbox selection was changed."
        case .ordering:
            "These Inbox positions could not be saved. Reorder the existing queue, then try again. No selection was changed."
        }
    }
}
