import Foundation
import SwiftData

var checks = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    guard value() else { fatalError("FAIL: \(message)") }
}

let calendar = Calendar.current
func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
}
// The design's Wednesday, inside the default working hours.
let now = date(23, 10)

let directory = URL(fileURLWithPath: CommandLine.arguments[1])
let schema = Schema([TaskList.self, Block.self, SidebarSection.self, TaskLabel.self, Attachment.self, ActivityEvent.self,
                     WorkSession.self, CompletionRecord.self, SchedulePlacement.self])
let configuration = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("Actions.store"), cloudKitDatabase: .none)
let container = try ModelContainer(for: schema, configurations: [configuration])
let store = Store(context: container.mainContext)
store.bootstrap()
let defaults = ReviewSession.defaults
defer { defaults.removePersistentDomain(forName: ReviewSession.suiteName) }

// MARK: - Fixture

let inbox = store.inboxList()!
let home = store.createList(title: "Home", icon: "🏡", accent: .green, in: store.defaultSection())
let old = store.createList(title: "Old trip", icon: "🧳", accent: .brown, in: store.defaultSection())
store.setArchived(true, for: old)

var nextIndex = 0.0
func task(_ title: String, in list: TaskList = home) -> Block {
    nextIndex += 1
    let task = Block(kind: .task, text: title, listID: list.id, sortIndex: nextIndex)
    store.context.insert(task)
    store.save()
    return task
}

let plumber = task("Call the plumber")
let deposit = task("Pay the ryokan deposit")
let planters = task("Water the planters")
planters.dueDate = date(23)
planters.recurrence = .daily
let packing = task("Pack the old bags", in: old)
let report = task("File the expense report")
// Two tasks planned back to back, so running past the first one's estimate
// would move the second and has to be confirmed.
let okrs = task("Draft Q3 OKRs")
let notes = task("Write interview notes")
for (task, priority) in [(okrs, 3), (notes, 2)] {
    task.selectedForDay = now
    task.schedulingEstimateMinutes = 30
    task.priorityRaw = priority
}
store.save()
store.toggleCompletion(report, now: date(22, 9))

let external = ExternalCalendarSource(defaults: defaults, fixtureBusyTimes: [])
let coordinator = CalendarCoordinator(store: store, defaults: defaults, externalCalendars: external)
coordinator.bootstrap(now: now, monitorsEnabled: false)
let publisher = WidgetSnapshotPublisher(store: store,
    sources: .live(calendar: coordinator, settings: AppSettings(defaults: defaults), libraryID: UUID()))
let processor = WidgetCommandProcessor(store: store, calendar: coordinator, publisher: publisher)
var prepared = 0
processor.prepare = { prepared += 1 }
var settled: [UUID] = []
processor.settleWindowCompletion = { settled.append($0) }

/// A tap on the row the widget drew for `task`, or for another occurrence of it.
/// Made by the real clock unless `at` says when: that is later than every
/// fixture time, so the app takes a tick as made the moment it applies it.
/// A Start, Pause or Resume that far ahead is dropped, as from a clock set
/// back since the tap, so taps on work go through `apply`.
func tap(_ action: WidgetCommand.Action, _ task: Block? = nil, occurrence: UUID? = nil,
         at issuedAt: Date = .now) -> WidgetCommand {
    WidgetCommand(action: action, taskID: task?.id, occurrenceID: occurrence ?? task?.occurrenceID, issuedAt: issuedAt)
}

/// Applies a tap made the moment the app applies it, unless `at` says when.
func apply(_ action: WidgetCommand.Action, _ task: Block? = nil, occurrence: UUID? = nil,
           at issuedAt: Date? = nil, now: Date) -> Bool {
    processor.apply(tap(action, task, occurrence: occurrence, at: issuedAt ?? now), now: now)
}

// MARK: - Completing and reopening

check(processor.apply(tap(.complete, plumber), now: now) && plumber.isCompleted, "a tick completes the task")
check(settled == [plumber.id], "a tick first settles the window's own dwell on the row")
check(plumber.completedAt == now, "a tap stamped ahead of the app's clock counts as made now")
check(!apply(.complete, plumber, now: now), "a second tick on a done row changes nothing")
check(!apply(.complete, deposit, occurrence: UUID(), now: now) && !deposit.isCompleted,
      "a tick for another occurrence is ignored")
check(!processor.apply(WidgetCommand(action: .complete, taskID: deposit.id), now: now) && !deposit.isCompleted,
      "a tick naming no occurrence is ignored")
check(!processor.apply(WidgetCommand(action: .complete, occurrenceID: deposit.occurrenceID), now: now) && !deposit.isCompleted,
      "as is one naming no task")

let rolled = tap(.complete, planters)
check(processor.apply(rolled, now: now) && !planters.isCompleted && planters.occurrenceID != rolled.occurrenceID,
      "a tick on a repeat rolls it forward")
let nextDue = planters.dueDate
check(!processor.apply(rolled, now: now) && planters.dueDate == nextDue,
      "a stale tick never completes the repeat's next occurrence")
check(!apply(.complete, packing, now: now) && !packing.isCompleted, "tasks in archived lists are left alone")
let trashed = task("Recycle the boxes")
let trashedTap = tap(.complete, trashed)
check(store.trashBlocks([trashed]), "fixture: a task goes to Trash")
check(!processor.apply(trashedTap, now: now), "tasks in Trash are left alone")

let reopen = tap(.reopen, report)
check(processor.apply(reopen, now: now) && !report.isCompleted, "reopen restores a done row")
check(!processor.apply(reopen, now: now), "a second reopen of the same row changes nothing")
check(!apply(.reopen, deposit, now: now) && !deposit.isCompleted, "reopen on an open task is ignored")
check(!processor.apply(WidgetCommand(action: .reopen, taskID: plumber.id), now: now) && plumber.isCompleted,
      "a reopen naming no occurrence is ignored")

// MARK: - Work

check(apply(.startWork, okrs, now: now) && coordinator.activeSession?.taskID == okrs.id,
      "Start records work on the task")
check(!coordinator.isWorkPanelPresented, "Start never opens the Work panel")
check(!apply(.startWork, notes, now: date(23, 10, 5)) && coordinator.activeSession?.taskID == okrs.id,
      "Start while other work runs is ignored: switching is confirmed in the app")
check(!apply(.startWork, okrs, occurrence: UUID(), now: date(23, 10, 5)), "Start for another occurrence is ignored")

check(!apply(.pauseWork, okrs, occurrence: UUID(), now: date(23, 10, 10)) && coordinator.activeSession?.taskID == okrs.id,
      "Pause for another occurrence of the running task is ignored")
check(apply(.pauseWork, okrs, now: date(23, 10, 10)) && coordinator.activeSession == nil, "Pause stops recording")
check(coordinator.resumableTask?.id == okrs.id, "paused work stays on the toolbar timer to resume")
check(store.workSessions(taskID: okrs.id).first?.durationMinutes() == 10, "the paused segment ends at the tap")
check(!apply(.pauseWork, okrs, now: date(23, 10, 11)), "Pause with nothing running changes nothing")

check(!apply(.resumeWork, notes, now: date(23, 10, 15)) && coordinator.activeSession == nil,
      "Resume naming work other than the paused task is ignored")
check(apply(.resumeWork, okrs, now: date(23, 10, 15)) && coordinator.activeSession?.taskID == okrs.id,
      "Resume restarts the paused task")
check(!apply(.resumeWork, okrs, now: date(23, 10, 16)), "Resume while recording changes nothing")

coordinator.tick(now: date(23, 10, 35), checkClockGap: false)
check(coordinator.overrunNudge?.needsConfirmation == true && coordinator.activeSession == nil,
      "fixture: work stops at its estimate to ask before moving the next task")
check(apply(.resumeWork, okrs, now: date(23, 10, 36)) && coordinator.activeSession?.taskID == okrs.id,
      "Resume after the estimate is the go-ahead for more time, as in the toolbar")
check(coordinator.overrunNudge == nil, "and the question is answered")

check(!apply(.finishWork, notes, now: date(23, 10, 40)) && !notes.isCompleted,
      "Done for a task that is not the work in progress is ignored")
check(apply(.finishWork, okrs, now: date(23, 10, 40)) && okrs.isCompleted, "Done completes the running task")
check(coordinator.activeSession == nil && coordinator.resumableTask == nil, "and clears the toolbar timer")
check(coordinator.workCompletion?.recordedMinutes == 34, "reporting every segment's time, as Complete Current Task does")

check(apply(.startWork, notes, now: date(23, 10, 41)), "fixture: work starts on the next task")
// A widget still drawing the finished task: its buttons name that task, not the work that followed.
check(!apply(.pauseWork, okrs, now: date(23, 10, 42)) && coordinator.activeSession?.taskID == notes.id,
      "a stale Pause never stops work that started since")
check(apply(.pauseWork, notes, now: date(23, 10, 45)) && coordinator.resumableTask?.id == notes.id, "fixture: and pauses")
check(!apply(.resumeWork, okrs, now: date(23, 10, 45)) && coordinator.activeSession == nil,
      "nor does a stale Resume start recording on it")
check(apply(.finishWork, notes, now: date(23, 10, 46)) && notes.isCompleted,
      "Done completes paused work")
check(coordinator.resumeTaskID == nil, "which leaves the toolbar timer")

let review = task("Review the proposal")
let book = task("Book the Nozomi seats")
check(!processor.apply(WidgetCommand(action: .startWork, taskID: review.id), now: date(23, 10, 50))
      && coordinator.activeSession == nil, "a Start naming no occurrence is ignored")
check(apply(.startWork, review, now: date(23, 10, 50)), "fixture: work starts on a third task")
check(apply(.startWork, book, now: date(23, 10, 55)) == false, "fixture: a second Start is ignored")
check(apply(.complete, review, now: date(23, 11)) && review.isCompleted && coordinator.activeSession == nil,
      "ticking the running task off completes it and stops recording")
check(coordinator.workCompletion?.title == "Review the proposal", "it reports as finished work")
check(store.workSessions(taskID: review.id).first?.endedAt == date(23, 11), "its time is recorded up to the tap")

check(apply(.startWork, book, now: date(23, 11, 1)), "fixture: work on a fourth task")
// Every widget button names its work, so a command without ids names nothing,
// as the widget's overlay also takes it.
check(!apply(.pauseWork, now: date(23, 11, 2)) && coordinator.activeSession?.taskID == book.id,
      "a Pause naming no work is ignored, rather than pausing whatever runs")
check(!processor.apply(WidgetCommand(action: .pauseWork, taskID: book.id), now: date(23, 11, 2))
      && coordinator.activeSession?.taskID == book.id, "as is one naming the task but not its occurrence")
check(!processor.apply(WidgetCommand(action: .finishWork, taskID: book.id), now: date(23, 11, 2)) && !book.isCompleted,
      "a Done naming no occurrence is ignored")
check(!apply(.finishWork, now: date(23, 11, 2)) && !book.isCompleted, "as is one naming nothing")
check(apply(.pauseWork, book, now: date(23, 11, 2)) && coordinator.resumableTask?.id == book.id,
      "a Pause naming the running work pauses it")
check(!apply(.resumeWork, now: date(23, 11, 2)) && coordinator.activeSession == nil,
      "a Resume naming no work is ignored")
check(!processor.apply(WidgetCommand(action: .resumeWork, occurrenceID: book.occurrenceID), now: date(23, 11, 2))
      && coordinator.activeSession == nil, "as is one naming the occurrence but not the task")
check(apply(.complete, book, now: date(23, 11, 3)) && book.isCompleted && coordinator.resumeTaskID == nil,
      "ticking paused work off also takes it off the toolbar timer")

// MARK: - Late taps

// A queued tap can reach the app long after it was made, at the next launch.
let agenda = task("Draft the offsite agenda")
check(!apply(.startWork, agenda, at: date(23, 9), now: date(23, 11, 30)) && coordinator.activeSession == nil,
      "a Start from hours ago never begins recording at launch")
check(!apply(.startWork, agenda, at: date(23, 14), now: date(23, 11, 30)) && coordinator.activeSession == nil,
      "nor does one dated hours ahead, by a clock set back since the tap")
check(apply(.startWork, agenda, at: date(23, 11, 29), now: date(23, 11, 30)),
      "a Start from a moment ago does")
check(!apply(.pauseWork, agenda, at: date(23, 11, 25), now: date(23, 11, 35))
      && coordinator.activeSession?.taskID == agenda.id, "an old Pause leaves the work it never saw running")
check(apply(.pauseWork, agenda, at: date(23, 11, 34), now: date(23, 11, 35)), "fixture: a Pause from a moment ago")
check(!apply(.resumeWork, agenda, at: date(23, 11, 20), now: date(23, 11, 40)) && coordinator.activeSession == nil,
      "an old Resume never restarts it")
check(apply(.finishWork, agenda, at: date(23, 11, 36), now: date(23, 11, 40))
      && agenda.completedAt == date(23, 11, 36), "while an old Done still finishes it, as of the tap")

let queuedStart = task("Queued start")
WidgetCommandQueue.append(tap(.startWork, queuedStart, at: date(23, 11, 41)))
processor.drainQueue(now: date(23, 11, 50))
check(coordinator.activeSession == nil && WidgetCommandQueue.pending(now: date(23, 11, 50)).isEmpty,
      "a Start queued before a late drain is dropped, not replayed")

// Ticked before midnight, applied after it.
let bins = task("Take the bins out")
let lateTick = tap(.complete, bins, at: date(23, 23))
check(processor.apply(lateTick, now: date(24, 2)) && bins.completedAt == date(23, 23),
      "a late tick completes the task as of the tap")
check(store.completionRecords(taskID: bins.id).first?.completedAt == date(23, 23),
      "so Activity and done today count it on the day it was made")
let watering = task("Water the ferns")
watering.dueDate = date(23)
watering.recurrence = Recurrence(frequency: .daily, interval: 1, anchor: .completionDate)
store.save()
check(apply(.complete, watering, at: date(23, 23), now: date(24, 2)) && watering.dueDate == date(24),
      "and a repeat that runs from completion rolls forward from the tap")

let late = task("Plan the weekend")
coordinator.notice = nil
check(!apply(.startWork, late, now: date(23, 22)) && coordinator.activeSession == nil,
      "Start outside the list's hours is refused")
check(coordinator.notice == nil, "without leaving the refusal for the Work panel to show later")
check(!coordinator.isWorkPanelPresented, "and without opening the Work panel")

// MARK: - The queue

let snapshotURL = AppGroup.snapshotURL!
let queuedDone = task("Queued tick")
let queuedStale = task("Queued stale tick")
WidgetCommandQueue.append(tap(.complete, queuedDone))
WidgetCommandQueue.append(tap(.complete, queuedStale, occurrence: UUID()))
check(WidgetCommandQueue.pending().count == 2, "fixture: the extension queued two taps")
try? FileManager.default.removeItem(at: snapshotURL)
prepared = 0
processor.drainQueue(now: date(23, 11, 5))
check(queuedDone.isCompleted && !queuedStale.isCompleted, "draining applies valid taps and ignores stale ones")
check(WidgetCommandQueue.pending().isEmpty, "every drained tap leaves the queue")
check(prepared == 1, "draining bootstraps first")
check(FileManager.default.fileExists(atPath: snapshotURL.path), "draining rewrites the snapshot")
check(WidgetSnapshotStore.read()?.lists.first { $0.id == home.id }?.doneItems.contains { $0.id == queuedDone.id } == true,
      "which shows the queued tick")
prepared = 0
processor.drainQueue()
check(prepared == 0, "an empty queue costs nothing")

// In-app intents apply what was queued first: a tick, then a reopen, not the other way round.
let toggled = task("Tick then reopen")
let toggledOccurrence = toggled.occurrenceID
WidgetCommandQueue.append(tap(.complete, toggled))
try? FileManager.default.removeItem(at: snapshotURL)
processor.handle(tap(.reopen, toggled, occurrence: toggledOccurrence), now: date(23, 11, 10))
check(!toggled.isCompleted && toggled.occurrenceID != toggledOccurrence, "an in-app intent applies earlier queued taps first")
check(WidgetCommandQueue.pending().isEmpty, "and takes them off the queue")
check(prepared == 1 && FileManager.default.fileExists(atPath: snapshotURL.path),
      "it bootstraps, and rewrites the snapshot before the intent returns")

/// Runs the main run loop until `condition` holds, for work that arrives
/// through a notification or a hop to the main actor.
func wait(until condition: () -> Bool) -> Bool {
    let deadline = Date.now.addingTimeInterval(5)
    while !condition(), Date.now < deadline { RunLoop.main.run(until: .now.addingTimeInterval(0.05)) }
    return condition()
}

WidgetCommandRouter.handler = { command in processor.handle(command) }
let dispatched = task("Dispatched tick")
var didDispatch = false
Task { didDispatch = await WidgetCommandRouter.dispatch(tap(.complete, dispatched)) }
check(wait { didDispatch } && dispatched.isCompleted, "the command router hands an in-app intent to the processor")

processor.listenForSignals()
let signalled = task("Signalled tick")
WidgetCommandQueue.append(tap(.complete, signalled))
WidgetCommandSignal.post()
check(wait { signalled.isCompleted } && WidgetCommandQueue.pending().isEmpty,
      "the extension's signal drains the queue in a running app")

// MARK: - Links

final class Screens: WidgetLinkScreens {
    let navigator: Navigator
    var inspected: [UUID] = []
    init(navigator: Navigator) { self.navigator = navigator }
    func go(_ route: AppRoute) { navigator.go(to: route) }
    func route(for list: TaskList) -> AppRoute { list.isSystemInbox ? .inbox : .list(list.id) }
    func inspect(_ id: UUID?) {
        if let id { inspected.append(id) }
        navigator.openTask(id)
    }
}

let navigator = Navigator(defaults: defaults)
navigator.inboxListID = inbox.id
let screens = Screens(navigator: navigator)
let router = WidgetLinkRouter(store: store, navigator: navigator, screens: screens)
var captures: [TaskCaptureRequest] = []
router.capture = { captures.append($0) }
func open(_ link: WidgetLink) { router.receive(link.url) }

// A cold launch: the link arrives before bootstrap puts the app on Today.
open(.calendar)
navigator.replace(with: .today)
check(navigator.route == .today, "a link waits for the library")
router.storeReady()
check(navigator.route == .today, "and for the main window")
router.windowReady(true)
check(navigator.route == .calendar, "then lands after bootstrap, which would otherwise overwrite it")

open(.inbox)
check(navigator.route == .inbox, "Inbox opens the Inbox")
navigator.setListViewMode(.document, for: inbox.id)
open(.today)
check(navigator.route == .today, "Today opens Today")
open(.triage)
check(navigator.route == .inbox && navigator.listViewMode(for: inbox.id) == .tasks && !navigator.hasDocumentEditor,
      "Triage opens the Inbox's card view, even when the Inbox was a document")
check(Navigator(defaults: defaults).listViewMode(for: inbox.id) == .document,
      "for this visit only: the Inbox's saved presentation stays a document")
open(.today)
open(.inbox)
check(navigator.hasDocumentEditor, "so the Inbox opens as its document again next time")
navigator.selection = [deposit.id]
open(.triage)
check(navigator.route == .inbox && !navigator.hasDocumentEditor && navigator.selection.isEmpty,
      "Triage from the Inbox's own document turns it to the cards, leaving the document's selection behind")
navigator.setListViewMode(.document, for: inbox.id)
check(navigator.hasDocumentEditor, "Show as Document from the cards goes back to the document")
open(.triage)
navigator.setListViewMode(.tasks, for: inbox.id)
open(.today)
open(.inbox)
check(!navigator.hasDocumentEditor && Navigator(defaults: defaults).listViewMode(for: inbox.id) == .tasks,
      "choosing Tasks while triaging is a choice, and it is kept")
navigator.setListViewMode(.document, for: inbox.id)
open(.activity)
check(navigator.route == .activity, "Activity opens Activity")
open(.list(home.id))
check(navigator.route == .list(home.id), "a list link opens the list")
open(.list(inbox.id))
check(navigator.route == .inbox, "the Inbox list opens through the screens' own route")
open(.list(UUID()))
check(navigator.route == .inbox, "a missing list changes nothing")

open(.task(deposit.id))
check(navigator.route == .list(home.id) && navigator.openTaskID == deposit.id && screens.inspected == [deposit.id],
      "a task link opens its list and inspects the task")
open(.task(trashed.id))
check(navigator.route == .list(home.id) && navigator.openTaskID == deposit.id, "a task in Trash changes nothing")
navigator.isShortcutSheetOpen = true
open(.today)
check(navigator.route == .today && !navigator.isShortcutSheetOpen, "navigating closes the shortcut sheet")

open(.capture(listID: nil))
check(captures.count == 1 && captures[0].suggestedListID == nil && !captures[0].appendsToSuggestedList,
      "Quick Add opens on the Inbox")
check(!captures[0].startsInSuggestedList, "and leaves a draft on screen where it is")
open(.capture(listID: home.id))
check(captures.count == 2 && captures[1].suggestedListID == home.id && captures[1].startsInSuggestedList
      && captures[1].appendsToSuggestedList, "Add to a list files into that list, at the end as from its Tasks screen")
check(captures[1].appendsToRoot(of: home, suggested: home), "while the task goes into that list")
check(!captures[1].appendsToRoot(of: inbox, suggested: home),
      "but not once it goes elsewhere: another list picked, or the Inbox when the list is archived or deleted")
check(!captures[1].appendsToRoot(of: inbox, suggested: nil), "or when the list is gone")
check(!captures[0].dueTodayWhenUndated && !captures[1].dueTodayWhenUndated, "neither dates what is typed")
check(!captures[0].undatedTaskIsDueToday(newTasksGoTo: .inbox) && captures[0].undatedTaskIsDueToday(newTasksGoTo: .today),
      "an undated task from Quick Add follows the New tasks setting")
open(.captureToday)
check(captures.count == 3 && captures[2].dueTodayWhenUndated && captures[2].suggestedListID == nil
      && !captures[2].appendsToSuggestedList, "New task on the Today widget captures into the Inbox, for Today")
check(captures[2].undatedTaskIsDueToday(newTasksGoTo: .inbox),
      "which makes an undated task due today, as the app's Today does, whatever the New tasks setting")
let fromToday = TaskCaptureDraft(text: "Call bank", dueTodayWhenUndated: captures[2].undatedTaskIsDueToday(newTasksGoTo: .inbox))
check(fromToday.preview.date == calendar.startOfDay(for: .now), "so a task typed there without a date is due today")
check(!TaskCaptureRequest(plansForToday: true, dueTodayWhenUndated: true).undatedTaskIsDueToday(newTasksGoTo: .today),
      "a task planned for today stays undated")
open(.capture(listID: inbox.id))
check(captures.count == 4 && captures[3].suggestedListID == inbox.id && captures[3].startsInSuggestedList
      && !captures[3].appendsToSuggestedList,
      "Add to Inbox starts in the Inbox, moving a draft aimed elsewhere, and prepends as every Inbox capture does")
check(!TaskCaptureRequest(suggestedListID: inbox.id, appendsToSuggestedList: true).appendsToRoot(of: inbox, suggested: inbox),
      "the Inbox never appends, whoever asks")
check(navigator.route == .today, "capture leaves the main window where it was")

for text in ["openlist-dev://widget/today", "openlist://widget/unknown", "openlist://widget/activity?from=widget",
             "openlist://widget/task/not-a-task", "openlist://widget/capture/list", "OPENLIST://WIDGET/calendar/extra"] {
    let url = URL(string: text)!
    check(WidgetLink.isWidgetLink(url), "\(text) is claimed before item-link handling")
    check(!router.receive(url), "\(text) is not one this build opens")
}
check(navigator.route == .today && captures.count == 4, "malformed links and the other build's are dropped")

// A widget link pasted into a task note gets a button, which the widget
// router opens; one it cannot open goes on to item links for their notice.
let pasted = WidgetLink.calendar.url
check(NoteItemLink.references(in: "Plan it on \(pasted.absoluteString) first").map(\.url) == [pasted],
      "a widget link in a task note gets a button")
check(router.receive(pasted) && navigator.route == .calendar, "which opens what the widget would")
let broken = URL(string: "openlist://widget/bogus")!
check(NoteItemLink.references(in: broken.absoluteString).count == 1 && !router.receive(broken),
      "a broken one is left to item links")
do { _ = try LocalLink.parse(broken); check(false, "item links refuse a widget link") }
catch { check(error as? LocalLinkError == .unsupported, "whose notice says it cannot be opened") }
open(.today)
check(!WidgetLink.isWidgetLink(URL(string: "openlist://v1/\(UUID())/task/\(UUID())")!), "item links keep their own handling")

router.windowReady(false)
open(.calendar)
check(navigator.route == .today, "with the main window closed, a link waits")
router.windowReady(true)
check(navigator.route == .calendar, "and lands once the window is back")

print("✅ \(checks) widget action checks passed")
