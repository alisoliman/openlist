import Foundation
import SwiftData

var checks = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    guard value() else { fatalError("FAIL: \(message)") }
}

var calendar = Calendar.current
calendar.firstWeekday = 2
func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0, month: Int = 9) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
}
// The design's "now": Wednesday 23 September 2026, 10:40.
let now = date(23, 10, 40)

let directory = URL(fileURLWithPath: CommandLine.arguments[1])
let schema = Schema([TaskList.self, Block.self, SidebarSection.self, TaskLabel.self, Attachment.self, ActivityEvent.self,
                     WorkSession.self, CompletionRecord.self, SchedulePlacement.self])
let configuration = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("Widget.store"), cloudKitDatabase: .none)
let container = try ModelContainer(for: schema, configurations: [configuration])
let store = Store(context: container.mainContext)
store.bootstrap()
let defaults = ReviewSession.defaults
defer { defaults.removePersistentDomain(forName: ReviewSession.suiteName) }

// MARK: - Fixture

let inbox = store.inboxList()!
let mine = store.defaultSection()!
let workSection = SidebarSection(title: "Work", sortIndex: 1)
store.context.insert(workSection)
func list(_ title: String, _ icon: String, _ accent: ListAccent, section: SidebarSection?, index: Double, pinned: Bool? = nil) -> TaskList {
    let list = store.createList(title: title, icon: icon, accent: accent, in: section)
    list.sectionID = section?.id
    list.isPinned = pinned ?? (section != nil)
    list.sidebarIndex = index
    store.save()
    return list
}
let home = list("Home", "🏡", .green, section: mine, index: 2)
let kyoto = list("Weekend in Kyoto", "🗻", .violet, section: mine, index: 1)
let q3 = list("Q3 planning", "💼", .blue, section: workSection, index: 0)
let hiring = store.createChildList(in: q3)!
hiring.title = "Hiring loop"
hiring.icon = "🎯"
hiring.accent = .pink
let someday = list("Someday", "💭", .graphite, section: nil, index: 0)
let errands = list("Errands", "🛒", .amber, section: nil, index: 5, pinned: true)
let old = list("Old trip", "🧳", .brown, section: mine, index: 0)
store.setArchived(true, for: old)

@discardableResult
func task(_ title: String, in list: TaskList, under parent: Block? = nil, index: Double = 0,
          due: Date? = nil, time: Bool = false) -> Block {
    let task = Block(kind: .task, text: title, listID: list.id, parentID: parent?.id, sortIndex: index)
    task.dueDate = due
    task.includesTime = time
    store.context.insert(task)
    return task
}

// Home holds the day's due work: ten long-overdue tasks push the list past its cap.
for day in 10..<20 { task("Overdue \(day)", in: home, index: Double(day), due: date(day)) }
let retro = task("Close out Q2 retro actions", in: home, index: 20, due: date(20))
let plumber = task("Call the plumber", in: home, index: 21, due: date(23, 9), time: true)
let deposit = task("Pay the ryokan deposit", in: home, index: 22, due: date(23))
let keys = task("Pick up the keys", in: home, index: 23, due: date(23, 18), time: true)
let passports = task("Renew passports", in: home, index: 24, due: date(24))

// Kyoto has an outline: a subtask, a task under a heading, and a repeat.
let planters = task("Water the planters", in: kyoto, index: 0.5, due: date(23))
planters.recurrence = .daily
var kyotoOpen: [Block] = []
for index in 1...14 {
    let row = task("Kyoto \(index)", in: kyoto, index: Double(index))
    kyotoOpen.append(row)
    if index == 1 { kyotoOpen.append(task("Kyoto 1a", in: kyoto, under: row, index: 1)) }
    if index == 7 {
        let heading = Block(kind: .heading2, text: "Tickets", listID: kyoto.id, sortIndex: 7.5)
        store.context.insert(heading)
        // A low index only lands in the right place if the heading is part of the outline.
        kyotoOpen.append(task("Book the Nozomi seats", in: kyoto, under: heading, index: 0.1))
    }
}
let doneDates = [date(23, 9), date(23, 9, 5), date(22, 15), date(22, 16), date(21, 11), date(20, 11),
                 date(18, 11), date(1, 11), date(31, 11, month: 8)]
let done = doneDates.indices.map { task("Done \($0 + 1)", in: kyoto, index: Double(200 + $0)) }

// Inbox captures, oldest last, with a subtask that triage never shows.
var captures: [Block] = []
for hour in 0..<8 {
    let capture = task("Capture \(hour)", in: inbox, index: Double(hour))
    capture.createdAt = date(23, 8 - hour)
    captures.append(capture)
}
let captureStep = task("Capture step", in: inbox, under: captures[0], index: 1)
captureStep.createdAt = date(23, 9)

let okrs = task("Draft Q3 OKRs", in: q3, index: 1)
okrs.schedulingEstimateMinutes = 45
task("Write interview feedback", in: hiring, index: 1)
task("Pack the old bags", in: old, index: 1)
store.save()

// Done 3 and Done 6 were ticked off in their calendar slots, which the Calendar
// keeps drawing done; a tick with no slot or recorded work leaves nothing there.
store.calendarPlannedBlocks = [2, 5].map { index in
    PlannedBlock(id: "slot-\(index)", taskID: done[index].id, occurrenceID: done[index].occurrenceID,
                 start: doneDates[index].addingTimeInterval(-1800), end: doneDates[index], isPinned: false,
                 placementID: nil, conflicts: [])
}
for (task, completedAt) in zip(done, doneDates) { store.toggleCompletion(task, now: completedAt) }
store.calendarPlannedBlocks = []
let plantersOccurrence = planters.occurrenceID
store.toggleCompletion(planters, now: date(23, 9, 30))
check(!planters.isCompleted && planters.occurrenceID != plantersOccurrence, "the fixture repeat rolls forward to a new occurrence")

// MARK: - Store-only snapshot

let libraryID = UUID()
let settings = AppSettings(defaults: defaults)
settings.firstWeekday = 2
settings.accent = .green
settings.serifTitles = false
let events = [
    FixedBusyTime(id: "standup", title: "Standup", start: date(21, 9, 30), end: date(21, 10)),
    FixedBusyTime(id: "board", title: "Board prep", start: date(23, 14), end: date(23, 15)),
    FixedBusyTime(id: "offsite", title: "Offsite", start: date(24), end: date(25)),
    FixedBusyTime(id: "next-week", title: "Planning", start: date(28, 9, 30), end: date(28, 10)),
]
let external = ExternalCalendarSource(defaults: defaults, fixtureBusyTimes: events)
let coordinator = CalendarCoordinator(store: store, defaults: defaults, externalCalendars: external)
var widgetStateChanges = 0
coordinator.onWidgetStateChange = { widgetStateChanges += 1 }
coordinator.bootstrap(now: date(23, 9, 55), monitorsEnabled: false)
check(widgetStateChanges > 0, "publishing the first plan tells the widgets")
store.setPlacement(for: okrs, start: date(23, 10), end: date(23, 10, 45), isPinned: true)
coordinator.replan(now: date(23, 9, 55))

let plain = WidgetSnapshotPublisher(store: store)
let bare = plain.buildSnapshot(now: now)
check(bare.work == nil && bare.agenda.isEmpty && bare.libraryID == nil, "empty sources publish no calendar, work or library")
check(bare.accentHex == 0x7C4DF0 && bare.serifTitles, "empty sources publish the app's default appearance")

let publisher = WidgetSnapshotPublisher(store: store,
    sources: .live(calendar: coordinator, settings: settings, libraryID: libraryID))
let snapshot = publisher.buildSnapshot(now: now)

check(snapshot.version == WidgetSnapshot.currentVersion, "the snapshot declares the current schema")
check(snapshot.libraryID == libraryID, "the library ID is published for item links")
check(snapshot.accentHex == 0x1F8A6D && !snapshot.serifTitles, "appearance follows the app's settings")
check(NextAccent.allCases.map(\.hex) == [0x7C4DF0, 0x2F6FE0, 0x1F8A6D, 0xC2532B] && snapshot.accentHex == settings.accent.hex,
      "the published accent is the app's own, from the one definition its colour is built from")
check(snapshot.firstWeekday == 2, "the settings' first weekday is published")

// Today
let expectedToday = (10..<20).map { "Overdue \($0)" } + [retro.displayTitle, deposit.displayTitle]
check(snapshot.todayItems.map(\.title) == expectedToday, "today holds overdue then due work, soonest first, capped at 12")
check(snapshot.overdueCount == 12 && snapshot.dueTodayCount == 2, "counts include the rows past the cap")
check(!snapshot.todayItems.contains { $0.id == plumber.id || $0.id == keys.id }, "the cap drops the latest rows")
check(snapshot.dueToday == [WidgetSnapshot.Due(date: date(23), includesTime: false), WidgetSnapshot.Due(date: date(23, 18), includesTime: true)],
      "every task behind the due-today count is published, past the rows' cap, so each can turn late on time")
// Tomorrow
check(Set(snapshot.tomorrowItems.map(\.id)) == [passports.id, planters.id],
      "tomorrow's rows are the open work due tomorrow, a repeat's next occurrence included")
check(snapshot.dueTomorrow == [WidgetSnapshot.Due(date: date(24), includesTime: false), WidgetSnapshot.Due(date: date(24), includesTime: false)],
      "every task due tomorrow is published with its date")
check(!snapshot.todayItems.contains { $0.id == passports.id || $0.id == planters.id }, "tomorrow's work is not in today's rows")
check(snapshot.tomorrowItems.first { $0.id == planters.id }.map { $0.listName == "Weekend in Kyoto" && $0.occurrenceID == planters.occurrenceID } == true,
      "tomorrow's rows carry their list and occurrence, as today's do")
let firstToday = snapshot.todayItems[0]
check(firstToday.listID == home.id && firstToday.listName == "Home" && firstToday.listIcon == "🏡", "rows carry their list")
check(firstToday.accentHex == ListAccent.green.hex, "rows carry their list's colour")
check(snapshot.todayItems.allSatisfy { item in
    store.block(id: item.id)?.occurrenceID == item.occurrenceID
}, "rows carry the occurrence a tap would complete")

// Inbox
check(snapshot.inboxCount == 8, "the Inbox count is the triage queue, as the Inbox badge counts it")
check(snapshot.inboxItems.map(\.title) == (0..<6).map { "Capture \($0)" }, "Inbox rows are newest first, capped at 6")
check(!snapshot.inboxItems.contains { $0.id == captureStep.id }, "a subtask goes with the open task above it, whose card carries it")
// A subtask under done tasks only is a card of its own, or triage could never reach it.
let doneCapture = task("Done capture", in: inbox, index: 20)
let orphanStep = task("Step left open", in: inbox, under: doneCapture, index: 1)
orphanStep.createdAt = date(23, 9, 30)
store.save()
store.toggleCompletion(doneCapture, now: date(23, 9, 40))
if orphanStep.isCompleted { store.toggleCompletion(orphanStep, now: date(23, 9, 41)) }
let orphaned = publisher.buildSnapshot(now: now)
check(orphaned.inboxCount == 9 && orphaned.inboxItems.first?.id == orphanStep.id,
      "a subtask whose tasks above are done waits in triage itself")
store.trashBlocks([orphanStep, doneCapture])

// Counts
check(snapshot.totalOpenCount == 15 + 17 + 9 + 1 + 1, "open work counts active lists only, subtasks included")
check(snapshot.completedTodayCount == 2, "done today leaves out the rolled-forward repeat, as the app's Today does")
check(snapshot.activity.today == snapshot.completedTodayCount + 1, "the heatmap still counts the repeat's finished occurrence")

// Lists
check(snapshot.lists.map(\.title) == ["Inbox", "Weekend in Kyoto", "Home", "Q3 planning", "Hiring loop", "Errands", "Someday"],
      "lists follow the sidebar: Inbox, sections, nested lists after their parent, then the rest")
check(!snapshot.lists.contains { $0.id == old.id }, "archived lists are left out")
let inboxSummary = snapshot.lists[0]
check(inboxSummary.isInbox && inboxSummary.path == "Inbox" && inboxSummary.icon == "📥", "Inbox is marked and has its own glyph")
check(inboxSummary.accentHex == ListAccent.inboxHex && inboxSummary.openCount == 9, "Inbox uses the app's Inbox blue and counts its subtasks")
check(snapshot.lists[4].path == "Q3 planning › Hiring loop" && snapshot.lists[4].accentHex == ListAccent.pink.hex, "nested lists carry their path")
let kyotoSummary = snapshot.list(id: kyoto.id)!
check(kyotoSummary.openCount == 17 && kyotoSummary.doneCount == 9, "list counts cover every row, not just the published ones")
check(kyotoSummary.openItems.map(\.id) == ([planters] + kyotoOpen.prefix(11)).map(\.id), "open rows follow the list's outline, capped at 12")
check(kyotoSummary.openItems.contains { $0.title == "Book the Nozomi seats" }, "a task under a heading keeps its place in the outline")
let repeatRow = kyotoSummary.openItems[0]
check(repeatRow.hasRepeat && repeatRow.occurrenceID == planters.occurrenceID && repeatRow.occurrenceID != planters.id,
      "a repeat's row carries its current occurrence")
check(kyotoSummary.doneItems.map(\.title) == ["Done 2", "Done 1", "Done 4", "Done 3", "Done 5", "Done 6"],
      "done rows are most recent first, capped at 6")
check(kyotoSummary.doneItems.allSatisfy { $0.isCompleted && $0.completedAt != nil }, "done rows carry their completion")
check(snapshot.list(id: nil)?.id == kyoto.id, "an unconfigured List widget falls back to the first real list")
// A list's Sort reorders each run of top-level tasks between its headings and
// prose, as the list's page draws it, each task's subtasks going with it.
store.setSorting(.alphabetical, for: kyoto)
check(publisher.buildSnapshot(now: now).list(id: kyoto.id)?.openItems.prefix(10).map(\.id)
      == (kyotoOpen.prefix(8) + [planters, kyotoOpen[8]]).map(\.id),
      "a sorted list's rows follow its page: the run before the heading sorted, a subtask under its parent, the heading's task after it")
store.setSorting(.dueDate, for: kyoto)
check(publisher.buildSnapshot(now: now).list(id: kyoto.id)?.openItems.map(\.id) == kyotoSummary.openItems.map(\.id),
      "sorted by due date, the dated repeat leads its run and the undated tasks keep their outline order")
store.setSorting(.manual, for: kyoto)

// Activity
let activity = snapshot.activity
check(activity.days.count == 143 && activity.days.first?.date == date(4, month: 5), "activity covers 21 weeks aligned to Monday")
check(activity.days.last?.date == date(23) && activity.days.last?.count == 3, "the last day is today, repeats included")
check(activity.today == 3 && activity.week == 6 && activity.month == 9, "today, this week and this month")
check(activity.streak == 4, "the streak runs back to the first empty day")
let screenStreak = try store.activityHeatmap(now: now, calendar: calendar).streak
check(screenStreak == activity.streak, "the widget's streak is the Activity screen's, whichever weeks each shows")
check(activity.monthName == calendar.standaloneMonthSymbols[8], "the month is named for the widget")
let thursday = publisher.buildSnapshot(now: date(24, 8))
check(thursday.activity.today == 0 && thursday.activity.streak == 4, "a day not yet worked does not break the streak")
check(thursday.completedTodayCount == 0, "done today resets with the day")
check(thursday.dueToday == snapshot.dueTomorrow && thursday.dueTodayCount == snapshot.dueTomorrow.count,
      "what Wednesday publishes for tomorrow is what Thursday's snapshot has due, so a widget can start the day without the app")

// Agenda
check(snapshot.weekStart == date(21), "the agenda week starts on the settings' first weekday")
check(zip(snapshot.agenda, snapshot.agenda.dropFirst()).allSatisfy { $0.start <= $1.start }, "the agenda is sorted by start")
let meetings = snapshot.agenda.filter { $0.kind == .meeting }.map(\.id)
check(meetings == ["standup", "board"], "meetings earlier in the week are kept; all-day time and next week are not")
let okrsBlock = snapshot.agenda.first { $0.taskID == okrs.id }
check(okrsBlock?.start == date(23, 10) && okrsBlock?.end == date(23, 10, 45), "planned blocks come from the calendar plan")
check(okrsBlock?.listName == "Q3 planning" && okrsBlock?.accentHex == ListAccent.blue.hex && okrsBlock?.occurrenceID == okrs.occurrenceID,
      "planned blocks carry their task and list")
check(snapshot.agenda.contains { $0.title == "Done 3" && $0.isCompleted }, "completed work from earlier in the week is kept")
check(!snapshot.agenda.contains { $0.title == "Done 6" }, "last week's completions are not")

// MARK: - Work

check(snapshot.work == nil, "nothing is shown as working before Start")
let beforeStart = widgetStateChanges
check(coordinator.start(task: okrs, now: date(23, 10)), "the fixture starts work")
check(widgetStateChanges > beforeStart, "starting work tells the widgets")
let started = publisher.buildSnapshot(now: date(23, 10, 5))
let firstSegment = started.work
check(firstSegment?.state == .working && firstSegment?.taskID == okrs.id && firstSegment?.occurrenceID == okrs.occurrenceID,
      "running work is published")
check(firstSegment?.segmentStartedAt == date(23, 10) && firstSegment?.priorSeconds == 0, "the running segment starts at Start")
check(firstSegment?.estimateMinutes == 45 && firstSegment?.accentHex == ListAccent.blue.hex, "the estimate and colour match the toolbar")
check(firstSegment?.blockStart == date(23, 10) && firstSegment?.blockEnd == date(23, 10, 45), "the block is the slot work was started in")
check(started.agenda.contains { $0.taskID == okrs.id && $0.isActive }, "the agenda marks the running block")

let beforePause = widgetStateChanges
coordinator.pause(now: date(23, 10, 10))
check(widgetStateChanges > beforePause, "pausing tells the widgets")
let paused = publisher.buildSnapshot(now: date(23, 10, 12)).work
check(paused?.state == .paused && paused?.segmentStartedAt == nil && paused?.priorSeconds == 600, "paused work keeps its recorded time")
check(paused?.blockStart == date(23, 10) && paused?.blockEnd == date(23, 10, 45), "paused work shows the slot it was interrupted in")
// The rest moves to Friday: a slot on another day never reads as a time today.
let pinned = store.placements(taskID: okrs.id).first!
store.setPlacement(for: okrs, start: date(25, 14), end: date(25, 14, 35), isPinned: true, placementID: pinned.id)
coordinator.replan(now: date(23, 10, 12))
check(coordinator.plannedWork(WorkTaskReference(okrs), now: date(23, 10, 12))?.start == date(25, 14), "the fixture plans the rest for Friday")
let pausedToday = publisher.buildSnapshot(now: date(23, 10, 12)).work
check(pausedToday?.blockStart == date(23, 10) && pausedToday?.blockEnd == date(23, 10, 45), "the interrupted slot is kept while the rest is planned days ahead")
let pausedThursday = publisher.buildSnapshot(now: date(24, 9)).work
check(pausedThursday?.state == .paused && pausedThursday?.blockStart == nil && pausedThursday?.blockEnd == nil,
      "yesterday's slot and Friday's block are both left out on Thursday")
let pausedFriday = publisher.buildSnapshot(now: date(25, 9)).work
check(pausedFriday?.blockStart == date(25, 14) && pausedFriday?.blockEnd == date(25, 14, 35), "on the day of the next block, that block stands in")
store.setPlacement(for: okrs, start: date(23, 10), end: date(23, 10, 45), isPinned: true, placementID: pinned.id)
coordinator.replan(now: date(23, 10, 12))

check(coordinator.start(task: okrs, now: date(23, 10, 30)), "the fixture resumes work")
let resumed = publisher.buildSnapshot(now: now)
check(resumed.work?.segmentStartedAt == date(23, 10, 30) && resumed.work?.priorSeconds == 600, "earlier segments are prior time")
check(resumed.work?.timerOrigin == date(23, 10, 20) && resumed.work?.elapsed(at: now) == 1200, "the timer counts the whole occurrence")
var announcedSaves = 0
store.onDidSave = { announcedSaves += 1 }
store.heartbeatWorkSession(coordinator.activeSession!, now: date(23, 10, 41))
check(coordinator.activeSession?.lastHeartbeatAt == date(23, 10, 41) && !store.context.hasChanges, "the heartbeat is saved")
check(announcedSaves == 0, "a heartbeat alone saves without announcing, so a running session does not rebuild the snapshot every minute")
check(publisher.buildSnapshot(now: date(23, 10, 41).addingTimeInterval(30)) == resumed,
      "a heartbeat leaves the snapshot equal, so the widgets are not reloaded every minute")
someday.summary = "Maybe later"
store.heartbeatWorkSession(coordinator.activeSession!, now: date(23, 10, 42))
check(announcedSaves == 1 && !store.context.hasChanges, "an edit the heartbeat saves along with it is announced as usual")
store.onDidSave = nil

// MARK: - Writing

let url = AppGroup.snapshotURL!
publisher.refreshNow()
check(FileManager.default.fileExists(atPath: url.path), "a refresh writes the snapshot")
let written = WidgetSnapshotStore.read()
check(written?.lists.map(\.id) == publisher.buildSnapshot().lists.map(\.id) && written?.work?.state == .working,
      "the written file decodes to the snapshot")
try FileManager.default.removeItem(at: url)
publisher.refreshNow()
check(!FileManager.default.fileExists(atPath: url.path), "an unchanged snapshot is not rewritten")
publisher.refreshNow(force: true)
check(FileManager.default.fileExists(atPath: url.path), "a forced refresh rewrites it anyway")

publisher.prepareForTermination(now: date(23, 10, 50))
let quit = WidgetSnapshotStore.read()?.work
check(quit?.state == .paused && quit?.segmentStartedAt == nil && quit?.timerOrigin == nil, "quitting writes running work as paused")
check(quit?.priorSeconds == 1800 && quit?.taskID == okrs.id, "the paused time includes the running segment")
coordinator.pause(reason: "Openlist closed", now: date(23, 10, 50))
let closed = publisher.buildSnapshot(now: date(23, 10, 51)).work
check(closed?.state == .paused && closed?.priorSeconds == quit?.priorSeconds, "the quit snapshot matches the pause the app then records")
coordinator.dismissResume()
check(publisher.buildSnapshot(now: date(23, 10, 52)).work == nil, "stopped work leaves the widgets")

// MARK: - Done today

// Done today follows current state, exactly as the app's Today counts it,
// while the Activity heatmap counts the completions that still stand, as the
// Activity screen does: an Undo or a reopen takes one back.
let noon = date(23, 12)
let dayStart = publisher.buildSnapshot(now: noon)
func doneToday() -> Int { publisher.buildSnapshot(now: noon).completedTodayCount }
store.toggleCompletion(deposit, now: date(23, 11))
let completedDeposit = publisher.buildSnapshot(now: noon)
check(completedDeposit.completedTodayCount == dayStart.completedTodayCount + 1 && completedDeposit.dueTodayCount == dayStart.dueTodayCount - 1,
      "completing a task due today moves it to done")
store.toggleCompletion(deposit, now: date(23, 11, 1))
let reopenedDeposit = publisher.buildSnapshot(now: noon)
check(reopenedDeposit.completedTodayCount == dayStart.completedTodayCount && reopenedDeposit.dueTodayCount == dayStart.dueTodayCount,
      "reopening it takes it off done again")
check(reopenedDeposit.activity.today == dayStart.activity.today, "and off the heatmap, as the Activity screen counts it")
store.toggleCompletion(deposit, now: date(23, 11, 2))
let undidDeposit = store.undoCompletion(store.completionUndo!.id)
check(undidDeposit && !deposit.isCompleted, "the fixture undoes a completion")
check(doneToday() == dayStart.completedTodayCount, "an undone completion is not done")
let finishedTuesday = done[2]
store.toggleCompletion(finishedTuesday, now: date(23, 11, 3))
store.toggleCompletion(finishedTuesday, now: date(23, 11, 4))
check(finishedTuesday.isCompleted && doneToday() == dayStart.completedTodayCount + 1,
      "a task first finished on an earlier day, reopened and finished again today is done today")
store.toggleCompletion(planters, now: date(23, 11, 5))
check(!planters.isCompleted && doneToday() == dayStart.completedTodayCount + 1,
      "a repeat finished today is not done today: it rolled forward and is open, as in the app's Today")
let beforeUndo = publisher.buildSnapshot(now: noon)
let undidRepeat = store.undoCompletion(store.completionUndo!.id)
check(undidRepeat, "the fixture undoes the repeat's roll-forward")
let undoneRepeat = publisher.buildSnapshot(now: noon)
check(undoneRepeat.completedTodayCount == dayStart.completedTodayCount + 1, "undoing a roll-forward leaves done as it was")
check(undoneRepeat.activity.today == beforeUndo.activity.today - 1, "while the heatmap gives up the completion the Undo took back")
let refill = task("Refill the watering can", in: kyoto, under: planters, index: 1)
store.save()
store.toggleCompletion(refill, now: date(23, 11, 6))
check(doneToday() == dayStart.completedTodayCount + 2, "a step of a repeat finished today is done")
store.toggleCompletion(refill, now: date(23, 11, 7))
check(!refill.isCompleted && doneToday() == dayStart.completedTodayCount + 1, "a reopened step of a repeat is not done")
// Finishing a routine resets its steps for the next occurrence, so a step
// ticked first is open again afterwards, as the app's Today shows it, and ends
// where a step left unticked does. The heatmap counts both completions.
let routine = task("Morning routine", in: kyoto, index: 0.25, due: date(23))
routine.recurrence = .daily
let stretch = task("Stretch", in: kyoto, under: routine, index: 1)
store.save()
let beforeRoutine = publisher.buildSnapshot(now: noon)
store.toggleCompletion(stretch, now: date(23, 11, 8))
check(stretch.isCompleted && doneToday() == beforeRoutine.completedTodayCount + 1, "a routine's step ticked today is done")
store.toggleCompletion(routine, now: date(23, 11, 9))
let afterRoutine = publisher.buildSnapshot(now: noon)
check(!stretch.isCompleted && !routine.isCompleted && afterRoutine.completedTodayCount == beforeRoutine.completedTodayCount,
      "finishing the routine rolls it forward and reopens its step, so neither is done")
check(afterRoutine.activity.today == beforeRoutine.activity.today + 2, "while the heatmap counts the step and the routine")
store.toggleCompletion(routine, now: date(23, 11, 10))
check(!stretch.isCompleted && doneToday() == beforeRoutine.completedTodayCount,
      "finishing it again with the step left unticked gives the same count")

// MARK: - Activity cache

// The heatmap is kept between rebuilds that leave the history alone.
let fresh = { WidgetSnapshotPublisher(store: store, sources: .live(calendar: coordinator, settings: settings, libraryID: libraryID)) }
check(publisher.buildSnapshot(now: noon).activity == fresh().buildSnapshot(now: noon).activity, "a kept Activity section matches a fresh one")
settings.firstWeekday = 1
let sundayWeeks = publisher.buildSnapshot(now: noon).activity
check(sundayWeeks == fresh().buildSnapshot(now: noon).activity && sundayWeeks.days.first.map { calendar.component(.weekday, from: $0.date) } == 1,
      "a new first weekday rebuilds it")
settings.firstWeekday = 2
let beforeKeys = publisher.buildSnapshot(now: noon).activity.today
store.toggleCompletion(keys, now: date(23, 12, 30))
check(publisher.buildSnapshot(now: noon).activity.today == beforeKeys, "a completion dated later today is left out until then")
check(publisher.buildSnapshot(now: date(23, 12, 31)).activity.today == beforeKeys + 1, "and counted once its time comes, with no new history")

// MARK: - Tomorrow

// Tomorrow's rows are ordered and capped as today's are, and all its due dates
// are published, so each can turn late on time once a widget moves them in.
let beforeErrands = publisher.buildSnapshot(now: noon)
let errandsTomorrow = (0..<13).map { task("Errand \($0)", in: errands, index: Double($0), due: date(24, 20 - $0), time: true) }
store.save()
let withErrands = publisher.buildSnapshot(now: noon)
let tomorrowDates = withErrands.tomorrowItems.compactMap(\.dueDate)
check(withErrands.tomorrowItems.count == 12 && tomorrowDates.count == 12 && tomorrowDates == tomorrowDates.sorted(),
      "tomorrow's rows are soonest first, capped at 12")
check(!withErrands.tomorrowItems.contains { $0.id == errandsTomorrow[0].id }, "the cap drops tomorrow's latest rows")
check(withErrands.dueTomorrow.count == beforeErrands.dueTomorrow.count + 13
      && withErrands.dueTomorrow.map(\.date) == withErrands.dueTomorrow.map(\.date).sorted()
      && withErrands.dueTomorrow.last == WidgetSnapshot.Due(date: date(24, 20), includesTime: true),
      "every due date tomorrow is published, past the rows' cap, soonest first")
check(withErrands.todayItems == beforeErrands.todayItems && withErrands.dueToday == beforeErrands.dueToday
      && withErrands.dueTodayCount == beforeErrands.dueTodayCount && withErrands.overdueCount == beforeErrands.overdueCount,
      "tomorrow's work leaves today's rows and counts alone")
check(withErrands.totalOpenCount == beforeErrands.totalOpenCount + 13, "and is counted as open once")

// Tasks due the same day with the same priority go in capture order, then by
// id, however the fetch returns them, so an unchanged library never reloads.
let ties = (0..<5).map { index -> Block in
    let tie = task("Tie \(index)", in: someday, index: Double(40 + index), due: date(25))
    tie.createdAt = date(22, 12 - index)
    return tie
}
store.save()
for _ in 0..<5 {
    let dayAfter = publisher.buildSnapshot(now: date(24, 8)).tomorrowItems.filter { $0.title.hasPrefix("Tie ") }
    check(dayAfter.map(\.id) == ties.reversed().map(\.id), "rows due together keep their capture order on every rebuild")
}
store.trashBlocks(ties)

// MARK: - Clearing activity

// Done today reads the tasks, not the history, so clearing the history leaves
// it where the app's Today has it, while the heatmap empties.
let beforeClear = publisher.buildSnapshot(now: date(23, 13))
check(beforeClear.activity.today > 0 && beforeClear.completedTodayCount > 0, "the fixture has completions today")
store.clearActivity()
let cleared = publisher.buildSnapshot(now: date(23, 13))
check(store.persistenceError == nil && cleared.activity.today == 0, "clearing activity empties the heatmap")
check(cleared.completedTodayCount == beforeClear.completedTodayCount, "and leaves done today alone: no repeat or reopened step comes back")

// MARK: - Reloads

func change(_ edit: (inout WidgetSnapshot) -> Void) -> WidgetSnapshotPublisher.Change {
    var edited = snapshot
    edit(&edited)
    return WidgetSnapshotPublisher.change(from: snapshot, to: edited)
}
let working = started.work!
check(change { $0.todayItems.removeFirst() } == .data && change { $0.activity.today += 1 } == .data
      && change { $0.completedTodayCount += 1 } == .data && change { $0.accentHex = 0 } == .data, "task and appearance changes reload every widget")
check(change { $0.work = working } == .work && change { $0.work = working; $0.agenda = [] } == .work, "a work session starting reloads Up Next and Agenda at once")
check(change { $0.agenda.removeFirst() } == .plan, "a block moving is a plan change only")
check(WidgetSnapshotPublisher.change(from: started, to: { var moved = started; moved.work?.blockEnd = date(23, 11); return moved }()) == .plan,
      "so is the running block's end moving")
check(WidgetSnapshotPublisher.change(from: started, to: { var paused = started; paused.work?.state = .paused; return paused }()) == .work,
      "pausing is a work change")

// A library with one task and nothing else on the calendar. The planner's own
// suggestion for it slides to the next free time every five minutes, which the
// Calendar doesn't draw, so neither do the widgets. Its slot, once placed,
// moving every five minutes with the app in the background reloads only Up
// Next and Agenda, and at most every quarter hour, while the file is
// rewritten each time.
let slideContainer = try ModelContainer(for: schema, configurations: [
    ModelConfiguration(schema: schema, url: directory.appendingPathComponent("Slide.store"), cloudKitDatabase: .none)])
let slideStore = Store(context: slideContainer.mainContext)
slideStore.bootstrap()
let letter = Block(kind: .task, text: "Post the forms", listID: slideStore.createList(title: "Errands").id)
letter.selectedForDay = date(23)
slideStore.context.insert(letter)
slideStore.save()
let slideStart = date(23, 13)
let slideCoordinator = CalendarCoordinator(store: slideStore, defaults: defaults,
    externalCalendars: ExternalCalendarSource(defaults: defaults, fixtureBusyTimes: []))
slideCoordinator.bootstrap(now: slideStart, monitorsEnabled: false)
check(slideCoordinator.plan.blocks.first?.start == slideStart, "the one task is planned for now")
let slider = WidgetSnapshotPublisher(store: slideStore, sources: .live(calendar: slideCoordinator, settings: settings, libraryID: libraryID))
var reloads: [WidgetSnapshotPublisher.Reload] = []
slider.reloadTimelines = { reloads.append($0) }
slider.sources.isAppActive = { false }
slider.refreshNow(now: slideStart)
check(reloads == [.all], "the first snapshot reloads every widget")
reloads = []
var slides = 0
var moment = slideStart
for _ in 0..<80 {
    moment = moment.addingTimeInterval(15)
    let before = slideCoordinator.plan.blocks.first?.start
    slideCoordinator.tick(now: moment, checkClockGap: false)
    slider.refreshNow(now: moment)
    if slideCoordinator.plan.blocks.first?.start != before { slides += 1 }
}
check(slides == 4 && reloads.isEmpty, "the planner's suggestion slides every five minutes, which no widget draws")
func moveSlot(to start: Date, at now: Date) {
    slideStore.setPlacement(for: letter, start: start, end: start.addingTimeInterval(1800), isPinned: false)
    slideCoordinator.storeDidChange(now: now)
    slider.refreshNow(now: now)
}
for _ in 0..<12 {
    moment = moment.addingTimeInterval(300)
    moveSlot(to: moment.addingTimeInterval(600), at: moment)
}
check(!reloads.contains(.all), "a moving slot never reloads Today, Lists, Summary, Quick Add or Activity")
check(reloads.count == 4, "Up Next and Agenda reload once a quarter hour while the app is in the background")
check(WidgetSnapshotStore.read()?.agenda == slider.buildSnapshot(now: moment).agenda, "the file has the latest plan all the same")
slider.sources.isAppActive = { true }
reloads = []
moment = moment.addingTimeInterval(300)
moveSlot(to: moment.addingTimeInterval(600), at: moment)
check(reloads == [.plan], "with the app in front, a plan change reloads Up Next and Agenda at once")
slider.sources.isAppActive = { false }
check(slideCoordinator.start(task: letter, now: moment.addingTimeInterval(10)), "the fixture starts the moved task")
slider.refreshNow(now: moment.addingTimeInterval(20))
check(reloads == [.plan, .plan], "starting work reloads Up Next and Agenda at once, in the background too")
slideCoordinator.complete(task: letter, now: moment.addingTimeInterval(30))
slider.refreshNow(now: moment.addingTimeInterval(40))
check(reloads == [.plan, .plan, .all], "a real data change reloads every widget at once")
slider.refreshNow(force: true, now: moment.addingTimeInterval(50))
check(reloads == [.plan, .plan, .all, .all], "and so does a widget action's forced refresh")

// The last of a run of held-back plan changes still lands once the interval is up.
var agenda: [WidgetSnapshot.AgendaEvent] = []
var planOnly = WidgetSnapshotSources()
planOnly.agenda = { _ in agenda }
planOnly.isAppActive = { false }
let held = WidgetSnapshotPublisher(store: store, sources: planOnly)
var heldReloads: [WidgetSnapshotPublisher.Reload] = []
held.reloadTimelines = { heldReloads.append($0) }
held.planReloadInterval = 0.3
held.refreshNow()
// Whole seconds, as the file's ISO 8601 dates keep them.
let meetingStart = Date(timeIntervalSinceReferenceDate: Date.now.timeIntervalSinceReferenceDate.rounded(.up) + 3600)
agenda = [WidgetSnapshot.AgendaEvent(id: "sync", kind: .meeting, title: "Sync", start: meetingStart, end: meetingStart.addingTimeInterval(1800))]
held.refreshNow()
agenda[0].start = meetingStart.addingTimeInterval(300)
held.refreshNow()
check(heldReloads == [.all] && WidgetSnapshotStore.read()?.agenda == agenda, "plan changes soon after a reload are written but held back")
RunLoop.main.run(until: Date.now.addingTimeInterval(0.8))
check(heldReloads == [.all, .plan], "then reload Up Next and Agenda once")

// MARK: - Day change

// Midnight rewrites the file even when the new day's snapshot equals the last
// one, so `generatedAt`, which a widget reads to tell which day the counts are
// for, keeps up with a running app.
check(publisher.buildSnapshot(now: date(24, 0, 1)).generatedAt == date(24, 0, 1), "a snapshot is stamped with the moment its counts are for")
let overnight = WidgetSnapshotPublisher(store: slideStore)
var overnightReloads: [WidgetSnapshotPublisher.Reload] = []
overnight.reloadTimelines = { overnightReloads.append($0) }
overnight.refreshNow()
overnight.refreshNow()
check(overnightReloads == [.all], "the fixture's snapshot is unchanged from one refresh to the next")
let dayChangedAt = Date.now
NotificationCenter.default.post(name: .NSCalendarDayChanged, object: nil)
RunLoop.main.run(until: Date.now.addingTimeInterval(0.1))
check(overnightReloads == [.all, .all], "a day change rewrites and reloads an unchanged snapshot")
check(WidgetSnapshotStore.read().map { abs($0.generatedAt.timeIntervalSince(dayChangedAt)) < 2 } == true,
      "so the file is stamped with the new day")

// MARK: - Timing

try runTimingChecks(directory: directory, now: now)

print("✅ \(checks) widget snapshot checks passed")
