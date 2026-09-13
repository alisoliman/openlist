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
    case block
    case list

    private var prefix: String {
        switch self {
        case .block: "openlist-block:"
        case .list: "openlist-list:"
        }
    }

    func encode(_ id: UUID) -> String { prefix + id.uuidString }

    func decode(_ value: String) -> UUID? {
        guard value.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(value.dropFirst(prefix.count)))
    }

    enum BlockDrop: Equatable {
        case blocks([UUID])
        case text(String)
        case invalid
    }

    static func encodeBlocks(_ ids: [UUID], session: UUID) -> String {
        "openlist-blocks:v1:\(session.uuidString):" + ids.map(\.uuidString).joined(separator: ",")
    }

    /// A bare UUID has no library identity. Accept the legacy shape only when
    /// this environment is actively dragging that exact single row. The drop
    /// delegate captures that local authorization before asynchronous loading.
    static func blockDrop(_ value: String, session: UUID, activeLegacyID: UUID?) -> BlockDrop {
        if value.hasPrefix("openlist-blocks:") {
            let parts = value.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 4, parts[1] == "v1", UUID(uuidString: String(parts[2])) == session else { return .invalid }
            let values = parts[3].split(separator: ",", omittingEmptySubsequences: false)
            guard !values.isEmpty, values.count <= 10_000 else { return .invalid }
            let ids = values.compactMap { UUID(uuidString: String($0)) }
            guard ids.count == values.count, Set(ids).count == ids.count else { return .invalid }
            return .blocks(ids)
        }
        if value.hasPrefix("openlist-block:") {
            guard let id = DragPayload.block.decode(value), id == activeLegacyID else { return .invalid }
            return .blocks([id])
        }
        if value.hasPrefix("openlist-list:") { return .invalid }
        return .text(value)
    }
}
