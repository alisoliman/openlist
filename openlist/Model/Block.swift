//
//  Block.swift
//  openlist
//

import Foundation
import SwiftData

/// A single line of content inside a list document.
///
/// Blocks form an arbitrarily deep tree. Parentage is expressed with
/// `parentID` rather than a SwiftData relationship so that reordering,
/// re-parenting and cross-container moves stay cheap and predictable.
/// `sortIndex` uses fractional ordering: inserting between two neighbours is
/// just the midpoint of their indices, so a move touches exactly one row.
@Model
final class Block {
    var id: UUID = UUID()

    /// Retained records keep their identity and payload until explicitly erased.
    var trashID: UUID?
    /// Present on the root; retained after recovery to explain its former location.
    var trashMetadataData: Data?

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
    /// Free-form note shown under the title in the list document and the inspector.
    var note: String = ""

    /// Inert legacy queue payload, retained for CloudKit and backup compatibility.
    /// Inbox membership is now determined solely by list ownership.
    var inboxMembershipData: Data?

    // MARK: Adaptive calendar

    /// Zero inherits the editable default estimate for this Mac.
    var schedulingEstimateMinutes: Int = 0
    /// Selection is separate from a deadline and carries forward until done.
    var selectedForDay: Date?
    var deferredUntil: Date?
    var keepsSessionsTogether: Bool = false
    var tracksAwayFromMac: Bool = false
    /// Nil means the first occurrence, whose identity is the task's own UUID.
    /// A migration-time UUID() default would be shared by every existing row.
    var calendarOccurrenceID: UUID?

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

// MARK: - Derived accessors

extension Block {
    var isTrashed: Bool { trashID != nil }
    var trashMetadata: TrashMetadata? {
        trashMetadataData.flatMap { try? JSONDecoder().decode(TrashMetadata.self, from: $0) }
    }

    /// Repeating tasks retain task identity while recording each occurrence.
    var occurrenceID: UUID {
        get { calendarOccurrenceID ?? id }
        set { calendarOccurrenceID = newValue }
    }

    var kind: BlockKind {
        get { BlockKind(rawValue: kindRaw) ?? .paragraph }
        set { kindRaw = newValue.rawValue }
    }

    var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRaw) ?? .none }
        set { priorityRaw = newValue.rawValue }
    }

    var recurrence: Recurrence? {
        get { Recurrence.decode(recurrenceData) }
        set { recurrenceData = newValue?.jsonData }
    }

    var isTask: Bool { kind == .task }

    /// Text shown when the block is referenced from outside the editor.
    var displayTitle: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return kind == .image ? (mediaCaption.isEmpty ? "Image" : mediaCaption) : "Untitled"
    }

    var isOverdue: Bool {
        guard !isCompleted, let dueDate else { return false }
        return includesTime ? dueDate < .now : dueDate < Calendar.current.startOfDay(for: .now)
    }

    /// Finished at some point today — the set Today's "completed" group shows.
    var isCompletedToday: Bool {
        guard isCompleted, let completedAt else { return false }
        return Calendar.current.isDateInToday(completedAt)
    }

    /// Due today or already past — the set Today surfaces.
    var isDueOnOrBeforeToday: Bool {
        guard let dueDate else { return false }
        let calendar = Calendar.current
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)) else { return false }
        return dueDate < tomorrow
    }

    func touch() { updatedAt = .now }

    // MARK: Ordering

    /// Soonest due first; undated tasks sink to the bottom.
    static func byDueDate(_ lhs: Block, _ rhs: Block) -> Bool {
        switch (lhs.dueDate, rhs.dueDate) {
        case let (left?, right?):
            return left == right ? lhs.priorityRaw > rhs.priorityRaw : left < right
        case (nil, _?): return false
        case (_?, nil): return true
        case (nil, nil): return lhs.createdAt < rhs.createdAt
        }
    }

    /// Most recently finished first.
    static func byCompletionDate(_ lhs: Block, _ rhs: Block) -> Bool {
        (lhs.completedAt ?? .distantPast) > (rhs.completedAt ?? .distantPast)
    }

    // MARK: Copying

    /// Copies reusable content, excluding identity, tree position, and Inbox
    /// curation. An independent copy starts explicitly outside the queue.
    ///
    /// Kept on the model so "what a block contains" is defined once, rather
    /// than re-listed at each place that clones one.
    func copyPayload(from source: Block) {
        kindRaw = source.kindRaw
        text = source.text
        richData = source.richData
        isCollapsed = source.isCollapsed
        isCompleted = source.isCompleted
        completedAt = source.completedAt
        dueDate = source.dueDate
        includesTime = source.includesTime
        reminderAt = source.reminderAt
        isStarred = source.isStarred
        priorityRaw = source.priorityRaw
        recurrenceData = source.recurrenceData
        labelIDs = source.labelIDs
        note = source.note
        schedulingEstimateMinutes = source.schedulingEstimateMinutes
        keepsSessionsTogether = source.keepsSessionsTogether
        tracksAwayFromMac = source.tracksAwayFromMac
        mediaFilename = source.mediaFilename
        mediaData = source.mediaData
        mediaWidth = source.mediaWidth
        mediaHeight = source.mediaHeight
        mediaCaption = source.mediaCaption
    }
}

/// Optional urgency flag. Superlist's free tier keeps this lightweight, so
/// this maps to a simple none/low/medium/high scale used for sorting.
enum TaskPriority: Int, Codable, CaseIterable, Sendable {
    case none = 0
    case low = 1
    case medium = 2
    case high = 3

    var title: String {
        switch self {
        case .none: "No priority"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    /// Tint used for the checkbox ring and the detail chip.
    var accent: ListAccent? {
        switch self {
        case .none: nil
        case .low: .blue
        case .medium: .orange
        case .high: .red
        }
    }
}
