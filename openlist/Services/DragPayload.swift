//
//  DragPayload.swift
//  openlist
//

import Foundation

/// Drag payloads travel as plain strings so a drop target can accept both
/// internal reorders and text dragged in from other apps.
///
/// Each kind carries its own prefix; anything without a known prefix is
/// treated as ordinary text by the receiving view.
nonisolated enum DragPayload {
    static let blockTypeIdentifier = "app.openlist.block-drag"
    /// A sidebar list's own type, which only the sidebar takes: a document
    /// line lists neither it nor text for it, so it marks no drop there.
    static let listTypeIdentifier = "app.openlist.list-drag"
    /// A sidebar list, dragged to reorder the sidebar.
    case list

    private var prefix: String { "openlist-list:" }

    func encode(_ id: UUID) -> String { prefix + id.uuidString }

    func decode(_ value: String) -> UUID? {
        guard value.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(value.dropFirst(prefix.count)))
    }

    /// The drag of `id`, on the list's own private type, so neither a line
    /// nor another app ever reads it as text.
    func provider(for id: UUID) -> NSItemProvider {
        let payload = encode(id)
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: Self.listTypeIdentifier, visibility: .ownProcess) { load in
            load(Data(payload.utf8), nil)
            return nil
        }
        return provider
    }

    enum BlockDrop: Equatable {
        case blocks([UUID])
        case text(String)
        case invalid
    }

    static func encodeBlocks(_ ids: [UUID], session: UUID) -> String {
        "openlist-blocks:v1:\(session.uuidString):" + ids.map(\.uuidString).joined(separator: ",")
    }

    /// Rows travel as `encodeBlocks`, tagged with this library's drag session.
    /// A bare UUID has no library identity, so the older single-row shape is
    /// never a local move, nor text to insert.
    static func blockDrop(_ value: String, session: UUID) -> BlockDrop {
        if value.hasPrefix("openlist-blocks:") {
            let parts = value.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 4, parts[1] == "v1", UUID(uuidString: String(parts[2])) == session else { return .invalid }
            let values = parts[3].split(separator: ",", omittingEmptySubsequences: false)
            guard !values.isEmpty, values.count <= 10_000 else { return .invalid }
            let ids = values.compactMap { UUID(uuidString: String($0)) }
            guard ids.count == values.count, Set(ids).count == ids.count else { return .invalid }
            return .blocks(ids)
        }
        if value.hasPrefix("openlist-block:") || value.hasPrefix("openlist-list:") { return .invalid }
        return .text(value)
    }
}
