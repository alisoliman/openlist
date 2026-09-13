// Frozen pre-calendar schema. A separate process writes the migration fixture.
//
//  TaskList.swift
//  openlist
//

import Foundation
import SwiftData

/// A list document. In Superlist a list is not merely a checklist — it is a
/// rich document that happens to contain tasks, so its content lives in
/// `Block` rows keyed by `listID`.
@Model
final class TaskList {
    var id: UUID = UUID()
    var title: String = ""
    /// Emoji shown in the sidebar and list header.
    var icon: String = "📋"
    /// Raw `ListAccent` for the list's tint.
    var accentRaw: String = ListAccent.graphite.rawValue
    var summary: String = ""

    /// Inbox is a singleton system list that receives unfiled tasks.
    var isSystemInbox: Bool = false
    /// Retained aliases route late-arriving records from another Mac's Inbox.
    var mergedIntoID: UUID?

    /// Position among all lists.
    var sortIndex: Double = 0
    /// Position within its sidebar section.
    var sidebarIndex: Double = 0
    /// Section this list is pinned under in the sidebar. `nil` means the list
    /// is not pinned and is only reachable from the Lists view.
    var sectionID: UUID?
    var isPinned: Bool = false
    var isArchived: Bool = false

    /// Per-list display preferences.
    var sortingRaw: String = "manual"
    var showsCompleted: Bool = true

    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var lastOpenedAt: Date?

    init(
        title: String = "",
        icon: String = "📋",
        accent: ListAccent = .graphite,
        isSystemInbox: Bool = false
    ) {
        self.id = UUID()
        self.title = title
        self.icon = icon
        self.accentRaw = accent.rawValue
        self.isSystemInbox = isSystemInbox
        self.createdAt = .now
        self.updatedAt = .now
    }
}
