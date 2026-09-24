import Foundation
import SwiftData

/// A logical, versioned reconstruction of the library, not a SQLite archive.
/// Historical references intentionally survive deletion of their subject.
nonisolated struct LibraryBackup: Codable, Equatable, Sendable {
    static let currentVersion = 5
    static let readableVersions: Set<Int> = [1, 2, 3, 4, 5]
    var version = currentVersion
    var libraryID: UUID
    var createdAt: Date
    var lists: [BackupTaskList]
    var blocks: [BackupBlock]
    var sections: [BackupSidebarSection]
    var labels: [BackupTaskLabel]
    var attachments: [BackupAttachment]
    var activity: [BackupActivityEvent]
    var workSessions: [BackupWorkSession]
    var completions: [BackupCompletionRecord]
    var placements: [BackupSchedulePlacement]
    var settings: LibraryBackupSettings

    init(libraryID: UUID, createdAt: Date,
         lists: [BackupTaskList],
         blocks: [BackupBlock],
         sections: [BackupSidebarSection],
         labels: [BackupTaskLabel],
         attachments: [BackupAttachment],
         activity: [BackupActivityEvent],
         workSessions: [BackupWorkSession],
         completions: [BackupCompletionRecord],
         placements: [BackupSchedulePlacement],
         settings: LibraryBackupSettings) {
        self.libraryID = libraryID
        self.createdAt = createdAt
        self.lists = lists
        self.blocks = blocks
        self.sections = sections
        self.labels = labels
        self.attachments = attachments
        self.activity = activity
        self.workSessions = workSessions
        self.completions = completions
        self.placements = placements
        self.settings = settings
    }

    /// Caller owns the quiescent, saved snapshot boundary. This deliberately
    /// does not save, migrate, reconcile or filter records from the context.
    @MainActor init(context: ModelContext, libraryID: UUID, settings: LibraryBackupSettings, createdAt: Date = .now) throws {
        self.libraryID = libraryID
        self.createdAt = createdAt
        self.settings = settings
        lists = try context.fetch(FetchDescriptor<TaskList>()).map(BackupTaskList.init).sorted { $0.id.uuidString < $1.id.uuidString }
        blocks = try context.fetch(FetchDescriptor<Block>()).map(BackupBlock.init).sorted { $0.id.uuidString < $1.id.uuidString }
        sections = try context.fetch(FetchDescriptor<SidebarSection>()).map(BackupSidebarSection.init).sorted { $0.id.uuidString < $1.id.uuidString }
        labels = try context.fetch(FetchDescriptor<TaskLabel>()).map(BackupTaskLabel.init).sorted { $0.id.uuidString < $1.id.uuidString }
        attachments = try context.fetch(FetchDescriptor<Attachment>()).map(BackupAttachment.init).sorted { $0.id.uuidString < $1.id.uuidString }
        activity = try context.fetch(FetchDescriptor<ActivityEvent>()).map(BackupActivityEvent.init).sorted { $0.id.uuidString < $1.id.uuidString }
        workSessions = try context.fetch(FetchDescriptor<WorkSession>()).map(BackupWorkSession.init).sorted { $0.id.uuidString < $1.id.uuidString }
        completions = try context.fetch(FetchDescriptor<CompletionRecord>()).map(BackupCompletionRecord.init).sorted { $0.id.uuidString < $1.id.uuidString }
        placements = try context.fetch(FetchDescriptor<SchedulePlacement>()).map(BackupSchedulePlacement.init).sorted { $0.id.uuidString < $1.id.uuidString }
    }

    var taskCount: Int { blocks.filter { $0.kindRaw == BlockKind.task.rawValue }.count }
    var recordCount: Int { lists.count + blocks.count + sections.count + labels.count + attachments.count + activity.count + workSessions.count + completions.count + placements.count }

    @MainActor func insert(into context: ModelContext) {
        lists.forEach { context.insert($0.model()) }
        blocks.forEach { context.insert($0.model()) }
        sections.forEach { context.insert($0.model()) }
        labels.forEach { context.insert($0.model()) }
        attachments.forEach { context.insert($0.model()) }
        activity.forEach { context.insert($0.model()) }
        workSessions.forEach { context.insert($0.model()) }
        completions.forEach { context.insert($0.model()) }
        placements.forEach { context.insert($0.model()) }
    }

    /// Version 1 had no queue membership. Preserve nil so the ownership-aware
    /// migration classifies legacy tasks only after the restored library opens.
    mutating func upgradeToCurrentVersion() throws {
        guard Self.readableVersions.contains(version) else { throw LibraryBackupError.unsupportedVersion(version) }
        if version == 1 {
            guard blocks.allSatisfy({ $0.inboxMembershipData == nil }) else {
                throw LibraryBackupError.invalid("A version 1 backup contains unsupported Inbox selection data.")
            }
        }
        if version < 3 {
            guard blocks.allSatisfy({ $0.trashID == nil && $0.trashMetadataData == nil }),
                  lists.allSatisfy({ $0.trashID == nil && $0.trashMetadataData == nil }) else {
                throw LibraryBackupError.invalid("An older backup contains unsupported Trash data.")
            }
        }
        if version < 4 {
            guard lists.allSatisfy({ $0.coverFilename == nil && $0.coverData == nil && $0.coverMetadataData == nil && $0.coverPresentationRaw == nil }) else {
                throw LibraryBackupError.invalid("An older backup contains unsupported list cover data.")
            }
        }
        if version < 5, lists.contains(where: { $0.parentListID != nil }) {
            throw LibraryBackupError.invalid("An older backup contains unsupported list ownership.")
        }
        version = Self.currentVersion
    }

    func validate() throws {
        guard version == Self.currentVersion else { throw LibraryBackupError.unsupportedVersion(version) }
        guard recordCount <= 1_000_000 else { throw LibraryBackupError.invalid("This backup exceeds the supported limit of one million records.") }
        func unique(_ ids: [UUID], _ name: String) throws -> Set<UUID> {
            let result = Set(ids)
            guard result.count == ids.count else { throw LibraryBackupError.invalid("Duplicate \(name) identity.") }
            return result
        }
        let listIDs = try unique(lists.map(\.id), "list")
        let blockIDs = try unique(blocks.map(\.id), "block")
        let sectionIDs = try unique(sections.map(\.id), "section")
        let labelIDs = try unique(labels.map(\.id), "label")
        _ = try unique(attachments.map(\.id), "attachment")
        _ = try unique(activity.map(\.id), "activity")
        _ = try unique(workSessions.map(\.id), "work session")
        _ = try unique(completions.map(\.id), "completion")
        _ = try unique(placements.map(\.id), "placement")

        func reference(_ id: UUID?, in ids: Set<UUID>, _ description: String) throws {
            if let id, !ids.contains(id) { throw LibraryBackupError.invalid("Missing \(description): \(id).") }
        }
        for list in lists {
            _ = try ListCoverMetadata.validatePayload(filename: list.coverFilename, data: list.coverData,
                metadataData: list.coverMetadataData, presentationRaw: list.coverPresentationRaw)
            if list.trashID == nil { try reference(list.sectionID, in: sectionIDs, "sidebar section") }
            try reference(list.mergedIntoID, in: listIDs, "list alias destination")
            guard ListSorting(rawValue: list.sortingRaw) != nil else { throw LibraryBackupError.invalid("Unsupported list sorting value.") }
        }
        for section in sections { try reference(section.mergedIntoID, in: sectionIDs, "section alias destination") }
        let byID = Dictionary(uniqueKeysWithValues: blocks.map { ($0.id, $0) })
        for block in blocks {
            if block.trashID == nil {
                try reference(block.listID, in: listIDs, "list for a line")
                try reference(block.parentID, in: blockIDs, "parent line")
            }
            if let parentID = block.parentID, let parent = byID[parentID], parent.listID != block.listID, block.trashID == nil {
                throw LibraryBackupError.invalid("A parent line belongs to a different list.")
            }
            if block.trashID == nil { for id in block.labelIDs { try reference(id, in: labelIDs, "task label") } }
            guard BlockKind(rawValue: block.kindRaw) != nil, TaskPriority(rawValue: block.priorityRaw) != nil else {
                throw LibraryBackupError.invalid("Unsupported line kind or priority.")
            }
        }
        let listsByID = Dictionary(uniqueKeysWithValues: lists.map { ($0.id, $0) })
        var trashMetadata: [UUID: TrashMetadata] = [:]
        for list in lists where list.trashID != nil {
            guard !list.isSystemInbox, list.mergedIntoID == nil else {
                throw LibraryBackupError.invalid("Invalid retained system list.")
            }
            if list.trashID != list.id { continue }
            guard
                  let data = list.trashMetadataData,
                  let metadata = try? JSONDecoder().decode(TrashMetadata.self, from: data) else {
                throw LibraryBackupError.invalid("Invalid retained list recovery information.")
            }
            trashMetadata[list.id] = metadata
        }
        for list in lists {
            if list.isSystemInbox && list.parentListID != nil {
                throw LibraryBackupError.invalid("The Inbox cannot be a nested list.")
            }
            if list.parentListID.flatMap({ listsByID[$0] })?.isSystemInbox == true {
                throw LibraryBackupError.invalid("The Inbox cannot hold nested lists.")
            }
            if let group = list.trashID, group != list.id {
                var next = list.parentListID, seen: Set<UUID> = [list.id]
                var reachedRoot = false
                while let id = next, seen.insert(id).inserted, let parent = listsByID[id], parent.trashID == group {
                    if id == group { reachedRoot = true; break }
                    next = parent.parentListID
                }
                guard reachedRoot, trashMetadata[group] != nil else {
                    throw LibraryBackupError.invalid("A nested list kept in Trash has no Trash entry of its own.")
                }
            }
        }
        for block in blocks where block.trashID == block.id {
            guard trashMetadata[block.id] == nil, let data = block.trashMetadataData,
                  let metadata = try? JSONDecoder().decode(TrashMetadata.self, from: data) else {
                throw LibraryBackupError.invalid("Invalid retained content recovery information.")
            }
            trashMetadata[block.id] = metadata
        }
        for block in blocks {
            if let group = block.trashID {
                guard let metadata = trashMetadata[group] else { throw LibraryBackupError.invalid("Missing Trash group.") }
                if let list = listsByID[group], list.trashID == group {
                    guard block.listID.flatMap({ listsByID[$0] })?.trashID == group,
                          block.parentID == nil || (byID[block.parentID!]?.trashID == group
                            && byID[block.parentID!]?.listID == block.listID) else {
                        throw LibraryBackupError.invalid("A retained list has content outside its hierarchy.")
                    }
                } else if block.id != group {
                    guard block.listID == byID[group]?.listID, let parentID = block.parentID,
                          byID[parentID]?.trashID == group else {
                        throw LibraryBackupError.invalid("Content kept in Trash has a missing or unrelated parent.")
                    }
                }
                let retainedLabels = Set(metadata.labels.map(\.id))
                for id in block.labelIDs where !labelIDs.contains(id) && !retainedLabels.contains(id) {
                    throw LibraryBackupError.invalid("A retained task label has no recovery information.")
                }
            } else if block.listID.flatMap({ listsByID[$0] })?.trashID != nil
                || block.parentID.flatMap({ byID[$0] })?.trashID != nil {
                throw LibraryBackupError.invalid("Active content has a retained owner.")
            }
        }
        for attachment in attachments {
            guard let blockID = attachment.blockID, byID[blockID]?.kindRaw == BlockKind.task.rawValue else {
                throw LibraryBackupError.invalid("An attachment has no owning task.")
            }
            guard attachment.byteCount >= 0 else { throw LibraryBackupError.invalid("Invalid attachment size.") }
        }
        // Placement, completion, work and activity references may outlive the
        // task or occurrence. Preserve those UUIDs and historical snapshots.
        try validateAcyclic(Dictionary(uniqueKeysWithValues: blocks.map { ($0.id, $0.parentID) }))
        try validateAcyclic(Dictionary(uniqueKeysWithValues: lists.map { ($0.id, $0.mergedIntoID) }))
        try validateAcyclic(Dictionary(uniqueKeysWithValues: sections.map { ($0.id, $0.mergedIntoID) }))
        try settings.validate()
        // JSON's finite-number requirement also rejects NaN/Infinity in dates,
        // order indexes, dimensions, durations and nested encoded settings.
        _ = try JSONEncoder().encode(self)
    }

    private func validateAcyclic(_ parents: [UUID: UUID?]) throws {
        var finished = Set<UUID>()
        for start in parents.keys where !finished.contains(start) {
            var path = Set<UUID>()
            var next: UUID? = start
            while let id = next, !finished.contains(id) {
                guard path.insert(id).inserted else { throw LibraryBackupError.invalid("Cyclic parent or alias relationship.") }
                next = parents[id] ?? nil
            }
            finished.formUnion(path)
        }
    }
}

nonisolated enum LibraryBackupError: LocalizedError {
    case unsupportedVersion(Int)
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): "Backup format version \(version) is not supported by this version of Openlist."
        case .invalid(let message): message
        }
    }
}
