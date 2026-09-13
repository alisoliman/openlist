import AppKit
import Observation
import SwiftData
import os

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    guard condition() else { fatalError("FAIL: \(message)") }
}
func rejected(_ message: String, _ operation: () throws -> Void) {
    do { try operation(); fatalError("FAIL: \(message)") }
    catch { check(!error.localizedDescription.isEmpty, message) }
}

struct Metadata: Equatable {
    let text: String, note: String, kind: String
    let richData: Data?, recurrence: Data?
    let listID: UUID?, parentID: UUID?
    let order: Double
    let createdAt: Date, updatedAt: Date
    let isCompleted: Bool, isStarred: Bool, isCollapsed: Bool, includesTime: Bool
    let completedAt: Date?, dueDate: Date?, reminderAt: Date?, selected: Date?, deferred: Date?
    let priority: Int, estimate: Int
    init(_ block: Block) {
        text = block.text; note = block.note; kind = block.kindRaw
        richData = block.richData; recurrence = block.recurrenceData
        listID = block.listID; parentID = block.parentID; order = block.sortIndex
        createdAt = block.createdAt; updatedAt = block.updatedAt
        isCompleted = block.isCompleted; isStarred = block.isStarred; isCollapsed = block.isCollapsed
        includesTime = block.includesTime; completedAt = block.completedAt; dueDate = block.dueDate
        reminderAt = block.reminderAt; selected = block.selectedForDay; deferred = block.deferredUntil
        priority = block.priorityRaw; estimate = block.schedulingEstimateMinutes
    }
}

let schema = Schema([TaskList.self, Block.self, SidebarSection.self, TaskLabel.self, Attachment.self,
                     ActivityEvent.self, WorkSession.self, CompletionRecord.self, SchedulePlacement.self])
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let phase = CommandLine.arguments[2]
let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
let container = try ModelContainer(for: schema, configurations: [configuration])
let store = Store(context: container.mainContext)
store.context.autosaveEnabled = false

func blocks(_ target: Store = store) throws -> [Block] { try target.context.fetch(FetchDescriptor<Block>()) }
func exactLabel(_ id: UUID, _ target: Store = store) -> TaskLabel? { target.allLabels().first { $0.id == id } }
let sourceID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
let destinationID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
let extraID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
let duplicateID = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!

if phase == "reopen" {
    check(exactLabel(sourceID) == nil, "removed label stays removed after relaunch")
    check(exactLabel(destinationID)?.name == "Home", "surviving name persists")
    check(exactLabel(destinationID)?.accent == .blue, "surviving color persists")
    check(exactLabel(duplicateID) != nil, "unselected old duplicate survives relaunch")
    check(store.labelMergeUndo == nil, "undo intentionally lasts for the current app session")
    let reopened = try blocks()
    check(!reopened.contains { $0.labelIDs.contains(sourceID) }, "no stale source reference survives relaunch")
    for block in reopened where block.text != "Unrelated" {
        check(block.labelIDs.filter { $0 == destinationID }.count == 1, "every merged record has one destination after relaunch")
    }
    check(reopened.first { $0.text == "Completed" }?.isCompleted == true, "completed task stays completed on disk")
    check(reopened.first { $0.text == "Nested" }?.parentID != nil, "nested hierarchy survives relaunch")
    check(store.allLists(includeArchived: true).contains { $0.isArchived }, "archive state survives relaunch")
    let event = try store.context.fetch(FetchDescriptor<ActivityEvent>()).first { $0.kind == .labeled && $0.detail == "Work" }!
    check(event.detail == "Work" && event.title == "Original task title", "historical name snapshots survive relaunch")
    print("✅ \(checks) label merge checks passed (reopen)")
    exit(0)
}

let source = TaskLabel(name: "Work", accent: .red, sortIndex: 33)
source.id = sourceID
let destination = TaskLabel(name: "Home", accent: .blue, sortIndex: 77)
destination.id = destinationID
let extra = TaskLabel(name: "Other", accent: .green)
extra.id = extraID
let duplicate = TaskLabel(name: "  #home  ", accent: .orange)
duplicate.id = duplicateID
destination.createdAt = .distantPast
for label in [source, destination, extra, duplicate] { store.context.insert(label) }
let active = TaskList(title: "Active")
let archived = TaskList(title: "Archived")
archived.isArchived = true
store.context.insert(active); store.context.insert(archived)
func task(_ name: String, labels: [UUID], listID: UUID? = active.id, kind: BlockKind = .task) -> Block {
    let task = Block(kind: kind, text: name, listID: listID, sortIndex: 45)
    task.labelIDs = labels
    task.note = "Keep \(name) note"
    task.richData = Data("Rich text".utf8)
    task.priority = .high
    task.dueDate = Date(timeIntervalSince1970: 100)
    task.includesTime = true
    task.reminderAt = Date(timeIntervalSince1970: 200)
    task.selectedForDay = Date(timeIntervalSince1970: 300)
    task.deferredUntil = Date(timeIntervalSince1970: 400)
    task.isStarred = true
    task.isCollapsed = true
    task.schedulingEstimateMinutes = 45
    store.context.insert(task)
    return task
}
let open = task("Open", labels: [sourceID, extraID])
let nested = task("Nested", labels: [sourceID]); nested.parentID = open.id
let completed = task("Completed", labels: [sourceID, destinationID, extraID, sourceID])
completed.isCompleted = true; completed.completedAt = .now
let archivedTask = task("Archived", labels: [sourceID], listID: archived.id)
let orphan = task("Missing list", labels: [sourceID], listID: UUID())
let unfiled = task("Unfiled", labels: [sourceID], listID: nil)
let destinationOnly = task("Destination only", labels: [destinationID])
let paragraph = task("Retained non-task reference", labels: [sourceID], kind: .paragraph)
let unrelated = task("Unrelated", labels: [extraID])
let event = ActivityEvent(kind: .labeled, title: "Original task title", detail: "Work", blockID: open.id)
store.context.insert(event)
try store.persistChanges()

check(TaskLabel.namesMatch(" \n###Work ", "wORK"), "creation and merge use normalized case-insensitive matching")
check(!TaskLabel.namesMatch("my label", "my  label"), "internal whitespace is intentionally not collapsed")
check(store.matchingLabels(named: " ##HOME ").map(\.id) == [destinationID, duplicateID], "old normalized duplicate names are discoverable without merging")
check(store.findOrCreateLabel(named: "  #HOME ")?.id == destinationID, "creation consistently reuses a normalized existing name")
check(store.allLabels().count == 4, "discovery and creation do not silently migrate duplicate labels")
try store.renameLabel(extra, to: "  ##OTHER ")
check(extra.id == extraID && extra.name == "OTHER", "case-only and whitespace-normalized rename keeps its own identity")
rejected("blank rename is explicitly rejected") { try store.renameLabel(extra, to: " ### \n") }
check(extra.name == "OTHER", "blank rename leaves the original name intact")
rejected("colliding rename cannot silently merge") { try store.renameLabel(source, to: "#home") }
check(source.name == "Work" && source.accent == .red, "colliding rename preserves source before confirmation")
rejected("source cannot merge with itself") { _ = try store.labelMergePlan(sourceID: sourceID, destinationID: sourceID) }
rejected("missing destination cannot be resolved to an arbitrary match") { _ = try store.labelMergePlan(sourceID: sourceID, destinationID: UUID()) }

let plan = try store.labelMergePlan(sourceID: sourceID, destinationID: destinationID)
check(plan.affectedTaskCount == 6, "confirmation counts all six source tasks, excluding prose")
check(plan.resultingTaskCount == 7, "confirmation shows unique union count including existing destination tasks")
check(plan.destination.id == destinationID && plan.destination.accent == .blue, "confirmation carries explicit survivor identity and color")
destinationOnly.labelIDs = [destinationID, destinationID]
let duplicatedDestinationPlan = try store.labelMergePlan(sourceID: sourceID, destinationID: destinationID)
check(duplicatedDestinationPlan.affectedTaskCount == 7, "affected count includes a destination-only duplicate that will be cleaned up")
destinationOnly.labelIDs = [destinationID]
try store.persistChanges()
let beforeLabels = Dictionary(uniqueKeysWithValues: try blocks().map { ($0.id, $0.labelIDs) })
let beforeMetadata = Dictionary(uniqueKeysWithValues: try blocks().map { ($0.id, Metadata($0)) })
check(exactLabel(sourceID) != nil && open.labelIDs.contains(sourceID), "preview or cancel never mutates source references")

destination.accent = .pink
try store.persistChanges()
rejected("a changed destination requires a refreshed confirmation") { try store.mergeLabels(plan) }
check(exactLabel(sourceID) != nil && open.labelIDs.contains(sourceID), "stale confirmation leaves merge unapplied")
destination.accent = .blue
try store.persistChanges()
unrelated.labelIDs.append(sourceID)
try store.persistChanges()
rejected("changed task references require a refreshed affected-task count") { try store.mergeLabels(plan) }
unrelated.labelIDs = [extraID]
try store.persistChanges()

// Retained picker identities and navigation history remain usable after commit.
let navigator = Navigator()
navigator.go(to: .label(sourceID))
navigator.openTask(open.id)
navigator.selection = [open.id]
store.onLabelsMerged = { navigator.retargetLabel(from: $0, to: $1) }
let sourceState = LabelMergePlan.LabelState(source)
let destinationState = LabelMergePlan.LabelState(destination)
let mergeObserved = OSAllocatedUnfairLock(initialState: false)
withObservationTracking { _ = open.labelIDs } onChange: { mergeObserved.withLock { $0 = true } }
try store.mergeLabels(try store.labelMergePlan(sourceID: sourceID, destinationID: destinationID))
check(mergeObserved.withLock { $0 }, "successful merge notifies observers of retained task models")
check(store.block(id: open.id) === open, "successful merge retains the live task instance")
check(exactLabel(sourceID) == nil, "source label is removed only after confirmed merge")
check(LabelMergePlan.LabelState(exactLabel(destinationID)!) == destinationState, "destination keeps every field including id, name, color and order")
check(exactLabel(duplicateID) != nil, "an unselected old duplicate is preserved")
for block in try blocks() {
    check(Metadata(block) == beforeMetadata[block.id], "merge preserves non-label task metadata: \(block.text)")
    check(!block.labelIDs.contains(sourceID), "merge rewrites every record regardless of visibility: \(block.text)")
    if block.id != unrelated.id {
        check(block.labelIDs.filter { $0 == destinationID }.count == 1, "merged destination is deduplicated: \(block.text)")
    }
}
check(completed.labelIDs == [destinationID, extraID], "a task with both labels keeps destination once and unrelated labels")
check(event.detail == "Work" && event.title == "Original task title", "merge preserves historical snapshots")
check(navigator.route == .label(destinationID), "open label view is retargeted to destination")
check(navigator.openTaskID == open.id && navigator.selection == [open.id], "retargeting preserves current task context")
check(store.label(id: sourceID)?.id == destinationID, "stale picker source id resolves to survivor")
check(!store.context.hasChanges, "merge leaves no pending partial save")
navigator.go(to: .today)
check(store.labelMergeUndo != nil, "undo survives leaving the label view")
let undoObserved = OSAllocatedUnfairLock(initialState: false)
withObservationTracking { _ = open.labelIDs } onChange: { undoObserved.withLock { $0 = true } }
check(store.undoLabelMerge(), "global merge undo succeeds after navigation")
check(undoObserved.withLock { $0 }, "successful undo notifies observers of retained task models")
check(store.allLabels().filter { $0.id == sourceID }.count == 1, "undo materializes exactly one saved source identity")
check(LabelMergePlan.LabelState(exactLabel(sourceID)!) == sourceState, "undo restores complete original source label identity and appearance")
for block in try blocks() {
    check(block.labelIDs == beforeLabels[block.id], "undo restores exact original references: \(block.text)")
    check(Metadata(block) == beforeMetadata[block.id], "undo preserves other task fields: \(block.text)")
}
check(store.label(id: sourceID)?.id == sourceID, "undo removes obsolete picker alias")
check(!store.context.hasChanges, "undo is saved atomically")

// Explicitly choose one destination when old stores already contain duplicates.
let duplicatePlan = try store.labelMergePlan(sourceID: duplicateID, destinationID: destinationID)
check(duplicatePlan.affectedTaskCount == 0, "unused duplicate labels can be deliberately merged")
try store.mergeLabels(duplicatePlan)
check(exactLabel(duplicateID) == nil && exactLabel(destinationID) != nil, "explicit duplicate merge keeps selected destination")
check(store.undoLabelMerge() && exactLabel(duplicateID) != nil, "duplicate merge remains undoable")

// Undo only owns changed references; later unrelated edits stay in place.
try store.mergeLabels(try store.labelMergePlan(sourceID: sourceID, destinationID: destinationID))
let laterID = UUID()
open.labelIDs.append(laterID)
open.text = "Edited after merge"
nested.labelIDs = [] // A deliberate removal must not be undone by label maintenance.
try store.persistChanges()
check(store.undoLabelMerge(), "undo supports later unrelated edits")
check(open.labelIDs == [sourceID, extraID, laterID], "undo preserves labels added later")
check(open.text == "Edited after merge", "undo preserves title edited later")
check(nested.labelIDs.isEmpty, "undo respects explicit removal of the merged label")
open.text = "Open"; open.labelIDs = [sourceID, extraID]; nested.labelIDs = [sourceID]
try store.persistChanges()

let history = Navigator()
history.go(to: .label(sourceID)); history.go(to: .tasks); history.goBack()
history.retargetLabel(from: sourceID, to: destinationID)
check(history.route == .label(destinationID), "history retarget updates current route")
history.goForward(); history.goBack()
check(history.route == .label(destinationID), "forward/back round trip cannot revive source route")
history.go(to: .today); history.goBack()
check(history.route == .label(destinationID), "back stack uses destination after navigation")
history.goBack(); history.retargetLabel(from: sourceID, to: destinationID); history.goForward()
check(history.route != .label(sourceID), "forward history never retains removed source identity")

// Editor undo and capture defaults can have been created in another window
// before Settings removes a label identity.
let deleted = task("Restored by editor undo", labels: [sourceID, destinationID])
let deletedID = deleted.id
let cleared = task("Labels restored by editor undo", labels: [sourceID])
try store.persistChanges()
let editorUndo = UndoManager()
editorUndo.groupsByEvent = false
editorUndo.beginUndoGrouping()
store.undoableEditorEdit(in: active.id, name: "Delete and clear labels", undoManager: editorUndo) {
    store.deleteBlock(deleted)
    store.clearLabels(on: cleared)
}
editorUndo.endUndoGrouping()
try store.mergeLabels(try store.labelMergePlan(sourceID: sourceID, destinationID: destinationID))
editorUndo.undo()
let restored = store.block(id: deletedID)!
check(restored.labelIDs == [destinationID], "pre-merge deletion undo resolves and deduplicates the old source identity")
check(cleared.labelIDs == [destinationID], "pre-merge clear-label undo restores the surviving identity")
let captured = store.captureTask(text: "Captured from an old label context", in: active,
                                defaults: CaptureDefaults(parsesNaturalLanguage: false, labelIDs: [sourceID, destinationID]))
check(captured.labelIDs == [destinationID], "pre-merge capture defaults resolve to one surviving label")
store.toggleLabel(id: sourceID, on: restored)
check(restored.labelIDs.isEmpty, "retained picker selection toggles the destination instead of resurrecting source")
store.toggleLabel(id: sourceID, on: restored)
check(restored.labelIDs == [destinationID], "retained picker can add the surviving label again")
check(store.undoLabelMerge(), "merge undo remains available after editor navigation and undo")

// A real read-only store fails after all mutations have been attempted.
let readonly = try ModelContainer(for: schema, configurations: [
    ModelConfiguration(schema: schema, url: url, allowsSave: false, cloudKitDatabase: .none)
])
let failing = Store(context: readonly.mainContext)
failing.context.autosaveEnabled = false
let failurePlan = try failing.labelMergePlan(sourceID: sourceID, destinationID: destinationID)
let retainedFailureBlocks = try blocks(failing)
let retainedFailureSource = exactLabel(sourceID, failing)!
let failureBefore = Dictionary(uniqueKeysWithValues: retainedFailureBlocks.map { ($0.id, $0.labelIDs) })
let failureMetadata = Dictionary(uniqueKeysWithValues: retainedFailureBlocks.map { ($0.id, Metadata($0)) })
var failureDidRetarget = false
failing.onLabelsMerged = { _, _ in failureDidRetarget = true }
let failureObserved = OSAllocatedUnfairLock(initialState: false)
withObservationTracking { _ = retainedFailureBlocks.map(\.labelIDs) } onChange: { failureObserved.withLock { $0 = true } }
rejected("read-only save failure rejects the entire merge") {
    try failing.mergeLabels(failurePlan)
}
check(retainedFailureSource.name == "Work" && !retainedFailureSource.isDeleted,
      "failed merge preserves the live source model immediately")
check(!failureObserved.withLock { $0 }, "failed merge never publishes a partial change to live observers")
for block in retainedFailureBlocks {
    check(block.labelIDs == failureBefore[block.id], "failed merge immediately restores retained live task references")
    check(Metadata(block) == failureMetadata[block.id], "failed merge preserves retained task metadata")
}
let labelsAfterFailure = failing.allLabels()
check(labelsAfterFailure.contains { $0.id == sourceID }, "first fetch after failed merge restores source label")
for block in try blocks(failing) { check(block.labelIDs == failureBefore[block.id], "failed merge restores every original reference") }
check(!failing.context.hasChanges, "failed merge leaves no changes for a later autosave")
check(failing.labelMergeUndo == nil && !failureDidRetarget, "failed merge never publishes success, undo, or route changes")
check(failing.label(id: sourceID)?.id == sourceID, "failed merge does not publish a stale-id alias")
rejected("read-only rename failure leaves the original name intact") { try failing.renameLabel(id: sourceID, to: "Uncommitted name") }
check(retainedFailureSource.name == "Work", "failed rename leaves the retained source name untouched")
let reopenedAfterFailure = try ModelContainer(for: schema, configurations: [configuration])
let afterFailureContext = ModelContext(reopenedAfterFailure)
let afterFailureLabels = try afterFailureContext.fetch(FetchDescriptor<TaskLabel>())
check(afterFailureLabels.contains { $0.id == sourceID }, "failed merge preserves source label on disk")
check(afterFailureLabels.first { $0.id == destinationID }?.accent == .blue, "failed merge preserves destination color on disk")
for block in try afterFailureContext.fetch(FetchDescriptor<Block>()) {
    check(block.labelIDs == failureBefore[block.id], "failed merge preserves every reference after reopening")
}

// Leave a successful merge on disk for the separate relaunch process.
let finalPlan = try store.labelMergePlan(sourceID: sourceID, destinationID: destinationID)
try store.mergeLabels(finalPlan)
let readonlyMerged = try ModelContainer(for: schema, configurations: [
    ModelConfiguration(schema: schema, url: url, allowsSave: false, cloudKitDatabase: .none)
])
let failingUndo = Store(context: readonlyMerged.mainContext)
failingUndo.context.autosaveEnabled = false
failingUndo.labelMergeUndo = finalPlan
let retainedUndoFailureBlocks = try blocks(failingUndo)
let beforeUndoFailure = Dictionary(uniqueKeysWithValues: retainedUndoFailureBlocks.map { ($0.id, $0.labelIDs) })
check(!failingUndo.undoLabelMerge(), "read-only undo failure is explicitly reported")
for block in retainedUndoFailureBlocks {
    check(block.labelIDs == beforeUndoFailure[block.id], "failed undo immediately preserves retained live references")
}
let labelsAfterUndoFailure = failingUndo.allLabels()
check(!labelsAfterUndoFailure.contains { $0.id == sourceID }, "first fetch after failed undo rolls back source insertion")
let failedUndoBlocks = try blocks(failingUndo)
check(!failedUndoBlocks.contains { $0.labelIDs.contains(sourceID) }, "failed undo leaves merged references intact")
check(!failingUndo.context.hasChanges && failingUndo.labelMergeUndo != nil, "failed undo remains retryable without partial state")
check(failingUndo.labelMaintenanceError != nil, "failed undo has understandable user feedback")
let reopenedAfterUndoFailure = try ModelContainer(for: schema, configurations: [configuration])
let afterUndoFailureContext = ModelContext(reopenedAfterUndoFailure)
let afterUndoFailureLabels = try afterUndoFailureContext.fetch(FetchDescriptor<TaskLabel>())
check(!afterUndoFailureLabels.contains { $0.id == sourceID }, "failed undo keeps source removed on disk")
let afterUndoFailureBlocks = try afterUndoFailureContext.fetch(FetchDescriptor<Block>())
check(!afterUndoFailureBlocks.contains { $0.labelIDs.contains(sourceID) }, "failed undo keeps all disk references merged")
print("✅ \(checks) label merge checks passed (merge, undo, rollback)")
