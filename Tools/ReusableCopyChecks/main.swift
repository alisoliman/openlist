import AppKit
import SwiftData

var checks = 0
func check(_ condition: Bool, _ message: String) {
    precondition(condition, message)
    checks += 1
}
func rejects(_ message: String, _ operation: () throws -> Void) {
    do { try operation(); preconditionFailure(message) } catch { checks += 1 }
}
let schema = Schema([TaskList.self, Block.self, SidebarSection.self, TaskLabel.self, Attachment.self,
    ActivityEvent.self, WorkSession.self, CompletionRecord.self, SchedulePlacement.self])
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
let container = try ModelContainer(for: schema, configurations: [configuration])
let store = Store(context: container.mainContext)
store.context.autosaveEnabled = false
let media = MediaStore.shared
let mediaFolder = media.url(for: "sentinel").deletingLastPathComponent()
let manifestURL = url.appendingPathExtension("json")
let imageBytes = Data([0, 12, 250, 255])
let fileBytes = Data("Independent attachment".utf8)

struct Manifest: Codable {
    let sourceID: UUID
    let copyID: UUID
    let listCopyID: UUID
    let expectedIDs: Set<UUID>
    let filenames: Set<String>
}

func files() throws -> Set<String> {
    _ = media.fileContents(filename: "sentinel") // Drain async removals.
    return Set(try FileManager.default.contentsOfDirectory(atPath: mediaFolder.path))
}
func activityIDs(in context: ModelContext) throws -> Set<UUID> {
    Set(try context.fetch(FetchDescriptor<ActivityEvent>()).map(\.id))
}
func history(_ id: UUID) throws -> [ActivityEvent] {
    try store.taskActivity(for: id, limit: 10_000)
}
func checkCreationHistory(_ blocks: [Block], owningList: TaskList) throws {
    for block in blocks {
        let events = try history(block.id)
        if block.isTask {
            check(events.count == 1 && events[0].kind == .created, "Each copied task starts with exactly one fresh creation event")
            let change = events[0].change
            check(change?.before == nil && change?.after == TaskActivityState(block, list: owningList), "Creation history snapshots the copied payload and owning list")
            check(change?.completionID == nil && change?.completedAt == nil && change?.advancesOccurrence == false,
                "A copied completed task never inherits an occurrence completion event")
        } else {
            check(events.isEmpty, "Mixed non-task descendants do not acquire task creation history")
        }
    }
}
func tree(_ id: UUID) -> [Block] {
    guard let block = store.block(id: id) else { return [] }
    return [block] + BlockTree.descendants(of: id, in: store.blocks(inList: block.listID!))
}
func checkMedia(_ blocks: [Block]) {
    for block in blocks {
        if let filename = block.mediaFilename {
            check(media.fileContents(filename: filename) == imageBytes, "Copied image retains complete independent bytes")
            check(block.mediaData == imageBytes, "Copied image keeps retained bytes for sync and relaunch")
        }
        for attachment in store.attachments(for: block.id) {
            check(media.fileContents(filename: attachment.filename) == fileBytes, "Copied attachment remains readable")
            check(attachment.contentData == fileBytes, "Copied attachment has its own retained bytes")
        }
    }
}

if CommandLine.arguments[2] == "reopen" {
    let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
    check(store.block(id: manifest.sourceID) == nil, "Source deletion remains committed across process relaunch")
    let copied = tree(manifest.copyID)
    check(Set(copied.map(\.id)) == manifest.expectedIDs, "Undo/Redo tree identities survive a separate process")
    checkMedia(copied)
    for task in copied where task.isTask {
        let events = try history(task.id)
        check(events.filter { $0.kind == .created }.count == 1 && events.contains { $0.kind == .restored },
            "Creation and Undo/Redo history persist under the copied UUID after relaunch")
    }
    let copiedList = store.blocks(inList: manifest.listCopyID)
    check(copiedList.count == copied.count + 1, "Template list retains the full document and sibling after relaunch")
    checkMedia(copiedList)
    try checkCreationHistory(copiedList, owningList: store.list(id: manifest.listCopyID)!)
    for block in copiedList {
        check(!block.isCompleted && block.dueDate == nil && block.reminderAt == nil, "Fresh list remains unscheduled after relaunch")
    }
    check(try files().isSuperset(of: manifest.filenames), "Every copied filename remains independently owned on disk")
    print("✅ \(checks) reusable copy relaunch checks passed")
    exit(0)
}

store.bootstrap()
let list = store.createList(title: "Reusable procedure")
list.summary = "Packing instructions"
list.isArchived = true
list.isPinned = true
list.sorting = .alphabetical
list.availabilityCategoryRaw = "personal"
let label = TaskLabel(name: "Travel", accent: .blue)
store.context.insert(label)
let root = store.appendBlock(kind: .task, text: "Procedure", to: DocumentContext(listID: list.id))
root.sortIndex = 1024
let sibling = store.appendBlock(kind: .task, text: "Next sibling", to: DocumentContext(listID: list.id))
sibling.sortIndex = 2048
var originals = [root]
var parent = root
// Mixed descendants remain complete regardless of collapsed/completed ancestors.
for index in 0..<18 {
    let kind: BlockKind = [.task, .paragraph, .heading2, .image, .code, .bullet][index % 6]
    let child = store.insertChild(kind: kind, of: parent)
    child.text = "Step \(index)"
    child.sortIndex = Double(index * 13)
    originals.append(child)
    parent = child
}
for (index, block) in originals.enumerated() {
    block.note = "Detailed note \(index) with café and 👨‍👩‍👧‍👦"
    block.richData = RichTextCodec.encode(NSAttributedString(string: block.text, attributes: [.font: NSFont.boldSystemFont(ofSize: 14)]), kind: block.kind)
    block.isCollapsed = true
    block.isCompleted = true
    block.completedAt = Date(timeIntervalSince1970: 3000)
    block.dueDate = Date(timeIntervalSince1970: 2_000_000_000)
    block.includesTime = true
    block.reminderAt = Date(timeIntervalSince1970: 1_999_999_000)
    block.isStarred = true
    block.priority = .high
    block.labelIDs = [label.id]
    block.selectedForDay = .now
    block.deferredUntil = .now
    block.calendarOccurrenceID = UUID()
    block.schedulingEstimateMinutes = 45
    block.keepsSessionsTogether = true
    block.tracksAwayFromMac = true
    block.recurrence = Recurrence(frequency: .monthly, interval: 2, dayOfMonth: 31,
        endDate: Date(timeIntervalSince1970: 100), occurrenceLimit: 12, completedOccurrences: 7)
    if block.kind == .image {
        let filename = "source-\(index).png"
        try media.restoreFile(imageBytes, filename: filename)
        block.mediaFilename = filename
        block.mediaCaption = "Figure \(index)"
        block.mediaWidth = 512
        block.mediaHeight = 256
    }
    if index.isMultiple(of: 4) {
        let filename = "source-\(index).txt"
        try media.restoreFile(fileBytes, filename: filename)
        let attachment = Attachment(blockID: block.id, filename: filename, displayName: "Instructions.txt",
            contentType: "text/plain", byteCount: fileBytes.count, sortIndex: 2)
        store.context.insert(attachment)
    }
}
let placement = SchedulePlacement(task: root, start: .now, end: .now.addingTimeInterval(3600), isPinned: true)
let session = WorkSession(task: root, deviceID: "fixture")
store.context.insert(placement); store.context.insert(session)
try store.persistChanges()
let sourceIDs = Set(originals.map(\.id))
let sourceOrder = originals.map { ($0.parentID, $0.sortIndex) }
let sourceFilenames = try files()
let rootID = root.id
let sourceHistoryIDs = Set(try store.context.fetch(FetchDescriptor<ActivityEvent>())
    .filter { $0.blockID.map(sourceIDs.contains) == true }.map(\.id))
func checkSourceHistory() throws {
    check(Set(try store.context.fetch(FetchDescriptor<ActivityEvent>())
        .filter { $0.blockID.map(sourceIDs.contains) == true }.map(\.id)) == sourceHistoryIDs,
        "Copy and its Undo/Redo do not append or transfer source history")
}

let undo = UndoManager()
undo.groupsByEvent = false
undo.beginUndoGrouping()
let copiedID = try store.undoableEditorEdit(in: list.id, name: "Duplicate task", undoManager: undo) {
    Result { try store.copyBlock(root, mode: .duplicate) }
}.get()
undo.endUndoGrouping()
let copied = tree(copiedID)
try checkCreationHistory(copied, owningList: list)
try checkSourceHistory()
check(copied.count == originals.count, "First live fetch includes the complete arbitrary-depth mixed subtree")
check(sourceIDs.isDisjoint(with: copied.map(\.id)), "Every copied block has a fresh identity")
let copiedByText = Dictionary(uniqueKeysWithValues: copied.map { ($0.text, $0) })
for original in originals {
    let copy = copiedByText[original.text]!
    check(copy.note == original.note && copy.richData == original.richData && copy.kind == original.kind, "Mixed content, note and inline formatting are preserved")
    check(copy.isCompleted && copy.completedAt == original.completedAt && copy.dueDate == original.dueDate && copy.reminderAt == original.reminderAt, "Duplicate retains completion, due date and reminder metadata")
    check(copy.recurrence == original.recurrence && copy.isStarred && copy.priority == .high && copy.labelIDs == [label.id], "Duplicate retains recurrence progress, labels, priority and stars")
    check(copy.selectedForDay == nil && copy.deferredUntil == nil && copy.occurrenceID != original.occurrenceID, "Calendar occurrence identity and placements are never shared")
    if original.id != root.id {
        let parentText = originals.first { $0.id == original.parentID }!.text
        check(copy.parentID == copiedByText[parentText]!.id && copy.sortIndex == original.sortIndex, "Descendant parent IDs remap while sibling order remains exact")
    }
    if let filename = copy.mediaFilename { check(filename != original.mediaFilename, "Images receive independent ownership") }
}
check(copied[0].sortIndex > root.sortIndex && copied[0].sortIndex < sibling.sortIndex, "Copy lands directly between source and next sibling")
check(originals.enumerated().allSatisfy { $0.element.parentID == sourceOrder[$0.offset].0 && $0.element.sortIndex == sourceOrder[$0.offset].1 }, "Copy leaves source hierarchy and ordering untouched")
checkMedia(copied)
let copiedIDs = Set(copied.map(\.id))
let copiedTaskIDs = copied.filter(\.isTask).map(\.id)
let copiedFilenames = try files().subtracting(sourceFilenames)
undo.undo()
check(store.block(id: copiedID) == nil && copiedIDs.isDisjoint(with: store.blocks(inList: list.id).map(\.id)), "One Undo removes the entire copied tree")
check(try files() == sourceFilenames, "Undo removes only copy-owned files")
check(undo.canRedo, "Recursive copy retains Redo support")
for taskID in copiedTaskIDs {
    let events = try history(taskID)
    check(events.count == 2 && Set(events.map(\.kind)) == [.created, .deleted], "Copy Undo appends deletion after creation under the copied UUID")
}
try checkSourceHistory()
undo.redo()
check(Set(tree(copiedID).map(\.id)) == copiedIDs, "Redo restores the exact new identities and hierarchy")
check(try files().isSuperset(of: copiedFilenames), "Redo restores all copied media")
checkMedia(tree(copiedID))
for taskID in copiedTaskIDs {
    let events = try history(taskID)
    check(events.count == 3 && Set(events.map(\.kind)) == [.created, .deleted, .restored], "Copy Redo appends restoration without another creation event")
}
try checkSourceHistory()

let freshID = try store.copyBlock(root, mode: .template(keepingRecurrence: false))
try checkCreationHistory(tree(freshID), owningList: list)
for copy in tree(freshID) {
    check(!copy.isCompleted && copy.completedAt == nil && copy.dueDate == nil && !copy.includesTime && copy.reminderAt == nil, "Template clears completion and every dated notification field")
    check(copy.recurrenceData == nil && copy.selectedForDay == nil && copy.deferredUntil == nil, "Default template cannot inherit recurrence or calendar selections")
    check(copy.labelIDs == [label.id] && copy.priority == .high && copy.isStarred && copy.isCollapsed, "Template preserves organization and task flags")
    check(copy.schedulingEstimateMinutes == 45 && copy.keepsSessionsTogether && copy.tracksAwayFromMac, "Template preserves reusable planning preferences")
}
let repeatID = try store.copyBlock(root, mode: .template(keepingRecurrence: true))
try checkCreationHistory(tree(repeatID), owningList: list)
for copy in tree(repeatID) {
    check(copy.recurrence?.completedOccurrences == 0 && copy.recurrence?.endDate == nil, "Opt-in recurrence clears old progress and dated expiry")
    check(copy.recurrence?.frequency == .monthly && copy.recurrence?.dayOfMonth == 31 && copy.recurrence?.occurrenceLimit == 12, "Opt-in recurrence keeps pattern and count limit")
    check(copy.dueDate == nil && copy.reminderAt == nil, "Keeping recurrence never retains a stale due date or reminder")
}
check(try store.context.fetch(FetchDescriptor<SchedulePlacement>()).map(\.taskID) == [rootID], "Copies do not duplicate calendar placements")
check(try store.context.fetch(FetchDescriptor<WorkSession>()).map(\.taskID) == [rootID], "Copies do not duplicate work history")
for copyID in [freshID, repeatID] { store.deleteBlock(store.block(id: copyID)!) }
store.save()

// A downstream missing asset fails after other files were successfully staged.
let deepAttachment = store.attachments(for: originals[16].id)[0]
let savedFilename = deepAttachment.filename
deepAttachment.filename = "missing-deep-file.txt"
let beforeFailureFiles = try files()
let beforeFailureIDs = Set(store.blocks(inList: list.id).map(\.id))
let beforeFailureHistory = try activityIDs(in: store.context)
rejects("A missing descendant asset must reject the whole task copy") { _ = try store.copyBlock(root, mode: .duplicate) }
let afterFailureFiles = try files()
check(Set(store.blocks(inList: list.id).map(\.id)) == beforeFailureIDs && afterFailureFiles == beforeFailureFiles, "Deep file failure leaves no partial models or staged files")
check(try activityIDs(in: store.context) == beforeFailureHistory, "Deep media failure leaves no creation history")
check(deepAttachment.filename == "missing-deep-file.txt" && store.context.hasChanges, "File failure preserves unrelated pending edits")
deepAttachment.filename = savedFilename
try store.persistChanges()

// A real disk failure must not mutate retained objects or discard pending edits.
let readonly = try ModelContainer(for: schema, configurations: [
    ModelConfiguration(schema: schema, url: url, allowsSave: false, cloudKitDatabase: .none)])
let failing = Store(context: readonly.mainContext)
failing.context.autosaveEnabled = false
let retainedRoot = failing.block(id: rootID)!
let retainedList = failing.list(id: list.id)!
retainedRoot.note = "Unsaved source note"
retainedList.summary = "Unsaved source summary"
let failedFiles = try files()
let failedBlockIDs = Set(failing.blocks(inList: list.id).map(\.id))
let failedListIDs = Set(failing.allLists(includeArchived: true).map(\.id))
let failedHistoryIDs = try activityIDs(in: failing.context)
rejects("Read-only insert transaction fails atomically for a task") { _ = try failing.copyBlock(retainedRoot, mode: .template(keepingRecurrence: true)) }
rejects("Read-only insert transaction fails atomically for a list") { _ = try failing.copyList(retainedList, mode: .duplicate) }
check(!retainedRoot.isDeleted && retainedRoot.note == "Unsaved source note" && retainedRoot.isCompleted, "Failed save leaves retained source block unchanged")
check(!retainedList.isDeleted && retainedList.summary == "Unsaved source summary", "Failed save leaves retained list unchanged")
check(failing.context.hasChanges, "Failed sibling save does not roll back pending live edits")
check(Set(failing.blocks(inList: list.id).map(\.id)) == failedBlockIDs && Set(failing.allLists(includeArchived: true).map(\.id)) == failedListIDs, "First live fetch after save failure contains no partial copy")
check(try files() == failedFiles, "Save failures remove every staged file")
check(try activityIDs(in: failing.context) == failedHistoryIDs, "First live history fetch after failed task/list copy contains no phantom events")
let failureReader = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
check(try activityIDs(in: failureReader.mainContext) == failedHistoryIDs, "Reopened disk history contains no failed copy events")
check(store.block(id: rootID)?.note == root.note && store.list(id: list.id)?.summary == "Packing instructions", "A separate writer sees no failed or pending source edits")

// Successful sibling copies capture the live payload without flushing pending
// source edits or accidentally recording them as source activity.
let pendingList = store.createList(title: "Committed source list")
let pendingTask = store.appendBlock(kind: .task, text: "Committed source title", to: .init(listID: pendingList.id))
try store.persistChanges()
let pendingSourceEvents = Set(try history(pendingTask.id).map(\.id))
store.setText("Unsaved reusable title", for: pendingTask)
pendingList.title = "Unsaved reusable list"
pendingList.icon = "🧭"
let pendingCopyID = try store.copyBlock(pendingTask, mode: .template(keepingRecurrence: false))
try checkCreationHistory(tree(pendingCopyID), owningList: pendingList)
check(store.context.hasChanges && pendingTask.text == "Unsaved reusable title" && pendingList.title == "Unsaved reusable list",
    "Successful task copy keeps source task/list edits pending")
check(Set(try history(pendingTask.id).map(\.id)) == pendingSourceEvents, "Successful copy records no unsaved source title event")
let pendingListCopyID = try store.copyList(pendingList, mode: .template(keepingRecurrence: false))
try checkCreationHistory(store.blocks(inList: pendingListCopyID), owningList: store.list(id: pendingListCopyID)!)
check(store.context.hasChanges && pendingList.title == "Unsaved reusable list", "Successful list copy also preserves pending source edits")
let pendingReader = ModelContext(container)
pendingReader.autosaveEnabled = false
let pendingTaskID = pendingTask.id
let pendingListID = pendingList.id
check(try pendingReader.fetch(FetchDescriptor<Block>(predicate: #Predicate { $0.id == pendingTaskID })).first?.text == "Committed source title",
    "A fresh reader sees no source title flush from successful copies")
check(try pendingReader.fetch(FetchDescriptor<TaskList>(predicate: #Predicate { $0.id == pendingListID })).first?.title == "Committed source list",
    "A fresh reader sees no source list flush from successful copies")
check(Set(try history(pendingTask.id).map(\.id)) == pendingSourceEvents, "Task and list copy leave source history unchanged")

// Delete extra copy, then create one list template for the relaunch manifest.
let detached = store.duplicateList(list)
try checkCreationHistory(store.blocks(inList: detached.id), owningList: detached)
check(detached.id != list.id && !detached.isArchived && detached.isPinned, "List Duplicate retains its existing active-copy destination behavior")
store.trashList(detached)
// The list template contains source + adjacent sibling; remove the task copy temporarily.
undo.undo()
let listCopyID = try store.copyList(list, mode: .template(keepingRecurrence: false))
try checkCreationHistory(store.blocks(inList: listCopyID), owningList: store.list(id: listCopyID)!)
undo.redo()
check(store.list(id: listCopyID)?.summary == list.summary && store.list(id: listCopyID)?.availabilityCategoryRaw == "personal", "List template retains description and reusable list preferences")
store.deleteBlock(root)
store.save()
check(store.block(id: rootID) == nil, "Source tree is deleted independently")
check(tree(copiedID).count == originals.count, "Deleting source does not remove copied descendants")
checkMedia(tree(copiedID))
checkMedia(store.blocks(inList: listCopyID))
let manifest = Manifest(sourceID: rootID, copyID: copiedID, listCopyID: listCopyID,
    expectedIDs: copiedIDs, filenames: try files())
try JSONEncoder().encode(manifest).write(to: manifestURL)
print("✅ \(checks) reusable copy, failure and Undo/Redo checks passed")
