import AppKit
import SwiftData

var checks = 0
func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    guard try condition() else { fatalError("FAIL: \(message)") }
    checks += 1
}
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
let phase = CommandLine.arguments[2]
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
try MediaStore.shared.selectStartupDirectory(directory.appendingPathComponent("Media"))
let schema = Schema([TaskList.self, Block.self, SidebarSection.self, TaskLabel.self, Attachment.self, ActivityEvent.self, WorkSession.self, CompletionRecord.self, SchedulePlacement.self])
let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: directory.appendingPathComponent("Trash.store"), cloudKitDatabase: .none)])
let context = container.mainContext
let store = Store(context: context)
let defaults = UserDefaults(suiteName: "TrashChecks-\(UUID())")!
let settings = LibraryBackupSettings(defaults: defaults)
let manifest = directory.appendingPathComponent("expected.json")
func snapshot() throws -> LibraryBackup { try LibraryBackup(context: context, libraryID: UUID(), settings: settings) }
func named(_ title: String) throws -> Block { try context.fetch(FetchDescriptor<Block>()).first { $0.text == title }! }

if phase == "delete" {
    store.bootstrap()
    let list = store.createList(title: "Rich source")
    let root = store.appendBlock(kind: .task, text: "Parent", to: DocumentContext(listID: list.id))
    let child = store.insertChild(kind: .task, text: "Nested", of: root)
    child.isCompleted = true
    child.completedAt = .now
    child.note = "A completed note"
    let heading = store.insertChild(kind: .heading2, text: "Deep heading", of: child)
    let image = store.insertChild(kind: .image, of: heading)
    image.mediaFilename = "retained.png"
    image.mediaData = Data("image bytes".utf8)
    image.mediaCaption = "Kept caption"
    root.richData = Data("rich archive".utf8)
    root.note = "Original note"
    root.reminderAt = Date.now.addingTimeInterval(86_400)
    root.dueDate = root.reminderAt
    root.includesTime = true
    root.selectedForDay = .now
    root.recurrence = Recurrence(frequency: .daily)
    root.isStarred = true
    root.priority = .high
    let label = store.findOrCreateLabel(named: "retained-label")!
    root.labelIDs = [label.id]
    let attachment = Attachment(blockID: root.id, filename: "retained.txt", displayName: "Original file", contentType: "text/plain", byteCount: 7, contentData: Data("payload".utf8))
    context.insert(attachment)
    try store.persistChanges()
    root.inboxMembershipData = Data("legacy".utf8); try store.persistChanges()
    let expected = try snapshot()
    try JSONEncoder().encode(expected).write(to: manifest)
    var closed = Set<UUID>()
    store.onEditorBlocksRemoved = { closed.formUnion($0) }
    try check(store.trashBlocks([root, child]), "Rich subtree can be retained")
    try check(closed == Set(expected.blocks.map(\.id)), "Deletion closes every descendant inspector and command owner")
    try check(store.trashEntries().count == 1, "Selected descendants are owned by selected ancestor")
    let entry = try store.trashEntries()[0]
    try check(entry.blockCount == 4 && entry.subtaskCount == 1 && entry.nestedSummary == "with 1 subtask and 2 more items",
              "A task's entry says what restores and erases with it")
    func summary(_ blocks: Int, subtasks: Int, isList: Bool = false) -> String? {
        TrashEntry(id: UUID(), title: "", isList: isList, blockCount: blocks, subtaskCount: subtasks).nestedSummary
    }
    try check(summary(1, subtasks: 0) == nil && summary(3, subtasks: 2) == "with 2 subtasks"
              && summary(2, subtasks: 0) == "with 1 nested item" && summary(5, subtasks: 0, isList: true) == nil,
              "Only a block holding others names them; a list counts its items")
    try check(store.block(id: root.id) == nil && store.blocks(inList: list.id).isEmpty, "Active lookup and outline exclude retained content")
    try check(ActiveTaskPolicy(lists: [list]).tasks(in: [root, child]).isEmpty, "Active policy excludes all retained tasks")
    try check([root, child].allSatisfy { !InboxPolicy(lists: [list]).includes($0) }, "Inbox excludes retained tasks")
    try check(!NotificationService.shared.scheduled.contains(root.id), "Saved deletion cancels reminder eligibility")
    let corpus = SearchCorpus(blocks: [root, child], lists: [list])
    try check(corpus.blocks.isEmpty, "Ordinary search excludes retained content")
    do { _ = try ContentReveal.resolve(.block(root.id), blocks: [root], lists: [list]); fatalError("Retained link revealed") }
    catch { checks += 1 }
    try snapshot().validate()
    try check(true, "Backup validates retained content")
} else if phase == "restore" {
    let expected = try JSONDecoder().decode(LibraryBackup.self, from: Data(contentsOf: manifest))
    let root = try named("Parent")
    try check(root.isTrashed, "Deletion persists in a new process")
    let id = root.id
    try check(store.restoreTrash(ids: [id]), "Rich subtree restores after restart")
    let actual = try snapshot()
    for original in expected.blocks {
        var restored = actual.blocks.first { $0.id == original.id }!
        restored.trashMetadataData = nil
        try check(restored == original, "Identity, hierarchy, order and every rich/task field restore unchanged")
    }
    try check(actual.attachments == expected.attachments, "Attachment identity, names and bytes survive")
    try check(NotificationService.shared.scheduled.contains(id), "Eligible future reminder reschedules")
    try check(store.restoreTrash(ids: [id]) == false, "Repeated restore cannot duplicate records")
    try check(context.fetchCount(FetchDescriptor<Block>()) == expected.blocks.count, "No live/trash duplication")
    let undo = UndoManager()
    undo.groupsByEvent = false
    undo.beginUndoGrouping()
    try check(store.trashBlocks([root], undoManager: undo), "Delete registers independent Undo")
    undo.endUndoGrouping()
    undo.undo()
    try check(store.block(id: id) != nil && store.trashEntries().isEmpty, "Immediate Undo restores the same identity and removes Trash entry")
    undo.redo()
    try check(store.block(id: id) == nil && store.trashEntries().count == 1, "Redo creates one retained entry")
    try check(store.restoreTrash(ids: [id]), "Trash restore after redo succeeds")
    if undo.canUndo { undo.undo() }
    try check(context.fetchCount(FetchDescriptor<Block>()) == expected.blocks.count, "Stale Undo cannot create duplicate identities after Trash restore")
} else if phase == "ownership" {
    let parent = try named("Parent")
    let child = try named("Nested")
    let list = store.list(id: parent.listID)!
    let oldListID = list.id
    let childID = child.id
    try check(store.trashBlocks([child]), "Child independently deleted")
    var closed = Set<UUID>()
    store.onEditorBlocksRemoved = { closed.formUnion($0) }
    try check(store.trashList(list), "List deleted after child")
    try check(context.fetch(FetchDescriptor<Block>(predicate: #Predicate { $0.trashID == nil })).allSatisfy { $0.listID != oldListID },
              "A trashed list's blocks leave live counts, as Settings' Your data takes them")
    try check(closed.contains(parent.id) && !closed.contains(childID), "List deletion closes its members and preserves independently retained ownership")
    try check(store.trashEntries().count == 2, "List deletion preserves independent child group")
    try check(store.allLists(includeArchived: true).allSatisfy { $0.id != oldListID }, "Retained list excluded even when including archives")
    try check(store.restoreTrash(ids: [oldListID]), "List restore succeeds")
    try check(store.block(id: parent.id) != nil && store.block(id: childID) == nil, "List restore never revives earlier deleted child")
    try check(store.trashList(list), "List can be retained again")
    try check(store.permanentlyEraseTrash(ids: [oldListID]), "List can be erased while separately retained child remains")
    try snapshot().validate()
    try check(store.trashEntries().count == 1, "Independent child remains a valid backup/recovery entry after owner erased")
    let oldNote = child.note
    try check(store.restoreTrash(ids: [childID]), "Missing original parent restores through recovery list")
    try check(child.id == childID && child.parentID == nil && child.listID != oldListID, "Recovery preserves identity and makes a visible root")
    try check(child.note == oldNote && child.trashMetadata?.recoveryNote?.contains("Rich source") == true, "Provenance is separate from untouched user notes")
    try check(store.list(id: child.listID)?.isPinned == true, "Recovery list is visible in sidebar")
    let recovery = store.list(id: child.listID)!
    try check(recovery.summary == Store.recoveredItemsSummary, "Recovered items doesn't promise a former location it doesn't show")
    let former = "Content restored from an unavailable location. Each recovered item keeps its former location."
    recovery.summary = former
    let edited = store.createList(title: "Recovered items")
    edited.summary = former + " Mine."
    store.bootstrap()
    try check(recovery.summary == Store.recoveredItemsSummary && edited.summary == former + " Mine.",
              "An older Recovered items list takes the new description at launch; one edited since keeps its own")
    // Another task whose list is gone goes to the same Recovered items list,
    // never to a list of the user's that's only called that.
    func orphan(_ title: String) throws -> Block {
        let gone = store.createList(title: "Gone \(title)")
        let task = store.appendBlock(kind: .task, text: title, to: DocumentContext(listID: gone.id))
        try store.persistChanges()
        try check(store.trashBlocks([task]) && store.trashList(gone) && store.permanentlyEraseTrash(ids: [gone.id]),
                  "A task can outlive its erased list in Trash")
        return task
    }
    let second = try orphan("Second orphan")
    let listCount = try context.fetchCount(FetchDescriptor<TaskList>())
    let reused = store.restoreTrashRecoveries(ids: [second.id])
    try check(second.listID == recovery.id && reused?.first?.madeList == false
              && context.fetchCount(FetchDescriptor<TaskList>()) == listCount,
              "A second task restores into the Recovered items list there is, not another")
    try check(store.trashBlocks([second], puttingBack: reused ?? []) && store.list(id: recovery.id) != nil,
              "Undo leaves a Recovered items list the restore didn't make")
    try check(second.trashMetadata?.formerLocation == "Gone Second orphan" && second.trashMetadata?.recoveryNote == nil,
              "Undo puts the task back in Trash saying where it came from")
    // With none there, the restore makes one, and its Undo takes it back out.
    store.rename(recovery, to: "Kept")
    let third = try orphan("Third orphan")
    let before = third.trashMetadata
    let made = store.restoreTrashRecoveries(ids: [third.id])
    let madeID = third.listID!
    try check(made?.first?.madeList == true && madeID != recovery.id && madeID != edited.id
              && store.list(id: madeID)?.title == "Recovered items", "A restore makes Recovered items when there's none")
    try check(store.trashBlocks([third], puttingBack: made ?? []), "A restore that made Recovered items can be undone")
    try check(store.list(id: madeID) == nil && context.fetchCount(FetchDescriptor<TaskList>(predicate: #Predicate { $0.id == madeID })) == 0
              && third.trashMetadata == before && third.listID != madeID && store.trashEntries().contains { $0.id == third.id },
              "Its Undo returns the task to Trash as it was and takes the list it made with it")
    try check(store.restoreTrashRecoveries(ids: [third.id])?.first?.madeList == true && third.listID != madeID
              && store.list(id: third.listID)?.title == "Recovered items", "Redo makes it again")
    try check(store.restoreTrash(ids: [second.id]) && second.listID == third.listID && store.trashEntries().isEmpty,
              "The next one goes to that list")
    try snapshot().validate()
 } else if phase == "readonly" {
    let list = store.createList(title: "Read-only failures")
    let task = store.appendBlock(kind: .task, text: "Read-only task", to: DocumentContext(listID: list.id))
    task.reminderAt = .now.addingTimeInterval(100_000)
    let bytes = Data("readonly retained payload".utf8)
    let attachment = Attachment(blockID: task.id, filename: "readonly.txt", displayName: "Read only", contentType: "text/plain", byteCount: bytes.count, contentData: bytes)
    context.insert(attachment)
    let session = WorkSession(task: task, deviceID: "fixture", startedAt: .now.addingTimeInterval(-30))
    context.insert(session)
    try store.persistChanges()
    let savedCount = try context.fetchCount(FetchDescriptor<ActivityEvent>())
    let taskID = task.id, listID = list.id
    func withReadonly(_ body: (Store) throws -> Void) throws {
        try autoreleasepool {
            let readonly = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema,
                url: directory.appendingPathComponent("Trash.store"), allowsSave: false, cloudKitDatabase: .none)])
            let failing = Store(context: ModelContext(readonly))
            try body(failing)
        }
    }
    try withReadonly { failing in
        let live = failing.block(id: taskID)!
        let savedSession = failing.workSessions(taskID: taskID).first!
        try check(!failing.trashBlocks([live]), "Actual readonly database rejects final deletion commit")
        try check(!live.isTrashed && savedSession.endedAt == nil, "Same live task and session recover from actual save failure")
        try check(failing.trashEntries().isEmpty, "Failed deletion publishes no Trash ghost")
        try check(failing.recentActivity().count == savedCount, "Failed delete publishes no ghost history")
        let liveList = failing.list(id: listID)!
        try check(!failing.trashList(liveList) && !liveList.isTrashed, "Same list recovers from actual readonly failure")
    }
    try check(!task.isTrashed && session.endedAt == nil, "Independent writer still has original values")
    try check(store.trashBlocks([task]), "Writer prepares retained fixture for readonly restore/erase")
    try withReadonly { failing in
        let live = try failing.context.fetch(FetchDescriptor<Block>(predicate: #Predicate { $0.id == taskID })).first!
        try check(!failing.restoreTrash(ids: [taskID]) && live.isTrashed, "Actual readonly restore preserves same retained instance")
        try check(!failing.permanentlyEraseTrash(ids: [taskID]), "Actual readonly erase fails after cache removal")
        try check(live.isTrashed && !live.isDeleted, "Deleted model survives actual failed purge")
        try check(failing.attachments(for: taskID).first?.contentData == bytes, "Real failed purge retains attachment bytes")
    }
    try check(store.restoreTrash(ids: [taskID]), "Original writer restores after readonly failure")
    try check(MediaStore.shared.readFile(filename: "readonly.txt") == bytes, "Restore rebuilds cache removed by rejected erase")
    let goneList = store.createList(title: "Gone before readonly recovery")
    let orphan = store.appendBlock(kind: .task, text: "Readonly orphan", to: DocumentContext(listID: goneList.id))
    let orphanID = orphan.id, goneListID = goneList.id
    try check(store.trashBlocks([orphan]) && store.trashList(goneList)
        && store.permanentlyEraseTrash(ids: [goneListID]), "Prepare a retained root whose original list vanished")
    let liveListCount = store.allLists(includeArchived: true).count
    try withReadonly { failing in
        let retained = try failing.context.fetch(FetchDescriptor<Block>(predicate: #Predicate { $0.id == orphanID })).first!
        try check(!failing.restoreTrash(ids: [orphanID]), "Actual readonly fallback creation fails atomically")
        try check(retained.isTrashed && retained.listID == goneListID && retained.parentID == nil,
            "Failed fallback restores original identity and ownership on same model")
        try check(failing.allLists(includeArchived: true).count == liveListCount,
            "Failed fallback publishes no ghost recovery list")
    }
    try check(store.restoreTrash(ids: [orphanID]), "Fallback remains retryable after actual readonly rejection")

 } else if phase == "validation" {
    let list = TaskList(title: "Original list")
    let other = TaskList(title: "Unrelated list")
    let root = Block(kind: .task, text: "Retained root", listID: list.id)
    root.trashID = root.id
    root.trashMetadataData = try JSONEncoder().encode(TrashMetadata(deletedAt: .now, listTitle: list.title, labels: []))
    let child = Block(kind: .paragraph, text: "Retained child", listID: list.id, parentID: root.id)
    child.trashID = root.id
    let base = LibraryBackup(libraryID: UUID(), createdAt: .now, lists: [BackupTaskList(list), BackupTaskList(other)],
        blocks: [BackupBlock(root), BackupBlock(child)], sections: [], labels: [], attachments: [], activity: [],
        workSessions: [], completions: [], placements: [], settings: settings)
    func rejects(_ value: LibraryBackup) -> Bool { do { try value.validate(); return false } catch { return true } }
    try base.validate()
    var invalid = base
    invalid.blocks[1].parentID = UUID()
    try check(rejects(invalid), "Backup rejects a missing retained nonroot parent")
    invalid = base; invalid.blocks[1].parentID = nil; invalid.blocks[1].listID = other.id
    try check(rejects(invalid), "Backup rejects a disconnected retained member")
    invalid = base; invalid.blocks[1].labelIDs = [UUID()]
    try check(rejects(invalid), "Backup rejects a retained label without global or recovery record")
    var independent = base
    let missingListID = UUID()
    for index in independent.blocks.indices { independent.blocks[index].listID = missingListID }
    independent.blocks[0].parentID = UUID()
    try independent.validate()
    try check(true, "Backup permits unavailable external owners of a connected retained root")
    var listGroup = base
    listGroup.lists[0].trashID = list.id
    listGroup.lists[0].trashMetadataData = root.trashMetadataData
    for index in listGroup.blocks.indices { listGroup.blocks[index].trashID = list.id }
    try listGroup.validate()
    listGroup.blocks[1].listID = other.id
    try check(rejects(listGroup), "Backup rejects list-group content owned by another list")
    var version2 = base
    version2.blocks = [BackupBlock(Block(kind: .task, text: "Version 2 queue", listID: list.id))]
    version2.blocks[0].inboxMembershipData = try LegacyInboxMembership.included(order: 827.25, occurrenceID: UUID()).encoded()
    let bytes = version2.blocks[0].inboxMembershipData
    version2.version = 2
    try version2.upgradeToCurrentVersion()
    try version2.validate()
    try check(version2.version == LibraryBackup.currentVersion && version2.blocks[0].inboxMembershipData == bytes, "Version 2 upgrade preserves Inbox payload byte-for-byte")
 } else if phase == "prior-actions" {
    let list = store.createList(title: "Prior actions")
    let task = store.appendBlock(kind: .task, text: "Inbox retained", to: DocumentContext(listID: list.id))
    try store.persistChanges()
    task.inboxMembershipData = Data("legacy payload".utf8)
    try store.persistChanges()
    let selection = task.inboxMembershipData
    try check(store.trashList(list), "Retain owning list")
    try check(store.restoreTrash(ids: [list.id]) && task.inboxMembershipData == selection, "Restore keeps inert legacy data")

    let source = store.findOrCreateLabel(named: "Trash merge source")!
    let destination = store.findOrCreateLabel(named: "Trash merge destination")!
    let destinationID = destination.id
    task.labelIDs = [source.id]
    try store.persistChanges()
    try check(store.trashBlocks([task]), "Retain task before its global label is merged")
    try store.mergeLabels(store.labelMergePlan(sourceID: source.id, destinationID: destinationID))
    try check(task.labelIDs == [destinationID], "Merge updates retained label reference")
    store.deleteLabel(destination)
    try snapshot().validate()
    try check(store.trashEntries().first { $0.id == task.id }?.metadata?.labels.contains { $0.id == destinationID } == true,
        "Deleting merged label retains its recovery record")
    try check(store.restoreTrash(ids: [task.id]) && store.allLabels().contains { $0.id == destinationID },
        "Restore recreates missing merged label identity")
    try snapshot().validate()

    let parent = store.appendBlock(kind: .task, text: "Outdent parent", to: DocumentContext(listID: list.id))
    let child = store.insertChild(kind: .task, text: "Outdent child", of: parent)
    try store.persistChanges()
    let structuralUndo = UndoManager(); structuralUndo.groupsByEvent = false
    structuralUndo.beginUndoGrouping()
    store.undoableEditorEdit(in: list.id, name: "Outdent child", undoManager: structuralUndo) {
        _ = store.outdent(child)
        store.save()
    }
    structuralUndo.endUndoGrouping()
    try check(child.parentID == nil, "Outdent leaves child outside former parent")
    let parentID = parent.id
    try check(store.trashBlocks([parent]) && store.permanentlyEraseTrash(ids: [parentID]), "Permanently erase former parent")
    structuralUndo.undo()
    try check(child.parentID == nil && store.block(id: parentID) == nil, "Earlier outdent Undo cannot reattach to permanently erased parent")
    try snapshot().validate()
} else if phase == "failure" {
    let list = store.createList(title: "Failures", icon: "🧯")
    let task = store.appendBlock(kind: .task, text: "Atomic task", to: DocumentContext(listID: list.id))
    let attachment = Attachment(blockID: task.id, filename: "shared.dat", displayName: "Shared", contentType: "application/octet-stream", byteCount: 4, contentData: Data("safe".utf8))
    context.insert(attachment)
    try store.persistChanges()
    let failing = Store(context: context, commitContext: { _ in throw CocoaError(.fileWriteOutOfSpace) })
    var failedClosures = Set<UUID>()
    failing.onEditorBlocksRemoved = { failedClosures.formUnion($0) }
    try check(!failing.trashBlocks([task]), "Rejected save reports deletion failure")
    try check(failedClosures.isEmpty, "Failed deletion leaves inspectors and command owner open")
    try check(!task.isTrashed && store.block(id: task.id) != nil, "Failed deletion rolls back active state")
    try check(failing.trashError != nil, "Failed deletion has actionable error")
    try check(store.trashBlocks([task]), "Deletion remains retryable")
    try check(task.trashMetadata?.listIcon == "🧯" && task.trashMetadata?.listTitle == "Failures",
              "Deletion records the list's icon with its title")
    let legacy = try JSONDecoder().decode(TrashMetadata.self, from: Data(#"{"deletedAt":0,"listTitle":"Older","labels":[]}"#.utf8))
    try check(legacy.listIcon == nil && legacy.listTitle == "Older", "Metadata saved before list icons were recorded still decodes")
    failing.trashError = nil
    try check(!failing.restoreTrash(ids: [task.id]) && task.isTrashed, "Rejected restore save retains recoverable group")
    try check(failing.trashError != nil, "Failed restore reports its own error")
    failing.trashError = nil
    try check(!failing.permanentlyEraseTrash(ids: [task.id]), "Rejected erase save reports failure")
    try check(failing.trashError != nil, "Failed erase reports its own error")
    try check(task.isTrashed && attachment.contentData == Data("safe".utf8), "Failed erase preserves retained data")
    try check(store.restoreTrash(ids: [task.id]), "Restore after failed erase rematerializes bytes")
    try check(MediaStore.shared.readFile(filename: "shared.dat") == Data("safe".utf8), "Files survive rejected erase through durable payload")
    let other = store.appendBlock(kind: .task, text: "Other owner", to: DocumentContext(listID: list.id))
    let shared = Attachment(blockID: other.id, filename: "shared.dat", displayName: "Shared too", contentType: "application/octet-stream", byteCount: 4, contentData: Data("safe".utf8))
    context.insert(shared)
    try store.persistChanges()
    try check(store.trashBlocks([task]), "First shared owner retained")
    try check(store.permanentlyEraseTrash(ids: [task.id]), "First shared owner erased")
    try check(MediaStore.shared.readFile(filename: "shared.dat") == Data("safe".utf8), "Permanent erase preserves a live shared file")
    try check(store.trashBlocks([other]), "Other owner retained")
    shared.filename = "../invalid.dat"
    try store.persistChanges()
    try check(!store.restoreTrash(ids: [other.id]) && other.isTrashed, "Media restoration failure retains original Trash item")
    try check(!store.permanentlyEraseTrash(ids: [other.id]) && other.isTrashed, "Media erase failure retains original Trash item")
    shared.filename = "shared.dat"
    try store.persistChanges()
    try check(store.permanentlyEraseTrash(ids: [other.id]), "Media failure can be retried")
    try check(!FileManager.default.fileExists(atPath: MediaStore.shared.url(for: "shared.dat").path), "Last reference erase removes cached bytes")
    let a = store.appendBlock(kind: .paragraph, text: "Before", to: DocumentContext(listID: list.id))
    let b = store.insertBlock(kind: .paragraph, text: "", after: a)
    try store.persistChanges()
    let before = try store.trashEntries().count
    store.deleteBlock(b, liftChildren: true)
    try store.persistChanges()
    try check(store.trashEntries().count == before, "Removing an empty document line does not create Trash")
    let eraseUndo = UndoManager()
    eraseUndo.groupsByEvent = false
    eraseUndo.beginUndoGrouping()
    var editedID: UUID!
    store.undoableEditorEdit(in: list.id, name: "Insert", undoManager: eraseUndo) {
        editedID = store.appendBlock(kind: .task, text: "Never resurrect", to: DocumentContext(listID: list.id)).id
        store.save()
    }
    eraseUndo.endUndoGrouping()
    eraseUndo.beginUndoGrouping()
    try check(store.trashBlocks([store.block(id: editedID)!], undoManager: eraseUndo), "Retain edited content")
    eraseUndo.endUndoGrouping()
    try check(store.permanentlyEraseTrash(ids: [editedID]), "Erase edited content")
    eraseUndo.undo()
    try check(store.trashError == nil && store.block(id: editedID) == nil,
              "Deletion Undo after erase restores nothing and reports no failure")
    eraseUndo.undo()
    if eraseUndo.canRedo { eraseUndo.redo() }
    try check(store.block(id: editedID) == nil, "Old structural Undo/Redo cannot resurrect permanent erase")
    let fileOwner = store.appendBlock(kind: .task, text: "Erase attachment owner", to: DocumentContext(listID: list.id))
    let owned = Attachment(blockID: fileOwner.id, filename: "undo-erase.txt", displayName: "Attachment", contentType: "text/plain", byteCount: 4, contentData: Data("gone".utf8))
    context.insert(owned)
    try store.persistChanges()
    let attachmentUndo = UndoManager()
    attachmentUndo.groupsByEvent = false
    attachmentUndo.beginUndoGrouping()
    store.undoableEditorEdit(in: list.id, name: "Rename attachment", undoManager: attachmentUndo) {
        owned.displayName = "Renamed attachment"
        store.save()
    }
    attachmentUndo.endUndoGrouping()
    let fileOwnerID = fileOwner.id
    try check(store.trashBlocks([fileOwner]), "Attachment-only edited task retained")
    attachmentUndo.undo()
    try check(owned.displayName == "Renamed attachment" && owned.contentData == Data("gone".utf8)
        && store.attachments(for: fileOwnerID).count == 1, "Attachment-only earlier Undo cannot mutate retained content")
    try check(store.permanentlyEraseTrash(ids: [fileOwnerID]), "Attachment-only edited owner erased")
    if attachmentUndo.canUndo { attachmentUndo.undo() }
    try check(store.attachments(for: fileOwnerID).isEmpty && store.block(id: fileOwnerID) == nil,
              "Attachment-only Undo cannot recreate orphan records after owner erase")
    try check(!FileManager.default.fileExists(atPath: MediaStore.shared.url(for: "undo-erase.txt").path),
              "Older Undo does not rematerialize permanently erased bytes")
    let kept = store.appendBlock(kind: .task, text: "Kept from partial erase", to: DocumentContext(listID: list.id))
    let erased = store.appendBlock(kind: .task, text: "Partly erased", to: DocumentContext(listID: list.id))
    try store.persistChanges()
    let keptID = kept.id, erasedID = erased.id
    let partialUndo = UndoManager()
    partialUndo.groupsByEvent = false
    partialUndo.beginUndoGrouping()
    try check(store.trashBlocks([kept, erased], undoManager: partialUndo), "Two tasks move to Trash as one deletion")
    partialUndo.endUndoGrouping()
    try check(store.isInTrash(keptID) && store.isInTrash(erasedID), "Each deleted task is its own Trash entry")
    try check(store.permanentlyEraseTrash(ids: [erasedID]) && !store.isInTrash(erasedID), "One of them is erased")
    partialUndo.undo()
    try check(store.trashError == nil && store.block(id: keptID) != nil && store.block(id: erasedID) == nil,
              "Undo restores what is left of a partly erased deletion")
    partialUndo.redo()
    try check(store.trashError == nil && store.block(id: keptID) == nil && store.isInTrash(keptID),
              "Redo moves the rest to Trash again")
    try check(!store.isInTrash(list.id), "A live list is not in Trash")
    store.bootstrap()
    let inbox = store.inboxList()!
    let inboxIcon = inbox.icon
    inbox.icon = "🗂"
    let inboxTask = store.appendBlock(kind: .task, text: "Inbox deletion", to: DocumentContext(listID: inbox.id))
    try store.persistChanges()
    try check(store.trashBlocks([inboxTask]) && inboxTask.trashMetadata?.listIcon == "📥",
              "Inbox deletion records the icon Inbox shows, whatever it stores")
    inbox.icon = inboxIcon
    try store.persistChanges()
    try check(store.permanentlyResetLibrary(), "Explicit Delete everything erases retained and active content")
    try check(context.fetchCount(FetchDescriptor<Block>()) == 0 && store.trashEntries().isEmpty, "Explicit reset leaves no recoverable content")
}
print("✅ \(checks) Trash checks passed (\(phase))")
