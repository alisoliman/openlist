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
enum DragPayload {
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
}
