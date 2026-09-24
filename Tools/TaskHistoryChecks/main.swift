import AppKit
import SwiftData

var checks = 0
func check(_ value: @autoclosure () throws -> Bool, _ message: String) {
    checks += 1
    guard (try? value()) == true else { fatalError("FAIL: \(message)") }
}
let schema = Schema([TaskList.self, Block.self, SidebarSection.self, TaskLabel.self, Attachment.self,
                     ActivityEvent.self, WorkSession.self, CompletionRecord.self, SchedulePlacement.self])
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let phase = CommandLine.arguments[2]
let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
let container = try ModelContainer(for: schema, configurations: [configuration])
var injectedFailures = 0
let store = Store(context: container.mainContext) { context in
    if injectedFailures > 0 {
        injectedFailures -= 1
        throw CocoaError(.fileWriteNoPermission)
    }
    try context.save()
}
let fixedID = UUID(uuidString: "31000000-0000-0000-0000-000000000001")!
func history(_ task: Block, _ target: Store = store) throws -> [ActivityEvent] {
    try target.taskActivity(for: task.id, limit: 10_000)
}
func events(_ target: Store = store) throws -> [ActivityEvent] { try target.context.fetch(FetchDescriptor<ActivityEvent>()) }
if phase == "legacy" {
    let old = try store.taskActivity(for: fixedID).first!
    check(old.title == "Historic task title" && old.listTitle == "Historic list title", "migration preserves old title and list snapshots")
    check(old.changeData == nil && old.recordedDetail == "Tomorrow", "optional additive migration does not invent old schedule details")
    old.changeData = Data("invalid old or future payload".utf8)
    check(old.change == nil && old.recordedDetail == "Tomorrow", "unreadable detail payload uses recorded legacy text")
    print("✅ \(checks) task history checks passed (legacy migration)")
    exit(0)
}
if phase == "reopen" {
    let task = store.block(id: fixedID)!
    let saved = try history(task)
    check(saved.count > 400, "all old task events persist across process relaunch")
    check(saved.contains { $0.kind == .renamed && $0.change?.before?.title == "Original title" && $0.change?.after?.title == "Final title" }, "structured title snapshots survive relaunch")
    check(saved.contains { $0.change == nil && $0.detail == "Only this old fact was recorded" }, "legacy event remains honest after reopening")
    check(saved.contains { $0.kind == .moved && $0.change?.before?.listTitle == "Renamed source" && $0.change?.after?.listTitle == "Destination" }, "old list names remain frozen")
    let readonly = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, allowsSave: false, cloudKitDatabase: .none)])
    let failingClear = Store(context: readonly.mainContext)
    let retainedEvents = try events(failingClear)
    failingClear.clearActivity()
    check(failingClear.persistenceError != nil, "clear reports a real delete transaction failure")
    check(try Set(events(failingClear).map(\.id)) == Set(retainedEvents.map(\.id)), "failed clear leaves first live event membership intact")
    check(retainedEvents.allSatisfy { !$0.isDeleted }, "failed clear leaves retained event objects intact")
    store.clearActivity()
    check(store.persistenceError == nil && (try? events().isEmpty) == true, "successful clear removes all shared event rows")
    check(store.block(id: fixedID) != nil, "clear retains the current task")
    print("✅ \(checks) task history checks passed (reopen)")
    exit(0)
}
if phase == "verify-clear" {
    check(try events().isEmpty, "history clear persists across process relaunch")
    check(store.block(id: fixedID)?.text == "Successful retry title", "clearing history retains the successfully retried task after relaunch")
    print("✅ \(checks) task history checks passed (clear reopen)")
    exit(0)
}

store.bootstrap()
let source = store.createList(title: "Source")
let destination = store.createList(title: "Destination")
let task = store.appendBlock(kind: .task, text: "Original title", to: .init(listID: source.id))
task.id = fixedID
try store.persistChanges()
check(!store.context.autosaveEnabled, "Store owns task and history commit boundary")
check(try history(task).count == 1 && history(task).first?.kind == .created, "one creation event is generated centrally")
check(try history(task).first?.listTitle == "Source", "creation retains historical list title")
for text in ["F", "Fi", "Final", "Final title"] { store.setText(text, for: task) }
check(try history(task).count == 1, "typing stages no observable activity before commit")
try store.persistChanges()
let rename = try history(task).first!
check(rename.kind == .renamed && rename.change?.before?.title == "Original title" && rename.change?.after?.title == "Final title", "keystrokes coalesce to committed before/after")
let countAfterRename = try history(task).count
store.setText("Final title", for: task)
store.setDueDate(nil, for: task)
store.save(); store.save()
check(try history(task).count == countAfterRename, "no-op writes and repeated saves do not create events")
let due = Date(timeIntervalSince1970: 2_100_000_000)
store.setDueDate(due, includesTime: true, for: task)
check(try history(task).first?.change?.before?.dueDate == nil && history(task).first?.change?.after?.dueDate == due, "due date records old and new values")
check(try history(task).first?.change?.after?.includesTime == true, "time precision is recorded")
store.setDueDate(due, includesTime: false, for: task)
check(try history(task).first?.change?.before?.includesTime == true && history(task).first?.change?.after?.includesTime == false, "date-only change is meaningful")
store.rename(source, to: "Renamed source")
check(rename.listTitle == "Source", "later list rename never rewrites historical snapshot")
let child = store.insertChild(text: "Nested child", of: task)
try store.persistChanges()
store.moveToList(task, list: destination)
check(try history(task).first?.kind == .moved, "parent move is recorded")
check(try history(child).first?.kind == .moved && history(child).first?.change?.before?.listTitle == "Renamed source", "subtree move records each child's own before/after")
store.toggleCompletion(task, now: due)
check(try history(task).first?.kind == .completed, "parent completion recorded")
check(try history(child).first?.kind == .completed && history(child).first?.blockID == child.id, "cascaded child completion gets its own event")
let completionAction = store.completionUndo!
check(store.undoCompletion(completionAction.id), "completion undo succeeds")
check(try history(task).first?.kind == .completionUndone && history(child).first?.kind == .completionUndone, "completion undo is explicit per affected task")
let undoCount = try history(task).count
check(!store.undoCompletion(completionAction.id), "same undo cannot be applied twice")
check(try history(task).count == undoCount, "no-op undo adds no duplicate")
store.toggleCompletion(task, now: due)
store.toggleCompletion(task, now: due)
check(try history(task).first?.kind == .reopened, "ordinary reopening remains distinct from undo")

let recurring = store.appendBlock(kind: .task, text: "Weekly", to: .init(listID: source.id))
recurring.dueDate = due
recurring.recurrence = .weekly
let recurringChild = store.insertChild(text: "Weekly child", of: recurring)
try store.persistChanges()
let originalOccurrence = recurring.occurrenceID
let manager = UndoManager()
manager.groupsByEvent = false
store.onCompletionUndoAvailable = { action in
    manager.beginUndoGrouping()
    store.registerCompletionUndo(action, with: manager)
    manager.endUndoGrouping()
}
store.toggleCompletion(recurring, now: due)
let recurringEvent = try history(recurring).first!
check(recurring.id != recurring.occurrenceID && recurringEvent.blockID == recurring.id, "repeat retains task identity")
check(recurringEvent.change?.before?.occurrenceID == originalOccurrence && recurringEvent.change?.after?.occurrenceID == recurring.occurrenceID, "occurrence identities captured separately")
check(recurringEvent.change?.completedDueDate == due && recurringEvent.change?.after?.dueDate == recurring.dueDate, "completed and next occurrence dates are accurate")
check(recurringEvent.change?.advancesOccurrence == true && recurringEvent.recordedDetail.contains("Next occurrence"), "repeat completion explains its next occurrence")
check(try history(recurringChild).first?.kind == .completed, "repeat child completion has its own history")
manager.undo()
check(try history(recurring).first?.kind == .completionUndone && recurring.dueDate == due, "native undo records occurrence restoration")
manager.redo()
check(try history(recurring).first?.kind == .completed && recurring.dueDate != due, "redo records re-applied completion without losing old history")
store.onCompletionUndoAvailable = nil

let editor = UndoManager()
editor.groupsByEvent = false
editor.beginUndoGrouping()
store.undoableEditorEdit(in: destination.id, name: "Edit title", undoManager: editor) {
    store.setContent(task, attributed: NSAttributedString(string: "Editor title"))
    store.save()
}
editor.endUndoGrouping()
check(try history(task).first?.change?.after?.title == "Editor title", "outline rich-text path logs plain title change")
editor.undo()
check(try history(task).first?.change?.after?.title == "Final title", "editor undo records inverse title change")
editor.redo()
check(try history(task).first?.change?.after?.title == "Editor title", "editor redo records restored title")

let deletedTask = store.appendBlock(kind: .task, text: "Retained historical task", to: .init(listID: destination.id))
let deletedID = deletedTask.id
try store.persistChanges()
editor.beginUndoGrouping()
store.undoableEditorEdit(in: destination.id, name: "Delete task", undoManager: editor) {
    store.deleteBlock(deletedTask)
    store.save()
}
editor.endUndoGrouping()
check(try store.taskActivity(for: deletedID).first?.kind == .deleted, "deletion adds history without erasing earlier task events")
check(try store.taskActivity(for: deletedID).first?.change?.before?.title == "Retained historical task", "deleted task keeps its last real title snapshot")
editor.undo()
check(try store.taskActivity(for: deletedID).first?.kind == .restored && store.block(id: deletedID) != nil, "structural Undo restores the same task UUID and appends a restoration event")
editor.redo()
check(try store.taskActivity(for: deletedID).first?.kind == .deleted, "structural Redo records its new deletion")

let captured = try store.saveCapture(.init(title: "Captured", date: due, includesTime: true), destinationID: source.id)
check(try history(captured).count == 1 && history(captured).first?.change?.after?.dueDate == due, "capture records one final creation with metadata")
let freshCompletion = store.appendBlock(kind: .task, text: "Created and completed", to: .init(listID: source.id))
freshCompletion.dueDate = due
freshCompletion.includesTime = true
store.toggleCompletion(freshCompletion, now: due)
check(try history(freshCompletion).map(\.kind).contains(.created) && history(freshCompletion).map(\.kind).contains(.completed), "create and complete in one transaction retain both real facts")
check(try history(freshCompletion).first { $0.kind == .completed }?.recordedDetail.contains(MomentText.moment(due)) == true, "create and complete in one transaction retains the known due time")
// History and the Work panel write a moment as the app's pills and clock do.
let momentNow = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 9))!
let momentToday = Calendar.current.date(bySettingHour: 18, minute: 5, second: 0, of: momentNow)!
let momentLastYear = Calendar.current.date(from: DateComponents(year: 2025, month: 10, day: 3, hour: 7, minute: 30))!
let momentThisYear = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 7, minute: 30))!
check(MomentText.moment(momentToday, now: momentNow) == "Today 18:05" && MomentText.moment(momentToday, inSentence: true, now: momentNow) == "today 18:05",
      "a moment today reads as the design's day and 24-hour clock, lower case in a sentence")
check(MomentText.moment(momentToday.addingTimeInterval(2 * 86_400), includesTime: false, now: momentNow)
          == momentToday.addingTimeInterval(2 * 86_400).formatted(.dateTime.weekday(.abbreviated).day()),
      "a day in the week ahead reads as its weekday and date")
check(MomentText.moment(momentThisYear, now: momentNow) == "\(momentThisYear.formatted(.dateTime.day().month(.abbreviated))) 07:30"
          && MomentText.moment(momentLastYear, now: momentNow) == "\(momentLastYear.formatted(.dateTime.day().month(.abbreviated).year())) 07:30",
      "a moment names its year only when it isn't this one")
check(MomentText.clock(momentLastYear) == "07:30" && MomentText.day(momentLastYear, now: momentNow) == momentLastYear.formatted(.dateTime.day().month(.abbreviated)),
      "the pills' day and the clock stay the design's, with no year")
check(WorkSession.stopText("Mac was unavailable") == "Paused while the Mac was away" && WorkSession.stopText(nil) == "Paused"
          && WorkSession.stopText("Library restored; paused at last recorded time") == "Paused when the library was restored"
          && WorkSession.stopText("Changed to a note") == "Ended when the task was turned into text"
          && WorkSession.stopText("Completion undone") == "Paused when the completion was undone"
          && WorkSession.stopText("Completion restored") == "Ended when the task was done",
      "Work history words each saved pause reason as the Work panel does, older reasons included")
check(["Completed", "Completion restored", "Reopened", "Next occurrence"].allSatisfy { WorkSession.resumableStopText($0) == "Paused" }
          && WorkSession.resumableStopText("Completion undone") == "Paused when the completion was undone"
          && WorkSession.resumableStopText("Mac slept") == "Paused while the Mac was asleep",
      "The Work panel's paused card, beside Resume working, never says the work ended")

// Debounced fallback persists even without Return; it never inserts a row per key.
let beforeDebounce = try history(task).count
for text in ["Deb", "Debounced", "Debounced title"] { store.setText(text, for: task) }
try await Task.sleep(for: .milliseconds(1_250))
check(try history(task).count == beforeDebounce + 1 && history(task).first?.change?.after?.title == "Debounced title", "title pause commits exactly one fallback event")

// Legacy events and old task history remain reachable even with a busy global feed.
for index in 0..<405 {
    let event = ActivityEvent(kind: .scheduled, title: "Historic title", detail: "Only this old fact was recorded", blockID: task.id)
    event.timestamp = Date(timeIntervalSince1970: Double(index))
    store.context.insert(event)
}
for index in 0..<320 {
    let event = ActivityEvent(kind: .created, title: "Other task \(index)", blockID: UUID())
    event.timestamp = Date.now.addingTimeInterval(100)
    store.context.insert(event)
}
try store.persistChanges()
check(store.recentActivity().count == 300 && !store.recentActivity().contains { $0.blockID == task.id }, "global window can contain none of this task's history")
check(try store.taskActivity(for: task.id, limit: 50).count == 50, "task page uses independent filter and limit")
check(try store.taskActivity(for: task.id, limit: 50, offset: 400).count > 0, "old task entries past 300 remain reachable")
let old = try store.taskActivity(for: task.id, limit: 10_000).last!
check(old.change == nil && old.recordedDetail == "Only this old fact was recorded", "old events do not invent absent before values")

let readonly = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, allowsSave: false, cloudKitDatabase: .none)])
let failing = Store(context: readonly.mainContext)
let retained = failing.block(id: task.id)!
let savedTitle = retained.text
let beforeFailure = try history(retained, failing).map(\.id)
failing.setText("Retryable unsaved title", for: retained)
for _ in 0..<2 {
    do { try failing.persistChanges(); check(false, "read-only commit must fail") } catch {}
    check(retained.text == "Retryable unsaved title", "failed save preserves current user edit")
    let afterFailure = try history(retained, failing)
    if Set(afterFailure.map(\.id)) != Set(beforeFailure) {
        print("Failure event membership: before \(beforeFailure.count), after \(afterFailure.count), extra \(afterFailure.filter { !beforeFailure.contains($0.id) }.map { ($0.kindRaw, $0.title, $0.isDeleted) })")
        fflush(stdout)
    }
    check(Set(afterFailure.map(\.id)) == Set(beforeFailure), "first live fetch after failed save shows no failed event or retry duplicate")
    check(try failing.taskActivity(for: task.id, limit: 51).count == 51, "failed models do not consume the first page or its older-row sentinel")
    check(try failing.taskActivity(for: task.id, limit: 50, offset: 50).map(\.id) == store.taskActivity(for: task.id, limit: 50, offset: 50).map(\.id), "failed models do not shift subsequent page boundaries")
}
failing.clearActivity()
check(failing.persistenceError != nil && (try? history(retained, failing).count) == beforeFailure.count, "clear cannot publish failed edits or remove existing history when its preflush fails")
let reopened = try ModelContainer(for: schema, configurations: [configuration])
let savedStore = Store(context: ModelContext(reopened))
check(savedStore.block(id: task.id)?.text == savedTitle, "failed save leaves on-disk task unchanged")
check(try Set(savedStore.taskActivity(for: task.id, limit: 10_000).map(\.id)) == Set(beforeFailure), "failed save leaves on-disk history unchanged")
failing.context.rollback()

// Deterministic retry seam complements the actual read-only SwiftData failure
// above. This lets the same live context later complete a successful save.
injectedFailures = 2
store.setText("Successful retry title", for: task)
store.log(.listCreated, title: "Retry draft", list: destination)
for _ in 0..<2 {
    do { try store.persistChanges(); check(false, "injected commit must fail") } catch {}
    check(task.text == "Successful retry title", "recoverable failure preserves retained task edits")
    check(try history(task).count == beforeFailure.count, "injected failed insert never publishes task activity")
}
let failedIDs = store.uncommittedActivityIDs
check(failedIDs.count >= 4, "each failed task and legacy insertion is quarantined")
// Recreate any absent failed attempt identity in the live cache, matching the
// real read-only failure's observed ghost membership before retrying.
let cachedIDs = Set(try events().map(\.id))
for id in failedIDs.subtracting(cachedIDs) {
    let ghost = ActivityEvent(kind: .renamed, title: "Failed attempt", blockID: task.id)
    ghost.id = id
    store.context.insert(ghost)
}
check(try events().contains { failedIDs.contains($0.id) }, "retry fixture contains the observed failed-attempt live membership")
check(try history(task).count == beforeFailure.count, "even cached failed attempts remain unpublished before retry")
try store.persistChanges()
check(try history(task).count == beforeFailure.count + 1, "successful retry records the user change exactly once")
check(try events().filter { $0.title == "Retry draft" && !failedIDs.contains($0.id) }.count == 1, "legacy draft commits exactly once after retries")
store.setSummary("Unrelated later save", for: destination)
let afterRetryContainer = try ModelContainer(for: schema, configurations: [configuration])
let afterRetryStore = Store(context: ModelContext(afterRetryContainer))
check(try events(afterRetryStore).allSatisfy { !failedIDs.contains($0.id) }, "no failed attempt reaches disk on retry or unrelated later save")
check(try afterRetryStore.taskActivity(for: task.id, limit: 10_000).count == beforeFailure.count + 1, "reopened store contains one committed retry event")
check(store.uncommittedActivityIDs.isEmpty, "successful removal prunes the failed-attempt registry")

let legacyTask = store.appendBlock(kind: .task, text: "Legacy retry actions", to: .init(listID: source.id))
try store.persistChanges()
let initialLegacyIDs = try history(legacyTask).map(\.id)
injectedFailures = 1
store.setNote("Never committed note", for: legacyTask)
check(store.persistenceError != nil && !store.pendingActivity.isEmpty, "failed note save keeps its action pending")
store.setNote("", for: legacyTask)
check(store.persistenceError == nil && (try? history(legacyTask).map(\.id)) == initialLegacyIDs, "reversing a failed note addition commits no false noteAdded entry")
injectedFailures = 1
store.toggleStar(legacyTask)
check(store.persistenceError != nil && legacyTask.isStarred, "failed star save leaves the edit available to reverse")
store.toggleStar(legacyTask)
check(store.persistenceError == nil && (try? history(legacyTask).map(\.id)) == initialLegacyIDs, "reversing a failed star commits no false starred entry")
injectedFailures = 1
store.setNote("First attempted note", for: legacyTask)
store.isSavingSuspended = true
store.setNote("", for: legacyTask)
store.setNote("Finally committed note", for: legacyTask)
store.isSavingSuspended = false
try store.persistChanges()
check(try history(legacyTask).filter { $0.kind == .noteAdded }.count == 1, "repeated pending note additions coalesce to the one committed addition")
let legacyReopened = try ModelContainer(for: schema, configurations: [configuration])
let legacySavedStore = Store(context: ModelContext(legacyReopened))
check(try legacySavedStore.taskActivity(for: legacyTask.id).filter { $0.kind == .starred }.isEmpty, "reopened storage has no cancelled star entry")
check(try legacySavedStore.taskActivity(for: legacyTask.id).filter { $0.kind == .noteAdded }.count == 1, "reopened storage has exactly one actual note addition")

let seededContainer = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
let seeded = Store(context: seededContainer.mainContext)
seeded.bootstrap()
SampleData.seed(into: seeded)
check(try events(seeded).isEmpty, "sample seeding and its deferred final save create no fabricated activity")

// Query/save cost is reported with a realistic unrelated corpus, not a hard
// timing threshold that depends on the test machine.
seeded.withoutLogging {
    let listID = seeded.inboxList()!.id
    for index in 0..<10_000 { seeded.context.insert(Block(kind: .task, text: "Scale \(index)", listID: listID)) }
}
seeded.save()
let scaleTask = seeded.blocks(inList: seeded.inboxList()!.id).first!
let start = ContinuousClock.now
seeded.setText("One changed task", for: scaleTask)
try seeded.persistChanges()
print("10k task commit elapsed: \(start.duration(to: .now))")
check(try history(scaleTask, seeded).count == 1, "single-task edit in 10k library records only one change")
seeded.clearActivity()
check(try events(seeded).isEmpty && seeded.block(id: scaleTask.id) != nil, "clear removes shared history while preserving tasks")

let restoreContainer = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
var failRestoration = false
let restoring = Store(context: restoreContainer.mainContext) { context in
    if failRestoration { throw CocoaError(.fileWriteNoPermission) }
    try context.save()
}
restoring.bootstrap()
let restoreList = restoring.inboxList()!
let restoreTask = restoring.appendBlock(kind: .task, text: "Restore after clear", to: .init(listID: restoreList.id))
let restoreID = restoreTask.id
try restoring.persistChanges()
let restoreUndo = UndoManager()
restoreUndo.groupsByEvent = false
restoreUndo.beginUndoGrouping()
restoring.undoableEditorEdit(in: restoreList.id, name: "Delete task", undoManager: restoreUndo) {
    restoring.deleteBlock(restoreTask)
    restoring.save()
}
restoreUndo.endUndoGrouping()
restoring.clearActivity()
check(try events(restoring).isEmpty, "clear removes all creation and deletion records before Undo")
failRestoration = true
restoreUndo.undo()
check(restoring.pendingRestoredTaskIDs.contains(restoreID), "failed restoration save retains its explicit Undo identity")
check(try restoring.taskActivity(for: restoreID).isEmpty, "failed Undo publishes no restoration history")
failRestoration = false
try restoring.persistChanges()
check(try restoring.taskActivity(for: restoreID).count == 1 && restoring.taskActivity(for: restoreID).first?.kind == .restored, "Undo after clearing history records exactly one known restoration")
check(restoring.block(id: restoreID)?.text == "Restore after clear", "Undo after clear restores the actual task")
check(restoring.pendingRestoredTaskIDs.isEmpty, "successful save consumes the restoration signal")
// The history one change saves, a task each, shares a batch, which Changes
// shows as the change's one row; another change's has its own.
let batchContainer = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
let batching = Store(context: batchContainer.mainContext)
batching.bootstrap()
let batchList = batching.createList(title: "Batch source")
let batchParent = batching.appendBlock(kind: .task, text: "Batch parent", to: .init(listID: batchList.id))
_ = batching.insertChild(kind: .task, text: "Batch child", of: batchParent)
try batching.persistChanges()
func batch(of kind: ActivityKind) throws -> [ActivityEvent] {
    let all = try events(batching).filter { $0.kind == kind }.sorted { $0.timestamp > $1.timestamp }
    guard let newest = all.first?.batchID else { return [] }
    return try events(batching).filter { $0.batchID == newest }
}
check(batching.trashBlocks([batchParent]), "a task trashes with its subtask")
let trashBatch = try batch(of: .deleted)
check(trashBatch.count == 2 && trashBatch.allSatisfy { $0.kind == .deleted }, "a task trashed with its subtask saves one batch")
check(batching.restoreTrash(ids: [batchParent.id]), "the task restores with its subtask")
let restoreBatch = try batch(of: .restored)
check(restoreBatch.count == 2 && restoreBatch.allSatisfy { $0.kind == .restored } && restoreBatch[0].batchID != trashBatch[0].batchID,
      "its restore is a batch of its own")
check(batching.trashList(batchList), "the list trashes")
let listTrash = try batch(of: .listDeleted)
check(listTrash.count == 3 && listTrash.filter { $0.kind == .deleted }.count == 2,
      "a list trashed saves its own event and its tasks' in one batch")
check(listTrash.first { $0.kind == .listDeleted }?.recordedDetail == "", "a list's event, with only its batch, says only what it recorded")
check(batching.restoreTrash(ids: [batchList.id]), "the list restores")
let listRestore = try batch(of: .restored)
check(listRestore.count == 3 && listRestore.contains { $0.blockID == nil && $0.listID == batchList.id && $0.title == "Batch source" },
      "a list restored saves an event of its own, in its tasks' batch")
let listCopyID = try batching.copyList(batchList, mode: .duplicate)
let listCopy = try batch(of: .listCreated)
check(listCopy.count == 3 && listCopy.contains { $0.kind == .listCreated && $0.listID == listCopyID && $0.title == "Batch source"
          && $0.change?.copy == .duplicate } && listCopy.filter { $0.kind == .created }.allSatisfy { $0.change?.copy == nil },
      "a list duplicated saves one event for the copy, naming the list it copied, in its tasks' batch")
let taskCopyID = try batching.copyBlock(batching.block(id: batchParent.id)!, mode: .template(keepingRecurrence: false))
let copied = try events(batching)
let copyBatch = copied.first { $0.blockID == taskCopyID }?.batchID
let taskCopy = copied.filter { $0.kind == .created && copyBatch != nil && $0.batchID == copyBatch }
check(taskCopy.count == 2 && taskCopy.first { $0.blockID == taskCopyID }?.change?.copy == .template
          && taskCopy.filter { $0.change?.copy == nil }.count == 1, "a task copied names its copy as a template, its subtask with it")
let together = ["First together", "Second together"].map { batching.appendBlock(kind: .task, text: $0, to: .init(listID: batchList.id)) }
try batching.persistChanges()
let shared = UUID()
batching.withActivityBatch(shared) {
    for task in together { batching.toggleCompletion(task) }
}
check(try events(batching).filter { $0.kind == .completed && $0.batchID == shared }.count == 2,
      "a change saved more than once, like tasks completed together, keeps one batch")
// A parent done with its open subtasks saves a completion each, and its row
// counts them all, as the log does; a repeat resets its subtasks as it rolls
// on, so its row counts the repeat alone, again as the log does.
func completions(_ batch: UUID) throws -> [ActivityEvent] {
    try events(batching).filter { $0.kind == .completed && $0.batchID == batch }
}
func counted(_ batch: UUID) throws -> Int {
    NXSavedChanges.counted(try completions(batch).map { NXSavedTask(id: $0.blockID, rolls: $0.change?.advancesOccurrence == true) },
                           kind: ActivityKind.completed.rawValue) { batching.blockIncludingTrash(id: $0)?.parentID }.count
}
let doneParent = batching.appendBlock(kind: .task, text: "Done parent", to: .init(listID: batchList.id))
for title in ["Open one", "Open two"] { _ = batching.insertChild(kind: .task, text: title, of: doneParent) }
let secondParent = batching.appendBlock(kind: .task, text: "Second parent", to: .init(listID: batchList.id))
for title in ["Open three", "Open four"] { _ = batching.insertChild(kind: .task, text: title, of: secondParent) }
let doneBeside = batching.appendBlock(kind: .task, text: "Done beside", to: .init(listID: batchList.id))
let rolling = batching.appendBlock(kind: .task, text: "Rolling", to: .init(listID: batchList.id))
rolling.dueDate = .now
rolling.recurrence = .weekly
for title in ["Reset one", "Reset two"] { _ = batching.insertChild(kind: .task, text: title, of: rolling) }
let closesBeside = batching.appendBlock(kind: .task, text: "Closes beside", to: .init(listID: batchList.id))
try batching.persistChanges()
let parentDone = UUID()
batching.withActivityBatch(parentDone) { batching.toggleCompletion(doneParent) }
check(try completions(parentDone).count == 3 && counted(parentDone) == 3, "a parent done with two open subtasks counts three tasks")
let withBeside = UUID()
batching.withActivityBatch(withBeside) { for task in [secondParent, doneBeside] { batching.toggleCompletion(task) } }
check(try completions(withBeside).count == 4 && counted(withBeside) == 4, "such a parent done with another task counts four")
let rolled = UUID()
batching.withActivityBatch(rolled) { for task in [rolling, closesBeside] { batching.toggleCompletion(task) } }
check(try completions(rolled).count == 4 && counted(rolled) == 2,
      "a repeat done with its open subtasks and another task counts two, the subtasks it reset left out")
// Earlier words a repeat's completion as the log does, "rolls to" its next
// date, which the completion's own event saves.
let rolledChange = try completions(rolled).first { $0.blockID == rolling.id }?.change
check(rolledChange?.advancesOccurrence == true && rolledChange?.after?.dueDate == rolling.dueDate
          && rolledChange?.after?.dueDate.map { due in rolledChange?.completedDueDate.map { due > $0 } == true } == true,
      "a repeat's completion saves the next date it rolled on to")
// Repeats done together with no other task closing count as rolls alone, so
// Earlier draws their row with the repeat glyph, as the log does.
let bothRolling = ["Rolls one", "Rolls two"].map { batching.appendBlock(kind: .task, text: $0, to: .init(listID: batchList.id)) }
for task in bothRolling { task.dueDate = .now; task.recurrence = .weekly }
_ = batching.insertChild(kind: .task, text: "Reset three", of: bothRolling[0])
try batching.persistChanges()
let rolledTogether = UUID()
batching.withActivityBatch(rolledTogether) { for task in bothRolling { batching.toggleCompletion(task) } }
let togetherTasks = try completions(rolledTogether).map { NXSavedTask(id: $0.blockID, rolls: $0.change?.advancesOccurrence == true) }
let togetherCounted = NXSavedChanges.counted(togetherTasks, kind: ActivityKind.completed.rawValue) {
    batching.blockIncludingTrash(id: $0)?.parentID
}
check(togetherTasks.count == 3 && togetherCounted.count == 2 && togetherCounted.allSatisfy { togetherTasks[$0].rolls },
      "two repeats done together count two, each a roll, the subtask one reset left out")
// A list's restore saves where it went back to, as its tray says it.
let placeParent = batching.createList(title: "Place parent")
let placeChild = batching.createChildList(in: placeParent)!
try batching.persistChanges()
func restoredPlaces(_ list: TaskList) throws -> Set<String> {
    Set(try events(batching).filter { $0.kind == .restored && $0.blockID == nil && $0.listID == list.id }.map(\.detail))
}
check(try restoredPlaces(batchList) == [""], "a list restored at the top level saves no place")
check(batching.trashList(placeChild) && batching.restoreTrash(ids: [placeChild.id]), "a nested list restores")
check(try restoredPlaces(placeChild) == ["to Place parent"], "a list restored under its parent saves that it went back there")
check(batching.trashList(placeChild) && batching.trashList(placeParent) && batching.permanentlyEraseTrash(ids: [placeParent.id])
          && batching.restoreTrash(ids: [placeChild.id]), "a nested list restores once its parent is erased")
check(try restoredPlaces(placeChild) == ["to Place parent", "to the top level — its parent list is unavailable"],
      "a list restored with its parent gone saves that it went to the top level")
print("✅ \(checks) task history checks passed (commits, recurrence, undo, failure, paging, coalescing, batches)")
