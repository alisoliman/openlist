import CoreData
import Foundation
import SwiftData

/// Owns a public SwiftData-to-Core Data model bridge. The model is frozen once
/// attached to a coordinator, never exposed, and all access is serialized.
/// This is a logical read snapshot; no live database files are copied.
nonisolated final class BackupSnapshotReader: @unchecked Sendable {
    private let model: NSManagedObjectModel
    private let schema: Schema
    private let lock = NSLock()

    @MainActor init(schema: Schema) throws {
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: schema) else {
            throw LibraryBackupError.invalid("The current library schema could not be read for backup.")
        }
        self.model = model
        self.schema = schema
    }

    func createStore(from snapshot: LibraryBackup, at url: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        try autoreleasepool {
            let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
            let store = try coordinator.addPersistentStore(type: .sqlite, at: url)
            defer { try? coordinator.remove(store) }
            let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            context.persistentStoreCoordinator = coordinator
            try context.performAndWait {
                func insert(_ name: String, _ values: [String: Any]) {
                    let record = NSEntityDescription.insertNewObject(forEntityName: name, into: context)
                    for (key, value) in values { record.setValue(value, forKey: key) }
                }
                for record in snapshot.lists { insert("TaskList", record.backupValues) }
                for record in snapshot.blocks { insert("Block", record.backupValues) }
                for record in snapshot.sections { insert("SidebarSection", record.backupValues) }
                for record in snapshot.labels { insert("TaskLabel", record.backupValues) }
                for record in snapshot.attachments { insert("Attachment", record.backupValues) }
                for record in snapshot.activity { insert("ActivityEvent", record.backupValues) }
                for record in snapshot.workSessions { insert("WorkSession", record.backupValues) }
                for record in snapshot.completions { insert("CompletionRecord", record.backupValues) }
                for record in snapshot.placements { insert("SchedulePlacement", record.backupValues) }
                try context.save()
            }
        }
    }

    func read(at url: URL, settings: LibraryBackupSettings, createdAt: Date = .now,
              afterFirstFetch: @Sendable () throws -> Void = {}) throws -> LibraryBackup {
        lock.lock()
        defer { lock.unlock() }
        return try readSnapshot(at: url, settings: settings, createdAt: createdAt,
                                isPrivateCopy: false, afterFirstFetch: afterFirstFetch)
    }

    /// Startup only: no application or synchronization writer may be open.
    /// Core Data copies the closed source with read-only options. Only this
    /// disposable copy permits the WAL initialization required to pin a cold
    /// SwiftData store. No CloudKit container or app bootstrap is constructed.
    func readClosedStore(at url: URL, settings: LibraryBackupSettings, createdAt: Date = .now,
                         temporaryDirectory: URL = FileManager.default.temporaryDirectory,
                         afterCopy: @Sendable (URL) throws -> Void = { _ in }) throws -> LibraryBackup {
        lock.lock()
        defer { lock.unlock() }
        let manager = FileManager.default
        let directory = temporaryDirectory.appendingPathComponent("OpenlistRestoreRead-\(UUID())", isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: false,
                                    attributes: [.posixPermissions: 0o700])
        do {
            let snapshot = try autoreleasepool {
                let options: [AnyHashable: Any] = [NSReadOnlyPersistentStoreOption: true,
                    NSMigratePersistentStoresAutomaticallyOption: false,
                    NSInferMappingModelAutomaticallyOption: false]
                let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: url, options: options)
                guard let raw = metadata[NSStoreUUIDKey] as? String, let sourceID = UUID(uuidString: raw) else {
                    throw LibraryBackupError.invalid("The saved library schema or identity could not be verified.")
                }
                let requiresMigration = !model.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata)
                if requiresMigration {
                    // Accept the shipped additive predecessors: pre-cover,
                    // pre-Trash, and pre-Inbox-membership. Only migrate the private copy.
                    let recognized = [0, 1, 2].contains { predecessor in
                        guard let legacy = model.copy() as? NSManagedObjectModel else { return false }
                        for entity in legacy.entities where entity.name == "Block" || entity.name == "TaskList" {
                            entity.properties = entity.properties.filter {
                                !(entity.name == "TaskList" && ["coverFilename", "coverData", "coverMetadataData", "coverPresentationRaw"].contains($0.name))
                                    && !(predecessor >= 1 && ["trashID", "trashMetadataData"].contains($0.name))
                                    && !(predecessor == 2 && entity.name == "Block" && $0.name == "inboxMembershipData")
                            }
                        }
                        return legacy.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata)
                    }
                    guard recognized else {
                        throw LibraryBackupError.invalid("This library uses an incompatible schema. Its files have been kept. Open it with a compatible Openlist version or recover a logical backup.")
                    }
                }
                let copiedURL = directory.appendingPathComponent("Openlist.store")
                try autoreleasepool {
                    let copier = NSPersistentStoreCoordinator(managedObjectModel: model)
                    try copier.replacePersistentStore(at: copiedURL, withPersistentStoreFrom: url,
                                                       sourceOptions: options, type: .sqlite)
                }
                // Check ownership and reject links before a migration opens
                // anything writable; recheck files created by migration below.
                try protectPrivateCopy(in: directory)
                if requiresMigration {
                    // SwiftData performs its supported lightweight migration
                    // only on this disposable copy. No original file, app
                    // context, cloud integration or bootstrap is opened here.
                    try autoreleasepool {
                        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema,
                            url: copiedURL, cloudKitDatabase: .none)])
                        withExtendedLifetime(container) {}
                    }
                }
                try protectPrivateCopy(in: directory)
                try afterCopy(directory)
                let value = try readSnapshot(at: copiedURL, settings: settings, createdAt: createdAt,
                                             isPrivateCopy: true, afterFirstFetch: {})
                guard value.libraryID == sourceID else {
                    throw LibraryBackupError.invalid("The recovery copy did not preserve the library identity.")
                }
                return value
            }
            try manager.removeItem(at: directory)
            return snapshot
        } catch {
            try? manager.removeItem(at: directory)
            throw error
        }
    }

    private func protectPrivateCopy(in directory: URL) throws {
        let manager = FileManager.default
        guard let files = manager.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            throw LibraryBackupError.invalid("The recovery copy could not be inspected.")
        }
        for case let url as URL in files {
            let attributes = try manager.attributesOfItem(atPath: url.path)
            let kind = attributes[.type] as? FileAttributeType
            guard kind == .typeDirectory || (kind == .typeRegular && (attributes[.referenceCount] as? NSNumber)?.intValue == 1) else {
                throw LibraryBackupError.invalid("The recovery copy contains an unsupported file.")
            }
            try manager.setAttributes([.posixPermissions: kind == .typeDirectory ? 0o700 : 0o600], ofItemAtPath: url.path)
        }
    }

    private func readSnapshot(at url: URL, settings: LibraryBackupSettings, createdAt: Date,
                              isPrivateCopy: Bool, afterFirstFetch: @Sendable () throws -> Void) throws -> LibraryBackup {
        return try autoreleasepool {
            let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
            let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: url)
            guard model.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata),
                  let raw = metadata[NSStoreUUIDKey] as? String, let libraryID = UUID(uuidString: raw) else {
                throw LibraryBackupError.invalid("The saved library schema or identity could not be verified.")
            }
            var options: [AnyHashable: Any] = [
                NSReadOnlyPersistentStoreOption: !isPrivateCopy,
                NSMigratePersistentStoresAutomaticallyOption: false,
                NSInferMappingModelAutomaticallyOption: false
            ]
            if isPrivateCopy {
                // SwiftData stores require history tracking for Core Data
                // coexistence; without it the framework forces read-only mode.
                options[NSPersistentHistoryTrackingKey] = true
            }
            let store = try coordinator.addPersistentStore(type: .sqlite, at: url, options: options)
            defer { try? coordinator.remove(store) }
            let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            context.persistentStoreCoordinator = coordinator
            return try context.performAndWait {
                // Pin before the first fetch; all nine entities and externally
                // stored bytes are materialized before releasing this generation.
                try context.setQueryGenerationFrom(.current)
                func payloadIDs(_ entity: String, _ property: String) throws -> Set<UUID> {
                    let request = NSFetchRequest<NSDictionary>(entityName: entity)
                    request.resultType = .dictionaryResultType
                    request.includesPendingChanges = false
                    request.propertiesToFetch = ["id"]
                    request.predicate = NSPredicate(format: "%K != nil", property)
                    return Set(try context.fetch(request).map { value in
                        guard let id = value["id"] as? UUID else { throw LibraryBackupError.invalid("A saved media identity could not be read.") }
                        return id
                    })
                }
                let expectedCovers = try payloadIDs("TaskList", "coverData")
                let expectedImages = try payloadIDs("Block", "mediaData")
                let expectedAttachments = try payloadIDs("Attachment", "contentData")
                func records<T>(_ name: String, _ decode: ([String: Any]) throws -> T) throws -> [T] {
                    let request = NSFetchRequest<NSDictionary>(entityName: name)
                    request.resultType = .dictionaryResultType
                    request.includesPendingChanges = false
                    request.sortDescriptors = [NSSortDescriptor(key: "id", ascending: true)]
                    return try context.fetch(request).map { dictionary in
                        guard let values = dictionary as? [String: Any] else {
                            throw LibraryBackupError.invalid("A saved library record could not be decoded.")
                        }
                        return try decode(values)
                    }
                }
                // Fetch a scalar-only entity first; every external payload is
                // hydrated after the same preflight and generation boundary.
                let sections = try records("SidebarSection", BackupSidebarSection.init(values:))
                try afterFirstFetch()
                let snapshot = LibraryBackup(
                    libraryID: libraryID, createdAt: createdAt,
                    lists: try records("TaskList", BackupTaskList.init(values:)),
                    blocks: try records("Block", BackupBlock.init(values:)),
                    sections: sections,
                    labels: try records("TaskLabel", BackupTaskLabel.init(values:)),
                    attachments: try records("Attachment", BackupAttachment.init(values:)),
                    activity: try records("ActivityEvent", BackupActivityEvent.init(values:)),
                    workSessions: try records("WorkSession", BackupWorkSession.init(values:)),
                    completions: try records("CompletionRecord", BackupCompletionRecord.init(values:)),
                    placements: try records("SchedulePlacement", BackupSchedulePlacement.init(values:)),
                    settings: settings)
                // Query generations pin row references, but Core Data can remove
                // an old external blob during a concurrent replacement/deletion.
                // Never mistake that missing payload for legacy file-only data.
                let hydratedCovers = Set(snapshot.lists.filter { $0.coverData != nil }.map(\.id))
                let hydratedImages = Set(snapshot.blocks.filter { $0.mediaData != nil }.map(\.id))
                let hydratedAttachments = Set(snapshot.attachments.filter { $0.contentData != nil }.map(\.id))
                guard expectedCovers.isSubset(of: hydratedCovers), expectedImages.isSubset(of: hydratedImages), expectedAttachments.isSubset(of: hydratedAttachments) else {
                    throw LibraryBackupError.invalid("Media changed while the backup was being read. No backup was created. Try again after synchronization finishes.")
                }
                try snapshot.validate()
                return snapshot
            }
        }
    }
}

private nonisolated struct BackupRecordValues {
    let values: [String: Any]
    func required<T>(_ key: String, as type: T.Type = T.self) throws -> T {
        guard let value = values[key] as? T else {
            throw LibraryBackupError.invalid("A saved record has an invalid or missing field: \(key).")
        }
        return value
    }
    func optional<T>(_ key: String, as type: T.Type = T.self) throws -> T? {
        guard let value = values[key], !(value is NSNull) else { return nil }
        guard let typed = value as? T else {
            throw LibraryBackupError.invalid("A saved record has an invalid field: \(key).")
        }
        return typed
    }
}

extension BackupTaskList {
    nonisolated fileprivate init(values: [String: Any]) throws {
        let record = BackupRecordValues(values: values)
        id = try record.required("id")
        trashID = try record.optional("trashID")
        trashMetadataData = try record.optional("trashMetadataData")
        title = try record.required("title")
        icon = try record.required("icon")
        accentRaw = try record.required("accentRaw")
        summary = try record.required("summary")
        coverFilename = try record.optional("coverFilename")
        coverData = try record.optional("coverData")
        coverMetadataData = try record.optional("coverMetadataData")
        coverPresentationRaw = try record.optional("coverPresentationRaw")
        isSystemInbox = try record.required("isSystemInbox")
        mergedIntoID = try record.optional("mergedIntoID")
        sortIndex = try record.required("sortIndex")
        sidebarIndex = try record.required("sidebarIndex")
        sectionID = try record.optional("sectionID")
        isPinned = try record.required("isPinned")
        isArchived = try record.required("isArchived")
        sortingRaw = try record.required("sortingRaw")
        showsCompleted = try record.required("showsCompleted")
        completedVisibilityRaw = try record.optional("completedVisibilityRaw")
        availabilityCategoryRaw = try record.required("availabilityCategoryRaw")
        createdAt = try record.required("createdAt")
        updatedAt = try record.required("updatedAt")
        lastOpenedAt = try record.optional("lastOpenedAt")
    }
}

extension BackupBlock {
    nonisolated fileprivate init(values: [String: Any]) throws {
        let record = BackupRecordValues(values: values)
        id = try record.required("id")
        trashID = try record.optional("trashID")
        trashMetadataData = try record.optional("trashMetadataData")
        kindRaw = try record.required("kindRaw")
        text = try record.required("text")
        richData = try record.optional("richData")
        sortIndex = try record.required("sortIndex")
        listID = try record.optional("listID")
        parentID = try record.optional("parentID")
        isCollapsed = try record.required("isCollapsed")
        createdAt = try record.required("createdAt")
        updatedAt = try record.required("updatedAt")
        isCompleted = try record.required("isCompleted")
        completedAt = try record.optional("completedAt")
        dueDate = try record.optional("dueDate")
        includesTime = try record.required("includesTime")
        reminderAt = try record.optional("reminderAt")
        isStarred = try record.required("isStarred")
        priorityRaw = try record.required("priorityRaw")
        recurrenceData = try record.optional("recurrenceData")
        labelIDs = try record.required("labelIDs")
        note = try record.required("note")
        inboxMembershipData = try record.optional("inboxMembershipData")
        schedulingEstimateMinutes = try record.required("schedulingEstimateMinutes")
        selectedForDay = try record.optional("selectedForDay")
        deferredUntil = try record.optional("deferredUntil")
        keepsSessionsTogether = try record.required("keepsSessionsTogether")
        tracksAwayFromMac = try record.required("tracksAwayFromMac")
        calendarOccurrenceID = try record.optional("calendarOccurrenceID")
        mediaFilename = try record.optional("mediaFilename")
        mediaData = try record.optional("mediaData")
        mediaWidth = try record.required("mediaWidth")
        mediaHeight = try record.required("mediaHeight")
        mediaCaption = try record.required("mediaCaption")
    }
}

extension BackupSidebarSection {
    nonisolated fileprivate init(values: [String: Any]) throws {
        let record = BackupRecordValues(values: values)
        id = try record.required("id")
        title = try record.required("title")
        sortIndex = try record.required("sortIndex")
        isCollapsed = try record.required("isCollapsed")
        isDefault = try record.required("isDefault")
        mergedIntoID = try record.optional("mergedIntoID")
        createdAt = try record.required("createdAt")
    }
}

extension BackupTaskLabel {
    nonisolated fileprivate init(values: [String: Any]) throws {
        let record = BackupRecordValues(values: values)
        id = try record.required("id")
        name = try record.required("name")
        accentRaw = try record.required("accentRaw")
        sortIndex = try record.required("sortIndex")
        createdAt = try record.required("createdAt")
    }
}

extension BackupAttachment {
    nonisolated fileprivate init(values: [String: Any]) throws {
        let record = BackupRecordValues(values: values)
        id = try record.required("id")
        blockID = try record.optional("blockID")
        filename = try record.required("filename")
        contentData = try record.optional("contentData")
        displayName = try record.required("displayName")
        contentType = try record.required("contentType")
        byteCount = try record.required("byteCount")
        sortIndex = try record.required("sortIndex")
        createdAt = try record.required("createdAt")
    }
}

extension BackupActivityEvent {
    nonisolated fileprivate init(values: [String: Any]) throws {
        let record = BackupRecordValues(values: values)
        id = try record.required("id")
        kindRaw = try record.required("kindRaw")
        timestamp = try record.required("timestamp")
        title = try record.required("title")
        detail = try record.required("detail")
        blockID = try record.optional("blockID")
        listID = try record.optional("listID")
        listTitle = try record.required("listTitle")
        listIcon = try record.required("listIcon")
        changeData = try record.optional("changeData")
    }
}

extension BackupWorkSession {
    nonisolated fileprivate init(values: [String: Any]) throws {
        let record = BackupRecordValues(values: values)
        id = try record.required("id")
        taskID = try record.required("taskID")
        occurrenceID = try record.required("occurrenceID")
        listID = try record.optional("listID")
        title = try record.required("title")
        startedAt = try record.required("startedAt")
        endedAt = try record.optional("endedAt")
        lastHeartbeatAt = try record.required("lastHeartbeatAt")
        deviceID = try record.required("deviceID")
        correctedMinutes = try record.optional("correctedMinutes")
        pauseReason = try record.optional("pauseReason")
        plannedIntervalsData = try record.optional("plannedIntervalsData")
    }
}

extension BackupCompletionRecord {
    nonisolated fileprivate init(values: [String: Any]) throws {
        let record = BackupRecordValues(values: values)
        id = try record.required("id")
        taskID = try record.required("taskID")
        occurrenceID = try record.required("occurrenceID")
        listID = try record.optional("listID")
        title = try record.required("title")
        completedAt = try record.required("completedAt")
        dueDate = try record.optional("dueDate")
        estimateMinutes = try record.required("estimateMinutes")
        wasRecurring = try record.required("wasRecurring")
        plannedIntervalsData = try record.optional("plannedIntervalsData")
    }
}

extension BackupSchedulePlacement {
    nonisolated fileprivate init(values: [String: Any]) throws {
        let record = BackupRecordValues(values: values)
        id = try record.required("id")
        taskID = try record.required("taskID")
        occurrenceID = try record.required("occurrenceID")
        start = try record.required("start")
        end = try record.required("end")
        isPinned = try record.required("isPinned")
    }
}

extension BackupTaskList {
    nonisolated fileprivate var backupValues: [String: Any] {
        var values: [String: Any] = [:]
        values["id"] = id
        if let trashID { values["trashID"] = trashID }
        if let trashMetadataData { values["trashMetadataData"] = trashMetadataData }
        values["title"] = title
        values["icon"] = icon
        values["accentRaw"] = accentRaw
        values["summary"] = summary
        if let coverFilename { values["coverFilename"] = coverFilename }
        if let coverData { values["coverData"] = coverData }
        if let coverMetadataData { values["coverMetadataData"] = coverMetadataData }
        if let coverPresentationRaw { values["coverPresentationRaw"] = coverPresentationRaw }
        values["isSystemInbox"] = isSystemInbox
        if let mergedIntoID { values["mergedIntoID"] = mergedIntoID }
        values["sortIndex"] = sortIndex
        values["sidebarIndex"] = sidebarIndex
        if let sectionID { values["sectionID"] = sectionID }
        values["isPinned"] = isPinned
        values["isArchived"] = isArchived
        values["sortingRaw"] = sortingRaw
        values["showsCompleted"] = showsCompleted
        if let completedVisibilityRaw { values["completedVisibilityRaw"] = completedVisibilityRaw }
        values["availabilityCategoryRaw"] = availabilityCategoryRaw
        values["createdAt"] = createdAt
        values["updatedAt"] = updatedAt
        if let lastOpenedAt { values["lastOpenedAt"] = lastOpenedAt }
        return values
    }
}

extension BackupBlock {
    nonisolated fileprivate var backupValues: [String: Any] {
        var values: [String: Any] = [:]
        values["id"] = id
        if let trashID { values["trashID"] = trashID }
        if let trashMetadataData { values["trashMetadataData"] = trashMetadataData }
        values["kindRaw"] = kindRaw
        values["text"] = text
        if let richData { values["richData"] = richData }
        values["sortIndex"] = sortIndex
        if let listID { values["listID"] = listID }
        if let parentID { values["parentID"] = parentID }
        values["isCollapsed"] = isCollapsed
        values["createdAt"] = createdAt
        values["updatedAt"] = updatedAt
        values["isCompleted"] = isCompleted
        if let completedAt { values["completedAt"] = completedAt }
        if let dueDate { values["dueDate"] = dueDate }
        values["includesTime"] = includesTime
        if let reminderAt { values["reminderAt"] = reminderAt }
        values["isStarred"] = isStarred
        values["priorityRaw"] = priorityRaw
        if let recurrenceData { values["recurrenceData"] = recurrenceData }
        values["labelIDs"] = labelIDs
        values["note"] = note
        if let inboxMembershipData { values["inboxMembershipData"] = inboxMembershipData }
        values["schedulingEstimateMinutes"] = schedulingEstimateMinutes
        if let selectedForDay { values["selectedForDay"] = selectedForDay }
        if let deferredUntil { values["deferredUntil"] = deferredUntil }
        values["keepsSessionsTogether"] = keepsSessionsTogether
        values["tracksAwayFromMac"] = tracksAwayFromMac
        if let calendarOccurrenceID { values["calendarOccurrenceID"] = calendarOccurrenceID }
        if let mediaFilename { values["mediaFilename"] = mediaFilename }
        if let mediaData { values["mediaData"] = mediaData }
        values["mediaWidth"] = mediaWidth
        values["mediaHeight"] = mediaHeight
        values["mediaCaption"] = mediaCaption
        return values
    }
}

extension BackupSidebarSection {
    nonisolated fileprivate var backupValues: [String: Any] {
        var values: [String: Any] = [:]
        values["id"] = id
        values["title"] = title
        values["sortIndex"] = sortIndex
        values["isCollapsed"] = isCollapsed
        values["isDefault"] = isDefault
        if let mergedIntoID { values["mergedIntoID"] = mergedIntoID }
        values["createdAt"] = createdAt
        return values
    }
}

extension BackupTaskLabel {
    nonisolated fileprivate var backupValues: [String: Any] {
        var values: [String: Any] = [:]
        values["id"] = id
        values["name"] = name
        values["accentRaw"] = accentRaw
        values["sortIndex"] = sortIndex
        values["createdAt"] = createdAt
        return values
    }
}

extension BackupAttachment {
    nonisolated fileprivate var backupValues: [String: Any] {
        var values: [String: Any] = [:]
        values["id"] = id
        if let blockID { values["blockID"] = blockID }
        values["filename"] = filename
        if let contentData { values["contentData"] = contentData }
        values["displayName"] = displayName
        values["contentType"] = contentType
        values["byteCount"] = byteCount
        values["sortIndex"] = sortIndex
        values["createdAt"] = createdAt
        return values
    }
}

extension BackupActivityEvent {
    nonisolated fileprivate var backupValues: [String: Any] {
        var values: [String: Any] = [:]
        values["id"] = id
        values["kindRaw"] = kindRaw
        values["timestamp"] = timestamp
        values["title"] = title
        values["detail"] = detail
        if let blockID { values["blockID"] = blockID }
        if let listID { values["listID"] = listID }
        values["listTitle"] = listTitle
        values["listIcon"] = listIcon
        if let changeData { values["changeData"] = changeData }
        return values
    }
}

extension BackupWorkSession {
    nonisolated fileprivate var backupValues: [String: Any] {
        var values: [String: Any] = [:]
        values["id"] = id
        values["taskID"] = taskID
        values["occurrenceID"] = occurrenceID
        if let listID { values["listID"] = listID }
        values["title"] = title
        values["startedAt"] = startedAt
        if let endedAt { values["endedAt"] = endedAt }
        values["lastHeartbeatAt"] = lastHeartbeatAt
        values["deviceID"] = deviceID
        if let correctedMinutes { values["correctedMinutes"] = correctedMinutes }
        if let pauseReason { values["pauseReason"] = pauseReason }
        if let plannedIntervalsData { values["plannedIntervalsData"] = plannedIntervalsData }
        return values
    }
}

extension BackupCompletionRecord {
    nonisolated fileprivate var backupValues: [String: Any] {
        var values: [String: Any] = [:]
        values["id"] = id
        values["taskID"] = taskID
        values["occurrenceID"] = occurrenceID
        if let listID { values["listID"] = listID }
        values["title"] = title
        values["completedAt"] = completedAt
        if let dueDate { values["dueDate"] = dueDate }
        values["estimateMinutes"] = estimateMinutes
        values["wasRecurring"] = wasRecurring
        if let plannedIntervalsData { values["plannedIntervalsData"] = plannedIntervalsData }
        return values
    }
}

extension BackupSchedulePlacement {
    nonisolated fileprivate var backupValues: [String: Any] {
        var values: [String: Any] = [:]
        values["id"] = id
        values["taskID"] = taskID
        values["occurrenceID"] = occurrenceID
        values["start"] = start
        values["end"] = end
        values["isPinned"] = isPinned
        return values
    }
}
