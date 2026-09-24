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
let appended = try store.saveCapture(CaptureSnapshot(title: "Alphabetically first"), destinationID: list.id)
check(appended.listID == list.id && appended.parentID == nil && appended.sortIndex > heading.sortIndex,
      "A capture goes at the end of its list's document, whatever the list's sort, as the design's does")
check(zip([task, heading, nested], storedOrder).allSatisfy { block, snapshot in
    block.id == snapshot.0 && block.parentID == snapshot.1 && block.sortIndex == snapshot.2
}, "Appending leaves the document's hierarchy and indices untouched")
let later = try store.saveCapture(CaptureSnapshot(title: "Later capture"), destinationID: list.id)
check(later.parentID == nil && later.sortIndex > appended.sortIndex,
      "Captures follow each other in the order they were made")
check(task.dueDate == nil && task.recurrence == nil && task.labelIDs.isEmpty, "Capture saves only what its snapshot holds")
let foldedList = store.createList(title: "Folded end")
let foldedDocument = DocumentContext(listID: foldedList.id)
let chapter = store.appendBlock(kind: .heading1, text: "Chapter", to: foldedDocument)
let earlier = store.appendBlock(kind: .heading2, text: "Earlier", to: foldedDocument)
let lastSection = store.appendBlock(kind: .heading2, text: "Last", to: foldedDocument)
_ = store.appendBlock(kind: .task, text: "Inside", to: foldedDocument)
for heading in [chapter, earlier, lastSection] { heading.isCollapsed = true }
store.save()
check(Set(store.foldedSections(atEndOf: foldedList.id).map(\.id)) == [chapter.id, lastSection.id],
      "The folded headings a capture goes under are the last one's and those of a higher level above it")
let unfolded = try store.saveCapture(CaptureSnapshot(title: "Shows"), destinationID: foldedList.id)
check(unfolded.parentID == nil && !chapter.isCollapsed && !lastSection.isCollapsed && earlier.isCollapsed
      && store.foldedSections(atEndOf: foldedList.id).isEmpty,
      "A capture under folded headings opens them, so it shows wherever the list is opened, and leaves the others folded")
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
// Only chips of typed tokens pop in, as the design's `fresh` capture chips: its Today is simply there.
func chipsTyped(_ text: String, forToday: Bool = false) -> [Bool] {
    let parse = CaptureParse(text, reference: captureReference)
    var preview = parse.snapshot()
    if forToday, preview.date == nil { preview.date = NXFormat.day(offset: 0, now: captureReference) }
    return parse.chips(for: preview, forToday: forToday, now: captureReference).map(\.typed)
}
check(chipsTyped("Call mum 6pm", forToday: true) == [false, true], "Capture for Today's own Today chip isn't typed")
check(chipsTyped("Call mum today", forToday: true) == [true] && chipsTyped("Call mum 9am") == [true, true],
      "A typed day, and the day a typed time saves, come from typing")

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

// The tray and Changes name a date change by one rule, so it reads the same after a relaunch.
let setAt = NXFormat.day(offset: 0)
let evening = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: setAt)!
let tomorrowEvening = NXFormat.day(NXFormat.day(offset: 1, now: setAt), at: evening)
check(NXFormat.dueChange(tomorrowEvening, includesTime: true, from: evening, oldIncludesTime: true, now: setAt) == "Tomorrow",
      "A timed task moved to another day keeps its time unnamed, as the design's date pills name only the day")
check(NXFormat.dueChange(evening.addingTimeInterval(3600), includesTime: true, from: evening, oldIncludesTime: true, now: setAt) == "Today 19:00",
      "A new time is named with its day")
check(NXFormat.dueChange(evening, includesTime: true, from: setAt, oldIncludesTime: false, now: setAt) == "Today 18:00",
      "A time set on a task that had none is named")
check(NXFormat.dueChange(NXFormat.day(offset: 1, now: setAt), includesTime: false, from: evening, oldIncludesTime: true, now: setAt) == "Tomorrow",
      "A day without a time is named as the day")
check(NXFormat.dueChange(tomorrowEvening, includesTime: true, from: evening, oldIncludesTime: true, now: tomorrowEvening) == "Today",
      "A date change is named as of when it was made")
print("Passed \(checks) capture and triage checks")
