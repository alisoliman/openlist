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
      && old?.todayItems.first?.priority == 0, "Version 1 rows decode, new keys at their defaults")
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
check([WidgetAction.Kind.startWork, .pauseWork, .resumeWork, .finishWork].allSatisfy(\.isWork)
      && ![WidgetAction.Kind.complete, .reopen].contains(where: \.isWork), "Only the timer's buttons are work")

// MARK: List

let list = ListModel(design.lists.first { $0.id == id("kyoto") }!, showsCompleted: false, clock: clock)
check(list.open == 5 && list.done == 1, "Weekend in Kyoto: 5 open, 1 done")
check(list.rows.map(\.dueText) == ["2d late", "Repeats", "18:00", "Sat 26", "Sun 27"], "List rows read as the design")
check(abs(list.progress - 1.0 / 6) < 0.0001, "The bar shows the list's progress")
let withDone = ListModel(design.lists.first { $0.id == id("kyoto") }!, showsCompleted: true, clock: clock)
check(withDone.rows.count == 6 && withDone.rows.last?.dueText == "Done", "Show completed adds done rows last")
check(design.lists.map(\.title) == ["Weekend in Kyoto", "Home", "Reading", "Q3 planning", "Hiring loop"], "Every list but Inbox, in order")

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
check(AgendaModel(session, clock: clock).week[1].items.first { $0.title == "Close out Q2 retro actions" }?.isDone == true,
      "A done slot shows done")
let across = clockAt(WidgetSampleData.referenceDate.addingTimeInterval(6 * 86_400))
check(AgendaModel(design, clock: across).range == "28 September – 4 October", "A week across months names both")

// MARK: Emoji

// The List tile's 15 px emoji, a row's 10 px meta line and Up Next's 10.5 px list line, as the app sizes them.
check(abs(EmojiSize.points(forDesign: 15) - 38.0 / 3) < 0.001 && abs(EmojiSize.points(forDesign: 10) - 8.3) < 0.001
      && abs(EmojiSize.points(forDesign: 10.5) - 8.8) < 0.001, "Small emoji draw at the design's size, not Core Text's larger one")
check(EmojiSize.points(forDesign: 24) == 24 && EmojiSize.points(forDesign: 30) == 30, "From 24 px the two agree")
// A list icon from synced or older data can name an SF Symbol, which draws as the symbol.
check(ListIcon.isSymbolName("briefcase.fill") && ListIcon.isSymbolName("checklist"), "SF Symbol names read as symbols")
check(!["🗻", "📋", "", "ab", "not.a.symbol.name"].contains(where: ListIcon.isSymbolName), "Emoji and other text stay text")

print("Passed \(checks) widget snapshot, route, overlay and design checks")
