//
//  ActivityEvent.swift
//  openlist
//

import Foundation
import SwiftData

/// A record of something that happened, powering Activity's Changes and task history.
///
/// In shared Superlist workspaces this feed shows teammate activity. On the
/// personal side it becomes a personal history: what you completed, created,
/// rescheduled or moved, grouped by day.
@Model
final class ActivityEvent {
    var id: UUID = UUID()
    var kindRaw: String = ActivityKind.created.rawValue
    var timestamp: Date = Date.now

    /// Snapshot of the subject at the time of the event, so the feed still
    /// reads correctly after the underlying block is renamed or deleted.
    var title: String = ""
    var detail: String = ""

    var blockID: UUID?
    var listID: UUID?
    var listTitle: String = ""
    var listIcon: String = ""
    /// Optional, additive history details. Older events retain only their
    /// original text; absent values never imply a known before/after state.
    var changeData: Data?

    init(
        kind: ActivityKind,
        title: String,
        detail: String = "",
        blockID: UUID? = nil,
        listID: UUID? = nil,
        listTitle: String = "",
        listIcon: String = ""
    ) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.timestamp = .now
        self.title = title
        self.detail = detail
        self.blockID = blockID
        self.listID = listID
        self.listTitle = listTitle
        self.listIcon = listIcon
    }
}

extension ActivityEvent {
    var kind: ActivityKind {
        get { ActivityKind(rawValue: kindRaw) ?? .created }
        set { kindRaw = newValue.rawValue }
    }

    var change: TaskActivityChange? {
        get { changeData.flatMap { try? JSONDecoder().decode(TaskActivityChange.self, from: $0) } }
        set { changeData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }
}

enum ActivityKind: String, Codable, CaseIterable, Sendable {
    case created
    case completed
    case reopened
    case scheduled
    case unscheduled
    case moved
    case deleted
    case labeled
    case starred
    case listCreated
    case listDeleted
    case noteAdded
    case renamed
    case completionUndone
    case restored

    var symbol: String {
        switch self {
        case .created: "plus.circle.fill"
        case .completed: "checkmark.circle.fill"
        case .reopened: "arrow.uturn.backward.circle.fill"
        case .scheduled: "calendar.circle.fill"
        case .unscheduled: "calendar.badge.minus"
        case .moved: "arrow.right.circle.fill"
        case .deleted: "trash.circle.fill"
        case .labeled: "tag.circle.fill"
        case .starred: "star.circle.fill"
        case .listCreated: "folder.circle.fill"
        case .listDeleted: "folder.badge.minus"
        case .noteAdded: "text.bubble.fill"
        case .renamed: "pencil.circle.fill"
        case .completionUndone: "arrow.uturn.backward.circle.fill"
        case .restored: "arrow.uturn.backward.circle.fill"
        }
    }

    var verb: String {
        switch self {
        case .created: "Created"
        case .completed: "Completed"
        case .reopened: "Reopened"
        case .scheduled: "Scheduled"
        case .unscheduled: "Cleared date on"
        case .moved: "Moved"
        case .deleted: "Deleted"
        case .labeled: "Labelled"
        case .starred: "Starred"
        case .listCreated: "Created list"
        case .listDeleted: "Deleted list"
        case .noteAdded: "Added a note to"
        case .renamed: "Renamed"
        case .completionUndone: "Undid completion of"
        case .restored: "Restored"
        }
    }

    var accent: ListAccent {
        switch self {
        case .completed: .green
        case .created, .listCreated: .blue
        case .scheduled: .violet
        case .starred: .amber
        case .deleted, .listDeleted: .red
        case .labeled: .pink
        default: .graphite
        }
    }
}
