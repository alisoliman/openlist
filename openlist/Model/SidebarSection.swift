//
//  SidebarSection.swift
//  openlist
//

import Foundation
import SwiftData

/// A user-defined grouping of lists in the sidebar.
///
/// Superlist ships one default section named "My lists" that collects pinned
/// lists until the user makes their own. Deleting a section never deletes the
/// lists inside it — they simply become unpinned.
@Model
final class SidebarSection {
    var id: UUID = UUID()
    var title: String = ""
    var sortIndex: Double = 0
    var isCollapsed: Bool = false
    /// The section created on first launch, which cannot be deleted.
    var isDefault: Bool = false
    /// Default sections created offline converge without discarding references.
    var mergedIntoID: UUID?
    var createdAt: Date = Date.now

    init(title: String, sortIndex: Double = 0, isDefault: Bool = false) {
        self.id = UUID()
        self.title = title
        self.sortIndex = sortIndex
        self.isDefault = isDefault
        self.createdAt = .now
    }
}

extension SidebarSection {
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled section" : trimmed
    }
}
