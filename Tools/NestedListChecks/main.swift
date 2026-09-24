import AppKit
import Foundation
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
let schema = Schema([TaskList.self, Block.self, SidebarSection.self, TaskLabel.self, Attachment.self,
    ActivityEvent.self, WorkSession.self, CompletionRecord.self, SchedulePlacement.self])
let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema,
    url: directory.appendingPathComponent("Nested.store"), cloudKitDatabase: .none)])
let context = container.mainContext
let store = Store(context: context)
let settings = LibraryBackupSettings(defaults: UserDefaults(suiteName: "NestedChecks-\(UUID())")!)
func snapshot() throws -> LibraryBackup { try LibraryBackup(context: context, libraryID: UUID(), settings: settings) }
func named(_ title: String) throws -> TaskList { try context.fetch(FetchDescriptor<TaskList>()).first { $0.title == title }! }
func task(_ title: String, in list: TaskList) -> Block { store.appendBlock(kind: .task, text: title, to: DocumentContext(listID: list.id)) }

if phase == "write" {
    store.bootstrap()
    let parent = store.createList(title: "Project")
    let child = store.createChildList(in: parent)!
    store.rename(child, to: "Research")
    let grandchild = store.createChildList(in: child)!
    store.rename(grandchild, to: "Sources")
    let parentTask = task("Parent task", in: parent)
    let childTask = task("Unique child task", in: child)
    let grandTask = task("Grandchild task", in: grandchild)
    let nestedTask = store.insertChild(kind: .task, text: "Nested task stays in child document", of: childTask)
    childTask.reminderAt = Date.now.addingTimeInterval(86_400)
    childTask.richData = RichTextCodec.encode(NSAttributedString(string: childTask.text))
    childTask.note = "Independent document payload"
    let mediaBytes = Data(repeating: 0x35, count: 1_048_611)
    child.coverFilename = "child-cover.png"
    child.coverData = mediaBytes
    child.coverMetadataData = try JSONEncoder().encode(ListCoverMetadata(displayName: "Child cover.png",
        contentType: "image/png", byteCount: mediaBytes.count, pixelWidth: 10, pixelHeight: 10))
    child.coverPresentationRaw = "hidden"
    let image = store.insertChild(kind: .image, of: childTask)
    image.mediaFilename = "child-image.png"; image.mediaData = Data("image bytes".utf8)
    let attachment = Attachment(blockID: childTask.id, filename: "child-file.txt", displayName: "Child file.txt",
        contentType: "text/plain", byteCount: 10, contentData: Data("file bytes".utf8))
    context.insert(attachment)
    let childID = child.id, taskID = childTask.id
    try store.persistChanges()
    try check(child.parentListID == parent.id && nestedTask.listID == child.id && nestedTask.parentID == childTask.id, "Document ownership is independent of task indentation")
    try check(store.listHierarchy().ancestors(of: grandchild.id).map(\.id) == [parent.id, child.id], "Ancestor paths preserve order")
    try check(!store.moveList(parent, under: grandchild.id) && !store.moveList(child, under: child.id), "Self and descendant moves are rejected")
    try check(!store.moveList(child, under: store.inboxList()!.id), "Inbox cannot own documents")
    try check(store.createChildList(in: store.inboxList()!) == nil, "Inbox child creation is rejected")
    let other = store.createList(title: "Other project")
    try check(store.moveList(child, under: other.id), "A subtree moves to a different parent")
    try check(child.id == childID && childTask.id == taskID && childTask.listID == childID && grandchild.parentListID == childID, "Move preserves every document and task identity")
    try check(store.moveList(child, under: parent.id), "Subtree can return to its original parent")
    store.setArchived(true, for: grandchild)
    store.setArchived(true, for: parent)
    try check(!child.isArchived && grandchild.isArchived && child.isEffectivelyArchived, "Ancestor archive preserves child archive choices")
    try check(!store.allLists().contains { $0.id == child.id }, "Default list fetch excludes inherited archive")
    try check(ActiveTaskPolicy(lists: [child]).tasks(in: [childTask]).isEmpty, "Filtered policies still load an archived ancestor")
    try check(!NotificationService.shared.scheduled.contains(childTask.id), "Ancestor archive cancels descendant reminder")
    let corpus = SearchCorpus(blocks: [childTask], lists: [parent, child, grandchild])
    try check(corpus.lists.first { $0.id == child.id }?.isArchived == true && corpus.lists.first { $0.id == child.id }?.path == "Project › Research", "Search snapshot retains effective archive and owning path")
    store.setArchived(false, for: parent)
    try check(!child.isEffectivelyArchived && grandchild.isEffectivelyArchived && NotificationService.shared.scheduled.contains(childTask.id), "Unarchive resumes only descendants without their own archive choice")

    let copy = store.list(id: try store.copyList(parent, mode: .duplicate))!
    let copied = store.listHierarchy().subtree(of: copy.id)
    try check(copied.count == 3 && Set(copied.map(\.id)).isDisjoint(with: [parent.id, child.id, grandchild.id]), "Duplicate owns all available child documents with fresh IDs")
    let copiedChild = copied.first { $0.title == "Research" }!
    let copiedTask = store.blocks(inList: copiedChild.id).first { $0.text == childTask.text }!
    try check(copiedChild.coverFilename != child.coverFilename && copiedChild.coverData == child.coverData
        && copiedChild.coverPresentationRaw == child.coverPresentationRaw, "Descendant copy owns fresh cover media with original bytes and visibility")
    let copiedImage = store.blocks(inList: copiedChild.id).first { $0.kind == .image }!
    try check(copiedImage.mediaFilename != image.mediaFilename && copiedImage.mediaData == image.mediaData
        && store.attachments(for: copiedTask.id).first?.filename != attachment.filename,
        "Child block media and attachments get independent filenames")
    try check(copiedTask.id != childTask.id && copiedTask.note == childTask.note, "Duplicate preserves child contents under new document identity")
    let events = try context.fetch(FetchDescriptor<ActivityEvent>())
    try check(events.first { $0.blockID == copiedTask.id }?.listTitle == copiedChild.displayTitle, "Copied activity belongs to the correct child document")
    try check(copied.first { $0.title == "Sources" }!.isArchived, "Duplicate preserves a descendant's archive choice")

    let export = directory.appendingPathComponent("Project export")
    try MarkdownExporter.write(list: parent, store: store, to: export)
    let files = try FileManager.default.contentsOfDirectory(at: export, includingPropertiesForKeys: nil)
    let markdownFiles = files.filter { $0.pathExtension == "md" }
    try check(markdownFiles.count == 3, "Folder export writes one Markdown file per owned document")
    let childMarkdown = try String(contentsOf: markdownFiles.first { $0.lastPathComponent.contains(child.id.uuidString) }!, encoding: .utf8)
    try check(childMarkdown.contains("Parent: [Project]") && childMarkdown.contains("Child lists:") && childMarkdown.contains(childTask.text) && !childMarkdown.contains(parentTask.text), "Export keeps parent/child links and block boundaries")
    try check(Data(contentsOf: export.appendingPathComponent("assets/Child cover.png")) == mediaBytes,
        "Folder export includes the child cover's exact bytes")
    try check(MarkdownExporter.markdown(for: parent, store: store).contains("Document: Project › Research"), "Clipboard export identifies each document path")
    do { try MarkdownExporter.write(list: parent, store: store, to: export); fatalError("Overwrote an existing export") }
    catch { checks += 1 }
    let everyList = directory.appendingPathComponent("Every list")
    try FileManager.default.createDirectory(at: everyList, withIntermediateDirectories: false)
    var exported = 0
    try MarkdownExporter.writeAll(store: store, to: everyList) { exported += $0 }
    let written = try FileManager.default.contentsOfDirectory(atPath: everyList.path)
    try check(written.contains("Project") && written.contains("Other project.md") && !written.contains("Project.md")
        && !written.contains { $0.hasPrefix("Research") || $0.hasPrefix("Sources") },
        "Export every list writes each top-level list once, a parent as a folder of its nested lists")
    try check(try FileManager.default.contentsOfDirectory(atPath: everyList.appendingPathComponent("Project").path)
        .filter { $0.hasSuffix(".md") }.count == 3, "Export every list keeps the parent's nested lists in its folder")
    try check(exported == store.allLists(includeArchived: true).count, "Export every list counts each list, nested ones included, once")

    let beforeMove = BackupTaskList(child)
    let rejecting = Store(context: context, commitContext: { _ in throw CocoaError(.fileWriteOutOfSpace) })
    try check(!rejecting.moveList(child, under: other.id) && BackupTaskList(child) == beforeMove,
        "A rejected move preserves the same live model's parent and all fields")
    try check(rejecting.createChildList(in: parent) == nil && store.listHierarchy().children(of: parent.id).count == 1,
        "A rejected child creation leaves no phantom owned document")
    try store.persistChanges()
    try check(!rejecting.trashList(parent) && child.trashID == nil && parent.trashID == nil && image.trashID == nil,
        "A rejected parent deletion restores child documents, blocks and media")
    try store.persistChanges()
    childTask.isCompleted = true; childTask.completedAt = .now; try store.persistChanges()
    let template = store.list(id: try store.copyList(parent, mode: .template(keepingRecurrence: false)))!
    let templateChild = store.listHierarchy().subtree(of: template.id).first { $0.title == child.title }!
    try check(store.blocks(inList: templateChild.id).filter(\.isTask).allSatisfy { !$0.isCompleted },
        "Template reset applies inside every copied child document")
    childTask.isCompleted = false; childTask.completedAt = nil; try store.persistChanges()

    try autoreleasepool {
        let readOnly = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema,
            url: directory.appendingPathComponent("Nested.store"), allowsSave: false, cloudKitDatabase: .none)])
        let readonly = Store(context: ModelContext(readOnly))
        let roParent = readonly.list(id: parent.id)!, roChild = readonly.list(id: child.id)!
        let original = BackupTaskList(roChild)
        try check(!readonly.moveList(roChild, under: other.id) && BackupTaskList(roChild) == original,
            "Actual read-only save failure restores the same child ownership model")
        try check(!readonly.trashList(roParent) && roParent.trashID == nil && roChild.trashID == nil,
            "Actual read-only subtree deletion cannot retain only part of the document tree")
        let mediaDirectory = directory.appendingPathComponent("Media")
        let before = Set(try FileManager.default.contentsOfDirectory(atPath: mediaDirectory.path))
        do { _ = try readonly.copyList(roParent, mode: .duplicate); fatalError("Read-only subtree copy succeeded") }
        catch { checks += 1 }
        _ = MediaStore.shared.fileContents(filename: "sentinel") // Drain the serial cache-cleanup queue.
        try check(Set(try FileManager.default.contentsOfDirectory(atPath: mediaDirectory.path)) == before,
            "Rejected subtree copy discards only its newly staged child media")
    }

    let independent = store.createChildList(in: child)!
    store.rename(independent, to: "Previously deleted")
    _ = task("Independently deleted child task", in: independent)
    try check(store.trashList(independent), "Child can be independently retained before its ancestor")
    try check(store.trashList(parent), "Deleting parent retains its whole owned available subtree")
    try check(child.trashID == parent.id && grandchild.trashID == parent.id && childTask.trashID == parent.id && grandTask.trashID == parent.id, "Parent group owns all child documents and blocks")
    try check(independent.trashID == independent.id, "Earlier child deletion retains its separate Trash group")
    try check(store.trashEntries().first { $0.id == parent.id }?.listCount == 3, "Trash describes the complete retained document count")
    try snapshot().validate()
    var invalidBoundary = try snapshot()
    let childOffset = invalidBoundary.blocks.firstIndex { $0.id == childTask.id }!
    invalidBoundary.blocks[childOffset].parentID = parentTask.id
    do { try invalidBoundary.validate(); fatalError("Accepted a retained task parent in another child document") }
    catch { checks += 1 }
    try check(!rejecting.restoreTrash(ids: [parent.id]) && parent.trashID == parent.id && child.trashID == parent.id
        && child.parentListID == parent.id, "Rejected subtree restore preserves its retained unit and parent references")
    try store.persistChanges()
    try check(!rejecting.permanentlyEraseTrash(ids: [parent.id]) && parent.trashID == parent.id
        && child.trashID == parent.id && child.coverData == mediaBytes,
        "Rejected permanent subtree erasure retains every document and durable cover byte")
    try store.persistChanges()
    try check(store.restoreTrash(ids: [parent.id]), "A parent deletion restores as one unit")
    try check(child.trashID == nil && child.parentListID == parent.id && grandchild.trashID == nil && independent.isTrashed, "Restore keeps original ownership and excludes separate earlier deletion")

    // Imported child/list blocks arrive after the parent reached Trash.
    try check(store.trashList(parent), "Parent can be retained again")
    let late = TaskList(title: "Late child"); late.parentListID = child.id; context.insert(late)
    let lateTask = Block(kind: .task, text: "Late task", listID: late.id); context.insert(lateTask)
    let lateBlock = Block(kind: .task, text: "Late root block", listID: parent.id); context.insert(lateBlock)
    try store.persistChanges()
    try check(store.list(id: late.id) == nil && store.block(id: lateTask.id) == nil && store.blocks(inList: parent.id).isEmpty, "Late imports remain hidden before reconciliation")
    try check(SearchCorpus(blocks: [lateTask], lists: [late]).blocks.isEmpty, "Search excludes a late child under retained ancestors")
    let lateBefore = BackupTaskList(late)
    try check(!rejecting.reconcileRetainedListDescendants() && BackupTaskList(late) == lateBefore && lateTask.trashID == nil,
        "Failed late-import retention leaves source payload and own membership unchanged")
    try store.persistChanges()
    try check(store.reconcileRetainedListDescendants(), "Late imports are retained explicitly")
    try check(late.trashID == parent.id && lateTask.trashID == parent.id && lateBlock.trashID == parent.id, "Late documents and blocks join the same root group")
    try snapshot().validate()

    let orphan = store.createList(title: "Missing parent child")
    let missingID = UUID(); orphan.parentListID = missingID
    try store.persistChanges()
    try check(store.listHierarchy().parent(of: orphan.id) == nil && store.listHierarchy().recoveryContext(for: orphan.id) != nil && store.list(id: orphan.id) != nil, "Missing parent preserves ownership reference and recoverable top-level access")
    let laterParent = TaskList(title: "Later parent"); laterParent.id = missingID; context.insert(laterParent)
    try store.persistChanges()
    try check(store.listHierarchy().parent(of: orphan.id)?.id == missingID, "An arriving parent reconnects the original child")
    let cycleA = store.createList(title: "Cycle A"), cycleB = store.createList(title: "Cycle B")
    cycleA.parentListID = cycleB.id; cycleB.parentListID = cycleA.id
    try store.persistChanges()
    let cycle = store.listHierarchy()
    try check(cycle.ancestors(of: cycleA.id).count <= 1 && cycle.ancestors(of: cycleB.id).count <= 1 && cycleA.parentListID == cycleB.id && cycleB.parentListID == cycleA.id, "Imported cycles have bounded deterministic display without rewriting source references")
    try check(!store.moveList(other, under: cycleA.id), "Moves into imported cycles are rejected")
    try check(store.moveList(cycleA, under: nil), "An explicit move repairs an imported cycle")
    try store.persistChanges()

    // Sidebar, gallery and search rows share a body-local graph for paths and membership.
    let owner = TaskList(title: "Owner"), descendant = TaskList(title: "Child")
    descendant.parentListID = owner.id
    var projected = [owner, descendant]
    try check(ListHierarchy(projected).path(for: descendant.id) == "Owner › Child", "Shared row projection includes the current owning path")
    owner.title = "Renamed owner"
    try check(ListHierarchy(projected).path(for: descendant.id) == "Renamed owner › Child", "Rebuilding the parent projection reflects ancestor rename")
    owner.isArchived = true
    var projection = ListHierarchy(projected)
    try check(!projection.activeIDs.contains(descendant.id) && projection.isArchived(descendant.id),
        "Shared active membership and card archive state change together")
    owner.isArchived = false
    descendant.parentListID = UUID()
    projection = ListHierarchy(projected)
    try check(projection.ancestors(of: descendant.id).isEmpty && projection.recoveryContext(for: descendant.id) != nil,
        "Shared projection represents an unavailable parent without a stale path")
    let arriving = TaskList(title: "Arriving owner"); arriving.id = descendant.parentListID!
    projected.append(arriving)
    projection = ListHierarchy(projected)
    try check(projection.path(for: descendant.id) == "Arriving owner › Child" && projection.recoveryContext(for: descendant.id) == nil,
        "Late parent arrival updates shared row paths and clears recovery context")
    descendant.parentListID = owner.id
    try check(ListHierarchy(projected).path(for: descendant.id) == "Renamed owner › Child",
        "Moving a document updates the shared row projection to its new parent")

    let expected = try snapshot(); try expected.validate()
    try JSONEncoder().encode(expected).write(to: directory.appendingPathComponent("expected.json"))
} else {
    let expected = try JSONDecoder().decode(LibraryBackup.self, from: Data(contentsOf: directory.appendingPathComponent("expected.json")))
    let actual = try snapshot()
    try check(actual.lists == expected.lists && actual.blocks == expected.blocks, "Cold reopen preserves all ownership and retained document fields")
    let parent = try named("Project"), child = try named("Research"), late = try named("Late child")
    try check(child.coverData == expected.lists.first { $0.id == child.id }?.coverData, "Cold child cover bytes survive parent Trash")
    try check(parent.isTrashed && child.trashID == parent.id && late.trashID == parent.id, "Parent Trash group survives process restart")
    try check(store.restoreTrash(ids: [parent.id]), "Cold restore includes the late child")
    try check(child.parentListID == parent.id && late.parentListID == child.id && store.list(id: late.id) != nil, "Cold restore preserves every original parent and identity")
    let independent = try named("Previously deleted")
    try check(independent.isTrashed && store.restoreTrash(ids: [independent.id]), "Separately deleted child restores only when requested")
    try check(independent.parentListID == child.id, "Independent child reconnects to its restored parent")
    try check(store.trashList(parent), "Retain restored subtree before explicit erasure")
    let orphan = TaskList(title: "Arrives after permanent erasure"); orphan.parentListID = parent.id
    try check(store.permanentlyEraseTrash(ids: [parent.id]), "Permanent erase removes exactly the selected document group")
    context.insert(orphan); try store.persistChanges()
    try check(store.reconcileRetainedListDescendants() && store.list(id: orphan.id) != nil && orphan.parentListID == parent.id, "An import after permanent parent erasure stays available with its missing reference")
    try check(store.trashList(orphan) && store.restoreTrash(ids: [orphan.id]), "An orphan child restores safely")
    try check(orphan.parentListID == nil && orphan.trashMetadata?.recoveryNote != nil, "Restoring to an unavailable parent recovers at top level with explanation")
    try snapshot().validate()
}
if phase == "reopen" {
    for parentFirst in [true, false] {
        let isolated = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema,
            url: directory.appendingPathComponent("Reset-\(parentFirst).store"), cloudKitDatabase: .none)])
        let reset = Store(context: isolated.mainContext); reset.bootstrap()
        let parent = reset.createList(title: "Reset parent")
        let child = reset.createChildList(in: parent)!
        child.sortIndex = parentFirst ? parent.sortIndex + 1 : parent.sortIndex - 1
        _ = reset.appendBlock(kind: .task, text: "Nested reset task", to: DocumentContext(listID: child.id))
        try reset.persistChanges()
        try check(reset.permanentlyResetLibrary(), "Delete everything finishes with parentFirst=\(parentFirst)")
        try check(reset.allLists(includeArchived: true).allSatisfy(\.isSystemInbox)
            && reset.trashEntries().isEmpty && isolated.mainContext.fetchCount(FetchDescriptor<Block>()) == 0,
            "Reset removes all child documents and content in either list order")
    }
}
print("✅ \(checks) nested-list checks passed (\(phase))")
