import Foundation

var checks = 0
func check(_ value: Bool, _ message: String) {
    precondition(value, message)
    checks += 1
}

let english = Locale(identifier: "en_GB")
func clockAt(_ date: Date = WidgetSampleData.referenceDate) -> WidgetClock {
    WidgetClock(now: date, firstWeekday: WidgetSampleData.firstWeekday, locale: english)
}
let clock = clockAt()
let design = WidgetSampleData.snapshot()
let session = WidgetSampleData.snapshot(fixture: .session)
func id(_ key: String) -> UUID { WidgetSampleData.id(key) }

// MARK: Schema

let version1 = """
{"generatedAt":"2026-09-20T08:00:00Z","todayItems":[{"id":"6B1D8E0A-7C1F-4B7E-9D55-2B8B2F1A0C11","title":"Pay the electricity bill",
"listName":"Personal","listIcon":"🌱","accent":"green","dueDate":"2026-09-19T00:00:00Z","includesTime":false,"isCompleted":false,
"isStarred":false,"hasRepeat":true}],"overdueCount":1,"dueTodayCount":2,"completedTodayCount":3,"inboxCount":2,"totalOpenCount":9,
"lists":[{"id":"0E6C6F4B-2E6A-4C0F-9B1E-6B7C2C9A1D22","title":"Personal","icon":"🌱","accent":"green","openCount":4,"doneCount":2}]}
"""
let old = WidgetSnapshotStore.decode(Data(version1.utf8))
check(old != nil, "A version 1 file still decodes")
check(old?.version == 1, "A file without a version reads as version 1")
check(old?.todayItems.first?.title == "Pay the electricity bill" && old?.todayItems.first?.occurrenceID == nil
      && old?.todayItems.first?.priority == 0 && old?.todayItems.first?.isInbox == false, "Version 1 rows decode, new keys at their defaults")
check(old?.totalOpenCount == 9 && old?.inboxCount == 2 && old?.completedTodayCount == 3, "Version 1 counts keep their meaning")
check(old?.lists.first?.openCount == 4 && old?.lists.first?.openItems.isEmpty == true, "Version 1 lists decode without rows")
check(old?.work == nil && old?.agenda.isEmpty == true && old?.activity == nil, "Version 1 has no work, agenda or activity")
let builtAt = clockAt(ISO8601DateFormatter().date(from: "2026-09-20T08:00:00Z")!)
let builtCounts = old.map { DueCounts($0, clock: builtAt) }
check(builtCounts?.overdue == 1 && builtCounts?.dueToday == 2, "Version 1's counts read as they did on the day it was built")
check(old.map { DueCounts($0, clock: clock).overdue } == 3, "and what was due that day is late by now")

// A version 1 widget, sharing the App Group with a newer app, still reads the file.
struct Version1: Decodable {
    struct Item: Decodable {
        var id: UUID, title: String, listName: String, listIcon: String, accent: String, dueDate: Date?
        var includesTime: Bool, isCompleted: Bool, isStarred: Bool, hasRepeat: Bool
    }
    struct ListSummary: Decodable {
        var id: UUID, title: String, icon: String, accent: String, openCount: Int, doneCount: Int
    }
    var generatedAt: Date, todayItems: [Item], overdueCount: Int, dueTodayCount: Int, completedTodayCount: Int
    var inboxCount: Int, totalOpenCount: Int, lists: [ListSummary]
}
var published = design
published.overdueCount = 3
published.dueTodayCount = 4
let reader = JSONDecoder()
reader.dateDecodingStrategy = .iso8601
let legacy = try? reader.decode(Version1.self, from: WidgetSnapshotStore.encode(published)!)
check(legacy?.overdueCount == 3 && legacy?.dueTodayCount == 4 && legacy?.todayItems.count == design.todayItems.count
      && legacy?.lists.count == design.lists.count, "A version 1 widget reads a version 2 file")
check(published == design, "Version 1's counts don't decide a reload")

let encoded = WidgetSnapshotStore.encode(design)!
check(WidgetSnapshotStore.decode(encoded) == design, "Version 2 round-trips")
check(WidgetSnapshotStore.decode(WidgetSnapshotStore.encode(session)!) == session, "The session fixture round-trips")
var future = design
future.version = WidgetSnapshot.currentVersion + 1
check(WidgetSnapshotStore.decode(WidgetSnapshotStore.encode(future)!) == nil, "A newer app's file is left unread")
var later = design
later.generatedAt = later.generatedAt.addingTimeInterval(90)
later.heartbeatAt = .now
check(later == design, "Equality ignores when the snapshot was built and its heartbeat")
later.inboxCount += 1
check(later != design, "Equality sees what the widget shows")

// Open tasks are counted by the day they fall due, however many share one.
let noon = WidgetSampleData.referenceDate
let days = WidgetSnapshot.dueDays([noon, noon.addingTimeInterval(3_600), noon.addingTimeInterval(-86_400), noon], calendar: clock.calendar)
check(days.map(\.count) == [1, 3] && days[1].day == clock.today, "Due dates count by day, soonest first")
check(design.dueDays.count == Set(design.dueDays.map(\.day)).count && design.dueDays.reduce(0) { $0 + $1.count } == 13,
      "The design's thirteen dated tasks, one entry a day")
var counted = design
counted.countDue(on: noon, by: -4, calendar: clock.calendar)
check(!counted.dueDays.contains { $0.day == clock.today }, "A day with nothing left due drops out")
counted.countDue(on: noon, by: 2, calendar: clock.calendar)
check(counted.dueDays.first { $0.day == clock.today }?.count == 2 && counted.dueDays == counted.dueDays.sorted { $0.day < $1.day },
      "and comes back in its place")

// MARK: Routes

let libraryID = UUID()
let taskID = UUID()
let listID = UUID()
check(WidgetRoute.taskURL(libraryID: libraryID, taskID: taskID) == LocalLink(libraryID: libraryID, target: .task(taskID)).url(),
      "Task links are exactly the app's version 1 links")
check(WidgetRoute.listURL(libraryID: libraryID, listID: listID) == LocalLink(libraryID: libraryID, target: .list(listID)).url(),
      "List links are exactly the app's version 1 links")
check(try LocalLink.parse(WidgetRoute.taskURL(libraryID: libraryID, taskID: taskID)).target == .task(taskID), "Task links open through LocalLink")
check(WidgetRoute.taskURL(libraryID: nil, taskID: taskID) == WidgetRoute.today.url, "Without a library identity a row opens Today")
check(WidgetRoute.scheme == LocalLink.scheme, "Widget routes use the edition's scheme")
for route in [WidgetRoute.capture(listID: nil, forToday: false), .capture(listID: listID, forToday: true), .capture(listID: nil, forToday: true),
              .inbox, .triage, .today, .calendar, .activity, .lists] {
    check(WidgetRoute(url: route.url) == route, "\(route.url.absoluteString) round-trips")
}
check(WidgetRoute(url: WidgetRoute.taskURL(libraryID: libraryID, taskID: taskID)) == nil, "Item links are left to LocalLink")
check(WidgetRoute(url: URL(string: "\(WidgetRoute.scheme)://capture/extra")!) == nil, "Unknown paths are not widget routes")
check(WidgetRoute(url: URL(string: "https://capture")!) == nil, "Other schemes are not widget routes")
check(WidgetRoute.capture(listID: nil, forToday: false).url.absoluteString == "\(WidgetRoute.scheme)://capture", "Quick Add is openlist://capture")

// MARK: Today

let today = TodayModel(design, clock: clock)
check(today.done == 2 && today.total == 9, "Today reads 2 of 9 done")
check(today.late == 3 && today.dueToday == 4, "3 late, 4 due today")
check(today.rows.map(\.id) == ["q4", "k3", "h1", "q1", "p1", "k2", "k4"].map(id), "Late by day first, then timed before untimed")
check(today.rows.prefix(3).map(\.dueText) == ["3d late", "2d late", "1d late"], "Late rows say how late")
check(today.rows[3].dueText == "10:00" && today.rows[6].dueText == "Repeats", "Timed rows show the time; an untimed repeat says so")
check(today.weekday == "Wednesday" && today.dayNumber == "23", "Medium's side shows the day")
check(abs(today.progress - 2.0 / 9) < 0.0001, "The ring shows the day's progress")

let sessionToday = TodayModel(session, clock: clock)
check(sessionToday.done == 3 && sessionToday.total == 9 && sessionToday.late == 2, "After the session: 3 of 9 done, 2 late")
check(sessionToday.rows.first?.id == id("k3"), "The ticked task has settled out")

// The next day, from the same snapshot.
let tomorrow = clockAt(WidgetSampleData.referenceDate.addingTimeInterval(86_400))
let nextDay = TodayModel(design, clock: tomorrow)
check(nextDay.done == 0, "Done today starts again after midnight")
check(nextDay.late == 7 && nextDay.dueToday == 1, "Yesterday's work is late; tomorrow's is due")
check(nextDay.rows.last?.id == id("q2") && nextDay.rows.last?.dueText == "Today", "Tomorrow's row is today's the next day")
check(nextDay.rows.first?.dueText == "4d late", "Lateness counts from the entry's day")

// MARK: Overlay

let tick = WidgetAction(kind: .complete, taskID: id("k3"), occurrenceID: id("k3"), createdAt: WidgetSampleData.referenceDate)
let ticked = SnapshotOverlay.apply([tick], to: design)
let tickedToday = TodayModel(ticked, clock: clock)
check(!tickedToday.rows.contains { $0.id == id("k3") }, "A queued tick hides the row")
check(tickedToday.done == 3 && tickedToday.late == 2 && tickedToday.total == 9, "and moves it to done")
let kyoto = ticked.lists.first { $0.id == id("kyoto") }!
check(kyoto.openCount == 4 && kyoto.doneCount == 2 && kyoto.doneItems.first?.id == id("k3"), "The list counts it done")
check(SummaryModel(ticked, clock: clock).overdue == 2, "Summary counts one fewer overdue")
check(SnapshotOverlay.apply([tick, tick], to: design) == ticked, "A tick counts once")
check(TodayModel(SnapshotOverlay.apply([tick], to: ticked), clock: clock).done == 3, "A tick the app already published changes nothing")
let stale = WidgetAction(kind: .complete, taskID: id("k3"), occurrenceID: UUID())
check(SnapshotOverlay.apply([stale], to: design) == design, "A tick on an occurrence that rolled on is ignored")
let reopen = WidgetAction(kind: .reopen, taskID: id("k6"), occurrenceID: id("k6"))
let reopened = SnapshotOverlay.apply([reopen], to: design).lists.first { $0.id == id("kyoto") }!
check(reopened.openCount == 6 && reopened.doneCount == 0 && reopened.openItems.last?.id == id("k6"), "A queued reopen moves the row back")
let planned = SnapshotOverlay.apply([WidgetAction(kind: .complete, taskID: id("p1"), occurrenceID: id("p1"))], to: design)
check(planned.agenda.flatMap(\.items).first { $0.taskID == id("p1") }?.isCompleted == true, "The Agenda shows a queued tick done")
check(SnapshotOverlay.apply([WidgetAction(kind: .startWork, taskID: id("q1"))], to: design) == design, "Work waits for the app")
check(DueCounts(SnapshotOverlay.apply([reopen], to: ticked), clock: clock) == DueCounts(ticked, clock: clock),
      "A queued reopen of an undated task counts nothing due")
let kyotoDue = WidgetAction(kind: .complete, taskID: id("k5"), occurrenceID: id("k5"))
check(SnapshotOverlay.apply([kyotoDue], to: design).dueDays.reduce(0) { $0 + $1.count } == 12, "A list row's tick counts one fewer due")
// A Today tick on a task past the open rows its list carries: the list still
// counts it done and shows it among its latest, as when it carries the row.
var uncarried = design
let kyotoIndex = uncarried.lists.firstIndex { $0.id == id("kyoto") }!
uncarried.lists[kyotoIndex].openItems.removeAll { $0.id == id("k3") }
check(SnapshotOverlay.apply([tick], to: uncarried) == ticked, "A Today tick past its list's rows still counts in the list")
check(SnapshotOverlay.apply([tick, tick], to: uncarried) == ticked, "and counts once")
let backAgain = SnapshotOverlay.apply([tick, WidgetAction(kind: .reopen, taskID: id("k3"), occurrenceID: id("k3"))], to: uncarried)
check(backAgain == uncarried && backAgain.todayItems.contains { $0.id == id("k3") }, "and a reopen after it counts it open again")

// A tick and its untick queued while the app is quit take each other back, as
// the app skips them: the task is where it was, its Agenda block tinted, and
// Up Next offers it, as the design's untick leaves it.
func action(_ kind: WidgetAction.Kind, _ key: String) -> WidgetAction {
    WidgetAction(kind: kind, taskID: id(key), occurrenceID: id(key), createdAt: WidgetSampleData.referenceDate)
}
let deposit = SnapshotOverlay.apply([action(.complete, "k2"), action(.reopen, "k2")], to: design)
check(deposit == design, "A queued tick and untick leave the snapshot as the app published it, agenda included")
check(ListModel(deposit.lists[kyotoIndex], showsCompleted: true, clock: clock).rows.map(\.id) == ["k3", "k4", "k2", "k1", "k5", "k6"].map(id),
      "and the row keeps its place in the list")
check(SnapshotOverlay.apply([action(.reopen, "k6"), action(.complete, "k6")], to: design) == design, "An untick and its tick do too")
check(SnapshotOverlay.apply([action(.complete, "k2"), action(.complete, "k3"), action(.reopen, "k2")], to: design)
      == SnapshotOverlay.apply([action(.complete, "k3")], to: design), "whatever other tasks are ticked between them")
check(SnapshotOverlay.apply([action(.complete, "k2"), action(.reopen, "k2"), action(.complete, "k2")], to: design)
      == SnapshotOverlay.apply([action(.complete, "k2")], to: design), "and a third tick still counts")
let reopenElsewhere = WidgetAction(kind: .reopen, taskID: id("k2"), occurrenceID: UUID())
check(WidgetAction.takingBack(0, in: [action(.complete, "k2"), action(.complete, "k3"), action(.reopen, "k2")]) == 2
      && WidgetAction.takingBack(0, in: [action(.complete, "k2"), reopenElsewhere]) == nil
      && WidgetAction.takingBack(0, in: [action(.complete, "k2"), action(.startWork, "k2"), action(.reopen, "k2")]) == nil
      && WidgetAction.takingBack(0, in: [action(.startWork, "k2"), action(.startWork, "k2")]) == nil,
      "Only the next action on the task, the opposite tick on the same occurrence, takes one back")
// The app skips the pair only while the task is as the first found it, which
// is what the overlay reads off the snapshot: open for a tick, done for an untick.
check(WidgetAction.takingBack(0, in: [action(.complete, "k2"), action(.reopen, "k2")], whileCompleted: false) == 1
      && WidgetAction.takingBack(0, in: [action(.complete, "k2"), action(.reopen, "k2")], whileCompleted: true) == nil
      && WidgetAction.takingBack(0, in: [action(.reopen, "k6"), action(.complete, "k6")], whileCompleted: true) == 1
      && WidgetAction.takingBack(0, in: [action(.reopen, "k6"), action(.complete, "k6")], whileCompleted: false) == nil
      && WidgetAction.takingBack(0, in: [action(.startWork, "k2"), action(.startWork, "k2")], whileCompleted: false) == nil,
      "The app skips a tick and its untick only from the state the first found")
// A tick the app already published, then an untick: the untick still reopens it.
let publishedDone = SnapshotOverlay.apply([action(.complete, "k2")], to: design)
let evenings = clockAt(WidgetSampleData.referenceDate.addingTimeInterval(6 * 3_600 + 20 * 60))
check(UpNextModel(publishedDone, clock: evenings).state == .clear, "At 17:00, with the deposit done, the day is clear")
for queued in [[action(.reopen, "k2")], [action(.complete, "k2"), action(.reopen, "k2")]] {
    // The app, finding the task done, skips no pair here either.
    check(WidgetAction.takingBack(0, in: queued, whileCompleted: true) == nil, "The app applies the reopen, \(queued.count) queued")
    let open = SnapshotOverlay.apply(queued, to: publishedDone)
    let blocks = open.agenda.flatMap(\.items)
    check(!blocks.contains { $0.taskID == id("k2") } && blocks.count == design.agenda.flatMap(\.items).count - 1,
          "A queued reopen takes the task's done block off the Agenda, as the app does, \(queued.count) queued")
    check(UpNextModel(open, clock: evenings).state == .clear, "so Up Next offers no Start the app would drop")
    check(open.lists[kyotoIndex].openItems.map(\.id) == ["k3", "k4", "k1", "k5", "k2"].map(id)
          && open.lists[kyotoIndex].openCount == 5 && open.todayItems.contains { $0.id == id("k2") },
          "A row the app published done goes back after the list's open rows")
}
check([WidgetAction.Kind.startWork, .pauseWork, .resumeWork].allSatisfy(\.answersTimer)
      && ![WidgetAction.Kind.complete, .reopen, .finishWork].contains(where: \.answersTimer),
      "Only Start, Pause and Resume answer the timer; Done completes the task however long it waits")

// Up Next's Done, queued in the extension before macOS 27 pins it to the app:
// shown done at once, as the design's finish() ticks the task, and its work gone.
let finish = WidgetAction(kind: .finishWork, taskID: id("q1"), occurrenceID: id("q1"), createdAt: WidgetSampleData.referenceDate)
let finished = SnapshotOverlay.apply([finish], to: session)
let finishedNext = UpNextModel(finished, clock: clock)
check(finished.work == nil && finishedNext.state == .next && finishedNext.title == "Write interview feedback for Priya",
      "A queued Done ends the work, and Up Next moves on to the next block")
check(TodayModel(finished, clock: clock).done == 4 && !TodayModel(finished, clock: clock).rows.contains { $0.id == id("q1") }
      && finished.agenda.flatMap(\.items).first { $0.taskID == id("q1") }?.isCompleted == true
      && finished.lists.first { $0.id == id("q3") }?.doneItems.first?.id == id("q1"), "and shows the task done, as a tick does")
check(SnapshotOverlay.apply([finish, finish], to: session) == finished && SnapshotOverlay.apply([finish], to: finished) == finished,
      "A Done counts once, and one the app already published changes nothing")
check(SnapshotOverlay.apply([WidgetAction(kind: .finishWork, taskID: id("q1"), occurrenceID: UUID())], to: session) == session,
      "A Done on an occurrence that rolled on is ignored")
var workOnly = session
workOnly.todayItems.removeAll { $0.id == id("q1") }
for index in workOnly.lists.indices { workOnly.lists[index].openItems.removeAll { $0.id == id("q1") } }
let workOnlyFinished = SnapshotOverlay.apply([finish], to: workOnly)
check(workOnlyFinished.work == nil && UpNextModel(workOnlyFinished, clock: clock).state == .next
      && workOnlyFinished.completedTodayCount == 4 && workOnlyFinished.totalOpenCount == workOnly.totalOpenCount - 1,
      "A Done on work past the rows carried still ends it and counts it done")
// From the row the work carries: its list, Today's due counts and its total
// settle as they do for a row carried, where Today would read 4 of 10.
let workListID = session.work!.item!.listID!
let workList = workOnly.lists.first { $0.id == workListID }!
let workListFinished = workOnlyFinished.lists.first { $0.id == workListID }!
check(workListFinished.openCount == workList.openCount - 1 && workListFinished.doneCount == workList.doneCount + 1
      && workListFinished.doneItems.first?.id == id("q1") && workListFinished.doneItems.first?.isCompleted == true
      && workOnlyFinished.lists.filter { $0.id != workListID } == workOnly.lists.filter { $0.id != workListID },
      "and its list counts it done among its latest")
check(DueCounts(workOnlyFinished, clock: clock) == DueCounts(finished, clock: clock)
      && TodayModel(workOnlyFinished, clock: clock).total == 9 && TodayModel(finished, clock: clock).total == 9,
      "and Today and Summary count it off its due day: 4 of 9 done")
var inboxWork = workOnly
inboxWork.work!.item!.listID = id("inbox")
inboxWork.work!.item!.isInbox = true
inboxWork.inboxCount = WidgetSnapshot.inboxRows + 1
let inboxWorkFinished = SnapshotOverlay.apply([finish], to: inboxWork)
check(inboxWorkFinished.inboxCount == WidgetSnapshot.inboxRows && inboxWorkFinished.lists == inboxWork.lists
      && SnapshotOverlay.apply([finish], to: workOnly).inboxCount == workOnly.inboxCount,
      "Work on an Inbox task past the newest rows counts one fewer in the Inbox; other work leaves it")
var olderWork = session
olderWork.work!.item = nil
let olderWorkJSON = String(decoding: WidgetSnapshotStore.encode(olderWork)!, as: UTF8.self)
check(!olderWorkJSON.contains("\"item\"") && WidgetSnapshotStore.decode(Data(olderWorkJSON.utf8))?.work == olderWork.work,
      "Work written without its row, as an older app does, still decodes")

// MARK: List

let list = ListModel(design.lists.first { $0.id == id("kyoto") }!, showsCompleted: false, clock: clock)
check(list.open == 5 && list.done == 1, "Weekend in Kyoto: 5 open, 1 done")
check(list.rows.map(\.dueText) == ["2d late", "Repeats", "18:00", "Sat 26", "Sun 27"], "List rows read as the design")
check(abs(list.progress - 1.0 / 6) < 0.0001, "The bar shows the list's progress")
let withDone = ListModel(design.lists.first { $0.id == id("kyoto") }!, showsCompleted: true, clock: clock)
check(withDone.rows.count == 6 && withDone.rows.last?.dueText == "Done", "Show completed adds done rows last")
check(design.lists.map(\.title) == ["Weekend in Kyoto", "Home", "Reading", "Q3 planning", "Hiring loop"], "Every list but Inbox, in order")

// Ticks queued while the app is quit still leave large List 6 open rows, the
// next ones moving up ahead of the done ones, as the design's: a list carries
// spare open rows, as the publisher writes them.
var long = design.lists.first { $0.id == id("kyoto") }!
long.openCount = 20
long.openItems = (0..<WidgetSnapshot.ListSummary.openRows).map { number in
    var item = long.openItems[0]
    item.id = id("long-\(number)")
    item.occurrenceID = item.id
    item.title = "Task \(number)"
    item.dueDate = nil
    return item
}
var longSnapshot = design
longSnapshot.lists = [long]
for ticks in [2, WidgetSnapshot.ListSummary.openRows - 6] {
    let queued = (0..<ticks).map { WidgetAction(kind: .complete, taskID: id("long-\($0)"), occurrenceID: id("long-\($0)")) }
    let ticked = ListModel(SnapshotOverlay.apply(queued, to: longSnapshot).lists[0], showsCompleted: true, clock: clock)
    check(ticked.rows.prefix(6).map(\.title) == (ticks..<ticks + 6).map { "Task \($0)" }, "\(ticks) queued ticks leave large List 6 open rows")
    check(ticked.rowCount - 6 == (20 - ticks) + (1 + ticks) - 6, "and +N more counts the rest, done ones too")
}

// MARK: Up Next

let upNext = UpNextModel(design, clock: clock)
check(upNext.state == .now && upNext.label == "Now", "Up Next: Now")
check(upNext.time == "10:00–11:30" && upNext.title == "Draft Q3 OKRs", "on Draft Q3 OKRs, 10:00–11:30")
check(upNext.note == "50 min left" && abs(upNext.progress - 40.0 / 90) < 0.001, "50 min left, the bar at 0.444")
check(upNext.later.map(\.title) == ["Write interview feedback for Priya", "Update the design role scorecard", "Board prep", "Priya debrief"],
      "Later today: the next four, meetings and tasks together")
check(upNext.later.map(\.time) == ["11:30", "13:00", "14:00", "15:30"] && upNext.later[2].isMeeting, "at their times")
let early = UpNextModel(design, clock: clockAt(WidgetSampleData.referenceDate.addingTimeInterval(-3_600)))
check(early.state == .next && early.note == "in 20 min" && early.progress == 0, "Before a block: Next, in 20 min")
let evening = UpNextModel(design, clock: clockAt(WidgetSampleData.referenceDate.addingTimeInterval(9 * 3_600)))
check(evening.state == .clear && evening.title == "Nothing else planned" && evening.listName == "Your day is clear", "After the last block: clear")
// The design counts minutes past an hour too: finish q1 and p1 in its gallery and Up Next reads "in 140 min".
var morningDone = design
morningDone.agenda = morningDone.agenda.map { day in
    var day = day
    day.items = day.items.map { item in
        var item = item
        if item.id == "p-q1" || item.id == "p-p1" { item.isCompleted = true }
        return item
    }
    return day
}
let afternoon = UpNextModel(morningDone, clock: clock)
check(afternoon.state == .next && afternoon.time == "13:00–13:30" && afternoon.note == "in 140 min", "Long waits count minutes, as the design")
check(UpNextModel.minutes(80 * 60) == "80 min" && UpNextModel.minutes(-30) == "0 min", "80 min left, never below 0 min")
check(upNext.accent == "blue" && evening.accent == nil, "The block's list colour, for a symbol icon; none once the day is clear")

let paused = UpNextModel(session, clock: clock)
check(paused.state == .paused && paused.label == "Paused" && paused.timer == .paused(seconds: 18), "The session: paused at 00:18")
check(paused.time == "10:00–11:30" && paused.later.first?.time == "11:30", "Paused work keeps its slot and what follows")
var running = session
running.work?.isRunning = true
running.work?.elapsedAnchor = WidgetSampleData.referenceDate.addingTimeInterval(-600)
running.heartbeatAt = WidgetSampleData.referenceDate
let live = UpNextModel(running, clock: clock, heartbeatLimit: WidgetSampleData.referenceDate.addingTimeInterval(-180))
check(live.state == .working && live.timer == .running(anchor: WidgetSampleData.referenceDate.addingTimeInterval(-600)), "Running work ticks from its anchor")
check(abs(live.progress - 600.0 / 5_400) < 0.001, "Its bar fills with the work")
let orphaned = UpNextModel(running, clock: clock, heartbeatLimit: WidgetSampleData.referenceDate.addingTimeInterval(60))
check(orphaned.state == .paused && orphaned.timer == .paused(seconds: 600), "A timer whose heartbeat stopped shows paused at it")

// MARK: Quick Add, Summary, Activity

let capture = CaptureModel(design, clock: clock)
check(capture.count == 6 && capture.items.map(\.age) == ["2h", "5h", "1d", "2d"], "Quick Add: 6 waiting, the newest four with ages")
check(CaptureModel.age(WidgetSampleData.referenceDate.addingTimeInterval(-20), now: WidgetSampleData.referenceDate) == "1m", "A fresh capture reads 1m")
// An Inbox task due today, ticked in Today while the app is quit: the snapshot
// carries spare Inbox rows, as the publisher writes them, so medium Quick Add
// still lists the newest four, the next one moving up, as the design's.
var dueInInbox = design
dueInInbox.inboxItems = Array(design.inboxItems.prefix(5))
dueInInbox.inboxCount = 5
var inboxRow = design.todayItems[0]
inboxRow.id = dueInInbox.inboxItems[1].id
inboxRow.occurrenceID = inboxRow.id
inboxRow.listID = id("inbox")
inboxRow.isInbox = true
dueInInbox.todayItems.append(inboxRow)
let inboxTicked = CaptureModel(SnapshotOverlay.apply([WidgetAction(kind: .complete, taskID: inboxRow.id, occurrenceID: inboxRow.id)],
                                                     to: dueInInbox), clock: clock)
check(inboxTicked.count == 4 && inboxTicked.items.map(\.id) == [0, 2, 3, 4].map { dueInInbox.inboxItems[$0].id },
      "A queued tick on an Inbox task leaves Quick Add 4 rows under Inbox 4")
check(WidgetSnapshot.inboxRows > CaptureModel.shown, "The snapshot carries spare Inbox rows")
// An Inbox of 9 whose oldest task, due today, is past the 8 newest carried:
// ticked in Today while the app is quit, Quick Add and Summary still count it gone.
var fullInbox = design
fullInbox.inboxItems = (0..<WidgetSnapshot.inboxRows).map {
    WidgetSnapshot.InboxItem(id: id("inbox-\($0)"), title: "Capture \($0)", createdAt: noon.addingTimeInterval(-Double($0 + 1) * 3_600))
}
fullInbox.inboxCount = WidgetSnapshot.inboxRows + 1
var oldestInbox = design.todayItems[0]
oldestInbox.id = id("inbox-oldest")
oldestInbox.occurrenceID = oldestInbox.id
oldestInbox.listID = id("inbox")
oldestInbox.isInbox = true
fullInbox.todayItems.append(oldestInbox)
check(WidgetSnapshotStore.decode(WidgetSnapshotStore.encode(fullInbox)!) == fullInbox, "A row's Inbox flag round-trips")
let oldestTicked = SnapshotOverlay.apply([WidgetAction(kind: .complete, taskID: oldestInbox.id, occurrenceID: oldestInbox.id)], to: fullInbox)
check(oldestTicked.inboxCount == 8 && oldestTicked.inboxItems == fullInbox.inboxItems
      && CaptureModel(oldestTicked, clock: clock).count == 8 && SummaryModel(oldestTicked, clock: clock).inbox == 8
      && !TodayModel(oldestTicked, clock: clock).rows.contains { $0.id == oldestInbox.id },
      "A queued Today tick on an Inbox task past the rows carried counts one fewer in the Inbox")
var elsewhere = fullInbox
elsewhere.todayItems[elsewhere.todayItems.count - 1].isInbox = false
check(SnapshotOverlay.apply([WidgetAction(kind: .complete, taskID: oldestInbox.id, occurrenceID: oldestInbox.id)], to: elsewhere).inboxCount == 9,
      "and one in another list leaves the Inbox's count")

// Quick Add's timeline has an entry wherever an age shown moves on, so none stays behind.
let captureStart = WidgetSampleData.referenceDate
var captured = design
let capturedAges: [(TimeInterval, String)] = [(20, "Just now"), (1_807, "Half an hour ago"), (18_011, "This morning"), (183_600, "Two days ago")]
captured.inboxItems = capturedAges.map { age, title in
    WidgetSnapshot.InboxItem(id: UUID(), title: title, createdAt: captureStart.addingTimeInterval(-age))
}
let ageEntries = [captureStart] + CaptureModel.ageChanges(captured, after: captureStart)
check(ageEntries == ageEntries.sorted() && Set(ageEntries).count == ageEntries.count && ageEntries.count < 200
      && ageEntries.last! < captureStart.addingTimeInterval(86_400), "Age entries run in order through the day ahead: \(ageEntries.count)")
check(ageEntries[1] == captureStart.addingTimeInterval(100) && ageEntries.contains(captureStart.addingTimeInterval(3_580)),
      "A fresh capture moves to 2m two minutes in, and to 1h at the hour")
var newestBehind: Date?
var ageLag: TimeInterval = 0
var behindSince: Date?
var ageEntry = 0
for step in stride(from: 0.0, to: 86_400, by: 5) {
    let moment = captureStart.addingTimeInterval(step)
    while ageEntry + 1 < ageEntries.count, ageEntries[ageEntry + 1] <= moment { ageEntry += 1 }
    let drawn = CaptureModel(captured, clock: clockAt(ageEntries[ageEntry])).items.map(\.age)
    let exact = CaptureModel(captured, clock: clockAt(moment)).items.map(\.age)
    if drawn[0] != exact[0], newestBehind == nil { newestBehind = moment }
    behindSince = drawn == exact ? nil : behindSince ?? moment
    if let behindSince { ageLag = max(ageLag, moment.timeIntervalSince(behindSince)) }
}
check(newestBehind == nil, "The newest capture's age is never behind: at \(String(describing: newestBehind))")
check(ageLag < 60, "Older ages are at most a minute behind: \(ageLag)s")
var emptyInbox = design
emptyInbox.inboxItems = []
check(CaptureModel.ageChanges(emptyInbox, after: captureStart).isEmpty, "An empty Inbox has no ages to move on")

let summary = SummaryModel(design, clock: clock)
check([summary.due, summary.overdue, summary.inbox, summary.done] == [4, 3, 6, 2], "Summary: 4, 3, 6, 2")
check(summary.week.map(\.day) == ["M", "T", "W", "T", "F", "S", "S"] && summary.week[2].isToday, "The week runs Monday to Sunday")
check(summary.week.map(\.count) == [0, 0, 2, nil, nil, nil, nil] && summary.weekTotal == 2, "This week: 2 done, days to come empty")

let activity = ActivityModel(design, clock: clock, weeks: 21)
check(activity.weeks.count == 21 && activity.weeks.allSatisfy { $0.count == 7 }, "21 weeks of seven days")
check(activity.todayIndex == 2 && activity.weeks[20][2] == 2 && activity.weeks[20][3] == nil, "Today is Wednesday of the last week")
check(activity.streak == 1 && activity.today == 2 && activity.week == 2 && activity.month == 49, "1-day streak; 2 today, 2 this week, 49 in September")
check(activity.monthName == "September", "The month is named")
check(ActivityModel(design, clock: clock, weeks: 10).weeks.count == 10, "Small shows 10 weeks")
// A repeat done today rolls on rather than sit done, so today's done tasks
// leave it out; the heatmap, the Activity screen's, counts it, today as any day.
var repeated = design
repeated.activity!.counts[repeated.activity!.counts.count - 1] = 3
let repeatedActivity = ActivityModel(repeated, clock: clock, weeks: 21)
check(repeatedActivity.today == 3 && repeatedActivity.weeks[20][2] == 3 && repeatedActivity.week == 3 && repeatedActivity.month == 50,
      "A repeat done today counts in the Activity widget's today, as on the screen")
let repeatedSummary = SummaryModel(repeated, clock: clock)
check(repeatedSummary.week[2].count == 3 && repeatedSummary.weekTotal == 3 && repeatedSummary.done == 2 && TodayModel(repeated, clock: clock).done == 2,
      "and in Summary's week, while Done and Today count the tasks done today, as the app's Today")
var onlyRepeat = repeated
onlyRepeat.completedTodayCount = 0
onlyRepeat.activity!.counts[onlyRepeat.activity!.counts.count - 1] = 1
check(ActivityModel(onlyRepeat, clock: clock, weeks: 21).streak == 1, "and in the streak")
let dayAfter = ActivityModel(repeated, clock: tomorrow, weeks: 21)
check(dayAfter.today == 0 && dayAfter.weeks[20][2] == 3 && dayAfter.weeks[20][3] == 0, "The next day it's yesterday's, and today starts at 0")
var noHeatmap = design
noHeatmap.activity = nil
check(ActivityModel(noHeatmap, clock: clock, weeks: 21).today == 2, "A file without a heatmap counts today's done tasks")
// A tick queued while the app is quit counts on the heatmap too, a reopen of
// one done today takes it off, and one after midnight counts on the new day.
check(ActivityModel(ticked, clock: clock, weeks: 21).today == 3 && SummaryModel(ticked, clock: clock).weekTotal == 3,
      "A queued tick counts in today's cell")
let sessionReopened = SnapshotOverlay.apply([WidgetAction(kind: .reopen, taskID: id("q4"), occurrenceID: id("q4"))], to: session)
check(ActivityModel(session, clock: clock, weeks: 21).today == 3 && ActivityModel(sessionReopened, clock: clock, weeks: 21).today == 2
      && TodayModel(sessionReopened, clock: clock).done == 2, "A queued reopen of a task done today takes it off")
let afterMidnight = SnapshotOverlay.apply([WidgetAction(kind: .complete, taskID: id("k3"), occurrenceID: id("k3"), createdAt: tomorrow.now)],
                                          to: design, calendar: tomorrow.calendar)
let afterMidnightActivity = ActivityModel(afterMidnight, clock: tomorrow, weeks: 21)
check(afterMidnightActivity.today == 1 && afterMidnightActivity.weeks[20][2] == 2 && afterMidnightActivity.streak == 2
      && TodayModel(afterMidnight, clock: tomorrow).done == 1, "A tick queued after midnight counts on the new day")
check([0, 1, 2, 3, 4, 6, 7].map(ActivityModel.opacity) == [0, 0.28, 0.5, 0.5, 0.75, 0.75, 1],
      "The heatmap's steps change at the legend's 1, 2–3, 4–6 and 7+ bands")

// MARK: Agenda

let agenda = AgendaModel(design, clock: clock)
check(agenda.daySubtitle == "Wed 23 · 4 meetings · 5 planned", "Today's subtitle")
check(agenda.range == "21 – 27 September", "This week's range")
check(agenda.week.map(\.label) == ["Mon 21", "Tue 22", "Wed 23", "Thu 24", "Fri 25", "Sat 26", "Sun 27"], "Seven day heads")
let draft = agenda.today.items.first { $0.title == "Draft Q3 OKRs" }!
let frame = AgendaModel.frame(start: draft.start, end: draft.end, pxh: 29)
check(frame.top == 30 && frame.height == 41.5 && draft.timeText == "10:00–11:30", "10:00–11:30 sits at 30, 41.5 tall")
check(abs(AgendaModel.nowOffset(agenda.nowHour, pxh: 29)! - 48.333) < 0.01, "The now line at 10:40")
check(AgendaModel.nowOffset(20, pxh: 29) == nil && AgendaModel.nowOffset(8.5, pxh: 29) == nil, "No now line outside the grid's hours")
check(AgendaModel.frame(start: 16.5, end: 16.6667, pxh: 29).height == 13, "Short slots keep their minimum height")
// A meeting starting inside a pinned slot: the day reads in start order, and
// the slot draws over the meeting, as the design draws its meetings first.
var overlapping = design
let pinned = clock.today.addingTimeInterval(13.5 * 3_600)
overlapping.agenda = [WidgetSnapshot.AgendaDay(day: clock.today, items: [
    WidgetSnapshot.AgendaItem(id: "p-pinned", kind: .task, title: "Pinned slot", start: pinned, end: pinned.addingTimeInterval(3_600),
                              taskID: id("pinned"), occurrenceID: id("pinned"), accent: "blue",
                              isCompleted: false, isActive: false, isFlexible: false),
    WidgetSnapshot.AgendaItem(id: "m-later", kind: .meeting, title: "Later meeting", start: pinned.addingTimeInterval(1_800),
                              end: pinned.addingTimeInterval(5_400), isCompleted: false, isActive: false, isFlexible: false),
])]
let overlap = AgendaModel(overlapping, clock: clock).today.items
check(overlap.map(\.title) == ["Pinned slot", "Later meeting"] && overlap[0].layer > overlap[1].layer,
      "A planned block draws over a meeting that starts inside it")
check(AgendaModel(session, clock: clock).week[1].items.first { $0.title == "Close out Q2 retro actions" }?.isDone == true,
      "A done slot shows done")
let across = clockAt(WidgetSampleData.referenceDate.addingTimeInterval(6 * 86_400))
check(AgendaModel(design, clock: across).range == "28 September – 4 October", "A week across months names both")
check(clock.hours(WidgetSampleData.referenceDate.addingTimeInterval(15 * 3_600), on: clock.today) == 25 + 40.0 / 60,
      "Past midnight the hours go on counting")

// On the days the clocks change, blocks and the now line keep to the hour labels.
var amsterdam = Calendar(identifier: .gregorian)
amsterdam.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
for (month, day, change) in [(3, 29, "go forward"), (10, 25, "go back")] {
    let moment = amsterdam.date(from: DateComponents(year: 2026, month: month, day: day, hour: 10, minute: 40))!
    let changeDay = WidgetClock(now: moment, firstWeekday: WidgetSampleData.firstWeekday, calendar: amsterdam, locale: english)
    check(abs(changeDay.nowHours - (10 + 40.0 / 60)) < 0.0001, "10:40 is 10.67 on the day the clocks \(change)")
    let block = AgendaModel(WidgetSampleData.snapshot(now: moment, calendar: amsterdam), clock: changeDay)
        .today.items.first { $0.title == "Draft Q3 OKRs" }!
    check(block.start == 10 && block.end == 11.5 && block.timeText == "10:00–11:30", "and 10:00–11:30 sits at 10 to 11.5")
}

// The gallery's sample week is the week today falls in: today with the design's
// Wednesday, the other days their own weekday's meetings, and planned slots on
// their tasks' due days.
func sampleAgenda(_ day: Int) -> (clock: WidgetClock, agenda: AgendaModel) {
    let at = clockAt(WidgetSampleData.referenceDate.addingTimeInterval(Double(day - 23) * 86_400))
    return (at, AgendaModel(WidgetSampleData.snapshot(now: at.now), clock: at))
}
func meetings(_ agenda: AgendaModel) -> [[String]] { agenda.week.map { $0.items.filter(\.isMeeting).map(\.title) } }
func slots(_ agenda: AgendaModel, _ column: Int) -> [String] {
    agenda.week[column].items.filter { !$0.isMeeting }.map { "\($0.title) \($0.timeText)" }
}
let designWeek = meetings(agenda)
check(designWeek[5] == ["Pottery class"] && designWeek[6].isEmpty && designWeek.prefix(5).allSatisfy { $0.first == "Standup" },
      "The design's week: a standup every weekday, pottery on Saturday")
check(slots(agenda, 1) == ["Close out Q2 retro actions 14:00–14:30"] && slots(agenda, 3) == ["Review hiring budget with Sam 13:00–13:45"]
      && slots(agenda, 4) == ["Prep board update slides 10:00–11:00"], "The design's slots around its Wednesday, where it has them")
let thursday = sampleAgenda(24)
check(meetings(thursday.agenda) == [designWeek[0], designWeek[1], designWeek[3], designWeek[2], designWeek[4], designWeek[5], designWeek[6]]
      && thursday.agenda.week[3].isToday, "On a Thursday the design's Wednesday is today, and Monday still starts the week")
check(thursday.agenda.daySubtitle == "Thu 24 · 4 meetings · 5 planned", "Today has the design's plan")
check(slots(thursday.agenda, 2) == ["Close out Q2 retro actions 14:00–14:30"]
      && slots(thursday.agenda, 4) == ["Review hiring budget with Sam 13:00–13:45"]
      && slots(thursday.agenda, 5) == ["Prep board update slides 11:30–12:30"],
      "Slots keep their days from today, one moved past Saturday's pottery")
let tuesday = sampleAgenda(22)
check(meetings(tuesday.agenda) == [designWeek[0], designWeek[2], designWeek[1], designWeek[3], designWeek[4], designWeek[5], designWeek[6]]
      && slots(tuesday.agenda, 3) == ["Prep board update slides 12:00–13:00"], "On a Tuesday a slot starts as Thursday's offsite ends")
let saturday = sampleAgenda(26)
check(meetings(saturday.agenda) == [designWeek[0], designWeek[1], designWeek[2], designWeek[3], designWeek[4], designWeek[2], designWeek[6]],
      "On a Saturday the weekdays keep their own meetings")
let sunday = sampleAgenda(27)
check(meetings(sunday.agenda) == [designWeek[0], designWeek[1], designWeek[2], designWeek[3], designWeek[4], designWeek[5], designWeek[2]]
      && slots(sunday.agenda, 5) == ["Close out Q2 retro actions 14:00–14:30"] && slots(sunday.agenda, 6).count == 5,
      "On a Sunday too, pottery still on Saturday")
let monday = sampleAgenda(21)
check(meetings(monday.agenda) == [designWeek[2], designWeek[1], designWeek[0], designWeek[3], designWeek[4], designWeek[5], designWeek[6]],
      "On a Monday, Monday's own meetings move to Wednesday")
for date in 21...27 {
    let (at, week) = sampleAgenda(date)
    let due = Dictionary(WidgetSampleData.snapshot(now: at.now).lists.flatMap(\.openItems).compactMap { item in
        item.dueDate.map { (item.title, at.calendar.startOfDay(for: $0)) }
    }, uniquingKeysWith: { first, _ in first })
    check(meetings(week).prefix(5).allSatisfy { $0.first == "Standup" }, "A standup every weekday, on the \(date)th too")
    for day in week.week {
        for slot in day.items where !slot.isMeeting {
            check(due[slot.title].map { $0 < at.today || $0 == day.day } ?? true, "\(slot.title) sits on its due day, on the \(date)th")
            check(!day.items.contains { $0.isMeeting && $0.start < slot.end && slot.start < $0.end }, "\(slot.title) clears the meetings")
        }
    }
}
let thursdaySample = WidgetSampleData.snapshot(now: thursday.clock.now)
let thursdayActivity = ActivityModel(thursdaySample, clock: thursday.clock, weeks: 21)
check(thursdayActivity.todayIndex == 3 && thursdayActivity.weeks[20][3] == 2 && thursdayActivity.weeks[20][4] == nil
      && Array(thursdayActivity.weeks.prefix(20)) == Array(activity.weeks.prefix(20)), "The heatmap keeps the design's weeks, today on Thursday")
let thursdayBars = SummaryModel(thursdaySample, clock: thursday.clock).week.map(\.count)
check(thursdayBars.prefix(2) == [0, 0] && thursdayBars[3] == 2 && thursdayBars.suffix(3) == [nil, nil, nil],
      "Summary's bars fall on their own days")

// MARK: Emoji

// The List tile's 15 px emoji, a row's 10 px meta line and Up Next's 10.5 px list line, as the app sizes them.
check(abs(EmojiSize.points(forDesign: 15) - 38.0 / 3) < 0.001 && abs(EmojiSize.points(forDesign: 10) - 8.3) < 0.001
      && abs(EmojiSize.points(forDesign: 10.5) - 8.8) < 0.001, "Small emoji draw at the design's size, not Core Text's larger one")
check(EmojiSize.points(forDesign: 24) == 24 && EmojiSize.points(forDesign: 30) == 30, "From 24 px the two agree")
// A list icon from synced or older data can name an SF Symbol, which draws as the symbol.
check(ListIcon.isSymbolName("briefcase.fill") && ListIcon.isSymbolName("checklist"), "SF Symbol names read as symbols")
check(!["🗻", "📋", "", "ab", "not.a.symbol.name"].contains(where: ListIcon.isSymbolName), "Emoji and other text stay text")

print("Passed \(checks) widget snapshot, route, overlay and design checks")
