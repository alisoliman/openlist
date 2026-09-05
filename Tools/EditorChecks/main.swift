import AppKit
import SwiftData

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
    checks += 1
}

let schema = Schema([TaskList.self, Block.self, SidebarSection.self, TaskLabel.self, Attachment.self, ActivityEvent.self])
let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
let store = Store(context: container.mainContext)
store.context.autosaveEnabled = false
store.bootstrap()
let list = store.createList(title: "Undo fixtures")
check(store.blocks(inList: list.id).isEmpty, "Creating a list must not persist placeholder tasks")
let document = DocumentContext(listID: list.id)
let first = store.appendBlock(kind: .task, text: "First", to: document)
let second = store.appendBlock(kind: .task, text: "Second", to: document)
let secondID = second.id
let child = store.insertChild(kind: .task, text: "Child", of: second)
let childID = child.id
let due = Date.now.addingTimeInterval(100_000)
second.dueDate = due
second.reminderAt = due.addingTimeInterval(-600)
second.includesTime = true
second.note = "Keep this note"
second.priority = .high
second.isStarred = true
let label = store.findOrCreateLabel(named: "undo-fixture")!
second.labelIDs = [label.id]
second.recurrence = Recurrence(frequency: .daily)
let rich = NSMutableAttributedString(string: "Second")
RichTextCodec.toggleTrait(.boldFontMask, in: rich, range: NSRange(location: 0, length: rich.length), kind: .task)
store.setContent(second, attributed: rich)
let richData = second.richData
let filename = "editor-undo-\(UUID().uuidString).txt"
let bytes = Data("attachment survives undo and redo".utf8)
try MediaStore.shared.restoreFile(bytes, filename: filename)
defer { MediaStore.shared.delete(filename: filename) }
let attachment = Attachment(blockID: second.id, filename: filename, displayName: "note.txt", contentType: "text/plain", byteCount: bytes.count)
let attachmentID = attachment.id
store.context.insert(attachment)
store.save()

let undo = UndoManager()
undo.groupsByEvent = false
undo.beginUndoGrouping()
store.undoableEditorEdit(in: list.id, name: "Merge blocks", undoManager: undo) {
    _ = store.backspaceAtStart(second, content: store.attributedContent(of: second), in: document)
    store.save()
}
undo.endUndoGrouping()
check(store.block(id: secondID) == nil, "Merge removes second row")
check(store.block(id: childID)?.parentID == first.id, "Merge adopts child")
check(first.note == "Keep this note" && first.dueDate == due && first.isStarred, "Merge preserves task details")
check(store.attachments(for: first.id).first?.id == attachmentID && MediaStore.shared.fileContents(filename: filename) == bytes, "Merge moves attachments without deleting their files")
check(undo.canUndo, "Merge registers an undo action")
// A later unrelated metadata edit to the surviving task must not be rolled back.
first.mediaCaption = "Unrelated later caption"
store.save()
undo.undo()
let restored = store.block(id: secondID)!
check(first.text == "First" && restored.text == "Second", "Undo restores separate texts")
check(restored.richData == richData, "Undo restores rich content")
check(restored.note == "Keep this note" && first.note.isEmpty && first.mediaCaption == "Unrelated later caption", "Undo restores notes without overwriting unrelated fields")
check(restored.dueDate == due && restored.reminderAt == due.addingTimeInterval(-600), "Undo restores schedule and reminder")
check(restored.isStarred && restored.priority == .high && restored.labelIDs == [label.id], "Undo restores flags and labels")
check(restored.recurrence?.frequency == .daily, "Undo restores recurrence")
check(store.block(id: childID)?.parentID == secondID, "Undo restores original child relationship")
check(store.attachments(for: secondID).first?.id == attachmentID, "Undo restores original attachment identity")
check(MediaStore.shared.fileContents(filename: filename) == bytes, "Undo restores deleted attachment bytes")
check(undo.canRedo, "Undo registers redo")
undo.redo()
check(store.block(id: secondID) == nil && first.text == "FirstSecond", "Redo reapplies merge")
undo.undo()
check(store.attachments(for: secondID).first?.filename == filename && MediaStore.shared.fileContents(filename: filename) == bytes, "Repeated undo restores attachment again")

undo.removeAllActions()
undo.beginUndoGrouping()
store.undoableEditorEdit(in: list.id, name: "Split block", undoManager: undo) {
    _ = store.splitBlock(first, at: 2, content: store.attributedContent(of: first))
    store.save()
}
undo.endUndoGrouping()
let countAfterSplit = store.blocks(inList: list.id).count
undo.undo()
check(first.text == "First" && store.blocks(inList: list.id).count == countAfterSplit - 1, "Split undo restores original block")
undo.redo()
check(store.blocks(inList: list.id).count == countAfterSplit, "Split redo restores new block")

undo.removeAllActions()
let destination = store.createList(title: "Move destination")
undo.beginUndoGrouping()
store.undoableEditorEdit(in: Set([list.id, destination.id]), name: "Move task", undoManager: undo) {
    _ = store.move(store.block(id: secondID)!, toParent: nil, above: nil, in: destination.id)
    store.save()
}
undo.endUndoGrouping()
check(store.block(id: secondID)?.listID == destination.id && store.block(id: childID)?.listID == destination.id, "Cross-list move includes descendants")
undo.undo()
check(store.block(id: secondID)?.listID == list.id && store.block(id: childID)?.listID == list.id, "Cross-list undo returns task and descendants to source")
undo.redo()
check(store.block(id: secondID)?.listID == destination.id && store.attachments(for: secondID).first?.id == attachmentID, "Cross-list redo retains attachments")
undo.undo()

let conflictList = store.createList(title: "Conflicting schedules")
let conflictDocument = DocumentContext(listID: conflictList.id)
let earlier = store.appendBlock(kind: .task, text: "Earlier", to: conflictDocument)
earlier.dueDate = due
let conflict = store.appendBlock(kind: .task, text: "Conflicting", to: conflictDocument)
conflict.dueDate = due.addingTimeInterval(86_400)
let conflictID = conflict.id
let beforeConflict = store.blocks(inList: conflictList.id).count
_ = store.backspaceAtStart(conflict, content: store.attributedContent(of: conflict), in: conflictDocument)
check(store.block(id: conflictID) != nil && store.blocks(inList: conflictList.id).count == beforeConflict && store.editorNotice != nil, "Conflicting task schedules do not lose a row")
_ = store.backspaceAtStart(earlier, content: store.attributedContent(of: earlier), in: conflictDocument)
check(earlier.isTask && earlier.dueDate == due, "Backspace at first task preserves its kind and schedule")

undo.removeAllActions()
let image = store.appendBlock(kind: .image, to: document)
let imageID = image.id
let imageFile = "editor-image-\(UUID().uuidString).png"
try MediaStore.shared.restoreFile(bytes, filename: imageFile)
defer { MediaStore.shared.delete(filename: imageFile) }
image.mediaFilename = imageFile
store.save()
undo.beginUndoGrouping()
store.undoableEditorEdit(in: list.id, name: "Delete image", undoManager: undo) {
    store.deleteBlock(image)
}
undo.endUndoGrouping()
check(MediaStore.shared.fileContents(filename: imageFile) == nil, "Deleting image removes file")
undo.undo()
check(store.block(id: imageID)?.mediaFilename == imageFile && MediaStore.shared.fileContents(filename: imageFile) == bytes, "Image undo restores row and file")
undo.redo()
check(store.block(id: imageID) == nil && MediaStore.shared.fileContents(filename: imageFile) == nil, "Image redo removes restored file")

let removedList = store.createList(title: "Permanent deletion fixture")
undo.removeAllActions()
undo.beginUndoGrouping()
store.undoableEditorEdit(in: removedList.id, name: "New task", undoManager: undo) {
    _ = store.appendBlock(kind: .task, text: "Cannot resurrect", to: DocumentContext(listID: removedList.id))
    store.save()
}
undo.endUndoGrouping()
let removedListID = removedList.id
store.deleteList(removedList)
undo.undo()
check(store.blocks(inList: removedListID).isEmpty && store.editorNotice?.contains("permanently deleted") == true, "Undo cannot recreate orphan tasks after permanent list deletion")

store.setArchived(true, for: list)
check(!NotificationService.shared.scheduled.contains(secondID), "Archiving cancels reminders")
store.setArchived(false, for: list)
check(NotificationService.shared.scheduled.contains(secondID), "Unarchiving restores future reminders")
print("✅ \(checks) editor/store checks passed")
