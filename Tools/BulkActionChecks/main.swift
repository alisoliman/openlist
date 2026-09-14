import AppKit
import SwiftData

var checks = 0
func check(_ result: @autoclosure () -> Bool, _ message: String) {
    precondition(result(), message)
    checks += 1
}
func rejects(_ message: String, _ body: () throws -> Void) {
    do { try body(); preconditionFailure(message) } catch {
        print("Expected failure: \(message): \(error)")
        fflush(stdout)
        checks += 1
    }
}
enum InjectedFailure: Error { case save }

let schema = Schema([TaskList.self, Block.self, SidebarSection.self, TaskLabel.self, Attachment.self,
                     ActivityEvent.self, WorkSession.self, CompletionRecord.self, SchedulePlacement.self])
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
let container = try ModelContainer(for: schema, configurations: [configuration])
if CommandLine.arguments.last == "reopen" {
    let saved = try container.mainContext.fetch(FetchDescriptor<Block>())
    let lists = try container.mainContext.fetch(FetchDescriptor<TaskList>())
    let targetID = lists.first { $0.title == "Destination" }!.id
    let savedFirst = saved.first { $0.text == "First" }!
    let savedParent = saved.first { $0.text == "Edited after move" }!
    let savedChild = saved.first { $0.text == "Child" }!
    check(savedFirst.listID == targetID && savedParent.listID == targetID && savedChild.listID == targetID,
          "A separate process observes no failed move or cross-list subtree")
    check(!savedFirst.isCompleted && savedFirst.note == "Draft before action", "A separate process observes the preserved draft and no failed completion")
    check(savedChild.parentID == savedParent.id && savedParent.note == "Metadata after move", "Subtree and later metadata survive process reopening")
    let savedFiles = try container.mainContext.fetch(FetchDescriptor<Attachment>())
    check(savedFiles.first?.blockID == savedChild.id && savedFiles.first?.contentData == Data("bulk selection attachment".utf8),
          "Independent process reads the same attachment owner and bytes")
    check(InboxPolicy.selection(savedParent) == nil && InboxPolicy.selection(savedFirst) != nil && InboxPolicy.selection(savedChild) != nil,
          "A separate process observes independent Inbox curation after move Undo and Redo")
    let savedDropParent = saved.first { $0.text == "Collapsed drop target" }!
    let savedDropOne = saved.first { $0.text == "Drop one" }!
    check(savedDropParent.isCollapsed && savedDropOne.listID == lists.first { $0.title == "Source" }!.id && savedDropOne.parentID == nil,
          "A separate process observes no failed destination expansion or inside-drop")
    print("\(checks) bulk action reopen checks passed")
    exit(0)
}
var failNextSave = false
var failedSaveIncludedCompletion = false
let store = Store(context: container.mainContext) { context in
    if failNextSave {
        failNextSave = false
        failedSaveIncludedCompletion = context.insertedModelsArray.contains { $0 is CompletionRecord }
        throw InjectedFailure.save
    }
    try context.save()
}
store.bootstrap()
let source = store.createList(title: "Source")
let destination = store.createList(title: "Destination")
let doc = DocumentContext(listID: source.id)
let first = store.appendBlock(kind: .task, text: "First", to: doc)
let parent = store.appendBlock(kind: .task, text: "Recurring parent", to: doc)
let child = store.insertChild(text: "Child", of: parent)
let previouslyDone = store.insertChild(text: "Previously done", of: parent)
store.toggleCompletion(previouslyDone)
parent.dueDate = Calendar.current.startOfDay(for: .now)
parent.recurrence = .weekly
parent.note = "Keep note"
let bytes = Data("bulk selection attachment".utf8)
let attachment = Attachment(blockID: child.id, filename: "bulk-proof.txt", displayName: "proof.txt",
                            contentType: "text/plain", byteCount: bytes.count)
attachment.contentData = bytes
store.context.insert(attachment)
store.save()
let placement = store.setPlacement(for: parent, start: .now, end: .now.addingTimeInterval(1_800), isPinned: true)!
let placementID = placement.id
check(store.setInboxMembership(true, taskIDs: [first.id, parent.id, child.id]), "The completion fixture includes selected tasks across the recurring subtree")
let oldParent = CompletionTaskState(parent)
let oldChild = CompletionTaskState(child)
let oldDone = CompletionTaskState(previouslyDone)
let oldRecords = Set(store.completionRecords().map(\.id))
let manager = UndoManager()
manager.groupsByEvent = false
var notifications = 0
store.onCompletionUndoAvailable = { action in
    notifications += 1
    store.registerCompletionUndo(action, with: manager)
}
manager.beginUndoGrouping()
let count = try store.setBulkCompletion(true, ids: [child.id, first.id, parent.id, child.id, previouslyDone.id])
manager.endUndoGrouping()
check(count == 3 && notifications == 1, "Duplicate group appearances and selected descendants produce one operation and Undo")
check(parent.recurrence?.completedOccurrences == 1 && !parent.isCompleted && !child.isCompleted,
      "Selected recurring parent advances once and resets its child once")
check(first.isCompleted && parent.occurrenceID != oldParent.occurrenceID, "Explicit Complete handles ordinary and recurring roots together")
check(store.completionRecords().count == oldRecords.count + 3, "Only pending parent, child and independent task create completion records")
check(store.placements(taskID: parent.id).isEmpty, "Completion removes occurrence placement")
check(InboxPolicy.selection(parent) == nil && InboxPolicy.selection(child) == nil && InboxPolicy.selection(first) != nil,
      "Bulk recurrence advances clear parent and child Inbox selection while ordinary completion retains curation")
parent.note = "Later note"; store.save()
manager.undo()
check(CompletionTaskState(parent) == oldParent && CompletionTaskState(child) == oldChild && CompletionTaskState(previouslyDone) == oldDone,
      "One Undo restores every recurring descendant and occurrence")
check(!first.isCompleted && Set(store.completionRecords().map(\.id)) == oldRecords && parent.note == "Later note",
      "Completion Undo restores all roots and exact history while preserving later metadata")
check(store.placements(taskID: parent.id).contains { $0.id == placementID }, "One Undo restores original placement identity")
manager.redo()
check(first.isCompleted && parent.recurrence?.completedOccurrences == 1 && store.completionRecords().count == oldRecords.count + 3,
      "Redo restores the same multi-root completion without duplicate records")
manager.removeAllActions()
manager.beginUndoGrouping()
let reopened = try store.setBulkCompletion(false, ids: [first.id, parent.id, first.id])
manager.endUndoGrouping()
check(reopened == 1 && !first.isCompleted && store.completionUndo?.isReopening == true, "Explicit Reopen skips already pending tasks and has accurate feedback")
check(InboxPolicy.selection(first)?.occurrenceID == first.occurrenceID,
      "Bulk reopen carries the same Inbox selection to the reopened occurrence")
let reopenedOccurrence = first.occurrenceID
manager.undo()
check(first.isCompleted && first.occurrenceID != reopenedOccurrence, "Reopen Undo works without creating completion records")
manager.redo()
check(!first.isCompleted && first.occurrenceID == reopenedOccurrence, "Reopen Redo restores the same new occurrence")

// A completed parent does not swallow a selected pending child during Complete.
let doneParent = store.appendBlock(kind: .task, text: "Done parent", to: doc)
manager.beginUndoGrouping()
store.toggleCompletion(doneParent)
manager.endUndoGrouping()
let pendingChild = store.insertChild(text: "New pending child", of: doneParent)
store.save()
manager.beginUndoGrouping()
let pendingCount = try store.setBulkCompletion(true, ids: [doneParent.id, pendingChild.id])
manager.endUndoGrouping()
check(pendingCount == 1 && pendingChild.isCompleted, "Completed selected parent does not hide pending child operation")
store.onCompletionUndoAvailable = nil
manager.removeAllActions()

let anchor = store.appendBlock(kind: .paragraph, text: "Anchor", to: .init(listID: destination.id))
let originalParentID = parent.parentID
let originalChildID = child.id
check(store.setInboxMembership(true, taskIDs: [first.id, parent.id, child.id]), "The move fixture has a curated multi-root selection")
let membershipBeforeMove = [first, parent, child].map(\.inboxMembershipData)
manager.beginUndoGrouping()
let moved = try store.moveSelection([first.id, child.id, parent.id, first.id], to: destination.id, above: anchor.id, undoManager: manager)
manager.endUndoGrouping()
check(moved == [first.id, parent.id], "Move canonicalizes descendant and repeated selections in visible order")
check(store.children(of: nil, listID: destination.id).map(\.id) == [first.id, parent.id, anchor.id], "Selected roots remain contiguous before destination anchor")
check(child.id == originalChildID && child.parentID == parent.id && child.listID == destination.id && attachment.blockID == child.id && attachment.contentData == bytes,
      "Moving preserves complete subtree IDs, attachment identity and bytes")
check([first, parent, child].map(\.inboxMembershipData) == membershipBeforeMove,
      "Ownership moves leave Inbox selection and manual queue order byte-for-byte unchanged")
check(store.setInboxMembership(false, taskIDs: [parent.id]), "A later curation decision removes only the moved parent from Inbox")
parent.text = "Edited after move"; parent.note = "Metadata after move"; store.save()
manager.undo()
check(parent.listID == source.id && first.listID == source.id && child.listID == source.id && parent.parentID == originalParentID,
      "One Undo restores all moved roots and descendants")
check(parent.text == "Edited after move" && parent.note == "Metadata after move" && attachment.contentData == bytes,
      "Move Undo touches only positions and preserves later content")
check(InboxPolicy.selection(parent) == nil && InboxPolicy.selection(first) != nil && InboxPolicy.selection(child) != nil,
      "Move Undo preserves the later Inbox exclusion and other tasks' selection")
manager.redo()
check(parent.listID == destination.id && child.parentID == parent.id, "Move Redo preserves subtree structure")
check(InboxPolicy.selection(parent) == nil && InboxPolicy.selection(first) != nil && InboxPolicy.selection(child) != nil,
      "Move Redo also preserves independent Inbox curation")
let laterChild = store.insertChild(text: "Added after move", of: parent)
store.save()
manager.undo()
check(parent.listID == destination.id && first.listID == destination.id && laterChild.listID == destination.id
      && laterChild.parentID == parent.id && store.editorNotice != nil,
      "Undo refuses an incompatible later child without orphaning it or partly restoring other roots")
manager.removeAllActions()
rejects("Cannot move ancestor into selected descendant") { _ = try store.moveSelection([parent.id, first.id], to: destination.id, parentID: child.id) }
rejects("Missing selected item cannot cause a partial move") { _ = try store.moveSelection([first.id, UUID()], to: source.id) }
check(first.listID == destination.id && parent.listID == destination.id, "Invalid preflight changes no selected item")

// A failed action cannot publish an Undo or discard already committed drafts.
first.note = "Draft before action"
failNextSave = true
rejects("Failed draft commit aborts before bulk mutations") { _ = try store.moveSelection([first.id, parent.id], to: source.id) }
check(first.note == "Draft before action" && first.listID == destination.id, "Initial save failure retains pending draft and original positions")
store.save()
failNextSave = true
rejects("Failed bulk move is atomic") { _ = try store.moveSelection([first.id, parent.id], to: source.id, undoManager: manager) }
check(first.listID == destination.id, "Move save failure restores first root position")
check(child.listID == destination.id, "Move save failure restores child position")
check(first.note == "Draft before action", "Move save failure preserves previously committed draft")
check(!manager.canUndo, "Move save failure publishes no Undo")
store.save()
check(!store.context.hasChanges, "Completion failure starts after any restored move fields are committed")
let completionCount = store.completionRecords().count
let beforeFailure = CompletionTaskState(first)
failNextSave = true
rejects("Failed bulk completion is atomic") { _ = try store.setBulkCompletion(true, ids: [first.id, parent.id]) }
check(failedSaveIncludedCompletion, "Injected failure reaches the completion mutation save with new history records")
check(CompletionTaskState(first) == beforeFailure && store.completionRecords().count == completionCount && store.pendingCompletionUndoChanges.isEmpty,
      "Completion save failure restores occurrence and records and clears unpublished action")
store.save()
// Inside-drop expansion shares the move's save and Undo, unlike toolbar moves.
let dropParent = store.appendBlock(kind: .task, text: "Collapsed drop target", to: .init(listID: destination.id))
let dropOne = store.appendBlock(kind: .task, text: "Drop one", to: doc)
let dropTwo = store.appendBlock(kind: .task, text: "Drop two", to: doc)
dropParent.isCollapsed = true
store.save()
_ = try store.moveSelection([dropOne.id], to: destination.id, parentID: dropParent.id)
check(dropParent.isCollapsed, "Ordinary Move does not change destination expansion")
_ = try store.moveSelection([dropOne.id], to: source.id)
let dropUndo = UndoManager()
dropUndo.groupsByEvent = false
dropUndo.beginUndoGrouping()
_ = try store.moveSelection([dropOne.id, dropTwo.id], to: destination.id, parentID: dropParent.id,
                           expandsParent: true, undoManager: dropUndo)
dropUndo.endUndoGrouping()
check(!dropParent.isCollapsed && store.children(of: dropParent.id, listID: destination.id).map(\.id) == [dropOne.id, dropTwo.id],
      "Inside-drop reveals a collapsed parent and preserves selected child order")
let expansionReader = ModelContext(container)
let savedExpandedParent = try expansionReader.fetch(FetchDescriptor<Block>()).first { $0.id == dropParent.id }!
check(!savedExpandedParent.isCollapsed, "Expansion is committed with the successful positional move")
dropUndo.undo()
check(dropParent.isCollapsed && dropOne.listID == source.id && dropTwo.listID == source.id && dropOne.parentID == nil,
      "One Undo restores the original collapse and both selected positions")
dropUndo.redo()
check(!dropParent.isCollapsed && dropOne.parentID == dropParent.id && dropTwo.parentID == dropParent.id,
      "One Redo restores both the move and destination expansion")
dropParent.isCollapsed = true
store.save()
dropUndo.undo()
check(dropParent.isCollapsed && dropOne.listID == source.id,
      "A later explicit collapse is preserved while Undo still restores movement")
dropUndo.redo()
check(dropParent.isCollapsed && dropOne.parentID == dropParent.id,
      "Redo preserves the same independent collapse decision")
dropUndo.removeAllActions()
dropUndo.beginUndoGrouping()
_ = try store.moveSelection([dropOne.id, dropTwo.id], to: destination.id, parentID: dropParent.id,
                           expandsParent: true, undoManager: dropUndo)
dropUndo.endUndoGrouping()
check(!dropParent.isCollapsed && dropUndo.canUndo, "An inside-drop with unchanged positions still records its expansion")
dropUndo.undo()
check(dropParent.isCollapsed && dropOne.parentID == dropParent.id && dropTwo.parentID == dropParent.id,
      "Expansion-only Undo leaves existing child positions intact")
dropUndo.removeAllActions()
dropUndo.beginUndoGrouping()
_ = try store.moveSelection([dropOne.id, dropTwo.id], to: destination.id, parentID: dropParent.id,
                           expandsParent: true, undoManager: dropUndo)
dropUndo.endUndoGrouping()
let beforeExpansionUndoFailure = dropParent.updatedAt
store.editorNotice = nil
failNextSave = true
dropUndo.undo()
check(!dropParent.isCollapsed && dropParent.updatedAt == beforeExpansionUndoFailure
      && dropOne.parentID == dropParent.id && dropTwo.parentID == dropParent.id,
      "Failed expansion Undo restores live destination state and all positions")
check(!dropUndo.canRedo && store.editorNotice != nil, "Failed expansion Undo reports an error without registering a partial Redo")
dropParent.isCollapsed = true
store.save()
_ = try store.moveSelection([dropOne.id, dropTwo.id], to: source.id)
dropUndo.removeAllActions()
let beforeExpansionFailure = dropParent.updatedAt
check(!store.context.hasChanges, "Expansion failure starts with committed input")
failNextSave = true
rejects("Inside-drop save failure must not leave its destination expanded") {
    _ = try store.moveSelection([dropOne.id, dropTwo.id], to: destination.id, parentID: dropParent.id,
                               expandsParent: true, undoManager: dropUndo)
}
check(dropParent.isCollapsed && dropParent.updatedAt == beforeExpansionFailure
      && dropOne.listID == source.id && dropTwo.parentID == nil && !dropUndo.canUndo,
      "Failed inside-drop restores live collapse, timestamp and positions without registering Undo")

let reader = ModelContext(container)
let savedFirst = try reader.fetch(FetchDescriptor<Block>()).first { $0.id == first.id }!
check(savedFirst.listID == destination.id && savedFirst.note == "Draft before action" && !savedFirst.isCompleted,
      "Independent disk reader observes preserved draft and no failed mutation")
let savedCompletionCount = try reader.fetchCount(FetchDescriptor<CompletionRecord>())
check(savedCompletionCount == completionCount, "Failed completion records never reach disk")
let readOnlyConfiguration = ModelConfiguration(schema: schema, url: url, allowsSave: false, cloudKitDatabase: .none)
let readOnlyContainer = try ModelContainer(for: schema, configurations: [readOnlyConfiguration])
let readOnly = Store(context: readOnlyContainer.mainContext)
let readOnlyFirst = readOnly.block(id: first.id)!
let readOnlyChild = readOnly.block(id: child.id)!
rejects("Real read-only store cannot acknowledge bulk move") { _ = try readOnly.moveSelection([first.id, parent.id], to: source.id) }
check(readOnlyFirst.listID == destination.id && readOnlyChild.listID == destination.id && readOnly.persistenceError != nil,
      "Actual read-only move failure restores retained root and child values")
let readOnlyCompletion = Store(context: ModelContext(readOnlyContainer))
let readOnlyCompletionFirst = readOnlyCompletion.block(id: first.id)!
let readOnlyBefore = CompletionTaskState(readOnlyCompletionFirst)
check(!readOnlyCompletion.context.hasChanges, "Read-only completion starts in a fresh context without rollback drafts")
rejects("Real read-only store cannot acknowledge bulk completion") { _ = try readOnlyCompletion.setBulkCompletion(true, ids: [first.id, parent.id]) }
check(CompletionTaskState(readOnlyCompletionFirst) == readOnlyBefore, "Actual read-only completion failure restores retained task values")
check(readOnlyCompletion.completionRecords().count == completionCount, "Actual read-only completion failure restores history values")
let readOnlyExpansion = Store(context: ModelContext(readOnlyContainer))
let readOnlyDropParent = readOnlyExpansion.block(id: dropParent.id)!
let readOnlyDropOne = readOnlyExpansion.block(id: dropOne.id)!
rejects("Actual read-only inside-drop cannot persist expansion") {
    _ = try readOnlyExpansion.moveSelection([dropOne.id, dropTwo.id], to: destination.id,
                                           parentID: dropParent.id, expandsParent: true)
}
check(readOnlyDropParent.isCollapsed && readOnlyDropOne.listID == source.id && readOnlyDropOne.parentID == nil,
      "A real read-only failure restores retained parent expansion and moved rows together")
try runBulkTrashChecks(at: url.deletingLastPathComponent())
try runBulkNestedOwnerChecks(at: url.deletingLastPathComponent())
print("\(checks) bulk action checks passed")
