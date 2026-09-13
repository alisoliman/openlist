// Frozen pre-calendar schema. A separate process writes the migration fixture.
//
//  Block.swift
//  openlist
//

import Foundation
import SwiftData

/// A single line of content inside a list document or a task's detail page.
///
/// Blocks form an arbitrarily deep tree. Parentage is expressed with
/// `parentID` rather than a SwiftData relationship so that reordering,
/// re-parenting and cross-container moves stay cheap and predictable.
/// `sortIndex` uses fractional ordering: inserting between two neighbours is
/// just the midpoint of their indices, so a move touches exactly one row.
@Model
final class Block {
    var id: UUID = UUID()

    /// Raw `BlockKind`. Stored as a string for schema stability.
    var kindRaw: String = BlockKind.paragraph.rawValue

    /// Plain-text mirror of the block's content. Kept in sync with `richData`
    /// so search, sorting and quick previews never need to decode RTF.
    var text: String = ""

    /// RTF archive preserving inline bold / italic / strikethrough / code / links.
    var richData: Data?

    /// Fractional position among siblings.
    var sortIndex: Double = 0

    /// The document this block belongs to. Every block has one, including
    /// deeply nested subtasks, which makes list-scoped queries a single predicate.
    var listID: UUID?

    /// Parent block, or `nil` when the block sits at the document root.
    var parentID: UUID?

    /// Collapsed blocks hide their subtree in the editor.
    var isCollapsed: Bool = false

    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    // MARK: Task payload

    var isCompleted: Bool = false
    var completedAt: Date?
    var dueDate: Date?
    /// `true` when the user picked a specific time rather than just a day.
    var includesTime: Bool = false
    var reminderAt: Date?
    /// Starred tasks are surfaced at the top of Today and the Tasks view.
    var isStarred: Bool = false
    var priorityRaw: Int = 0
    /// JSON-encoded `Recurrence`.
    var recurrenceData: Data?
    var labelIDs: [UUID] = []
    /// Free-form note shown under the title in the task detail page.
    var note: String = ""

    // MARK: Image payload

    /// Relative filename inside the app's media directory.
    var mediaFilename: String?
    /// The local file is a cache; these bytes travel with the record in iCloud.
    @Attribute(.externalStorage) var mediaData: Data?
    var mediaWidth: Double = 0
    var mediaHeight: Double = 0
    var mediaCaption: String = ""

    init(
        kind: BlockKind = .paragraph,
        text: String = "",
        listID: UUID? = nil,
        parentID: UUID? = nil,
        sortIndex: Double = 0
    ) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.text = text
        self.listID = listID
        self.parentID = parentID
        self.sortIndex = sortIndex
        self.createdAt = .now
        self.updatedAt = .now
    }
}
