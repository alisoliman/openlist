import Foundation
import SwiftData

// Frozen pre-iCloud persisted properties from 4bf580f. A separate executable
// writes this schema so migration is tested against an actual old SQLite store.
@Model final class TaskList {
    var id: UUID = UUID()
    var title: String = ""
    var icon: String = "📋"
    var accentRaw: String = "graphite"
    var summary: String = ""
    var isSystemInbox: Bool = false
    var sortIndex: Double = 0
    var sidebarIndex: Double = 0
    var sectionID: UUID?
    var isPinned: Bool = false
    var isArchived: Bool = false
    var sortingRaw: String = "manual"
    var showsCompleted: Bool = true
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var lastOpenedAt: Date?
    init() {}
}

@Model final class Block {
    var id: UUID = UUID()
    var kindRaw: String = "paragraph"
    var text: String = ""
    var richData: Data?
    var sortIndex: Double = 0
    var listID: UUID?
    var parentID: UUID?
    var isCollapsed: Bool = false
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var isCompleted: Bool = false
    var completedAt: Date?
    var dueDate: Date?
    var includesTime: Bool = false
    var reminderAt: Date?
    var isStarred: Bool = false
    var priorityRaw: Int = 0
    var recurrenceData: Data?
    var labelIDs: [UUID] = []
    var note: String = ""
    var mediaFilename: String?
    var mediaWidth: Double = 0
    var mediaHeight: Double = 0
    var mediaCaption: String = ""
    init() {}
}

@Model final class SidebarSection {
    var id: UUID = UUID()
    var title: String = ""
    var sortIndex: Double = 0
    var isCollapsed: Bool = false
    var isDefault: Bool = false
    var createdAt: Date = Date.now
    init() {}
}

@Model final class TaskLabel {
    var id: UUID = UUID()
    var name: String = ""
    var accentRaw: String = "violet"
    var sortIndex: Double = 0
    var createdAt: Date = Date.now
    init() {}
}

@Model final class Attachment {
    var id: UUID = UUID()
    var blockID: UUID?
    var filename: String = ""
    var displayName: String = ""
    var contentType: String = ""
    var byteCount: Int = 0
    var sortIndex: Double = 0
    var createdAt: Date = Date.now
    init() {}
}

@Model final class ActivityEvent {
    var id: UUID = UUID()
    var kindRaw: String = "created"
    var timestamp: Date = Date.now
    var title: String = ""
    var detail: String = ""
    var blockID: UUID?
    var listID: UUID?
    var listTitle: String = ""
    var listIcon: String = ""
    init() {}
}
