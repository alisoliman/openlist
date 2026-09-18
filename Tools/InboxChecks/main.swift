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
let store = Store(context: container.mainContext)
func all() throws -> [Block] { try store.context.fetch(FetchDescriptor<Block>()) }
func policy() throws -> InboxPolicy { InboxPolicy(lists: try store.context.fetch(FetchDescriptor<TaskList>())) }
let oldPayload = Data(#"{"version":50,"included":true}"#.utf8)

if phase == "verify-failure" {
    check(store.block(id: id(5))?.listID == id(1), "Failed filing does not persist across a separate process")
    check(store.block(id: id(5))?.parentID == id(3), "Failed filing preserves nesting on disk")
    print("\(checks) failed-save relaunch checks passed")
    exit(0)
}
if phase == "failure" {
    let readonly = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, allowsSave: false, cloudKitDatabase: .none)])
    let failing = Store(context: readonly.mainContext)
    let task = failing.block(id: id(5))!
    let manager = UndoManager(); manager.groupsByEvent = false
    do {
        _ = try failing.moveSelection([task.id], to: id(2), undoManager: manager)
        fatalError("Read-only filing must fail")
    } catch { }
    check(task.listID == id(1) && task.parentID == id(3), "Real save failure restores Inbox ownership and nesting")
    check(!manager.canUndo, "Failed filing registers no Undo")
    print("\(checks) read-only Inbox checks passed")
    exit(0)
}
if phase == "reopen" {
    store.bootstrap()
    check(try !policy().includes(store.block(id: id(4))!), "Filed task stays out of Inbox after relaunch")
    check(try policy().includes(store.block(id: id(3))!), "Rich note remains in Inbox")
    check(store.block(id: id(5))?.parentID == id(3), "Nested structure survives relaunch")
    check(store.block(id: id(3))?.richData == Data("retained rich bytes".utf8), "Rich bytes survive migration and relaunch")
    check(store.block(id: id(7))?.inboxMembershipData == oldPayload, "Legacy payload survives byte-for-byte")
    check(try !policy().includes(store.block(id: id(7))!), "Old cross-list selection never resurfaces in Inbox")
    print("\(checks) Inbox reopen checks passed")
    exit(0)
}

let original = try all().map(BackupBlock.init)
store.bootstrap()
for record in original {
    check(BackupBlock(store.block(id: record.id)!) == record, "Opening old library never rewrites content or metadata")
}
check(Block(kind: .task).inboxMembershipData == nil, "New captures do not create legacy metadata")
check(try policy().openCount(all()) == 2, "Badge counts only open tasks owned by Inbox")
check(try policy().includes(store.block(id: id(3))!), "Inbox contains standalone notes")
let inbox = store.inboxList()!
let project = store.list(id: id(2))!
let task = store.block(id: id(4))!
let nested = store.block(id: id(5))!
let other = store.block(id: id(7))!
other.inboxMembershipData = oldPayload
store.save()
check(try !policy().includes(other), "Legacy selected tasks in real lists stay filed")
store.setDueTomorrow(nested)
check(try policy().includes(nested), "Setting a date keeps a capture in Inbox")
let originalID = task.id, originalNote = task.note, labels = task.labelIDs
let descendants = BlockTree.descendants(of: task.id, in: store.blocks(inList: inbox.id))
let attachments = try store.context.fetch(FetchDescriptor<Attachment>()).map { ($0.id, $0.blockID, $0.contentData) }
let manager = UndoManager(); manager.groupsByEvent = false
manager.beginUndoGrouping()
_ = try store.moveSelection([task.id], to: project.id, undoManager: manager)
manager.endUndoGrouping()
check(try !policy().includes(task), "Filing immediately removes the task from Inbox")
check(task.id == originalID && task.note == originalNote && task.labelIDs == labels, "Filing preserves identity and metadata")
check(descendants.allSatisfy { $0.listID == project.id && $0.parentID == task.id }, "Filing moves the complete branch")
check(try policy().openCount(all()) == 1, "Filing updates the badge")
manager.undo()
check(try policy().includes(task), "Native Undo returns the item to Inbox")
check(descendants.allSatisfy { $0.listID == inbox.id }, "Undo returns the whole branch")
manager.redo()
check(try !policy().includes(task), "Redo files the same identity again")
let note = store.block(id: id(3))!
manager.removeAllActions(); manager.beginUndoGrouping()
_ = try store.moveSelection([note.id], to: project.id, undoManager: manager)
manager.endUndoGrouping()
check(try !policy().includes(note) && !policy().includes(nested), "Filing a note includes its nested tasks")
manager.undo()
check(note.listID == inbox.id && nested.parentID == note.id, "Undo restores note hierarchy")
for (attachmentID, owner, bytes) in attachments {
    let restored = try store.context.fetch(FetchDescriptor<Attachment>()).first { $0.id == attachmentID }
    check(restored?.blockID == owner && restored?.contentData == bytes, "Filing and Undo retain attachment IDs and bytes")
}
let recurring = store.appendBlock(kind: .task, text: "Recurring capture", to: .init(listID: inbox.id))
recurring.recurrence = .weekly; recurring.dueDate = .now
store.toggleCompletion(recurring)
check(try policy().includes(recurring) && !recurring.isCompleted, "Recurrence stays in Inbox until filed")
let completion = store.completionUndo!
check(store.undoCompletion(completion.id), "Recurring completion can be undone")
check(try policy().includes(recurring), "Completion Undo preserves capture ownership")
let copiedID = try store.copyBlock(nested, mode: .duplicate)
check(try policy().includes(store.block(id: copiedID)!), "A copy made in Inbox remains an unorganized capture")
check(BlockTree.hidingCompletedTasks(in: BlockTree.flatten(store.blocks(inList: inbox.id))).contains { $0.id == note.id }, "Hiding completed tasks never hides standalone notes")
try store.persistChanges()
print("\(checks) Inbox ownership checks passed")
