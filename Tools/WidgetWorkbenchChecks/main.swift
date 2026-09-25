import Foundation
import SwiftData

// A widget's tick, Start, Pause, Resume and Done go through the window's own
// actions: the processor is handed the app's `Workbench`, so the tray, the
// change log, Undo, subtasks and the completion dwell treat them as the
// window's rows and work controls do.

var checks = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    guard value() else { fatalError("FAIL: \(message)") }
}

let directory = URL(fileURLWithPath: CommandLine.arguments[1])
let schema = Schema([TaskList.self, Block.self, SidebarSection.self, TaskLabel.self, Attachment.self, ActivityEvent.self,
                     WorkSession.self, CompletionRecord.self, SchedulePlacement.self])
let configuration = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("Workbench.store"), cloudKitDatabase: .none)
let container = try ModelContainer(for: schema, configurations: [configuration])
let store = Store(context: container.mainContext)
store.bootstrap()
let defaults = ReviewSession.defaults
defer { defaults.removePersistentDomain(forName: ReviewSession.suiteName) }

let coordinator = CalendarCoordinator(store: store, defaults: defaults,
                                      externalCalendars: ExternalCalendarSource(defaults: defaults, fixtureBusyTimes: []))
coordinator.bootstrap(now: .now, monitorsEnabled: false)
let settings = AppSettings(defaults: defaults)
let workbench = Workbench(store: store, navigator: Navigator(defaults: defaults), settings: settings, calendar: coordinator,
                          defaults: defaults)
// As the main window installs them.
let undoManager = UndoManager()
workbench.undoManager = undoManager
workbench.installCompletionUndo()
let processor = WidgetCommandProcessor(store: store, calendar: coordinator, publisher: WidgetSnapshotPublisher(store: store),
                                       actions: workbench)

let home = store.createList(title: "Home", icon: "🏡", accent: .green, in: store.defaultSection())
var nextIndex = 0.0
func task(_ title: String, under parent: Block? = nil) -> Block {
    nextIndex += 1
    let task = Block(kind: .task, text: title, listID: home.id, parentID: parent?.id, sortIndex: nextIndex)
    store.context.insert(task)
    store.save()
    return task
}

/// A tap on the row a widget drew for `task`, made at `at`.
func tap(_ action: WidgetCommand.Action, _ task: Block, occurrence: UUID? = nil, at issuedAt: Date = .now) -> WidgetCommand {
    WidgetCommand(action: action, taskID: task.id, occurrenceID: occurrence ?? task.occurrenceID, issuedAt: issuedAt)
}

// MARK: - A tick

let move = task("Move house")
let boxes = task("Pack the boxes", under: move)
let tappedAt = Date.now.addingTimeInterval(-90)
check(processor.apply(tap(.complete, move, at: tappedAt)), "a widget tick completes the task")
check(move.isCompleted && move.completedAt == tappedAt, "dated at the tap")
check(boxes.isCompleted, "its open subtasks close with it, as a tick in the window closes them")
check(workbench.closing.isEmpty, "straight away, without the window's dwell: the widget's reload must find it done")
let tick = workbench.log.filter { $0.batch == workbench.log.first?.batch }
check(Set(tick.compactMap(\.taskID)) == [move.id, boxes.id] && tick.allSatisfy { $0.label == "2 tasks done" && $0.tone == .green },
      "the change log lists it as one change, named as the window names it")
check(workbench.tray?.text == "2 tasks done" && workbench.tray?.undoable == true, "the tray reports it, with Undo")
check(workbench.canUndo && undoManager.undoActionName == "2 tasks done", "and the window's Undo is for it")
workbench.undoLast()
check(!move.isCompleted && !boxes.isCompleted, "Undo reopens the task and its subtask")

// The window's own tick of the same rows, for the name it gives them.
workbench.complete([move.id])
check(workbench.log.first?.label == tick.first?.label && workbench.closing[move.id] != nil, "fixture: the window's tick is named alike, and dwells")
workbench.flushClosings()
check(move.isCompleted && boxes.isCompleted, "fixture: and lands")

// MARK: - The window's dwell

let ferns = task("Water the ferns")
let porch = task("Sweep the porch")
let recycling = task("Take the recycling out")
workbench.complete([porch.id])
workbench.complete([ferns.id])
workbench.beginTrash([recycling.id], label: "Deleted the recycling")
check(workbench.closing[ferns.id] != nil && !ferns.isCompleted && workbench.flying.contains(recycling.id),
      "fixture: two rows dwell after the window's ticks, and a third flies to Trash")
let logged = workbench.log.count
check(!processor.apply(tap(.complete, porch, occurrence: UUID())) && workbench.closing[porch.id] != nil && !porch.isCompleted,
      "a stale widget tap on a dwelling row leaves its dwell alone")
check(!processor.apply(tap(.complete, ferns)), "a widget tick on a row in the window's dwell adds no completion of its own")
check(ferns.isCompleted && store.completionRecords(taskID: ferns.id).count == 1 && workbench.log.count == logged,
      "the window's tick lands, once, with its one log entry")
check(workbench.closing[porch.id] != nil && !porch.isCompleted, "the window's other dwelling row keeps its dwell")
check(workbench.flying.contains(recycling.id) && recycling.trashID == nil, "and a row on its way to Trash is still flying")
workbench.flushClosings()
check(porch.isCompleted && recycling.trashID != nil, "fixture: the window's changes land")

// MARK: - Work

let report = task("Write the report")
check(processor.apply(tap(.startWork, report)) && coordinator.activeSession?.taskID == report.id, "Start records work on the task")
check(!coordinator.isWorkPanelPresented, "without opening the Work panel")
check(processor.apply(tap(.pauseWork, report)) && coordinator.activeSession == nil && workbench.workTask?.id == report.id
      && workbench.isWorkPaused, "Pause pauses the notch's work")
check(processor.apply(tap(.resumeWork, report)) && coordinator.activeSession?.taskID == report.id && !workbench.isWorkPaused,
      "Resume records again")
check(processor.apply(tap(.finishWork, report)) && report.isCompleted, "Done completes the work in progress")
check(coordinator.activeSession == nil && workbench.workTask == nil, "and takes it off the notch")
check(workbench.log.first?.taskID == report.id && workbench.canUndo, "logged and undoable, as the notch's Done is")
workbench.undoLast()
check(!report.isCompleted && workbench.workTask?.id == report.id, "Undo reopens it and offers the work to resume again")

print("✅ \(checks) widget workbench checks passed")
