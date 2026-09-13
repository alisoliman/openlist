import AppKit
import SwiftData

var checks = 0
func check(_ condition: @autoclosure () throws -> Bool, _ message: String) {
    checks += 1
    guard (try? condition()) == true else { fatalError("FAIL: \(message)") }
}
func id(_ value: Int) -> UUID { UUID(uuidString: String(format: "24000000-0000-0000-0000-%012d", value))! }
let schema = Schema([TaskList.self, Block.self, SidebarSection.self, TaskLabel.self, Attachment.self,
                     ActivityEvent.self, WorkSession.self, CompletionRecord.self, SchedulePlacement.self])
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let phase = CommandLine.arguments[2]
let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
var failures = 0
let store = Store(context: container.mainContext) { context in
    if failures > 0 { failures -= 1; throw CocoaError(.fileWriteNoPermission) }
    try context.save()
}
func all() throws -> [Block] { try store.context.fetch(FetchDescriptor<Block>()) }
func policy() throws -> InboxPolicy { InboxPolicy(lists: try store.context.fetch(FetchDescriptor<TaskList>())) }
func queue() throws -> [UUID] { try policy().ordered(all()).map(\.id) }
func nativeUndo(_ name: String, _ body: (UndoManager) -> Void) -> UndoManager {
    let manager = UndoManager(); manager.groupsByEvent = false
    manager.beginUndoGrouping(); body(manager); manager.endUndoGrouping()
    check(manager.canUndo && manager.undoActionName == name, "Successful operation registers one native Undo action")
    return manager
}

if phase == "verify-failure" {
    check(store.block(id: id(7))?.inboxMembershipData == InboxMembership.excludedData, "Real failed save remains excluded in an actual later process")
    check(store.block(id: id(7))?.note == "", "Unrelated failed draft was not persisted after actual relaunch")
    print("\(checks) failed-save relaunch checks passed")
    exit(0)
}
if phase == "failure" {
    let readonly = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, allowsSave: false, cloudKitDatabase: .none)])
    let failing = Store(context: readonly.mainContext)
    let task = failing.block(id: id(7))!
    let old = task.inboxMembershipData
    task.note = "Unrelated unsaved retryable draft"
    let manager = UndoManager()
    check(!failing.setInboxMembership(true, taskIDs: [task.id], undoManager: manager), "Real readonly save rejects membership")
    check(task.inboxMembershipData == old, "Real save failure restores original retained payload immediately")
    check(task.note == "Unrelated unsaved retryable draft", "Membership failure preserves unrelated live edits")
    check(failing.inboxError != nil && !manager.canUndo, "Failed membership reports error without Undo registration")
    let fetched = try readonly.mainContext.fetch(FetchDescriptor<Block>()).first { $0.id == task.id }!
    check(fetched.inboxMembershipData == old, "First live fetch after failed save has original selection")
    let reader = ModelContext(container)
    let saved = try reader.fetch(FetchDescriptor<Block>()).first { $0.id == task.id }!
    check(saved.inboxMembershipData == old && saved.note != task.note, "Failed selection and unrelated draft did not reach disk")
    print("\(checks) real save failure Inbox checks passed")
    exit(0)
}
if phase == "reopen" {
    store.bootstrap()
    check(InboxPolicy.selection(store.block(id: id(4))!) == nil, "Removed unfiled task is not reseeded after actual relaunch")
    check(store.block(id: id(4))?.listID == id(1), "Removed task remains in unfiled ownership")
    check(store.block(id: id(3))?.richData == Data("retained rich bytes".utf8), "Non-task rich content survives migration and relaunch")
    check(store.block(id: id(5))?.parentID == id(3), "Nested structure survives relaunch")
    let expected = try JSONDecoder().decode([UUID].self, from: Data(contentsOf: url.appendingPathExtension("queue.json")))
    check(try queue() == expected, "Independent manual queue order survives relaunch")
    check(store.block(id: id(7))?.inboxMembershipData == InboxMembership.excludedData, "Known other-list legacy records stay explicitly excluded")
    check(store.block(id: id(50))?.inboxMembershipData == Data(#"{"version":50,"included":true}"#.utf8), "Unknown version remains byte-for-byte intact across relaunch")
    check(InboxPolicy.issue(in: try all()) != nil, "Unknown version remains a visible recoverable issue")
    print("\(checks) Inbox reopen checks passed")
    exit(0)
}

check(try all().allSatisfy { $0.inboxMembershipData == nil }, "Real old-schema rows migrate with nil optional field before bootstrap")
check(Block(kind: .task).inboxMembershipData == InboxMembership.excludedData, "New model initialization explicitly excludes independent tasks")
let original = try all().map(BackupBlock.init)
store.bootstrap()
check(try Set(queue()) == Set([id(4), id(5), id(6)]), "Migration includes all legacy Inbox tasks including nested and completed")
check(try queue() == [id(5), id(4), id(6)], "Initial queue follows stable rich-document outline order")
check(store.block(id: id(3))?.inboxMembershipData == nil, "Migration leaves legacy non-task content untouched")
for record in original {
    var after = BackupBlock(store.block(id: record.id)!)
    after.inboxMembershipData = nil
    check(after == record, "Migration changes only the new membership field for \(record.id)")
}
check(try policy().openCount(all()) == 2, "Open count excludes completed member")
check(try policy().ordered(all(), showsCompleted: false).count == 2, "Completed visibility independently hides ordinary completed members")
let ownership = BackupBlock(store.block(id: id(5))!)
let remove = nativeUndo("Remove from Inbox") { check(store.setInboxMembership(false, taskIDs: [id(5)], undoManager: $0), "Remove selected nested task succeeds") }
check(!((try queue()).contains(id(5))), "Removed member leaves queue")
var removed = BackupBlock(store.block(id: id(5))!); removed.inboxMembershipData = ownership.inboxMembershipData
check(removed == ownership, "Removing nested task never changes ownership, hierarchy, title, labels or history metadata")
remove.undo(); check(try queue().contains(id(5)), "Undo restores membership")
remove.redo(); check(try !queue().contains(id(5)), "Redo removes membership again")
check(store.setInboxMembership(true, taskIDs: [id(5)]), "Add nested task succeeds")
let selected = store.block(id: id(5))!.inboxMembershipData
check(store.setInboxMembership(true, taskIDs: [id(5), id(5)]), "Repeated Add is idempotent")
check(store.block(id: id(5))!.inboxMembershipData == selected, "Idempotent Add does not reorder or duplicate selection")
let orderBefore = try queue()
let reorder = nativeUndo("Reorder Inbox") { check(store.moveInboxTask(id(6), before: id(5), undoManager: $0), "Persistent manual reorder succeeds") }
check(try queue().first == id(6), "Reorder changes queue order")
check(store.block(id: id(6))!.sortIndex == 600, "Reorder leaves document sort index unchanged")
reorder.undo(); check(try queue() == orderBefore, "Reorder Undo restores queue")
reorder.redo(); check(try queue().first == id(6), "Reorder Redo restores reordered queue")
let task = store.block(id: id(5))!
let project = store.list(id: id(2))!
store.moveToList(task, list: project)
check(try queue().contains(task.id), "Move to another list preserves membership")
store.moveToList(task, list: store.inboxList()!)
// Restore fixture nesting for the relaunch identity assertion.
task.parentID = id(3); task.sortIndex = 500; store.save()
project.isArchived = true; store.save()
check(store.setInboxMembership(true, taskIDs: [task.id]), "Unfiled selection unaffected by another archived list")
store.moveToList(task, list: project)
check(try !queue().contains(task.id), "Archived owner hides selected task")
let archivedSelection = task.inboxMembershipData
project.isArchived = false; store.save()
check(try queue().contains(task.id), "Unarchiving restores retained membership")
check(task.inboxMembershipData == archivedSelection, "Archiving does not mutate authoritative selection")
store.moveToList(task, list: store.inboxList()!); task.parentID = id(3); task.sortIndex = 500; store.save()
store.toggleCompletion(task)
check(InboxPolicy.selection(task) != nil, "Ordinary completion retains membership for completed visibility")
store.toggleCompletion(task)
check(InboxPolicy.selection(task) != nil, "Ordinary reopen retains membership despite new calendar occurrence")
let recurrence = store.appendBlock(kind: .task, text: "Repeat", to: .init(listID: id(1)))
recurrence.recurrence = .daily; recurrence.dueDate = .now
let child = store.insertChild(text: "Recurring child", of: recurrence)
store.save()
check(InboxPolicy.selection(recurrence) != nil && InboxPolicy.selection(child) != nil, "New unfiled task and child captures join queue")
let oldOccurrence = recurrence.occurrenceID
store.toggleCompletion(recurrence)
check(recurrence.occurrenceID != oldOccurrence && InboxPolicy.selection(recurrence) == nil, "Recurrence advances and clears selected occurrence")
check(InboxPolicy.selection(child) == nil, "Recurring descendant reset clears child focus too")
check(store.undoCompletion(store.completionUndo!.id), "Completion Undo succeeds")
check(InboxPolicy.selection(recurrence) != nil && InboxPolicy.selection(child) != nil, "Completion Undo restores selection and occurrence together")
let stale = recurrence.inboxMembershipData
recurrence.occurrenceID = UUID(); store.save()
check(InboxPolicy.selection(recurrence) == nil && recurrence.inboxMembershipData == stale, "Old-client occurrence advance cannot silently rejoin without clearing data")
let duplicateID = try store.copyBlock(task, mode: .duplicate)
check(store.block(id: duplicateID)?.inboxMembershipData == InboxMembership.excludedData, "Independent duplicate excludes source curation")
let templateID = try store.copyBlock(task, mode: .template(keepingRecurrence: true))
check(store.block(id: templateID)?.inboxMembershipData == InboxMembership.excludedData, "Template excludes source curation even retaining recurrence")
let paragraph = store.appendBlock(kind: .paragraph, text: "Convert", to: .init(listID: id(1)))
store.changeKind(paragraph, to: .task); store.save()
check(InboxPolicy.selection(paragraph) != nil, "Converting unfiled text to a task joins queue")
store.changeKind(paragraph, to: .paragraph); store.save()
check(InboxPolicy.selection(paragraph) == nil, "Converting a task to text removes task focus")
let unknown = store.appendBlock(kind: .task, text: "Future selection", to: .init(listID: id(2)))
unknown.id = id(50); unknown.inboxMembershipData = Data(#"{"version":50,"included":true}"#.utf8); store.save()
check(!store.setInboxMembership(false, taskIDs: [unknown.id]), "Unknown membership version cannot be overwritten by Remove")
check(InboxPolicy.issue(in: [unknown]) != nil, "Unknown membership provides user-visible recovery guidance")
let missing = Block(kind: .task, text: "Late cloud owner", listID: UUID())
missing.inboxMembershipData = nil; store.context.insert(missing); try store.migrateInboxMembership(); store.save()
check(missing.inboxMembershipData == nil, "Incomplete CloudKit owner leaves legacy membership undecided")
let late = TaskList(title: "Late Inbox", isSystemInbox: true); late.id = missing.listID!; store.context.insert(late)
try store.migrateInboxMembership(); store.save()
check(InboxPolicy.selection(missing) != nil, "Later imported owner permits one-time legacy classification")
// No alias reconciliation here: this fixture intentionally models a late owner.
let conflictUndo = nativeUndo("Remove from Inbox") { check(store.setInboxMembership(false, taskIDs: [task.id], undoManager: $0), "Prepare independent selection Undo") }
check(store.setInboxMembership(true, taskIDs: [task.id]), "Later deliberate selection succeeds")
let laterSelection = task.inboxMembershipData
conflictUndo.undo()
check(task.inboxMembershipData == laterSelection && store.inboxError != nil, "Stale membership Undo does not overwrite later selection")
let ordinaryPosition = task.inboxMembershipData
// Imported finite numbers can still exhaust subtraction precision. Reject the
// Add rather than claim it landed first with an unchanged floating-point key.
task.inboxMembershipData = try InboxMembership.included(order: -Double.greatestFiniteMagnitude, occurrenceID: task.occurrenceID).encoded()
store.save()
check(!store.setInboxMembership(true, taskIDs: [id(7)]), "Exhausted finite order fails without a guessed position")
check(store.block(id: id(7))?.inboxMembershipData == InboxMembership.excludedData, "Unrepresentable order does not change destination selection")
task.inboxMembershipData = ordinaryPosition; store.save()
let priorHistory = try store.taskActivity(for: task.id, limit: 1000).count
let oldPayload = task.inboxMembershipData
failures = 1
check(!store.setInboxMembership(false, taskIDs: [task.id]), "Injected save failure is reported")
check(task.inboxMembershipData == oldPayload, "Injected save failure restores retained membership")
check(store.setInboxMembership(false, taskIDs: [task.id]), "Retry explicitly reapplies the requested mutation")
check(store.setInboxMembership(true, taskIDs: [task.id]), "Selection remains usable after recoverable retry")
check(!store.setInboxMembership(true, taskIDs: [task.id, UUID()]), "Missing multi-selection identity fails before mutation")
check(try store.taskActivity(for: task.id, limit: 1000).count == priorHistory, "Membership retries do not fabricate activity history")
let widget = WidgetSnapshotPublisher(store: store).buildSnapshot()
check(try widget.inboxCount == policy().openCount(all()), "Widget open count uses exactly the queue policy")
check(store.setInboxMembership(false, taskIDs: [id(4)]), "Explicitly removed unfiled task remains excluded")
// Avoid the deliberate second-system-record fixture altering canonical IDs at relaunch.
missing.listID = id(1); store.context.delete(late); store.save()
try JSONEncoder().encode(queue()).write(to: url.appendingPathExtension("queue.json"))
let deletedID = task.id
let delete = nativeUndo("Delete selected task") { manager in
    store.undoableEditorEdit(in: id(1), name: "Delete selected task", undoManager: manager) { store.deleteBlock(task); store.save() }
}
check(store.block(id: deletedID) == nil, "Task deletion removes its reference naturally")
delete.undo()
check(store.block(id: deletedID)?.inboxMembershipData != nil && InboxPolicy.selection(store.block(id: deletedID)!) != nil, "Editor deletion Undo restores original membership for restored identity")
// Store schema stays CloudKit-compatible offline: optional field, no uniqueness.
let property = schema.entities.first { $0.name == "Block" }!.properties.first { $0.name == "inboxMembershipData" }!
check(property.isOptional, "New CloudKit field is optional for old/new record imports")
print("\(checks) Inbox migration and membership checks passed")
