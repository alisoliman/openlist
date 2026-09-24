import AppKit
import SwiftData

var checks = 0
func check(_ value: @autoclosure () throws -> Bool, _ message: String) {
    checks += 1
    guard (try? value()) == true else { fatalError("FAIL: \(message)") }
}
func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
calendar.firstWeekday = 2
let now = date("2026-09-14T12:00:00Z")
let first = date("2026-09-01T08:00:00Z")
let second = date("2026-09-02T08:00:00Z")
let third = date("2026-09-03T08:00:00Z")
let schema = Schema([TaskList.self, Block.self, SidebarSection.self, TaskLabel.self, Attachment.self,
                     ActivityEvent.self, WorkSession.self, CompletionRecord.self, SchedulePlacement.self])
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
let container = try ModelContainer(for: schema, configurations: [configuration])
var failNextSave = false
let store = Store(context: container.mainContext) { context in
    if failNextSave { failNextSave = false; throw CocoaError(.fileWriteNoPermission) }
    try context.save()
}
let aliasURL = url.deletingLastPathComponent().appendingPathComponent("Alias.store")
let aliasContainer = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: aliasURL, cloudKitDatabase: .none)])
var failAliasSave = false
let aliasStore = Store(context: aliasContainer.mainContext) { context in
    if failAliasSave { failAliasSave = false; throw CocoaError(.fileWriteNoPermission) }
    try context.save()
}
let aliasMiddleID = UUID(uuidString: "51000000-0000-0000-0000-000000000001")!
let aliasLeafID = UUID(uuidString: "51000000-0000-0000-0000-000000000002")!
func snapshot() throws -> ActivityHeatmap { try store.activityHeatmap(now: now, calendar: calendar) }
let phase = CommandLine.arguments[2]
if phase == "reopen" {
    let middle = aliasStore.block(id: aliasMiddleID)!
    let leaf = aliasStore.block(id: aliasLeafID)!
    aliasStore.toggleCompletion(leaf, now: second)
    aliasStore.toggleCompletion(leaf, now: third)
    check(try aliasStore.activityHeatmap(now: now, calendar: calendar).total == 3, "nested ancestor reopening alias survives process relaunch")
    aliasStore.toggleCompletion(middle, now: third)
    check(try aliasStore.activityHeatmap(now: now, calendar: calendar).total == 3, "relaunch preserves the self-recurring task's unadvanced completion cycle")
    check(try snapshot().total == 6, "saved heatmap and retained deleted-owner history survive a process relaunch")
    let readonly = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, allowsSave: false, cloudKitDatabase: .none)])
    let failing = Store(context: readonly.mainContext)
    failing.clearActivity()
    check(failing.persistenceError != nil, "failed history clear reports the write failure")
    check(try failing.activityHeatmap(now: now, calendar: calendar).total == 6, "failed clear retains committed counts")
    store.clearActivity()
    check(try store.persistenceError == nil && snapshot().total == 0, "successful clear removes counts without using remaining calendar records")
    check(try snapshot().days.allSatisfy { $0.countDescription == "No count available" }, "cleared history never turns missing days into confirmed zeroes")
    print("✅ \(checks) activity heatmap checks passed (relaunch and clear)")
    exit(0)
}
if phase == "verify-clear" {
    check(try snapshot().total == 0, "activity clear remains empty across process relaunch")
    check(!store.completionRecords().isEmpty, "remaining calendar history does not repopulate activity")
    print("✅ \(checks) activity heatmap checks passed (clear relaunch)")
    exit(0)
}

// Calendar arithmetic, not fixed 86,400-second strides, handles DST and years.
for (end, changedHours) in [("2026-03-30T12:00:00Z", 23.0), ("2026-10-26T12:00:00Z", 25.0)] {
    let grid = ActivityHeatmap(completions: [], now: date(end), calendar: calendar)
    check(grid.days.count == 78, "Monday-ending range includes 11 full weeks and today")
    check(Set(grid.days.map(\.id)).count == grid.days.count, "DST grid contains no repeated dates")
    check(zip(grid.days, grid.days.dropFirst()).contains { $1.id.timeIntervalSince($0.id) == changedHours * 3_600 }, "DST retains its short or long civil day")
    check(grid.days.allSatisfy { calendar.component(.hour, from: $0.id) == 0 }, "DST days remain local midnight")
}
let newYear = ActivityHeatmap(completions: [], now: date("2027-01-01T12:00:00Z"), calendar: calendar)
check(calendar.component(.year, from: newYear.start) == 2026 && calendar.component(.year, from: newYear.end) == 2027, "range crosses year without week-number ambiguity")
var sunday = calendar
sunday.firstWeekday = 1
let sundayGrid = ActivityHeatmap(completions: [], now: now, calendar: sunday)
check(sundayGrid.days.count == 79 && sunday.component(.weekday, from: sundayGrid.start) == 1, "first-weekday preference changes alignment")

let ordinaryID = UUID()
let repeatID = UUID()
let occurrence = UUID()
let firstFact = ActivityCompletion(taskID: ordinaryID, wasRecurring: false, date: first)
let recordID = UUID()
let recurring = ActivityCompletion(taskID: repeatID, completionID: recordID, occurrenceID: occurrence, wasRecurring: true, date: first)
let facts = [firstFact, firstFact,
    ActivityCompletion(taskID: ordinaryID, occurrenceID: UUID(), wasRecurring: false, date: second), recurring,
    ActivityCompletion(taskID: repeatID, completionID: recordID, occurrenceID: occurrence, wasRecurring: true, date: second),
    ActivityCompletion(taskID: repeatID, occurrenceID: occurrence, wasRecurring: true, date: third),
    ActivityCompletion(taskID: repeatID, occurrenceID: UUID(), wasRecurring: true, date: second)]
let unique = ActivityHeatmap(completions: facts.reversed(), now: now, calendar: calendar)
check(unique.total == 3, "duplicates, redo record IDs and ordinary toggles count once; distinct recurring occurrences count separately")
check(unique.days.first { $0.id == calendar.startOfDay(for: first) }?.count == 2, "first completion dates win independent of fetch ordering")
let duplicateID = UUID()
let incompleteDuplicate = ActivityCompletion(id: duplicateID, taskID: repeatID, completionID: recordID, wasRecurring: nil, date: first)
let completeDuplicate = ActivityCompletion(id: duplicateID, taskID: repeatID, completionID: recordID, occurrenceID: occurrence, wasRecurring: true, date: first)
for duplicates in [[incompleteDuplicate, completeDuplicate], [completeDuplicate, incompleteDuplicate], [incompleteDuplicate, recurring]] {
    let combined = ActivityHeatmap(completions: duplicates, now: now, calendar: calendar)
    check(combined.total == 1 && combined.unclassifiedCount == 0, "incomplete duplicate never consumes the complete copy's event or record identity")
}
var laterEnriched = completeDuplicate
laterEnriched.date = second
laterEnriched.title = "Later title"
let enriched = ActivityHeatmap(completions: [laterEnriched, incompleteDuplicate], now: now, calendar: calendar)
check(enriched.days.first { $0.id == calendar.startOfDay(for: second) }?.completions.first?.title == laterEnriched.title,
      "duplicate enrichment uses the first countable action rather than an incomplete entry's timestamp")
var conflicting = completeDuplicate
conflicting.wasRecurring = false
let conflict = ActivityHeatmap(completions: [completeDuplicate, conflicting], now: now, calendar: calendar)
check(conflict.total == 0 && conflict.unclassifiedCount == 1, "conflicting copies are disclosed instead of arbitrarily counted")
let oldID = UUID()
let clipped = ActivityHeatmap(completions: [ActivityCompletion(taskID: oldID, wasRecurring: false, date: date("2025-01-01T12:00:00Z")),
    ActivityCompletion(taskID: oldID, wasRecurring: false, date: first)], now: now, calendar: calendar)
check(clipped.total == 0, "deduplication runs across retained history before restricting the visible range")
let unknown = ActivityHeatmap(completions: [ActivityCompletion(taskID: UUID(), wasRecurring: nil, date: first),
    ActivityCompletion(taskID: nil, wasRecurring: false, date: second),
    ActivityCompletion(taskID: UUID(), wasRecurring: true, date: third)], now: now, calendar: calendar)
check(unknown.total == 0 && unknown.unclassifiedCount == 3, "missing historical identity or recurrence remains explicitly uncounted")
check(unknown.days.first { $0.id == calendar.startOfDay(for: first) }?.unclassifiedCount == 1, "unknown older details remain attached to the correct day")
let boundary = ActivityCompletion(taskID: UUID(), wasRecurring: false, date: date("2026-09-01T22:30:00Z"))
var pacific = calendar
pacific.timeZone = TimeZone(identifier: "America/Los_Angeles")!
let amsterdamDay = ActivityHeatmap(completions: [boundary], now: now, calendar: calendar).days.first { $0.count > 0 }!.id
let pacificDay = ActivityHeatmap(completions: [boundary], now: now, calendar: pacific).days.first { $0.count > 0 }!.id
check(calendar.component(.day, from: amsterdamDay) == 2 && pacific.component(.day, from: pacificDay) == 1, "timezone changes regroup by local completion date")
check(ActivityHeatmap(completions: [ActivityCompletion(taskID: UUID(), wasRecurring: false, date: now.addingTimeInterval(1))], now: now).total == 0, "future actions do not leak into today's count")
for (count, band) in [(0, 0), (1, 1), (2, 2), (3, 2), (4, 3), (6, 3), (7, 4)] {
    let day = ActivityHeatmapDay(id: first, completions: (0..<count).map { _ in firstFact }, unclassifiedCount: 0)
    check(ActivityBand.level(day.count) == band && day.accessibilityDescription.contains(day.countDescription),
          "legend bands and accessible numeric counts agree")
}

store.bootstrap()
let list = store.createList(title: "Completion-time list")
let ordinary = store.appendBlock(kind: .task, text: "Original title", to: .init(listID: list.id))
store.toggleCompletion(ordinary, now: first)
store.toggleCompletion(ordinary, now: second)
store.toggleCompletion(ordinary, now: third)
store.setText("Renamed task", for: ordinary)
store.rename(list, to: "Renamed list")
try store.persistChanges()
check(try snapshot().total == 1, "actual ordinary complete/reopen/complete is deduplicated")
let savedFirst = try snapshot().days.flatMap(\.completions).first!
check(savedFirst.title == "Original title" && savedFirst.listTitle == "Completion-time list", "day details preserve original task and list snapshots")

let parent = store.appendBlock(kind: .task, text: "Recurring parent", to: .init(listID: list.id))
store.setDueDate(first, for: parent)
var rule = Recurrence.daily
rule.occurrenceLimit = 2
store.setRecurrence(rule, for: parent)
let child = store.insertChild(text: "Recurring child", of: parent)
try store.persistChanges()
let childOccurrence = child.occurrenceID
store.toggleCompletion(child, now: first)
let childEvent = try store.taskActivity(for: child.id).first { $0.kind == .completed }!
check(childEvent.change?.completionWasRecurring == true && childEvent.change?.completedOccurrenceID == childOccurrence, "direct child completion captures its inherited recurring cycle and exact occurrence")
let firstParentCycle = parent.occurrenceID
store.toggleCompletion(child, now: first)
store.toggleCompletion(child, now: first)
check(try snapshot().total == 2, "inherited child repeated toggles stay within one parent cycle")
check(try store.taskActivity(for: child.id).filter { $0.kind == .completed }.allSatisfy { $0.change?.completionCycleID == firstParentCycle }, "child toggles record the stable ancestor cycle while calendar occurrence UUIDs change")
store.toggleCompletion(parent, now: second)
let manager = UndoManager()
manager.groupsByEvent = false
store.onCompletionUndoAvailable = { action in
    manager.beginUndoGrouping()
    store.registerCompletionUndo(action, with: manager)
    manager.endUndoGrouping()
}
let finalChildOccurrence = child.occurrenceID
store.toggleCompletion(parent, now: third)
check(parent.recurrence == nil, "fixture completes the last parent repeat")
let finalChildEvent = try store.taskActivity(for: child.id).first { $0.change?.completedOccurrenceID == finalChildOccurrence }!
check(finalChildEvent.change?.completionWasRecurring == true, "final parent cycle retains inherited recurrence after its rule is removed")
check(try snapshot().total == 5, "ordinary task plus two parent and two child occurrences count independently")
manager.undo()
check(try snapshot().total == 5, "completion Undo keeps the historical performed actions")
manager.redo()
check(try snapshot().total == 5, "native Redo does not inflate recurring parent or child counts")
store.onCompletionUndoAvailable = nil

let backupBytes = try JSONEncoder().encode(BackupActivityEvent(finalChildEvent))
let restoredEvent = try JSONDecoder().decode(BackupActivityEvent.self, from: backupBytes).model()
check(restoredEvent.changeData == finalChildEvent.changeData && restoredEvent.change?.completionWasRecurring == true,
      "existing backup roundtrip preserves optional heatmap payload bytes")
var legacyObject = try JSONSerialization.jsonObject(with: finalChildEvent.changeData!) as! [String: Any]
legacyObject.removeValue(forKey: "completedOccurrenceID")
legacyObject.removeValue(forKey: "completionWasRecurring")
legacyObject.removeValue(forKey: "completionCycleID")
let legacyBytes = try JSONSerialization.data(withJSONObject: legacyObject)
let decodedLegacy = try JSONDecoder().decode(TaskActivityChange.self, from: legacyBytes)
check(decodedLegacy.completedOccurrenceID == nil && decodedLegacy.completionWasRecurring == nil, "old history payload decodes without fabricated additive fields")
let legacyEvent = ActivityEvent(kind: .completed, title: "Legacy child", blockID: child.id)
legacyEvent.changeData = legacyBytes
let correspondingRecord = store.completionRecords(taskID: child.id).first { $0.id == decodedLegacy.completionID }!
let legacyFact = ActivityCompletion(event: legacyEvent, matchingRecord: correspondingRecord)
check(legacyFact.occurrenceID == finalChildOccurrence && legacyFact.wasRecurring == true, "legacy fallback uses the matching completion record's historical snapshot")
let unrelated = CompletionRecord(task: ordinary)
check(ActivityCompletion(event: legacyEvent, matchingRecord: unrelated).occurrenceID == nil, "unrelated calendar records cannot supply missing occurrence identity")

// Backup-compatible duplicate events may contain different amounts of detail.
let partialCopy = ActivityEvent(kind: .completed, title: finalChildEvent.title, blockID: child.id)
partialCopy.timestamp = first
partialCopy.change = TaskActivityChange(before: nil, after: nil, completionID: finalChildEvent.change?.completionID, completedAt: third)
store.context.insert(partialCopy)
try store.persistChanges()
check(try snapshot().total == 5, "persisted partial and complete copies with one completion ID do not suppress or inflate the known action")
let conflictingCopy = ActivityEvent(kind: .completed, title: "Conflicting backup copy", blockID: child.id)
conflictingCopy.change = TaskActivityChange(before: nil, after: nil, completionID: finalChildEvent.change?.completionID,
    completedAt: third, completedOccurrenceID: finalChildOccurrence, completionWasRecurring: false)
store.context.insert(conflictingCopy)
try store.persistChanges()
check(try snapshot().total == 4 && snapshot().unclassifiedCount == 1,
      "persisted conflicting copies are one ambiguous uncounted action")
store.context.delete(conflictingCopy)
try store.persistChanges()
check(try snapshot().total == 5, "removing a conflicting copy restores the usable original action")

let batchContainer = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
var failBatchSave = false
let batchStore = Store(context: batchContainer.mainContext) { context in
    if failBatchSave { failBatchSave = false; throw CocoaError(.fileWriteNoPermission) }
    try context.save()
}
batchStore.bootstrap()
let batchList = batchStore.createList(title: "Batch fixture")
let batchParent = batchStore.appendBlock(kind: .task, text: "Batch repeat", to: .init(listID: batchList.id))
batchStore.setDueDate(first, for: batchParent)
batchStore.setRecurrence(.daily, for: batchParent)
let batchChild = batchStore.insertChild(text: "Batch child", of: batchParent)
try batchStore.persistChanges()
batchStore.batch {
    batchStore.toggleCompletion(batchParent, now: first)
    batchStore.toggleCompletion(batchParent, now: second)
}
check(try batchStore.activityHeatmap(now: now, calendar: calendar).total == 4, "two recurring parent and child cycles in one save retain distinct exact cycle IDs")
check(try Set(batchStore.taskActivity(for: batchChild.id).filter { $0.kind == .completed }.compactMap { $0.change?.completionCycleID }).count == 2, "batch history does not reuse the committed ancestor's original cycle")
let cascadeParent = batchStore.appendBlock(kind: .task, text: "Ordinary cascade parent", to: .init(listID: batchList.id))
let selfRecurringChild = batchStore.insertChild(text: "Self recurring child", of: cascadeParent)
batchStore.setDueDate(first, for: selfRecurringChild)
batchStore.setRecurrence(.daily, for: selfRecurringChild)
batchStore.toggleCompletion(cascadeParent, now: first)
let beforeReopen = try batchStore.activityHeatmap(now: now, calendar: calendar).total
batchStore.toggleCompletion(selfRecurringChild, now: second)
batchStore.toggleCompletion(selfRecurringChild, now: third)
check(try batchStore.activityHeatmap(now: now, calendar: calendar).total == beforeReopen, "self-recurring child cascade then reopen does not count the unadvanced repeat twice")
batchStore.toggleCompletion(selfRecurringChild, now: third)
check(try batchStore.activityHeatmap(now: now, calendar: calendar).total == beforeReopen + 1, "self-recurring child's next advanced occurrence still counts")
let grandparent = batchStore.appendBlock(kind: .task, text: "Ordinary grandparent", to: .init(listID: batchList.id))
let middle = batchStore.insertChild(text: "Recurring middle", of: grandparent)
batchStore.setDueDate(first, for: middle)
batchStore.setRecurrence(.daily, for: middle)
let leaf = batchStore.insertChild(text: "Inherited leaf", of: middle)
try batchStore.persistChanges()
batchStore.toggleCompletion(grandparent, now: first)
let beforeNestedReopen = try batchStore.activityHeatmap(now: now, calendar: calendar).total
batchStore.toggleCompletion(middle, now: second)
batchStore.toggleCompletion(leaf, now: second)
batchStore.toggleCompletion(leaf, now: third)
check(try batchStore.activityHeatmap(now: now, calendar: calendar).total == beforeNestedReopen,
      "a leaf inherits its recurring ancestor's preserved reopening alias")
batchStore.toggleCompletion(leaf, now: third)
batchStore.toggleCompletion(middle, now: third)
check(try batchStore.activityHeatmap(now: now, calendar: calendar).total == beforeNestedReopen,
      "parent reset passes the aliased cycle rather than its newer calendar UUID")
batchStore.toggleCompletion(middle, now: third)
check(try batchStore.activityHeatmap(now: now, calendar: calendar).total == beforeNestedReopen + 2,
      "genuinely advanced nested parent and child cycles count separately")
let bulkParent = batchStore.appendBlock(kind: .task, text: "Bulk repeat", to: .init(listID: batchList.id))
batchStore.setDueDate(first, for: bulkParent)
batchStore.setRecurrence(.daily, for: bulkParent)
let bulkChild = batchStore.insertChild(text: "Bulk recurring child", of: bulkParent)
let bulkOrdinary = batchStore.appendBlock(kind: .task, text: "Bulk ordinary", to: .init(listID: batchList.id))
try batchStore.persistChanges()
let bulkManager = UndoManager()
bulkManager.groupsByEvent = false
batchStore.onCompletionUndoAvailable = { action in
    bulkManager.beginUndoGrouping()
    batchStore.registerCompletionUndo(action, with: bulkManager)
    bulkManager.endUndoGrouping()
}
let beforeBulk = try batchStore.activityHeatmap(now: now, calendar: calendar).total
check(try batchStore.setBulkCompletion(true, ids: [bulkParent.id, bulkChild.id, bulkOrdinary.id], now: first) == 3,
      "bulk selection resolves parent, selected descendant, and independent task")
check(try batchStore.activityHeatmap(now: now, calendar: calendar).total == beforeBulk + 3,
      "bulk completion counts parent, child and ordinary task once each")
bulkManager.undo()
bulkManager.redo()
check(try batchStore.activityHeatmap(now: now, calendar: calendar).total == beforeBulk + 3,
      "multi-root bulk completion Undo and Redo preserve captured recurring cycle IDs")
failBatchSave = true
do { _ = try batchStore.setBulkCompletion(true, ids: [bulkParent.id], now: second); fatalError("bulk failure expected") }
catch { check(batchStore.persistenceError != nil, "bulk completion failure reports its atomic rollback") }
check(try batchStore.activityHeatmap(now: now, calendar: calendar).total == beforeBulk + 3,
      "failed bulk recurring completion adds no activity")
check(batchStore.pendingCompletionCycleIDs.isEmpty && batchStore.pendingReopenedCycleIDs.isEmpty,
      "bulk rollback removes only its uncommitted cycle metadata")
_ = try batchStore.setBulkCompletion(true, ids: [bulkParent.id], now: second)
check(try batchStore.activityHeatmap(now: now, calendar: calendar).total == beforeBulk + 5,
      "retry after bulk rollback adds one parent and child cycle")

let bulkRoot = batchStore.appendBlock(kind: .task, text: "Bulk alias root", to: .init(listID: batchList.id))
let bulkMiddle = batchStore.insertChild(text: "Bulk alias middle", of: bulkRoot)
batchStore.setDueDate(first, for: bulkMiddle)
batchStore.setRecurrence(.daily, for: bulkMiddle)
let bulkLeaf = batchStore.insertChild(text: "Bulk alias leaf", of: bulkMiddle)
try batchStore.persistChanges()
_ = try batchStore.setBulkCompletion(true, ids: [bulkRoot.id], now: first)
let beforeBulkReopen = try batchStore.activityHeatmap(now: now, calendar: calendar).total
_ = try batchStore.setBulkCompletion(false, ids: [bulkMiddle.id, bulkLeaf.id], now: second)
bulkManager.undo()
check(try batchStore.activityHeatmap(now: now, calendar: calendar).total == beforeBulkReopen,
      "bulk Reopen Undo refers to the existing occurrence rather than another completion")
bulkManager.redo()
batchStore.toggleCompletion(bulkLeaf, now: third)
batchStore.toggleCompletion(bulkMiddle, now: third)
check(try batchStore.activityHeatmap(now: now, calendar: calendar).total == beforeBulkReopen,
      "bulk Reopen Undo/Redo preserves ancestor aliases for later child and parent completion")
batchStore.onCompletionUndoAvailable = nil

// Failed writes stay retryable, but a fresh history reader sees committed facts.
let failed = store.appendBlock(kind: .task, text: "Retry completion", to: .init(listID: list.id))
failNextSave = true
store.toggleCompletion(failed, now: third)
check(try store.persistenceError != nil && snapshot().total == 5, "failed completion does not publish a count from retained unsaved models")
try store.persistChanges()
check(try snapshot().total == 6, "retry publishes precisely one completion")
let totalBeforeDeletion = try snapshot().total
check(store.trashList(list), "fixture moves a whole owning list to Trash")
check(try snapshot().total == totalBeforeDeletion, "trashed tasks and deleted owner keep history counts")
check(store.restoreTrash(ids: [list.id]), "fixture restores the owning list")
check(try snapshot().total == totalBeforeDeletion, "restoration adds no completion")
check(store.trashList(list) && store.permanentlyEraseTrash(ids: [list.id]), "fixture permanently erases the owning list and tasks")
check(try snapshot().total == totalBeforeDeletion, "permanent deletion preserves recorded completions independently of tasks")
store.clearCalendarHistory()
check(try snapshot().total == totalBeforeDeletion, "new event payload retains exact counts after calendar history is cleared")
// Keep a calendar record for the clear/relaunch assertion without an event.
let retainedRecord = CompletionRecord(task: Block(kind: .task, text: "Calendar-only record"), completedAt: first)
store.context.insert(retainedRecord)
try store.persistChanges()
check(try snapshot().total == totalBeforeDeletion, "calendar records without activity never become invented heatmap history")
aliasStore.bootstrap()
let aliasList = aliasStore.createList(title: "Relaunch alias fixture")
let aliasRoot = aliasStore.appendBlock(kind: .task, text: "Alias root", to: .init(listID: aliasList.id))
let aliasMiddle = aliasStore.insertChild(text: "Alias middle", of: aliasRoot)
aliasMiddle.id = aliasMiddleID
aliasStore.setDueDate(first, for: aliasMiddle)
aliasStore.setRecurrence(.daily, for: aliasMiddle)
let aliasLeaf = aliasStore.insertChild(text: "Alias leaf", of: aliasMiddle)
aliasLeaf.id = aliasLeafID
try aliasStore.persistChanges()
aliasStore.toggleCompletion(aliasRoot, now: first)
failAliasSave = true
aliasStore.toggleCompletion(aliasMiddle, now: second)
check(try aliasStore.persistenceError != nil && aliasStore.activityHeatmap(now: now, calendar: calendar).total == 3,
      "failed recurring reopen leaves its committed heatmap unchanged")
try aliasStore.persistChanges()
check(try aliasStore.taskActivity(for: aliasMiddle.id).first { $0.kind == .reopened }?.change?.completionCycleID != nil,
      "retry durably records the reopening cycle alias")
print("✅ \(checks) activity heatmap checks passed (dates, deduplication, recurrence, failures, retention, backups)")
