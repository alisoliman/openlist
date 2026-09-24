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
let preview = CaptureParse("Call mum tomorrow at 6pm #home every week").snapshot()
check(preview.title == "Call mum", "The snapshot strips the date, time, label and repeat tokens")
check(preview.date != nil && preview.includesTime && preview.recurrence != nil, "The snapshot keeps the full parsed schedule")
check(preview.labels == ["home"], "The snapshot names labels without creating them")
check(store.allLabels().isEmpty && store.blocks(inList: inbox.id).isEmpty, "A snapshot never persists tasks or labels")
let task = try store.saveCapture(CaptureSnapshot(title: "Call mum"), destinationID: list.id)
check(task.listID == list.id && task.text == "Call mum", "Capture saves to explicitly chosen destination")
let heading = store.appendBlock(kind: .heading1, text: "Notes at the end", to: .init(listID: list.id))
let nested = store.appendBlock(kind: .task, text: "Original nested task", to: .init(listID: list.id, rootBlockID: task.id))
let storedOrder = [task, heading, nested].map { ($0.id, $0.parentID, $0.sortIndex) }
let appended = try store.saveCapture(CaptureSnapshot(title: "Alphabetically first"),
                                    destinationID: list.id, appendToRoot: true)
check(appended.listID == list.id && appended.parentID == nil && appended.sortIndex > heading.sortIndex,
      "Tasks-mode capture appends to the owning document root independently of displayed sort")
check(zip([task, heading, nested], storedOrder).allSatisfy { block, snapshot in
    block.id == snapshot.0 && block.parentID == snapshot.1 && block.sortIndex == snapshot.2
}, "Appending in Tasks mode leaves existing document hierarchy and indices untouched")
let prepended = try store.saveCapture(CaptureSnapshot(title: "Normal capture"), destinationID: list.id)
check(prepended.parentID == nil && prepended.sortIndex < task.sortIndex,
      "Existing capture keeps its default prepend behavior")
check(task.dueDate == nil && task.recurrence == nil && task.labelIDs.isEmpty, "Capture saves only what its snapshot holds")
let parsed = try store.saveCapture(preview, destinationID: nil)
check(parsed.listID == inbox.id && parsed.dueDate == preview.date && parsed.includesTime, "Inbox fallback preserves exact preview schedule")
check(parsed.recurrence != nil && store.labels(for: parsed).map(\.name) == ["home"], "Capture persists labels and recurrence")
check(store.recentActivity().filter { $0.blockID == parsed.id && $0.kind == .created }.count == 1, "Capture emits one creation event")
let labelOnly = CaptureParse("#home").snapshot()
check(labelOnly.title.isEmpty && labelOnly.labels == ["home"], "Label-only input has no title for Return to save")
let literal = CaptureParse("Call tomorrow", parsesDates: false).snapshot()
check(literal.title == "Call tomorrow" && literal.date == nil, "Disabled detection preserves literal date words")
let today = CaptureParse("Call mum").snapshot(dueToday: true)
check(today.date == Calendar.current.startOfDay(for: .now) && !today.includesTime, "A capture for today is due today when it names no date")
let named = CaptureParse("Call mum next week").snapshot(dueToday: true)
check(named.date.map { NXFormat.dayOffset($0) > 0 } == true, "A date in the text wins over today")
check(CaptureParse("Plan #Trip").snapshot(labels: ["trip", "work"]).labels == ["trip", "work"],
      "A label screen's label joins the text's without doubling")
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
    _ = try store.saveCapture(CaptureParse("   ").snapshot(), destinationID: nil)
    preconditionFailure("Whitespace capture should fail")
} catch {
    check(store.blocks(inList: inbox.id).count == 1, "Empty draft does not create a task")
}
let undo = UndoManager()
undo.groupsByEvent = false
let target = store.createList(title: "Triage")
let planningDate = Date.now
let plannedCapture = try store.saveCapture(CaptureSnapshot(title: "Review integration"),
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

// Capture tints exactly what it saves: the date parser's phrases, with the
// design's label, priority and estimate tokens kept out of its reach.
let captureReference = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 3, hour: 10))!
func kinds(_ parse: CaptureParse) -> [String] { parse.marks.map { "\($0.kind.rawValue):\($0.raw)" } }
let design = CaptureParse("Pay deposit friday 6pm #travel ~15m", reference: captureReference)
check(kinds(design) == ["date:friday", "time:6pm", "label:#travel", "estimate:~15m"], "Design example tints each token")
check(design.title == "Pay deposit" && design.schedule?.includesTime == true, "Design example saves its title and time")
let wider = CaptureParse("Plan trip next weekend !high", reference: captureReference)
check(kinds(wider) == ["date:next weekend", "priority:!high"], "Phrases only the date parser knows are tinted too")
check(wider.schedule?.date == DateParser.parse("Plan trip next weekend", reference: captureReference).date,
      "The tinted phrase is the date that saves")
check(kinds(CaptureParse("Renew passports in two weeks", reference: captureReference)) == ["date:in two weeks"],
      "Spelled-out offsets are tinted")
check(kinds(CaptureParse("pay rent friday", reference: captureReference)) == ["date:friday"],
      "A space the phrase took with it stays plain")
let literalParse = CaptureParse("Call friday 6pm #home", parsesDates: false, reference: captureReference)
check(kinds(literalParse) == ["label:#home"] && literalParse.schedule == nil && literalParse.title == "Call friday 6pm",
      "With dates off, date words are neither tinted nor saved")
let labelWord = CaptureParse("Plan #friday", reference: captureReference)
check(kinds(labelWord) == ["label:#friday"] && labelWord.schedule == nil, "A label is never read as a date")
check(CaptureParse("meet by friday #work", reference: captureReference).title == "meet", "Dangling joiners go with the date")
let dateOnly = CaptureParse("tomorrow", reference: captureReference)
check(dateOnly.title.isEmpty && dateOnly.schedule?.date != nil, "A date typed before any title already previews")
let designWeek = CaptureParse("Offsite next week", reference: captureReference)
check(designWeek.title == "Offsite" && Calendar.current.component(.day, from: designWeek.schedule!.date!) == 8,
      "next week is next Monday")
check(!(CaptureParse("Dinner tonight", reference: captureReference).schedule?.includesTime ?? true), "tonight has no time")

// The card's chips follow the typed tokens, as the design's capChips.
func chipLabels(_ text: String, forToday: Bool = false) -> [String] {
    let parse = CaptureParse(text, reference: captureReference)
    // As `snapshot(dueToday:)` makes it, on the reference day.
    var preview = parse.snapshot()
    if forToday, preview.date == nil { preview.date = NXFormat.day(offset: 0, now: captureReference) }
    return parse.chips(for: preview, forToday: forToday, now: captureReference).map(\.label)
}
func captureDay(_ offset: Int) -> String {
    let date = NXFormat.day(offset: offset, now: captureReference)
    return "\(NXFormat.dueLabel(date, now: captureReference)) · \(NXFormat.relativeDay(date, now: captureReference))"
}
check(chipLabels("Pay deposit friday 6pm #travel ~15m") == [captureDay(2), "18:00", "travel", "15m estimate"],
      "The design's example chips its tokens with the day's distance")
check(chipLabels("#travel !high pay deposit friday 6pm") == ["travel", "High", captureDay(2), "18:00"],
      "Chips come in the order the tokens were typed")
check(chipLabels("Call mum today") == ["Today · today"] && chipLabels("Call mum tomorrow") == ["Tomorrow · tomorrow"],
      "A typed today or tomorrow keeps its distance, as the design's")
check(chipLabels("Call mum 6pm") == ["18:00"], "A time alone shows only its time")
check(chipLabels("Call mum 6pm", forToday: true) == ["Today", "18:00"], "Capture for Today leads with Today")
check(chipLabels("Call mum", forToday: true) == ["Today"] && chipLabels("Call mum").isEmpty,
      "Only capture for Today shows a day nobody typed")
check(chipLabels("Call mum 9am") == [captureDay(1), "09:00"], "A time already past shows the day it saves")
check(chipLabels("Stretch every day") == ["every day"], "A repeat starting today shows only the repeat")
check(chipLabels("Standup every monday") == [captureDay(5), "every monday"],
      "A repeat whose first day isn't today shows the day it saves")
check(chipLabels("Plan friday #work", forToday: true) == [captureDay(2), "work"], "A typed day stands in for Today")

// Undoing a capture erases the task outright: no Trash entry and no history.
let undoList = store.createList(title: "Undo target")
let captured = try store.saveCapture(CaptureParse("Book ryokan tomorrow #travel").snapshot(), destinationID: undoList.id)
let capturedID = captured.id
let capturedFields = BackupBlock(captured)
let trashBefore = try store.trashEntries().count
guard let discarded = store.discardCapturedTask(id: capturedID) else { preconditionFailure("A fresh capture can be discarded") }
check(store.block(id: capturedID) == nil && store.blocks(inList: undoList.id).isEmpty, "Discarding a capture removes the task")
let trashAfterDiscard = try store.trashEntries().count
check(trashAfterDiscard == trashBefore, "Discarding a capture leaves nothing in Trash")
check(store.recentActivity().allSatisfy { $0.blockID != capturedID }, "Discarding a capture leaves no history")
check(!store.context.hasChanges, "Discarding a capture is saved")
let restored = store.restoreDiscardedTask(discarded)
check(restored?.id == capturedID && store.block(id: capturedID) != nil, "Redo brings back the same task")
check(restored.map(BackupBlock.init) == capturedFields, "Redo brings back every field")
check(store.recentActivity().filter { $0.blockID == capturedID && $0.kind == .created }.count == 1, "Redo logs the task as created again")
check(store.restoreDiscardedTask(discarded) == nil, "Redo never duplicates a task that is back")
_ = store.appendBlock(kind: .task, text: "Subtask", to: .init(listID: undoList.id, rootBlockID: capturedID))
store.save()
check(store.discardCapturedTask(id: capturedID) == nil && store.block(id: capturedID) != nil,
      "A capture that gained subtasks is left for Trash rather than erased")

// Undoing New list erases it too while it is still empty.
let newList = store.createList(title: "Untitled list")
let newListID = newList.id
guard let discardedList = store.discardCreatedList(id: newListID) else { preconditionFailure("An empty new list can be discarded") }
let trashAfterListDiscard = try store.trashEntries().count
check(store.list(id: newListID) == nil && trashAfterListDiscard == trashBefore, "Discarding a new list leaves nothing in Trash")
check(store.recentActivity().allSatisfy { $0.listID != newListID }, "Discarding a new list leaves no history")
check(store.restoreDiscardedList(discardedList)?.id == newListID && store.list(id: newListID)?.title == "Untitled list",
      "Redo brings back the same list")
check(store.discardCreatedList(id: undoList.id) == nil && store.list(id: undoList.id) != nil,
      "A list with content is left for Trash rather than erased")

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
    _ = try failingStore.saveCapture(CaptureParse("Preserve draft tomorrow #failure-label").snapshot(), destinationID: readonlyInbox.id)
    preconditionFailure("Read-only capture must fail")
} catch {
    check(failingStore.blocks(inList: readonlyInbox.id).isEmpty, "Failed persistence rolls back the inserted task")
    check(failingStore.allLabels().isEmpty, "Failed persistence rolls back new labels")
    check(failingStore.recentActivity().isEmpty, "Failed persistence rolls back creation events")
    check(!failingStore.context.hasChanges, "Failed capture leaves no records awaiting accidental autosave")
}
print("Passed \(checks) capture and triage checks")
