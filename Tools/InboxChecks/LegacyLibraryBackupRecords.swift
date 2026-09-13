import Foundation
import SwiftData

// Version 1 explicitly lists every persisted field. Adding a model field requires
// updating this contract and the schema-coverage regression before shipping.
// Computed presentation state and SwiftData implementation details are excluded.

nonisolated struct BackupTaskList: Codable, Equatable, Sendable {
    var id: UUID
    var title: String
    var icon: String
    var accentRaw: String
    var summary: String
    var isSystemInbox: Bool
    var mergedIntoID: UUID?
    var sortIndex: Double
    var sidebarIndex: Double
    var sectionID: UUID?
    var isPinned: Bool
    var isArchived: Bool
    var sortingRaw: String
    var showsCompleted: Bool
    var completedVisibilityRaw: String?
    var availabilityCategoryRaw: String
    var createdAt: Date
    var updatedAt: Date
    var lastOpenedAt: Date?

    @MainActor init(_ value: TaskList) {
        id = value.id
        title = value.title
        icon = value.icon
        accentRaw = value.accentRaw
        summary = value.summary
        isSystemInbox = value.isSystemInbox
        mergedIntoID = value.mergedIntoID
        sortIndex = value.sortIndex
        sidebarIndex = value.sidebarIndex
        sectionID = value.sectionID
        isPinned = value.isPinned
        isArchived = value.isArchived
        sortingRaw = value.sortingRaw
        showsCompleted = value.showsCompleted
        completedVisibilityRaw = value.completedVisibilityRaw
        availabilityCategoryRaw = value.availabilityCategoryRaw
        createdAt = value.createdAt
        updatedAt = value.updatedAt
        lastOpenedAt = value.lastOpenedAt
    }

    @MainActor func model() -> TaskList {
        let value = TaskList()
        value.id = id
        value.title = title
        value.icon = icon
        value.accentRaw = accentRaw
        value.summary = summary
        value.isSystemInbox = isSystemInbox
        value.mergedIntoID = mergedIntoID
        value.sortIndex = sortIndex
        value.sidebarIndex = sidebarIndex
        value.sectionID = sectionID
        value.isPinned = isPinned
        value.isArchived = isArchived
        value.sortingRaw = sortingRaw
        value.showsCompleted = showsCompleted
        value.completedVisibilityRaw = completedVisibilityRaw
        value.availabilityCategoryRaw = availabilityCategoryRaw
        value.createdAt = createdAt
        value.updatedAt = updatedAt
        value.lastOpenedAt = lastOpenedAt
        return value
    }
}

nonisolated struct BackupBlock: Codable, Equatable, Sendable {
    var id: UUID
    var kindRaw: String
    var text: String
    var richData: Data?
    var sortIndex: Double
    var listID: UUID?
    var parentID: UUID?
    var isCollapsed: Bool
    var createdAt: Date
    var updatedAt: Date
    var isCompleted: Bool
    var completedAt: Date?
    var dueDate: Date?
    var includesTime: Bool
    var reminderAt: Date?
    var isStarred: Bool
    var priorityRaw: Int
    var recurrenceData: Data?
    var labelIDs: [UUID]
    var note: String
    var schedulingEstimateMinutes: Int
    var selectedForDay: Date?
    var deferredUntil: Date?
    var keepsSessionsTogether: Bool
    var tracksAwayFromMac: Bool
    var calendarOccurrenceID: UUID?
    var mediaFilename: String?
    var mediaData: Data?
    var mediaWidth: Double
    var mediaHeight: Double
    var mediaCaption: String

    @MainActor init(_ value: Block) {
        id = value.id
        kindRaw = value.kindRaw
        text = value.text
        richData = value.richData
        sortIndex = value.sortIndex
        listID = value.listID
        parentID = value.parentID
        isCollapsed = value.isCollapsed
        createdAt = value.createdAt
        updatedAt = value.updatedAt
        isCompleted = value.isCompleted
        completedAt = value.completedAt
        dueDate = value.dueDate
        includesTime = value.includesTime
        reminderAt = value.reminderAt
        isStarred = value.isStarred
        priorityRaw = value.priorityRaw
        recurrenceData = value.recurrenceData
        labelIDs = value.labelIDs
        note = value.note
        schedulingEstimateMinutes = value.schedulingEstimateMinutes
        selectedForDay = value.selectedForDay
        deferredUntil = value.deferredUntil
        keepsSessionsTogether = value.keepsSessionsTogether
        tracksAwayFromMac = value.tracksAwayFromMac
        calendarOccurrenceID = value.calendarOccurrenceID
        mediaFilename = value.mediaFilename
        mediaData = value.mediaData
        mediaWidth = value.mediaWidth
        mediaHeight = value.mediaHeight
        mediaCaption = value.mediaCaption
    }

    @MainActor func model() -> Block {
        let value = Block()
        value.id = id
        value.kindRaw = kindRaw
        value.text = text
        value.richData = richData
        value.sortIndex = sortIndex
        value.listID = listID
        value.parentID = parentID
        value.isCollapsed = isCollapsed
        value.createdAt = createdAt
        value.updatedAt = updatedAt
        value.isCompleted = isCompleted
        value.completedAt = completedAt
        value.dueDate = dueDate
        value.includesTime = includesTime
        value.reminderAt = reminderAt
        value.isStarred = isStarred
        value.priorityRaw = priorityRaw
        value.recurrenceData = recurrenceData
        value.labelIDs = labelIDs
        value.note = note
        value.schedulingEstimateMinutes = schedulingEstimateMinutes
        value.selectedForDay = selectedForDay
        value.deferredUntil = deferredUntil
        value.keepsSessionsTogether = keepsSessionsTogether
        value.tracksAwayFromMac = tracksAwayFromMac
        value.calendarOccurrenceID = calendarOccurrenceID
        value.mediaFilename = mediaFilename
        value.mediaData = mediaData
        value.mediaWidth = mediaWidth
        value.mediaHeight = mediaHeight
        value.mediaCaption = mediaCaption
        return value
    }
}

nonisolated struct BackupSidebarSection: Codable, Equatable, Sendable {
    var id: UUID
    var title: String
    var sortIndex: Double
    var isCollapsed: Bool
    var isDefault: Bool
    var mergedIntoID: UUID?
    var createdAt: Date

    @MainActor init(_ value: SidebarSection) {
        id = value.id
        title = value.title
        sortIndex = value.sortIndex
        isCollapsed = value.isCollapsed
        isDefault = value.isDefault
        mergedIntoID = value.mergedIntoID
        createdAt = value.createdAt
    }

    @MainActor func model() -> SidebarSection {
        let value = SidebarSection(title: "")
        value.id = id
        value.title = title
        value.sortIndex = sortIndex
        value.isCollapsed = isCollapsed
        value.isDefault = isDefault
        value.mergedIntoID = mergedIntoID
        value.createdAt = createdAt
        return value
    }
}

nonisolated struct BackupTaskLabel: Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var accentRaw: String
    var sortIndex: Double
    var createdAt: Date

    @MainActor init(_ value: TaskLabel) {
        id = value.id
        name = value.name
        accentRaw = value.accentRaw
        sortIndex = value.sortIndex
        createdAt = value.createdAt
    }

    @MainActor func model() -> TaskLabel {
        let value = TaskLabel(name: "")
        value.id = id
        value.name = name
        value.accentRaw = accentRaw
        value.sortIndex = sortIndex
        value.createdAt = createdAt
        return value
    }
}

nonisolated struct BackupAttachment: Codable, Equatable, Sendable {
    var id: UUID
    var blockID: UUID?
    var filename: String
    var contentData: Data?
    var displayName: String
    var contentType: String
    var byteCount: Int
    var sortIndex: Double
    var createdAt: Date

    @MainActor init(_ value: Attachment) {
        id = value.id
        blockID = value.blockID
        filename = value.filename
        contentData = value.contentData
        displayName = value.displayName
        contentType = value.contentType
        byteCount = value.byteCount
        sortIndex = value.sortIndex
        createdAt = value.createdAt
    }

    @MainActor func model() -> Attachment {
        let value = Attachment(blockID: UUID(), filename: "", displayName: "", contentType: "", byteCount: 0)
        value.id = id
        value.blockID = blockID
        value.filename = filename
        value.contentData = contentData
        value.displayName = displayName
        value.contentType = contentType
        value.byteCount = byteCount
        value.sortIndex = sortIndex
        value.createdAt = createdAt
        return value
    }
}

nonisolated struct BackupActivityEvent: Codable, Equatable, Sendable {
    var id: UUID
    var kindRaw: String
    var timestamp: Date
    var title: String
    var detail: String
    var blockID: UUID?
    var listID: UUID?
    var listTitle: String
    var listIcon: String
    var changeData: Data?

    @MainActor init(_ value: ActivityEvent) {
        id = value.id
        kindRaw = value.kindRaw
        timestamp = value.timestamp
        title = value.title
        detail = value.detail
        blockID = value.blockID
        listID = value.listID
        listTitle = value.listTitle
        listIcon = value.listIcon
        changeData = value.changeData
    }

    @MainActor func model() -> ActivityEvent {
        let value = ActivityEvent(kind: .created, title: "")
        value.id = id
        value.kindRaw = kindRaw
        value.timestamp = timestamp
        value.title = title
        value.detail = detail
        value.blockID = blockID
        value.listID = listID
        value.listTitle = listTitle
        value.listIcon = listIcon
        value.changeData = changeData
        return value
    }
}

nonisolated struct BackupWorkSession: Codable, Equatable, Sendable {
    var id: UUID
    var taskID: UUID
    var occurrenceID: UUID
    var listID: UUID?
    var title: String
    var startedAt: Date
    var endedAt: Date?
    var lastHeartbeatAt: Date
    var deviceID: String
    var correctedMinutes: Double?
    var pauseReason: String?
    var plannedIntervalsData: Data?

    @MainActor init(_ value: WorkSession) {
        id = value.id
        taskID = value.taskID
        occurrenceID = value.occurrenceID
        listID = value.listID
        title = value.title
        startedAt = value.startedAt
        endedAt = value.endedAt
        lastHeartbeatAt = value.lastHeartbeatAt
        deviceID = value.deviceID
        correctedMinutes = value.correctedMinutes
        pauseReason = value.pauseReason
        plannedIntervalsData = value.plannedIntervalsData
    }

    @MainActor func model() -> WorkSession {
        let value = WorkSession(task: Block(), deviceID: "")
        value.id = id
        value.taskID = taskID
        value.occurrenceID = occurrenceID
        value.listID = listID
        value.title = title
        value.startedAt = startedAt
        value.endedAt = endedAt
        value.lastHeartbeatAt = lastHeartbeatAt
        value.deviceID = deviceID
        value.correctedMinutes = correctedMinutes
        value.pauseReason = pauseReason
        value.plannedIntervalsData = plannedIntervalsData
        return value
    }
}

nonisolated struct BackupCompletionRecord: Codable, Equatable, Sendable {
    var id: UUID
    var taskID: UUID
    var occurrenceID: UUID
    var listID: UUID?
    var title: String
    var completedAt: Date
    var dueDate: Date?
    var estimateMinutes: Int
    var wasRecurring: Bool
    var plannedIntervalsData: Data?

    @MainActor init(_ value: CompletionRecord) {
        id = value.id
        taskID = value.taskID
        occurrenceID = value.occurrenceID
        listID = value.listID
        title = value.title
        completedAt = value.completedAt
        dueDate = value.dueDate
        estimateMinutes = value.estimateMinutes
        wasRecurring = value.wasRecurring
        plannedIntervalsData = value.plannedIntervalsData
    }

    @MainActor func model() -> CompletionRecord {
        let value = CompletionRecord(task: Block())
        value.id = id
        value.taskID = taskID
        value.occurrenceID = occurrenceID
        value.listID = listID
        value.title = title
        value.completedAt = completedAt
        value.dueDate = dueDate
        value.estimateMinutes = estimateMinutes
        value.wasRecurring = wasRecurring
        value.plannedIntervalsData = plannedIntervalsData
        return value
    }
}

nonisolated struct BackupSchedulePlacement: Codable, Equatable, Sendable {
    var id: UUID
    var taskID: UUID
    var occurrenceID: UUID
    var start: Date
    var end: Date
    var isPinned: Bool

    @MainActor init(_ value: SchedulePlacement) {
        id = value.id
        taskID = value.taskID
        occurrenceID = value.occurrenceID
        start = value.start
        end = value.end
        isPinned = value.isPinned
    }

    @MainActor func model() -> SchedulePlacement {
        let value = SchedulePlacement(task: Block(), start: .now, end: .now)
        value.id = id
        value.taskID = taskID
        value.occurrenceID = occurrenceID
        value.start = start
        value.end = end
        value.isPinned = isPinned
        return value
    }
}
