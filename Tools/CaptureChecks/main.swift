import AppKit
import SwiftData

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
    checks += 1
}

let schema = Schema([TaskList.self, Block.self, SidebarSection.self, TaskLabel.self, Attachment.self, ActivityEvent.self, SchedulePlacement.self, WorkSession.self, CompletionRecord.self])
let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
let store = Store(context: container.mainContext)
store.context.autosaveEnabled = false
store.bootstrap()
let inbox = store.inboxList()!
let list = store.createList(title: "Work")
var draft = TaskCaptureDraft(text: "Call mum tomorrow at 6pm #home every week")
let preview = draft.preview
check(preview.title == "Call mum", "Preview strips accepted date, time, label and repeat tokens")
check(preview.date != nil && preview.includesTime && preview.recurrence != nil, "Preview shows full parsed schedule")
check(preview.labels == ["home"], "Preview names labels without creating them")
check(store.allLabels().isEmpty && store.blocks(inList: inbox.id).isEmpty, "Draft preview must never persist tasks or labels")
draft.removesDate = true
draft.removesRecurrence = true
draft.removedLabels = ["home"]
check(draft.preview.date == nil && draft.preview.recurrence == nil && draft.preview.labels.isEmpty, "Removed metadata stays removed in saved preview")
check(draft.preview.title == "Call mum", "Removing detected details preserves the reviewed task title")
let task = try store.saveCapture(draft.preview, destinationID: list.id)
check(task.listID == list.id && task.text == "Call mum", "Capture saves to explicitly chosen destination")
check(task.dueDate == nil && task.recurrence == nil && task.labelIDs.isEmpty, "Capture must not reparse removed metadata")
let parsed = try store.saveCapture(preview, destinationID: nil)
check(parsed.listID == inbox.id && parsed.dueDate == preview.date && parsed.includesTime, "Inbox fallback preserves exact preview schedule")
check(parsed.recurrence != nil && store.labels(for: parsed).map(\.name) == ["home"], "Capture persists labels and recurrence")
check(store.recentActivity().filter { $0.blockID == parsed.id && $0.kind == .created }.count == 1, "Capture emits one creation event")
let labelOnly = TaskCaptureDraft(text: "#home").preview
check(labelOnly.title == "#home" && labelOnly.labels.isEmpty, "Label-only input must not save an empty title")
let literal = TaskCaptureDraft(text: "Call tomorrow", parsesNaturalLanguage: false).preview
check(literal.title == "Call tomorrow" && literal.date == nil, "Disabled detection preserves literal date words")
let today = TaskCaptureDraft(text: "Call mum", dueTodayWhenUndated: true)
check(today.preview.date != nil, "Default Today schedule is part of visible preview")
var noDate = today
noDate.removesDate = true
check(noDate.preview.date == nil, "User can remove default Today schedule")
let before = store.blocks(inList: list.id).count
list.isArchived = true
store.save()
do {
    _ = try store.saveCapture(preview, destinationID: list.id)
    preconditionFailure("Archived destination should reject capture")
} catch {
    check(store.blocks(inList: list.id).count == before, "Rejected capture does not create a task")
}
do {
    _ = try store.saveCapture(TaskCaptureDraft(text: "   ").preview, destinationID: nil)
    preconditionFailure("Whitespace capture should fail")
} catch {
    check(store.blocks(inList: inbox.id).count == 1, "Empty draft does not create a task")
}
let undo = UndoManager()
undo.groupsByEvent = false
let target = store.createList(title: "Triage")
let planningDate = Date.now
let plannedCapture = try store.saveCapture(TaskCaptureDraft(text: "Review integration").preview,
                                         destinationID: target.id, selectedForDay: planningDate)
check(plannedCapture.selectedForDay == Calendar.current.startOfDay(for: planningDate), "Calendar capture preserves its planning day")
check(plannedCapture.dueDate == nil, "Planning a captured task does not invent a due date")
check(!store.context.hasChanges, "Calendar capture persists planning intent in the capture transaction")
check(task.selectedForDay == nil, "Ordinary capture leaves calendar selection unchanged")
undo.beginUndoGrouping()
store.undoableEditorEdit(in: Set([inbox.id, target.id]), name: "Move Inbox task", undoManager: undo) {
    store.moveToList(parsed, list: target)
}
undo.endUndoGrouping()
check(parsed.listID == target.id, "Inbox move files the task")
undo.undo()
check(parsed.listID == inbox.id, "Undo returns moved task to Inbox")
undo.beginUndoGrouping()
store.undoableEditorEdit(in: inbox.id, name: "Schedule Inbox task", undoManager: undo) {
    store.setDueDate(nil, for: parsed)
}
undo.endUndoGrouping()
undo.undo()
check(parsed.dueDate == preview.date && parsed.includesTime, "Undo restores original scheduling precision")
check(CommandMatchRank.rank(title: "Go to Inbox", query: "inbox") == 0, "Inbox is an exact navigation match")
check(CommandMatchRank.rank(title: "New List", query: "new list") == 0, "New List is an exact command match")
check(CommandMatchRank.rank(title: "New Task", query: "new task") == 0, "New Task command opens a draft before generic Create")
check(CommandMatchRank.rank(title: "Create Inbox", query: "inbox", isCreation: true) > CommandMatchRank.rank(title: "Go to Inbox", query: "inbox"), "Generic creation must follow matching navigation")

// Only locally edited text may be parsed when a row finishes or opens details.
var inlineEdits = InlineMetadataEdits()
let literalTask = store.appendBlock(kind: .task, text: "Do the weekly shop", to: .init(listID: inbox.id))
store.save()
check(!inlineEdits.consume(for: literalTask), "Opening an existing literal title does not authorize parsing")
inlineEdits.recordTextChange(for: literalTask, to: literalTask.text)
check(!inlineEdits.consume(for: literalTask), "Formatting-only callbacks do not authorize title parsing")
inlineEdits.recordTextChange(for: literalTask, to: "Call mum tomorrow #home")
store.setText("Call mum tomorrow #home", for: literalTask)
check(inlineEdits.consume(for: literalTask), "A deliberate typed title authorizes one metadata commit")
store.applyInlineMetadata(to: literalTask, parsesNaturalLanguage: true)
check(literalTask.text == "Call mum" && literalTask.dueDate != nil && literalTask.labelIDs.count == 1,
      "Typed dates and labels still apply on Return or blur")
check(!inlineEdits.consume(for: literalTask), "Opening details after a commit does not parse twice")
inlineEdits.recordTextChange(for: literalTask, to: "Temporary tomorrow")
store.setText("Temporary tomorrow", for: literalTask)
inlineEdits.recordTextChange(for: literalTask, to: "Call mum")
store.setText("Call mum", for: literalTask)
check(!inlineEdits.consume(for: literalTask), "Reverting a local edit to its starting title does not parse it")
inlineEdits.recordTextChange(for: literalTask, to: "Local tomorrow")
store.setText("Local tomorrow", for: literalTask)
store.setText("External next week", for: literalTask)
check(!inlineEdits.consume(for: literalTask), "A later external text refresh supersedes local parsing intent")
inlineEdits.recordTextChange(for: literalTask, to: "Pending tomorrow")
store.setText("Pending tomorrow", for: literalTask)
inlineEdits.retain(blockIDs: [])
check(!inlineEdits.consume(for: literalTask), "Leaving or removing a document row clears pending capture intent")

// A read-only on-disk fixture exercises a real save failure after insertion.
let fixtureURL = FileManager.default.temporaryDirectory.appending(path: "capture-failure-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: fixtureURL) }
let diskURL = fixtureURL.appending(path: "Capture.store")
let writable = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: diskURL, cloudKitDatabase: .none)])
let seedStore = Store(context: writable.mainContext)
seedStore.bootstrap()
let readonly = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: diskURL, allowsSave: false, cloudKitDatabase: .none)])
let failingStore = Store(context: readonly.mainContext)
failingStore.context.autosaveEnabled = false
let readonlyInbox = failingStore.inboxList()!
do {
    _ = try failingStore.saveCapture(TaskCaptureDraft(text: "Preserve draft tomorrow #failure-label").preview, destinationID: readonlyInbox.id)
    preconditionFailure("Read-only capture must fail")
} catch {
    check(failingStore.blocks(inList: readonlyInbox.id).isEmpty, "Failed persistence rolls back the inserted task")
    check(failingStore.allLabels().isEmpty, "Failed persistence rolls back new labels")
    check(failingStore.recentActivity().isEmpty, "Failed persistence rolls back creation events")
    check(!failingStore.context.hasChanges, "Failed capture leaves no records awaiting accidental autosave")
}
print("Passed \(checks) capture and triage checks")
