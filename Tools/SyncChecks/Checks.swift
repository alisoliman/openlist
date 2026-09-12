import AppKit
import CloudKit
import CoreData
import SwiftData

@main struct SyncChecks {
    @MainActor static var count = 0

    @MainActor static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
        count += 1
    }

    @MainActor static func main() async throws {
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let phase = CommandLine.arguments[3]
        let media = MediaStore.shared
        if phase == "cleanup" {
            let folder = media.url(for: "sentinel").deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
            guard folder.lastPathComponent == "Openlist-Review-\(ReviewSession.identifier!)" else {
                preconditionFailure("Refusing cleanup outside the fixture media directory")
            }
            if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
            return
        }

        let loaded = try AppPersistence.open(at: url, iCloudUnavailableReason: "Offline regression fixture")
        let store = Store(context: loaded.container.mainContext)
        store.context.autosaveEnabled = false
        let list = store.allLists().first { $0.title == "Existing local list" }!
        let task = store.blocks(inList: list.id).first(where: \.isTask)!
        let image = store.blocks(inList: list.id).first { $0.kind == .image }!
        let attachment = store.attachments(for: task.id).first!

        if phase == "migrate" {
            check(store.allLists().count == 2, "Upgrade reuses the old store rather than creating an empty store")
            check(image.mediaData == nil && attachment.contentData == nil, "New asset fields migrate as optional values")
            check(list.mergedIntoID == nil && store.defaultSection()?.mergedIntoID == nil, "System aliases are additive optional fields")
            let imageBytes = try media.readFile(filename: "legacy.png")
            let fileBytes = try media.readFile(filename: "legacy.bin")
            store.prepareForSync()
            check(store.syncPreparationError == nil && store.persistenceError == nil, "Legacy media backfill succeeds")
            check(image.mediaData == imageBytes && attachment.contentData == fileBytes, "Every legacy file is copied into synced attributes")
            check(media.fileContents(filename: "legacy.png") == imageBytes && media.fileContents(filename: "legacy.bin") == fileBytes, "Migration retains source files")
            store.prepareForSync()
            check(store.allLists().count == 2 && store.attachments(for: task.id).count == 1, "Repeated migration is idempotent")
            try validateSchema(at: url)
            try validateSystemRecords(store: store)
            try validateUndoAfterInboxMerge()
            try validateCyclicDeletion()
            validateRemoteDrafts()
            validateConcurrentTreeChanges()
            validateState()
            try await validateDiagnosticCheckpoints(in: url.deletingLastPathComponent())
            try await validateRemoteNotification(store: store)
            store.save()
        } else if phase == "reopen" {
            check(image.mediaData != nil && attachment.contentData?.count == 2 * 1024 * 1024, "Synced asset bytes survive a separate-process restart")
            check(task.text == "Legacy task" && task.note == "A note written before iCloud", "Original text and notes survive migration")
            check(task.richData == Data(#"{\rtf1\ansi Legacy \b task\b0}"#.utf8), "RTF survives migration byte-for-byte")
            check(task.recurrence?.frequency == .weekly && task.priority == .high && task.isStarred, "Recurrence, priority and stars are preserved")
            check(task.includesTime && task.dueDate == Date(timeIntervalSince1970: 2_100_000_000) && task.reminderAt != nil, "Due dates and reminders are preserved")
            check(task.labelIDs == store.allLabels().map(\.id) && image.parentID == task.id, "Labels and nested block references are preserved")
            check(store.recentActivity().contains { $0.blockID == task.id && $0.listID == list.id }, "Activity survives migration")
            try validateDownloadedMedia(store: store, list: list, task: task, image: image, attachment: attachment, folder: url.deletingLastPathComponent())
            try validateUnreadableStore(in: url.deletingLastPathComponent())
            store.save()
            check(store.persistenceError == nil, "All verification edits save durably")
        } else {
            preconditionFailure("Unknown test phase")
        }
        print("Passed \(count) iCloud checks (\(phase))")
    }

    @MainActor static func validateSchema(at url: URL) throws {
        let model = NSManagedObjectModel.makeManagedObjectModel(for: [
            TaskList.self, Block.self, SidebarSection.self, TaskLabel.self, Attachment.self, ActivityEvent.self
        ])!
        for entity in model.entities {
            check(entity.uniquenessConstraints.isEmpty, "\(entity.name!) has no CloudKit-incompatible uniqueness constraints")
            for attribute in entity.attributesByName.values {
                check(attribute.isOptional || attribute.defaultValue != nil, "\(entity.name!).\(attribute.name) is optional or has a default")
            }
            check(entity.relationshipsByName.values.allSatisfy(\.isOptional), "All relationships are optional")
        }
        check(model.entitiesByName["Block"]?.attributesByName["mediaData"]?.allowsExternalBinaryDataStorage == true, "Images use external binary storage")
        check(model.entitiesByName["Attachment"]?.attributesByName["contentData"]?.allowsExternalBinaryDataStorage == true, "Attachments use external binary storage")
        let cloud = AppPersistence.configuration(at: url, iCloudEnabled: true)
        let local = AppPersistence.configuration(at: url, iCloudEnabled: false)
        check(cloud.url == local.url && local.url == url, "Local and cloud configurations share the original URL")
        check(cloud.cloudKitContainerIdentifier == ICloudConfiguration.containerIdentifier, "Cloud mode explicitly chooses the private Openlist container")
        check(local.cloudKitContainerIdentifier == nil, "Offline configurations have no CloudKit container")
        check(ICloudConfiguration.unavailableReason?.contains("isolated") == true, "Review fixtures cannot connect to iCloud")
    }

    @MainActor static func validateSystemRecords(store: Store) throws {
        let oldInboxID = store.inboxList()!.id
        let oldSectionID = store.defaultSection()!.id
        store.inboxList()!.title = "Personal capture"
        store.defaultSection()!.title = "Personal lists"
        let freshInbox = TaskList(title: "Inbox", isSystemInbox: true)
        freshInbox.createdAt = store.inboxList()!.createdAt.addingTimeInterval(1000)
        let freshSection = SidebarSection(title: "My lists", isDefault: true)
        freshSection.createdAt = store.defaultSection()!.createdAt.addingTimeInterval(1000)
        store.context.insert(freshInbox)
        store.context.insert(freshSection)
        store.prepareForSync()
        check(store.inboxList()?.id == oldInboxID && store.inboxList()?.title == "Personal capture", "A fresh Mac's default Inbox does not replace an existing customized Inbox")
        check(store.defaultSection()?.id == oldSectionID && store.defaultSection()?.title == "Personal lists", "A fresh default section does not replace the user's existing section")
        store.rename(freshSection, to: freshSection.title)
        check(store.defaultSection()?.title == "Personal lists", "Committing an untouched stale section title cannot overwrite the canonical title")
        store.rename(freshSection, to: "Renamed from a stale section")
        check(store.defaultSection()?.title == "Renamed from a stale section", "Edits through a section alias reach the canonical record")
        let incoming = TaskList(title: "Inbox", isSystemInbox: true)
        incoming.id = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        incoming.createdAt = .distantPast
        let incomingSection = SidebarSection(title: "My lists", isDefault: true)
        incomingSection.id = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
        incomingSection.createdAt = .distantPast
        let localTask = Block(kind: .task, text: "Local offline capture", listID: oldInboxID)
        let remoteTask = Block(kind: .task, text: "Remote offline capture", listID: incoming.id)
        let event = ActivityEvent(kind: .created, title: localTask.text, blockID: localTask.id, listID: oldInboxID)
        let ordinary = SidebarSection(title: "My lists")
        store.context.insert(incoming)
        store.context.insert(incomingSection)
        store.context.insert(localTask)
        store.context.insert(remoteTask)
        store.context.insert(event)
        store.context.insert(ordinary)
        store.prepareForSync()
        check(store.allLists().filter(\.isSystemInbox).count == 1 && store.inboxList()?.id == incoming.id, "Concurrent Inboxes converge to one deterministic visible Inbox")
        check(localTask.listID == incoming.id && remoteTask.listID == incoming.id, "Both Macs' tasks are retained")
        check(event.listID == incoming.id, "Activity references follow the canonical Inbox")
        check(store.list(id: oldInboxID)?.id == incoming.id, "Old Inbox links resolve through the retained alias")
        check(store.allSections().filter(\.isDefault).count == 1 && store.defaultSection()?.id == incomingSection.id, "Default sections converge")
        check(store.allSections().contains { $0.id == ordinary.id }, "Same-name user-created sections are not merged")

        let late = Block(kind: .task, text: "Arrived in a later batch", listID: oldInboxID)
        store.context.insert(late)
        let lateList = store.createList(title: "Late list")
        lateList.sectionID = oldSectionID
        store.prepareForSync()
        check(late.listID == incoming.id && lateList.sectionID == incomingSection.id, "Later imports referencing old system records are repaired")
        store.bootstrap()
        check(store.blocks(inList: incoming.id).count == 3, "Repeated bootstrap preserves every capture without duplicating the Inbox")
        let raw = try store.context.fetch(FetchDescriptor<TaskList>(predicate: #Predicate { $0.isSystemInbox }))
        check(raw.count == 3, "Aliases are retained, not deleted before dependent records arrive")
        let oldInbox = raw.first { $0.id == oldInboxID }!
        store.rename(oldInbox, to: "Updated through the old Inbox")
        check(store.inboxList()?.title == "Updated through the old Inbox", "A stale Inbox header edits the canonical record, not its hidden alias")
        let captured = store.appendBlock(text: "Captured from an old editor", to: .init(listID: oldInboxID))
        check(captured.listID == incoming.id, "An editor holding a pre-sync Inbox ID writes to the canonical Inbox")
        store.move(list: lateList, toSection: oldSectionID, above: nil)
        check(lateList.sectionID == incomingSection.id, "A stale sidebar drag target resolves to the canonical section")
        check(store.blocks(inList: oldInboxID).contains { $0.id == captured.id }, "An old Inbox reference reads canonical content")

        let isolated = try ModelContainer(for: AppPersistence.schema, configurations: [
            ModelConfiguration(schema: AppPersistence.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        ])
        let otherStore = Store(context: isolated.mainContext)
        let alias = TaskList(title: "Inbox", isSystemInbox: true)
        alias.id = oldInboxID
        alias.mergedIntoID = incoming.id
        let waiting = Block(kind: .task, text: "Waiting for its list", listID: oldInboxID)
        otherStore.context.insert(alias)
        otherStore.context.insert(waiting)
        otherStore.bootstrap()
        check(otherStore.inboxList() == nil && waiting.listID == incoming.id, "An alias arriving before its target is not promoted or replaced")
        let winner = TaskList(title: "Inbox", isSystemInbox: true)
        winner.id = incoming.id
        winner.createdAt = .distantPast
        otherStore.context.insert(winner)
        otherStore.bootstrap()
        check(otherStore.inboxList()?.id == incoming.id && otherStore.blocks(inList: incoming.id).count == 1, "Out-of-order target arrival restores visibility without losing the task")
    }

    @MainActor static func validateUndoAfterInboxMerge() throws {
        let container = try ModelContainer(for: AppPersistence.schema, configurations: [
            ModelConfiguration(schema: AppPersistence.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        ])
        let store = Store(context: container.mainContext)
        store.context.autosaveEnabled = false
        store.bootstrap()
        let originalInbox = store.inboxList()!
        let task = store.appendBlock(text: "Deleted before Inbox convergence", to: .init(listID: originalInbox.id))
        let taskID = task.id
        store.save()
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        store.undoableEditorEdit(in: originalInbox.id, name: "Delete task", undoManager: undo) {
            store.deleteBlock(task)
        }
        undo.endUndoGrouping()
        store.save()

        let canonical = TaskList(title: "Existing Inbox", isSystemInbox: true)
        canonical.createdAt = originalInbox.createdAt.addingTimeInterval(-1000)
        store.context.insert(canonical)
        store.prepareForSync()
        check(originalInbox.mergedIntoID == canonical.id, "Undo fixture retains the original Inbox as an alias")
        undo.undo()
        check(store.block(id: taskID)?.listID == canonical.id, "Undo resolves a deleted task's pre-merge Inbox ID")
        check(store.blocks(inList: canonical.id).map(\.id) == [taskID], "The restored task is visible in the canonical Inbox")
        undo.redo()
        check(store.block(id: taskID) == nil, "Redo still removes the task after Inbox convergence")
        undo.undo()

        undo.beginUndoGrouping()
        let added = store.undoableEditorEdit(in: Set([originalInbox.id, canonical.id]), name: "Edit merged Inbox", undoManager: undo) {
            store.appendBlock(text: "Captured through an alias", to: .init(listID: originalInbox.id))
        }
        let addedID = added.id
        undo.endUndoGrouping()
        store.save()
        undo.undo()
        check(store.block(id: addedID) == nil && store.block(id: taskID) != nil, "A snapshot containing both Inbox IDs deduplicates canonical content")
        undo.redo()
        check(store.block(id: addedID)?.listID == canonical.id, "Redo through an alias preserves canonical ownership")
    }

    @MainActor static func validateCyclicDeletion() throws {
        let container = try ModelContainer(for: AppPersistence.schema, configurations: [
            ModelConfiguration(schema: AppPersistence.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        ])
        let store = Store(context: container.mainContext)
        store.bootstrap()
        let inbox = store.inboxList()!
        let first = Block(kind: .task, text: "First cyclic task", listID: inbox.id)
        let second = Block(kind: .task, text: "Second cyclic task", listID: inbox.id, parentID: first.id)
        first.parentID = second.id
        let retained = Block(kind: .task, text: "Not selected", listID: inbox.id)
        for block in [first, second, retained] { store.context.insert(block) }
        store.save()
        store.deleteBlocks([first, second])
        check(store.blocks(inList: inbox.id).map(\.id) == [retained.id], "Selecting both sides of a projected cycle deletes them without skipping both roots")

        let orphan = Block(kind: .task, text: "Missing imported parent", listID: inbox.id, parentID: UUID())
        let child = Block(kind: .task, text: "Orphan's child", listID: inbox.id, parentID: orphan.id)
        for block in [orphan, child] { store.context.insert(block) }
        store.save()
        store.deleteBlocks(store.blocks(inList: inbox.id))
        check(store.blocks(inList: inbox.id).isEmpty, "Reset's bulk deletion removes orphaned Inbox subtrees as well as stored roots")
    }

    @MainActor static func validateRemoteDrafts() {
        let trim: (String) -> String = { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        var draft = SyncedTextDraft()
        draft.reset(to: "Original title")
        draft.receive("Remote title")
        check(draft.value == "Remote title" && draft.editedValue(normalize: trim) == nil, "An untouched title draft follows a remote update without writing it back")
        draft.value = "Local edit"
        draft.receive("Newer remote title")
        check(draft.value == "Local edit" && draft.editedValue(normalize: trim) == "Local edit", "Incoming changes do not discard a dirty title draft")
        draft.value = draft.original
        check(draft.editedValue(normalize: trim) == nil, "Reverting a draft to its baseline cannot overwrite a newer remote title on blur")
        draft.reset(to: "Newer remote title")
        draft.value += "  "
        check(draft.editedValue(normalize: trim) == nil, "Whitespace-only draft changes cannot overwrite a remote title")
        draft.reset(to: "Label")
        draft.value = "#Label"
        check(draft.editedValue(normalize: TaskLabel.normalize) == nil, "Labels compare drafts using their own normalization")
        draft.value = "#Renamed"
        check(draft.editedValue(normalize: TaskLabel.normalize) == "Renamed", "Real label edits still commit normalized names")
        draft.reset(to: "Renamed")
        draft.receive("Remote after submit")
        check(draft.value == "Remote after submit" && draft.editedValue(normalize: trim) == nil, "Submitting a draft resets its baseline for subsequent remote updates")
    }

    @MainActor static func validateDownloadedMedia(store: Store, list: TaskList, task: Block, image: Block, attachment: Attachment, folder: URL) throws {
        let imageBytes = image.mediaData!
        let fileBytes = attachment.contentData!
        let imageID = image.id, taskID = task.id
        MediaStore.shared.delete(filename: image.mediaFilename!)
        MediaStore.shared.delete(filename: attachment.filename)
        check(MediaStore.shared.fileContents(filename: attachment.filename) == nil, "Downloaded fixture has no local attachment cache")
        check(MediaStore.shared.image(named: image.mediaFilename!, data: image.mediaData) != nil, "Downloaded image renders directly from synced bytes")
        let openedURL = try attachment.fileURL()
        let openedBytes = try Data(contentsOf: openedURL)
        check(openedBytes == fileBytes, "Opening a downloaded attachment recreates exact bytes")
        let duplicate = store.duplicateList(list)
        check(duplicate.id != list.id, "A cloud-only image can be duplicated without a pre-existing local file")
        let clonedImage = store.blocks(inList: duplicate.id).first { $0.kind == .image }!
        check(clonedImage.mediaData == imageBytes && clonedImage.mediaFilename != image.mediaFilename, "Duplicate preserves synced image bytes with independent file ownership")
        let clonedTask = store.blocks(inList: duplicate.id).first(where: \.isTask)!
        check(store.attachments(for: clonedTask.id).first?.contentData == fileBytes, "Duplicate preserves synced attachment bytes")
        store.deleteList(duplicate)
        check(image.mediaData == imageBytes && attachment.contentData == fileBytes, "Deleting a copy cannot delete the original synced data")
        let destination = folder.appendingPathComponent("Downloaded.md")
        try MarkdownExporter.write(list: list, store: store, to: destination)
        let markdown = try String(contentsOf: destination, encoding: .utf8)
        check(markdown.contains("Downloaded.assets/") && !markdown.contains("file:///"), "Downloaded media exports as a portable package")
        let assetFolder = folder.appendingPathComponent("Downloaded.assets", isDirectory: true)
        let exportedBytes = try Data(contentsOf: assetFolder.appendingPathComponent("Original document.bin"))
        check(exportedBytes == fileBytes, "Portable export includes the full downloaded attachment")

        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        store.undoableEditorEdit(in: list.id, name: "Delete synced task", undoManager: undo) { store.deleteBlock(task) }
        undo.endUndoGrouping()
        undo.undo()
        check(store.block(id: imageID)?.mediaData == imageBytes, "Undo restores synced image bytes")
        check(store.attachments(for: taskID).first?.contentData == fileBytes, "Undo restores synced attachment bytes")

        let missing = Attachment(blockID: taskID, filename: "missing.bin", displayName: "Missing", contentType: "application/octet-stream", byteCount: 1)
        store.context.insert(missing)
        store.prepareForSync()
        check(store.syncPreparationError?.contains("1 file(s)") == true && missing.contentData == nil, "Missing legacy files surface an error, not empty uploaded data")
        try MediaStore.shared.restoreFile(Data([1]), filename: missing.filename)
        store.prepareForSync()
        check(store.syncPreparationError == nil && missing.contentData == Data([1]), "Backfill can be retried after a missing file is restored")
        let source = folder.appendingPathComponent("new-import.txt")
        try Data("new imported content".utf8).write(to: source)
        let imported = try MediaStore.shared.importFile(at: source)
        check(imported.data == Data("new imported content".utf8) && imported.byteCount == imported.data.count, "New imports carry the exact bytes needed for immediate sync")
        do {
            _ = try MediaStore.shared.materialize(filename: "../outside.bin", data: Data([1]))
            check(false, "Path traversal must not materialize a cloud asset")
        } catch {
            check(true, "Malformed asset paths are rejected")
        }
    }

    @MainActor static func validateUnreadableStore(in folder: URL) throws {
        let broken = folder.appendingPathComponent("Unreadable.store")
        let sentinel = Data("not a SQLite database".utf8)
        try sentinel.write(to: broken)
        do {
            _ = try AppPersistence.open(at: broken, iCloudUnavailableReason: "Offline fixture")
            check(false, "An unreadable store must not produce a success-shaped fallback")
        } catch {
            let preserved = try Data(contentsOf: broken)
            check(preserved == sentinel, "Unreadable store remains intact and startup throws")
        }
    }

    @MainActor static func validateState() {
        let delegate = OpenlistApplicationDelegate()
        var launched = false
        delegate.onDidLaunch = { launched = true }
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        check(launched, "App launch starts initialization without relying on a main-window task")
        var state = ICloudSyncState()
        state.account = .available
        check(state.title == "iCloud available" && state.lastUpload == nil, "Account availability alone is not reported as a successful sync")
        let upload = UUID(), download = UUID()
        state.begin(.upload, id: upload)
        state.begin(.download, id: download)
        state.finish(.download, id: download, at: Date(timeIntervalSince1970: 1), error: nil)
        check(state.title == "Syncing with iCloud" && state.lastUpload == nil, "A download does not complete a pending upload")
        state.finish(.upload, id: upload, at: Date(timeIntervalSince1970: 2), error: "iCloud storage is full")
        state.finish(.download, id: UUID(), at: Date(timeIntervalSince1970: 3), error: nil)
        check(state.hasProblem && state.detail.contains("storage is full") && state.lastUpload == nil, "An unrelated successful download cannot hide an upload failure")
        state.finish(.upload, id: UUID(), at: Date(timeIntervalSince1970: 4), error: nil)
        check(!state.hasProblem && state.lastUpload == Date(timeIntervalSince1970: 4), "A successful upload clears its own failure")
        state.begin(.upload, id: upload)
        check(state.activeOperations.isEmpty, "A delayed duplicate start cannot make a finished operation look active")
        state.accountChanged()
        check(state.lastUpload == nil && state.lastDownload == nil && state.account == .checking, "Switching Apple Accounts clears the previous account's transfer status")
        state.account = .signedOut
        check(state.hasProblem && state.detail.contains("Local changes are kept"), "Signed-out state explains local preservation")
        state.unavailableReason = "Review fixture"
        state.finish(.upload, id: UUID(), at: .now, error: nil)
        check(state.title == "Local only" && state.lastUpload == nil, "Disabled sync cannot report cloud activity")
        let quota = NSError(domain: CKErrorDomain, code: CKError.Code.quotaExceeded.rawValue)
        let partial = NSError(domain: CKErrorDomain, code: CKError.Code.partialFailure.rawValue, userInfo: [
            CKPartialErrorsByItemIDKey: ["fixture": quota]
        ])
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: 134060, userInfo: ["encounteredErrors": [partial]])
        check(ICloudError.message(for: wrapped).contains("storage is full"), "Nested CloudKit quota errors have an actionable message")
        let offline = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        check(ICloudError.message(for: offline).contains("retry automatically"), "Network timeouts explain automatic retry")
        let unauthorized = NSError(domain: CKErrorDomain, code: CKError.Code.missingEntitlement.rawValue)
        check(ICloudError.message(for: unauthorized).contains("signing profile"), "Missing capabilities explain the signing requirement")
    }

    @MainActor static func validateConcurrentTreeChanges() {
        let first = Block(kind: .task, text: "First concurrent move")
        first.id = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let second = Block(kind: .task, text: "Second concurrent move")
        second.id = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
        first.parentID = second.id
        second.parentID = first.id
        check(BlockTree.flatten([second, first]).map(\.id) == [first.id, second.id], "Concurrent cyclic moves remain visible in deterministic order")
        check(BlockTree.flatten([first, second]).map(\.id) == [first.id, second.id], "Cycle projection is independent of import order")
        check(BlockTree.descendants(of: first.id, in: [first, second]).map(\.id) == [second.id], "Cyclic imports cannot make descendant traversal loop")
        check(BlockTree.subtaskCounts(in: [first, second])[first.id]?.total == 1, "Cyclic imports cannot overflow task progress recursion")
        check(first.parentID == second.id && second.parentID == first.id, "Cycle projection never rewrites synced parent fields")
        let delayedParent = Block(kind: .paragraph, text: "Arrives later")
        let child = Block(kind: .task, text: "Already downloaded", parentID: delayedParent.id)
        check(BlockTree.flatten([child]).map(\.id) == [child.id], "A child stays visible while its parent is missing")
        check(BlockTree.flatten([child, delayedParent]).map(\.id) == [delayedParent.id, child.id], "A later parent restores the intended outline without rewriting data")
        first.parentID = nil
        second.parentID = nil
        first.createdAt = .distantPast
        second.createdAt = .distantPast
        check(BlockTree.children(of: nil, in: [second, first]).map(\.id) == [first.id, second.id], "Equal ordering positions and timestamps have a stable UUID tiebreaker")
    }

    @MainActor static func validateDiagnosticCheckpoints(in folder: URL) async throws {
        let url = folder.appendingPathComponent("DiagnosticCheckpoints.json")
        let checkpoints = try CloudSyncCheckpoints(at: url)
        var imports = 0
        try await checkpoints.perform("verify:imported") { imports += 1 }
        let resumed = try CloudSyncCheckpoints(at: url)
        try await resumed.perform("verify:imported") { imports += 1 }
        check(imports == 1 && resumed.contains("verify:imported"), "A resumed diagnostic skips the durably verified import before retrying deletion")
        do {
            try await resumed.perform("verify:deleted") { throw CocoaError(.fileReadUnknown) }
            check(false, "A failed diagnostic operation must remain retryable")
        } catch {
            check(!resumed.contains("verify:deleted"), "A failed deletion cannot be checkpointed as complete")
        }
        let retried = try CloudSyncCheckpoints(at: url)
        var deletions = 0
        try await retried.perform("verify:deleted") { deletions += 1 }
        let finished = try CloudSyncCheckpoints(at: url)
        check(deletions == 1 && finished.contains("verify:imported") && finished.contains("verify:deleted"), "Successful retry retains both verified stages across process-style reloads")

        let blockedParent = folder.appendingPathComponent("NotADirectory")
        try Data([0]).write(to: blockedParent)
        let unwritable = try CloudSyncCheckpoints(at: blockedParent.appendingPathComponent("Checkpoint.json"))
        do {
            try unwritable.record("complete")
            check(false, "Checkpoint persistence failure must not report completion")
        } catch {
            check(!unwritable.contains("complete"), "An unwritten checkpoint never becomes success-shaped in memory")
        }
        try Data("invalid JSON".utf8).write(to: url)
        do {
            _ = try CloudSyncCheckpoints(at: url)
            check(false, "A corrupt checkpoint must not restart a destructive diagnostic silently")
        } catch {
            check(true, "Corrupt checkpoints surface an error instead of losing recovery history")
        }
    }

    @MainActor static func validateRemoteNotification(store: Store) async throws {
        let task = store.appendBlock(kind: .task, text: "Remote reminder fixture", to: .init(listID: store.inboxList()!.id))
        let taskID = task.id
        task.includesTime = true
        task.dueDate = .now.addingTimeInterval(3600)
        store.save()
        store.refreshAllReminders()
        check(NotificationService.shared.scheduled.contains(taskID), "Fixture reminder is scheduled before a remote completion")
        let publisher = WidgetSnapshotPublisher(store: store)
        let before = publisher.buildSnapshot()
        let imported = ModelContext(store.context.container)
        let importedTask = try imported.fetch(FetchDescriptor<Block>(predicate: #Predicate { $0.id == taskID })).first!
        importedTask.isCompleted = true
        importedTask.completedAt = .now
        try imported.save()
        let monitor = ICloudSyncMonitor(unavailableReason: nil)
        var refreshes = 0
        var snapshot: WidgetSnapshot?
        monitor.onRemoteChange = {
            store.context.processPendingChanges()
            store.prepareForSync()
            store.refreshAllReminders()
            snapshot = publisher.buildSnapshot()
            refreshes += 1
        }
        NotificationCenter.default.post(name: .NSPersistentStoreRemoteChange, object: nil)
        NotificationCenter.default.post(name: .NSPersistentStoreRemoteChange, object: nil)
        try await Task.sleep(for: .milliseconds(900))
        check(refreshes == 1, "Remote-store notifications trigger one coalesced refresh")
        check(store.block(id: taskID)?.isCompleted == true, "Remote completion is visible to the primary store")
        check(!NotificationService.shared.scheduled.contains(taskID), "Remote completion cancels an already scheduled local reminder")
        check(snapshot?.totalOpenCount == before.totalOpenCount - 1, "Remote completion refreshes the widget's open task count")
        check(!NotificationService.shared.scheduled.isEmpty, "Imported task reminders are rebuilt")
        let disabled = ICloudSyncMonitor(unavailableReason: "Review fixture")
        var disabledRefreshes = 0
        disabled.onRemoteChange = { disabledRefreshes += 1 }
        NotificationCenter.default.post(name: .NSPersistentStoreRemoteChange, object: nil)
        try await Task.sleep(for: .milliseconds(900))
        check(disabledRefreshes == 0, "Isolated review mode ignores cloud notifications")
        if let task = store.block(id: taskID) { store.deleteBlock(task) }
    }
}
