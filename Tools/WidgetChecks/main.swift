import CoreGraphics
import Foundation

var checks = 0

func check(_ condition: @autoclosure () throws -> Bool, _ message: String) {
    checks += 1
    guard (try? condition()) == true else { fatalError("FAIL: \(message)") }
}

// A fixed calendar, so names and day boundaries never depend on this Mac.
var calendar = Calendar(identifier: .gregorian)
calendar.locale = Locale(identifier: "en_US_POSIX")
calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam")!

let now = WidgetSnapshot.mockupNow(calendar: calendar)
let today = calendar.startOfDay(for: now)

/// A time on the mockup's Wednesday, or `day` days from it.
func at(_ hour: Int, _ minute: Int = 0, day: Int = 0) -> Date {
    calendar.date(byAdding: DateComponents(day: day, hour: hour, minute: minute), to: today)!
}

let sample = WidgetSnapshot.sample(now: now, calendar: calendar)
let q1 = WidgetSnapshot.sampleTaskID("q1")
let q4 = WidgetSnapshot.sampleTaskID("q4")
let k6 = WidgetSnapshot.sampleTaskID("k6")
let kyoto = WidgetSnapshot.sampleListID("kyoto")
let p1 = WidgetSnapshot.sampleTaskID("p1")

func item(_ key: String, in snapshot: WidgetSnapshot = sample) -> WidgetSnapshot.Item {
    let id = WidgetSnapshot.sampleTaskID(key)
    return (snapshot.todayItems + snapshot.lists.flatMap { $0.openItems + $0.doneItems }).first { $0.id == id }!
}

let q1Occurrence = item("q1").occurrenceID

func command(_ action: WidgetCommand.Action, _ taskID: UUID? = nil, occurrence: UUID? = nil, at date: Date = now) -> WidgetCommand {
    WidgetCommand(action: action, taskID: taskID, occurrenceID: occurrence, issuedAt: date)
}

/// A tap on the sample row `key`, naming its task and occurrence as every
/// widget button does.
func tap(_ action: WidgetCommand.Action, _ key: String, in snapshot: WidgetSnapshot = sample, at date: Date = now) -> WidgetCommand {
    let row = item(key, in: snapshot)
    return command(action, row.id, occurrence: row.occurrenceID, at: date)
}

// MARK: - Sample snapshot

check(sample.todayItems.map(\.title) == [
    "Close out Q2 retro actions", "Reserve the Nishiki market tour", "Fix the dripping bathroom tap",
    "Draft Q3 OKRs", "Write interview feedback for Priya", "Pay the ryokan deposit", "Ask Mika to water the planters",
], "the sample's Today rows follow the mockup: by day, timed before untimed")
check(sample.overdueCount == 4 && sample.dueTodayCount == 3, "the sample counts a 10:00 task as late at 10:40, as the app does")
check(sample.completedTodayCount == 2 && sample.inboxCount == 6 && sample.inboxItems.count == 6, "the sample has two done today and six Inbox captures")
check(sample.lists.map(\.title) == ["Inbox", "Weekend in Kyoto", "Home", "Reading", "Q3 planning", "Hiring loop"], "the sample lists come Inbox first")
check(sample.list(id: nil)?.id == kyoto, "the default list is the first real one")
check(sample.lists[1].openCount == 5 && sample.lists[1].doneCount == 1, "Kyoto has five open and one done")
check(sample.agenda.count { calendar.isDate($0.start, inSameDayAs: now) } == 9, "today has four meetings and five blocks")
check(sample.firstWeekday == 2 && sample.weekStart == at(0, day: -2), "the sample week starts on Monday the 21st")

// MARK: - Snapshot file

do {
    let data = try WidgetSnapshotStore.encode(sample)
    let decoded = try WidgetSnapshotStore.decode(data)
    check(decoded == sample, "a snapshot survives an encode and decode round trip")
    check(abs(decoded.generatedAt.timeIntervalSince(sample.generatedAt)) < 1, "the write time survives the round trip")
    check(decoded.version == WidgetSnapshot.currentVersion, "new files carry the current version")

    let taskID = UUID(), listID = UUID()
    let legacy = """
    {"generatedAt":"2026-09-23T08:40:00Z","overdueCount":2,"dueTodayCount":3,"completedTodayCount":1,
     "inboxCount":4,"totalOpenCount":9,"futureKey":true,
     "todayItems":[{"id":"\(taskID)","title":"Old","listName":"Home","listIcon":"🏡","accent":"green",
       "dueDate":"2026-09-23T08:00:00Z","includesTime":true,"isCompleted":false,"isStarred":false,"hasRepeat":false}],
     "lists":[{"id":"\(listID)","title":"Home","icon":"🏡","accent":"green","openCount":3,"doneCount":1}]}
    """
    let old = try WidgetSnapshotStore.decode(Data(legacy.utf8))
    check(old.version == 1, "a file without a version decodes as version 1")
    check(old.overdueCount == 2 && old.dueTodayCount == 3 && old.completedTodayCount == 1 && old.inboxCount == 4 && old.totalOpenCount == 9,
          "a version 1 file keeps its counters")
    check(old.todayItems.isEmpty && old.lists.isEmpty, "rows in the old shape fall back to empty instead of failing the file")
    check(old.agenda.isEmpty && old.work == nil && old.accentHex == 0x7C4DF0 && old.serifTitles, "fields a version 1 file lacks take their defaults")
    check((try? WidgetSnapshotStore.decode(Data("not json".utf8))) == nil, "a corrupt file is rejected")

    var later = sample
    later.generatedAt = sample.generatedAt.addingTimeInterval(3600)
    check(later == sample, "equality ignores when the snapshot was written")
    later.inboxCount += 1
    check(later != sample, "equality notices a changed field")
}

// MARK: - Widget links

do {
    let id = UUID()
    let links: [WidgetLink] = [.capture(listID: nil), .capture(listID: id), .inbox, .triage, .today, .calendar, .activity, .task(id), .list(id)]
    for link in links {
        check(WidgetLink(url: link.url) == link, "\(link) survives a URL round trip")
        check(WidgetLink.isWidgetLink(link.url), "\(link) is recognised as a widget link")
    }
    check(WidgetLink.capture(listID: nil).url.absoluteString == "openlist://widget/capture", "capture uses the widget host")
    check(WidgetLink.task(id).url.absoluteString == "openlist://widget/task/\(id.uuidString.lowercased())", "item links use lowercase IDs")
    check(WidgetLink(url: URL(string: "openlist://widget/task/\(id.uuidString.uppercased())")!) == .task(id), "uppercase IDs still parse")

    let rejected = [
        "openlist-dev://widget/today", "openlist://widget/today?x=1", "openlist://widget/today#top",
        "openlist://widget:8080/today", "openlist://widget/nope", "openlist://widget/task/not-a-uuid",
        "openlist://widget/task/\(id)/extra", "openlist://widget/capture/folder/\(id)", "openlist://widget",
    ]
    for string in rejected {
        check(WidgetLink(url: URL(string: string)!) == nil, "\(string) is rejected")
    }
    check(WidgetLink.isWidgetLink(URL(string: "openlist-dev://widget/today")!), "the other build's widget links are still claimed, not reported as item links")
    check(!WidgetLink.isWidgetLink(URL(string: "openlist://v1/\(id)/task/\(id)")!), "item links are left to LocalLink")
    check(!WidgetLink.isWidgetLink(URL(string: "https://widget/today")!), "web URLs are not widget links")
}

// MARK: - Command queue

do {
    let url = WidgetCommandQueue.url!
    check(url.path.contains("OpenlistUIReviews/WidgetChecks-"), "the checks use a throwaway container, never the App Group")
    check(WidgetCommandQueue.pending().isEmpty, "the queue starts empty")

    let a = UUID(), b = UUID()
    WidgetCommandQueue.append(WidgetCommand(action: .complete, taskID: a))
    check(WidgetCommandQueue.pending().map(\.action) == [.complete], "an appended command is pending")
    WidgetCommandQueue.append(WidgetCommand(action: .reopen, taskID: a))
    check(WidgetCommandQueue.pending().map(\.action) == [.reopen], "a newer tap on the same task supersedes the older one")
    WidgetCommandQueue.append(WidgetCommand(action: .startWork, taskID: a))
    WidgetCommandQueue.append(WidgetCommand(action: .complete, taskID: b))
    let pending = WidgetCommandQueue.pending()
    check(pending.map(\.action) == [.reopen, .startWork, .complete], "work commands do not supersede ticks, and order is kept")
    WidgetCommandQueue.remove([pending[0].id])
    check(WidgetCommandQueue.pending().map(\.action) == [.startWork, .complete], "applied commands are removed")

    WidgetCommandQueue.append(WidgetCommand(action: .pauseWork, issuedAt: Date.now.addingTimeInterval(-7 * 3600)))
    check(WidgetCommandQueue.pending().count == 2, "commands older than their lifetime are never replayed")
    WidgetCommandQueue.remove(Set(WidgetCommandQueue.pending().map(\.id)))
    check(WidgetCommandQueue.pending().isEmpty && !FileManager.default.fileExists(atPath: url.path), "an empty queue leaves no file behind")

    // Done on Up Next, then unticking the same row on Today: the untick takes
    // the Done back, and the row draws open again rather than stuck closing.
    let working = WidgetSnapshot.sample(now: now, work: .working, calendar: calendar)
    WidgetCommandQueue.append(WidgetCommand(action: .finishWork, taskID: q1, occurrenceID: q1Occurrence))
    WidgetCommandQueue.append(WidgetCommand(action: .reopen, taskID: q1, occurrenceID: q1Occurrence))
    check(WidgetCommandQueue.pending().map(\.action) == [.reopen], "unticking after Done supersedes the Done")
    let untaken = WidgetState(snapshot: working, pending: WidgetCommandQueue.pending(), now: now, calendar: calendar)
    check(untaken.check(for: item("q1", in: working)) == .open && untaken.snapshot.work == working.work, "a Done taken back leaves the row open and the work running")
    WidgetCommandQueue.remove(Set(WidgetCommandQueue.pending().map(\.id)))
    check(WidgetCommandSignal.name == "\(AppGroup.identifier).widget-commands", "the wake-up signal is namespaced by the App Group")
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

// MARK: - Pending commands over the snapshot

do {
    let base = WidgetState(snapshot: sample, now: now, calendar: calendar)
    check(base.snapshot == sample && base.closing.isEmpty, "with nothing pending the snapshot is drawn as published")
    check(base.todayProgress == (2, 9), "Today's progress counts done against everything due by today")
    check(base.check(for: item("k6")) == .done && base.check(for: item("q4")) == .open, "rows start open or done as published")

    let ticked = WidgetState(snapshot: sample, pending: [tap(.complete, "q4")], now: now, calendar: calendar)
    check(ticked.check(for: item("q4")) == .closing, "a pending tick draws the row closing")
    check(ticked.snapshot.todayItems.contains { $0.id == q4 }, "the closing row stays until the app applies it")
    check(ticked.snapshot.overdueCount == 3 && ticked.snapshot.completedTodayCount == 3, "a tick moves a late task to done")
    check(ticked.todayProgress == (3, 9), "progress already shows the tick")
    check(item("q4", in: ticked.snapshot).isOverdue(at: now, calendar: calendar), "a closing row keeps its late colour and section until the app settles it")
    let q3 = ticked.snapshot.lists.first { $0.title == "Q3 planning" }!
    check(q3.openCount == 3 && q3.doneCount == 2, "the list's counts follow the tick")
    check(ticked.snapshot.activity.today == 3 && ticked.snapshot.activity.days.last?.count == 3, "the heatmap counts the tick today")
    check(ticked.snapshot.agenda.first { $0.taskID == q4 }?.isCompleted == true, "the task's planned block is done too")

    var applied = sample
    applied.todayItems.removeAll { $0.id == q4 }
    for index in applied.lists.indices { applied.lists[index].openItems.removeAll { $0.id == q4 } }
    for index in applied.agenda.indices where applied.agenda[index].taskID == q4 { applied.agenda[index].isCompleted = true }
    applied.overdueCount -= 1
    applied.completedTodayCount += 1
    let replayed = WidgetState(snapshot: applied, pending: [tap(.complete, "q4")], now: now, calendar: calendar)
    check(replayed.snapshot == applied && replayed.closing.isEmpty, "a command the app already applied is not counted twice")

    let reopened = WidgetState(snapshot: sample, pending: [tap(.reopen, "k6")], now: now, calendar: calendar)
    let kyotoList = reopened.snapshot.lists.first { $0.id == kyoto }!
    check(kyotoList.openItems.last?.id == k6 && kyotoList.doneItems.isEmpty, "a reopened row moves to the open rows")
    check(kyotoList.openCount == 6 && kyotoList.doneCount == 0, "reopening restores the list's counts")
    check(reopened.snapshot.completedTodayCount == 1, "reopening today's completion takes it off done today")
    check(reopened.snapshot.activity == sample.activity, "Activity keeps a reopened completion as history, as the app's heatmap does")

    // A finished session stays on the agenda as history; reopening the task
    // does not turn that past block back into planned work.
    var withHistory = sample
    let k6Row = item("k6")
    withHistory.agenda.append(WidgetSnapshot.AgendaEvent(
        id: "completed-\(UUID())-0", kind: .task, title: k6Row.title, start: at(9), end: at(9, 20),
        taskID: k6, occurrenceID: k6Row.occurrenceID, isCompleted: true
    ))
    let reopenedHistory = WidgetState(snapshot: withHistory, pending: [command(.reopen, k6, occurrence: k6Row.occurrenceID)], now: now, calendar: calendar)
    check(reopenedHistory.snapshot.agenda.filter { $0.taskID == k6 }.allSatisfy(\.isCompleted), "reopening leaves the task's completed blocks done")

    let started = WidgetState(snapshot: sample, pending: [tap(.startWork, "q1")], now: now, calendar: calendar)
    let work = started.snapshot.work
    check(work?.state == .working && work?.segmentStartedAt == now && work?.blockStart == at(10) && work?.blockEnd == at(11, 30),
          "Start records against the block under way")
    check(work?.estimateMinutes == 90 && work?.title == "Draft Q3 OKRs", "the session takes the block's length and title")
    check(started.snapshot.agenda.first { $0.id == "block-q1" }?.isActive == true, "the recording block is marked active")
    let early = WidgetState(snapshot: sample, pending: [tap(.startWork, "q1", at: at(9, 50))], now: at(9, 51), calendar: calendar)
    check(early.snapshot.work?.blockStart == nil && early.snapshot.work?.estimateMinutes == 90,
          "Start ahead of the block records into no slot, since the app replans the block from the tap, but keeps its length")
    check(early.snapshot.agenda.allSatisfy { !$0.isActive }, "a block not yet under way is not marked as recording")
    check(early.upNext.phase == .working && early.upNext.rangeText.isEmpty && early.upNext.later.first?.time == "10:00",
          "Up Next shows no slot for it, and the rest of the day stays later")

    // Work taps are drawn only while the app would still apply them, so these
    // sequences happen within the two-minute window.
    let paused = WidgetState(snapshot: sample, pending: [tap(.startWork, "q1"), command(.pauseWork, q1, occurrence: q1Occurrence, at: at(10, 41))],
                             now: at(10, 42), calendar: calendar)
    check(paused.snapshot.work?.state == .paused && paused.snapshot.work?.priorSeconds == 60 && paused.snapshot.work?.segmentStartedAt == nil,
          "Pause closes the running segment")
    check(paused.snapshot.agenda.first { $0.id == "block-q1" }?.isActive == false, "a paused session records into no block")
    check(paused.upNext.phase == .paused && paused.upNext.elapsed == 60, "Up Next shows the paused session")

    let resumed = WidgetState(snapshot: sample, pending: [tap(.startWork, "q1"), command(.pauseWork, q1, occurrence: q1Occurrence, at: at(10, 41)),
                                                          command(.resumeWork, q1, occurrence: q1Occurrence, at: at(10, 42))],
                              now: at(10, 42), calendar: calendar)
    check(resumed.snapshot.work?.state == .working && resumed.snapshot.work?.elapsed(at: at(10, 43)) == 120, "Resume carries the recorded time forward")
    let restarted = WidgetState(snapshot: sample, pending: [tap(.startWork, "q1"), command(.pauseWork, q1, occurrence: q1Occurrence, at: at(10, 41)),
                                                            tap(.startWork, "q1", at: at(10, 42))],
                                now: at(10, 42), calendar: calendar)
    check(restarted.snapshot.work?.priorSeconds == 60 && restarted.snapshot.work?.state == .working, "Start on the paused task resumes it")

    let finished = WidgetState(snapshot: sample, pending: [tap(.startWork, "q1"), command(.finishWork, q1, occurrence: q1Occurrence, at: at(10, 41))],
                               now: at(10, 42), calendar: calendar)
    check(finished.snapshot.work == nil && finished.check(for: item("q1")) == .closing, "Done ends the session and ticks the task")
    check(finished.snapshot.overdueCount == 3, "finishing a late task takes it off the late count")
    check(finished.upNext.phase == .next && finished.upNext.title == "Write interview feedback for Priya", "Up Next moves on after Done")

    let working = WidgetSnapshot.sample(now: now, work: .working, calendar: calendar)
    let pausedLater = WidgetState(snapshot: working, pending: [command(.pauseWork, q1, occurrence: q1Occurrence, at: at(10, 41))], now: at(10, 42), calendar: calendar)
    check(pausedLater.snapshot.work?.priorSeconds == 64, "pausing a session the app started keeps its time")
    let doublePause = WidgetState(snapshot: pausedLater.snapshot, pending: [command(.pauseWork, q1, occurrence: q1Occurrence, at: at(10, 42))],
                                  now: at(10, 42), calendar: calendar)
    check(doublePause.snapshot == pausedLater.snapshot, "pausing twice is harmless")
    let unnamed = WidgetState(snapshot: working, pending: [command(.pauseWork, at: at(10, 41))], now: at(10, 42), calendar: calendar)
    check(unnamed.snapshot == working, "a Pause without ids is ignored, as the app ignores it")
    // The app drops Start, Pause and Resume older than two minutes rather than
    // replay them, so the widget stops drawing them too; ticks keep.
    let expiredPause = WidgetState(snapshot: working, pending: [command(.pauseWork, q1, occurrence: q1Occurrence, at: at(10, 41))], now: at(10, 45), calendar: calendar)
    check(expiredPause.snapshot.work?.state == .working, "a Pause the app will refuse as stale is not drawn")
    check(!WidgetState(snapshot: sample, now: at(23, 59), calendar: calendar).isOutdated
          && !WidgetState(snapshot: sample, now: at(8, day: 1), calendar: calendar).isOutdated
          && WidgetState(snapshot: sample, now: at(8, day: 2), calendar: calendar).isOutdated,
          "a snapshot is outdated once the app has missed a whole day")
    let expiredStart = WidgetState(snapshot: sample, pending: [tap(.startWork, "q1", at: at(10, 30))], now: now, calendar: calendar)
    check(expiredStart.snapshot.work == nil, "a stale Start draws no running clock")
    let oldTick = WidgetState(snapshot: sample, pending: [command(.complete, q1, occurrence: q1Occurrence, at: at(8))], now: now, calendar: calendar)
    check(oldTick.check(for: item("q1")) == .closing, "a tick stays drawn while it waits for the app")
    check(WidgetCommand(action: .resumeWork, issuedAt: at(10, 38)).isCurrent(at: now) && !WidgetCommand(action: .resumeWork, issuedAt: at(10, 37)).isCurrent(at: now),
          "work commands stay current for two minutes")

    // A stale widget still drew other work when it was tapped. The app ignores
    // these taps, so the overlay must not draw them either.
    let staleTaps: [(WidgetSnapshot, WidgetCommand, String)] = [
        (working, command(.pauseWork, p1, occurrence: item("p1").occurrenceID), "Pause aimed at other work"),
        (working, command(.pauseWork, q1, occurrence: UUID()), "Pause aimed at an earlier occurrence"),
        (working, command(.pauseWork, q1), "Pause naming the task but no occurrence"),
        (working, command(.finishWork, p1, occurrence: item("p1").occurrenceID), "Done aimed at other work"),
        (working, tap(.startWork, "p1"), "Start while other work runs"),
        (WidgetSnapshot.sample(now: now, work: .paused, calendar: calendar), command(.resumeWork, p1, occurrence: item("p1").occurrenceID),
         "Resume aimed at other work"),
    ]
    for (snapshot, tap, name) in staleTaps {
        let state = WidgetState(snapshot: snapshot, pending: [tap], now: now, calendar: calendar)
        check(state.snapshot == snapshot && state.closing.isEmpty, "\(name) changes nothing")
    }

    // Every button names its task and occurrence, and the app acts on
    // nothing a command leaves out, so the overlay draws none of these.
    let unnamedTaps: [(WidgetSnapshot, WidgetCommand, String)] = [
        (sample, command(.complete, q4), "a tick naming no occurrence"),
        (sample, command(.complete, occurrence: item("q4").occurrenceID), "a tick naming no task"),
        (sample, command(.reopen, k6), "an untick naming no occurrence"),
        (sample, command(.startWork, q1), "a Start naming no occurrence"),
        (working, command(.finishWork, q1), "a Done naming no occurrence"),
        (working, command(.finishWork), "a Done naming nothing"),
        (WidgetSnapshot.sample(now: now, work: .paused, calendar: calendar), command(.resumeWork), "a Resume naming nothing"),
    ]
    for (snapshot, tap, name) in unnamedTaps {
        let state = WidgetState(snapshot: snapshot, pending: [tap], now: now, calendar: calendar)
        check(state.snapshot == snapshot && state.closing.isEmpty, "\(name) changes nothing")
    }

    // The app drops every queued command after the queue's lifetime, so a
    // tick is drawn until then and no longer.
    let morningTick = tap(.complete, "q1", at: at(8))
    check(morningTick.isCurrent(at: at(13, 59)) && !morningTick.isCurrent(at: at(14)) && morningTick.expiry == at(14),
          "a tick stays current for the queue's lifetime")
    let expiredTick = WidgetState(snapshot: sample, pending: [morningTick], now: at(14), calendar: calendar)
    check(expiredTick.check(for: item("q1")) == .open && expiredTick.snapshot.completedTodayCount == 2 && expiredTick.snapshot.activity == sample.activity,
          "a tick the app would drop is drawn open, and counted nowhere")

    // A clock set back since the tap dates it in the future; that is no fresher.
    check(!command(.startWork, q1, occurrence: q1Occurrence, at: now.addingTimeInterval(10 * 60)).isCurrent(at: now),
          "a work command dated well ahead of now is not current")
    check(command(.resumeWork, q1, occurrence: q1Occurrence, at: now.addingTimeInterval(60)).isCurrent(at: now),
          "within the window, either side of the tap")
    let futureStart = WidgetState(snapshot: sample, pending: [tap(.startWork, "q1", at: now.addingTimeInterval(10 * 60))], now: now, calendar: calendar)
    check(futureStart.snapshot.work == nil, "a Start dated well ahead draws no running clock")
    let nearStart = WidgetState(snapshot: sample, pending: [tap(.startWork, "q1", at: now.addingTimeInterval(60))], now: now, calendar: calendar)
    check(nearStart.snapshot.work?.segmentStartedAt == now, "one just ahead records from now, as the app starts it")
    let futureTick = WidgetState(snapshot: sample, pending: [tap(.complete, "q4", at: now.addingTimeInterval(3600))], now: now, calendar: calendar)
    check(futureTick.check(for: item("q4")) == .closing && futureTick.snapshot.completedTodayCount == 3, "a tick dated ahead counts as made now")

    // Ticked at 23:50 and still waiting after midnight: the app dates the
    // completion at the tap, so it belongs to the day before.
    let lateTick = WidgetState(snapshot: sample, pending: [tap(.complete, "k2", at: at(23, 50))], now: at(0, 5, day: 1), calendar: calendar)
    check(lateTick.check(for: item("k2")) == .closing && lateTick.snapshot.completedTodayCount == 0 && lateTick.todayProgress == (0, 7),
          "a tick from before midnight is drawn, but not as done today")
    let lateStats = ActivityStats(activity: lateTick.snapshot.activity, now: at(0, 5, day: 1), calendar: lateTick.calendar)
    check(lateStats.today == 0 && lateTick.snapshot.activity.days.last?.date == today && lateTick.snapshot.activity.days.last?.count == 3,
          "Activity counts it on the day of the tap, not the entry's")
    let lateSameDay = WidgetState(snapshot: sample, pending: [tap(.complete, "k2", at: at(23, 50))], now: at(23, 55), calendar: calendar)
    check(lateSameDay.snapshot.completedTodayCount == 3 && lateSameDay.snapshot.activity.days.last?.count == 3, "on the same day, it is done today")
    var noDays = sample
    noDays.activity = WidgetSnapshot.Activity(streak: 3, today: 1, week: 4, month: 9)
    let noDaysTick = WidgetState(snapshot: noDays, pending: [tap(.complete, "q4")], now: now, calendar: calendar).snapshot.activity
    check(noDaysTick.days.isEmpty && noDaysTick.today == 2 && noDaysTick.week == 5 && noDaysTick.month == 10 && noDaysTick.streak == 3,
          "without published days the app's totals take the tick, and a day already counted keeps its streak")
    let noDaysLate = WidgetState(snapshot: noDays, pending: [tap(.complete, "k2", at: at(23, 50))], now: at(0, 5, day: 1), calendar: calendar).snapshot.activity
    check(noDaysLate.today == 1 && noDaysLate.week == 5 && noDaysLate.streak == 3, "and a tick from the day before is not today's")

    // The app rolls a repeat forward rather than complete it, so Today does
    // not count it as done; Activity counts every completion.
    let repeated = WidgetState(snapshot: sample, pending: [tap(.complete, "k4")], now: now, calendar: calendar)
    check(repeated.check(for: item("k4")) == .closing && repeated.snapshot.dueTodayCount == 2 && !repeated.snapshot.dueToday.contains { $0.date == today },
          "a ticked repeat leaves today's due work")
    check(repeated.snapshot.completedTodayCount == 2 && repeated.todayProgress == (2, 8), "but is not done today: the app has it open again")
    let repeatList = repeated.snapshot.lists.first { $0.id == kyoto }!
    check(repeated.snapshot.totalOpenCount == sample.totalOpenCount && repeatList.openCount == 5 && repeatList.doneCount == 1,
          "and it stays among the open tasks")
    check(repeated.snapshot.activity.today == 3 && repeated.snapshot.activity.days.last?.count == 3, "Activity still counts the repeat")

    let later = WidgetState(snapshot: sample, now: at(11, 31), calendar: calendar)
    check(later.snapshot.overdueCount == 5 && later.snapshot.dueTodayCount == 2, "the late count follows a timed task passing its time")
    let tomorrow = WidgetState(snapshot: sample, now: at(0, 30, day: 1), calendar: calendar)
    check(tomorrow.snapshot.completedTodayCount == 0, "done today starts again after midnight")
    check(tomorrow.snapshot.overdueCount == 7 && tomorrow.snapshot.dueTodayCount == 1, "yesterday's due tasks count as late after midnight, and tomorrow's are due")

    // Written at 22:00 and not rewritten since, as when the app has quit: the
    // new day's work was published with it, so Today starts the day anyway.
    let written = WidgetSnapshot.sample(now: at(22), calendar: calendar)
    let q2 = WidgetSnapshot.sampleTaskID("q2")
    check(written.tomorrowItems.map(\.id) == [q2] && written.dueTomorrow == [WidgetSnapshot.Due(date: at(0, day: 1), includesTime: false)],
          "the snapshot carries tomorrow's rows and due dates")
    let morning = WidgetState(snapshot: written, now: at(8, day: 1), calendar: calendar)
    check(morning.snapshot.todayItems.last?.id == q2 && morning.snapshot.dueTodayCount == 1 && morning.snapshot.overdueCount == 7,
          "the next morning, tomorrow's task is due today and the rest of the evening's work is late")
    check(morning.snapshot.dueToday == [WidgetSnapshot.Due(date: at(0, day: 1), includesTime: false)], "and moves to late on time")
    check(morning.snapshot.tomorrowItems.isEmpty && morning.snapshot.dueTomorrow.isEmpty, "tomorrow's work is merged once")
    let tickedMorning = WidgetState(snapshot: written, pending: [tap(.complete, "q2", in: written, at: at(8, 5, day: 1))], now: at(8, 10, day: 1), calendar: calendar)
    check(tickedMorning.snapshot.dueTodayCount == 0 && tickedMorning.snapshot.dueToday.isEmpty && tickedMorning.snapshot.completedTodayCount == 1,
          "ticking it off counts it once")
    check(tickedMorning.snapshot.activity.days.last?.date == at(0, day: 1) && tickedMorning.snapshot.activity.days.last?.count == 1,
          "on a day the app has not published yet, Activity gains that day")
    let twoDays = WidgetState(snapshot: written, now: at(8, day: 2), calendar: calendar)
    check(twoDays.snapshot.overdueCount == 8 && twoDays.snapshot.dueTodayCount == 0, "a day later, it is late too")
    var timedTomorrow = written
    timedTomorrow.tomorrowItems[0].dueDate = at(9, day: 1)
    timedTomorrow.tomorrowItems[0].includesTime = true
    timedTomorrow.dueTomorrow = [WidgetSnapshot.Due(date: at(9, day: 1), includesTime: true)]
    let pastMidnight = WidgetState(snapshot: timedTomorrow, now: at(0, 1, day: 1), calendar: calendar)
    check(TimelineSchedule.snapshotDates(for: pastMidnight.snapshot, now: at(0, 1, day: 1), calendar: calendar).contains(at(9, day: 1)),
          "the timeline built after midnight has an entry when tomorrow's timed task turns late")
    check(WidgetState(snapshot: timedTomorrow, now: at(9, 30, day: 1), calendar: calendar).snapshot.overdueCount == 8, "and it is late after its time")
    var capped = written
    capped.overdueCount += 5
    let cappedMorning = WidgetState(snapshot: capped, now: at(8, day: 1), calendar: calendar)
    check(!cappedMorning.snapshot.todayItems.contains { $0.id == q2 } && cappedMorning.snapshot.dueTodayCount == 1,
          "when today's rows were capped, tomorrow's only count: the rows left out come before them")
}

// MARK: - Entries

do {
    let entry = SnapshotEntry(date: now, snapshot: sample, list: ListSelection(listID: UUID()), calendar: calendar)
    check(entry.selectedList?.id == kyoto, "a list that has gone falls back to the first real list")
    check(SnapshotEntry(date: now, snapshot: sample, list: ListSelection(listID: WidgetSnapshot.sampleListID("home")), calendar: calendar).selectedList?.title == "Home",
          "the configured list is shown")
    check(entry.at(at(12)).date == at(12) && entry.at(at(12)).list == entry.list, "an entry moved in time keeps its data and configuration")
    check(entry.state.calendar.firstWeekday == 2, "entries use the app's first weekday")
}

// MARK: - Up Next through the day

do {
    func upNext(_ date: Date, _ snapshot: WidgetSnapshot = sample) -> UpNext { UpNext(snapshot: snapshot, now: date, calendar: calendar) }

    let early = upNext(at(8))
    check(early.phase == .next && early.title == "Draft Q3 OKRs" && early.note == "in 120 min" && early.progress == 0, "before the first block, Up Next shows it as next")
    check(early.later.map(\.time) == ["09:30", "11:30", "13:00", "14:00", "15:30", "16:00", "16:30", "18:00"],
          "before the first block, Later today lists what comes before it too")
    let between = upNext(at(13, 40))
    check(between.phase == .next && between.title == "Order new water filters" && between.later.map(\.time) == ["14:00", "15:30", "16:00", "18:00"],
          "between blocks, the meetings before the next block are later today")

    let current = upNext(now)
    check(current.phase == .now && current.note == "50 min left" && current.rangeText == "10:00–11:30", "during a block, Up Next counts it down")
    check(abs(current.progress - 40.0 / 90) < 0.0001, "progress is the share of the block gone by")
    check(current.listLine() == "💼 Q3 planning" && current.listLine(includesIcon: false) == "Q3 planning", "the list line drops its emoji when asked")
    check(WidgetFormat.listLine(icon: "folder", name: "Q3 planning") == "Q3 planning"
          && WidgetFormat.listLine(icon: "cart.fill", name: "") == "",
          "a list icon naming an SF Symbol is left out of a line of text, never printed as its name")
    check(current.later.first == UpNext.Later(id: "block-p1", start: at(11, 30), title: "Write interview feedback for Priya", time: "11:30", accentHex: 0xB8479A, isMeeting: false),
          "Later today lists the next block with its list colour")
    check(current.later[2].title == "Board prep" && current.later[2].isMeeting && current.later[2].accentHex == nil, "meetings have no colour of their own")

    let short = upNext(at(11, 35))
    check(short.phase == .now && short.title == "Write interview feedback for Priya" && short.note == "15 min left", "back-to-back blocks hand over at the boundary")
    check(short.later.count == 6, "Later today shrinks as the day goes on")
    check(upNext(at(12)).phase == .next && upNext(at(12)).note == "in 60 min", "between blocks, Up Next looks ahead")

    let afternoon = upNext(at(16, 5))
    check(afternoon.title == "Order new water filters" && afternoon.later.map(\.title) == ["Pay the ryokan deposit"], "a meeting already under way is not listed as later")

    let evening = upNext(at(18, 20))
    check(evening.phase == .none && evening.title == "Nothing else planned" && evening.later.isEmpty && evening.rangeText.isEmpty,
          "after the last block the day is clear")
    check(evening.listName == "Your day is clear", "and says so")
    var meetingsOnly = sample
    for index in meetingsOnly.agenda.indices where meetingsOnly.agenda[index].kind == .task { meetingsOnly.agenda[index].isCompleted = true }
    let onlyMeetings = upNext(now, meetingsOnly)
    check(onlyMeetings.phase == .none && onlyMeetings.later.map(\.time) == ["14:00", "15:30", "16:00"] && onlyMeetings.later.allSatisfy(\.isMeeting),
          "with every block done, the day's remaining meetings are later")
    check(onlyMeetings.listName == "Next: Board prep at 14:00", "and the day is not called clear: the subtitle names the next meeting")

    let working = upNext(now, WidgetSnapshot.sample(now: now, work: .working, calendar: calendar))
    check(working.phase == .working && working.elapsed == 4 && working.timerOrigin == now.addingTimeInterval(-4), "a running session wins over the plan")
    check(working.note == "of 90 min" && working.rangeText == "10:00–11:30" && working.isRecording, "a running session shows its estimate and block")
    let pausedSample = WidgetSnapshot.sample(now: now, work: .paused, calendar: calendar)
    let paused = upNext(now, pausedSample)
    check(paused.phase == .paused && paused.timerOrigin == nil && paused.elapsed == 14, "a paused session shows a still clock")
    check(paused.rangeText == "10:00–11:30" && paused.later.first?.time == "11:30", "paused inside its block, the block stays in the header")

    // Pausing replans the rest of the task, so the app publishes paused work
    // with its next planned block, later today or on another day.
    func replanned(to start: Date, _ end: Date) -> WidgetSnapshot {
        var snapshot = pausedSample
        snapshot.work?.blockStart = start
        snapshot.work?.blockEnd = end
        let index = snapshot.agenda.firstIndex { $0.id == "block-q1" }!
        snapshot.agenda[index].start = start
        snapshot.agenda[index].end = end
        return snapshot
    }
    let afterMeetings = upNext(now, replanned(to: at(16, 45), at(17, 30)))
    check(afterMeetings.rangeText == "16:45–17:30" && afterMeetings.later.map(\.time) == ["11:30", "13:00", "14:00", "15:30", "16:00", "16:30", "18:00"],
          "paused work holds no time: everything ahead today is later, except its own replanned block")
    let tomorrowBlock = upNext(now, replanned(to: at(9, day: 1), at(9, 50, day: 1)))
    check(tomorrowBlock.phase == .paused && tomorrowBlock.rangeText.isEmpty && tomorrowBlock.later.count == 7,
          "a block on another day is not shown as today's, and hides nothing")
    var workingElsewhere = WidgetSnapshot.sample(now: now, work: .working, calendar: calendar)
    workingElsewhere.work?.blockStart = at(13)
    workingElsewhere.work?.blockEnd = at(13, 30)
    check(upNext(now, workingElsewhere).later.first?.time == "11:30", "running work only holds a block that has started")

    let skipped = WidgetState(snapshot: sample, pending: [tap(.complete, "q1")], now: now, calendar: calendar).upNext
    check(skipped.phase == .next && skipped.note == "in 50 min", "a completed block is skipped")
}

// MARK: - Wording

do {
    func due(_ key: String) -> String { WidgetFormat.dueText(for: item(key), now: now, calendar: calendar) }
    check(due("q4") == "3d late" && due("h1") == "1d late", "late tasks say how many days")
    check(due("q1") == "10:00" && item("q1").isOverdue(at: now, calendar: calendar), "a timed task shows its time, and is late once it passes")
    check(due("p1") == "11:30" && due("k4") == "Repeats", "timed and repeating tasks due today")
    check(due("q2") == "Tomorrow" && due("k1") == "Sat 26" && due("k5") == "Sun 27" && due("h3") == "Tue 29", "the coming week uses day names")
    check(due("k6") == "Done" && due("h2") == "", "done and undated tasks")

    var plain = item("h2")
    plain.dueDate = today
    check(WidgetFormat.dueText(for: plain, now: now, calendar: calendar) == "Today", "an all-day task due today")
    plain.dueDate = at(0, day: 10)
    check(WidgetFormat.dueText(for: plain, now: now, calendar: calendar) == "3 Oct", "further out, the date")
    plain.dueDate = at(15, day: -1)
    plain.includesTime = true
    check(WidgetFormat.dueText(for: plain, now: now, calendar: calendar) == "1d late", "a timed task from yesterday is a day late")

    func age(_ seconds: TimeInterval) -> String { WidgetFormat.age(of: now.addingTimeInterval(-seconds), now: now) }
    check(age(30) == "now" && age(299) == "now", "a capture from the last five minutes")
    check(age(300) == "5m" && age(12 * 60) == "10m" && age(3599) == "55m", "minutes, in fives")
    check(age(2 * 3600) == "2h" && age(26 * 3600) == "1d", "hours and days")
    // The timeline has an entry for every change of the label, so between
    // two entries the label a widget drew is still true.
    let captured = at(10, 38)
    check(stride(from: 0.0, through: 3 * 86_400, by: 60).allSatisfy { offset in
        let date = captured.addingTimeInterval(offset)
        let next = WidgetFormat.ageChange(of: captured, after: date)
        let label = WidgetFormat.age(of: captured, now: date)
        return next > date && WidgetFormat.age(of: captured, now: next.addingTimeInterval(-1)) == label
            && WidgetFormat.age(of: captured, now: next) != label
    }, "an age label changes exactly when ageChange says it does")
    check(WidgetFormat.ageChange(of: captured, after: captured) == at(10, 43) && WidgetFormat.ageChange(of: captured, after: at(11, 35)) == at(11, 38)
          && WidgetFormat.ageChange(of: captured, after: at(11, 38)) == at(12, 38), "five-minute steps for the first hour, then hourly")
    check(WidgetFormat.clock(at(9, 5), calendar: calendar) == "09:05" && WidgetFormat.range(at(10), at(11, 30), calendar: calendar) == "10:00–11:30",
          "clock times are 24-hour")
    check(WidgetFormat.minutesLeft(until: at(11, 30), now: now) == "50 min left" && WidgetFormat.minutesUntil(at(11, 30), now: now) == "in 50 min",
          "countdowns in minutes")
    check(WidgetFormat.minutesLeft(until: now.addingTimeInterval(20), now: now) == "1 min left", "a running block never says zero")
    check(WidgetFormat.dayLabel(now, calendar: calendar) == "Wed 23" && WidgetFormat.weekdayName(now, calendar: calendar) == "Wednesday", "day names")
    check(WidgetFormat.weekRange(from: at(0, day: -2), calendar: calendar) == "21 – 27 September", "a week inside one month")
    check(WidgetFormat.weekRange(from: at(0, day: 5), calendar: calendar) == "28 September – 4 October", "a week across a month end")
    check(WidgetFormat.count(1, "meeting") == "1 meeting" && WidgetFormat.count(4, "meeting") == "4 meetings", "counted nouns")
    check(WidgetStyle.darkAccent(0x7C4DF0) == 0x9B78FF, "the default accent lifts to the design's dark value")
    var ring = item("k2")
    ring.priority = 2
    check(WidgetStyle.light.checkColor(for: ring, isLate: false) == WidgetStyle.light.amber, "medium priority rings are amber, as in the app's rows")
    check(WidgetStyle.light.checkColor(for: ring, isLate: true) == WidgetStyle.light.red, "late work rings red whatever its priority")
    ring.priority = 0
    check(WidgetStyle.light.checkColor(for: ring, isLate: false) == WidgetStyle.light.listColor(ring.accentHex), "other rings wear their list's colour")
    check(WidgetStyle.darkAccent(0x2F6FE0) >> 16 > 0x2F && WidgetStyle.darkAccent(0x2F6FE0) & 0xFF == 0xFF, "other accents brighten for dark mode")
}

// MARK: - Activity and Summary

do {
    let weekCalendar = sample.calendar(base: calendar)
    let small = ActivityGrid.weeks(10, activity: sample.activity, now: now, calendar: weekCalendar)
    check(small.count == 10 && small.allSatisfy { $0.count == 7 }, "the small heatmap has ten weeks of seven days")
    check(small.last?[0].date == at(0, day: -2) && small.first?[0].date == at(0, day: -65), "columns run from nine weeks ago to this week, Monday first")
    check(small.last?[2].isToday == true && small.last?[2].count == 2, "today sits in the current week with its count")
    check(small.last?[3...].allSatisfy(\.isFuture) == true && small.last?[..<3].allSatisfy { !$0.isFuture } == true, "days still to come are empty")
    check(ActivityGrid.weeks(21, activity: sample.activity, now: now, calendar: weekCalendar).count == 21, "the medium heatmap has 21 weeks")
    check([0, 1, 2, 3, 4, 6, 7, 12].map(ActivityGrid.band) == [0, 1, 2, 2, 3, 3, 4, 4], "bands are 0, 1, 2–3, 4–6 and 7+")

    let stats = ActivityStats(activity: sample.activity, now: now, calendar: weekCalendar)
    check(stats.today == 2 && stats.week == 2 && stats.month == 49 && stats.streak == 1 && stats.monthName == "September",
          "the sample's totals match the mockup: 2 today, 2 this week, 49 in September, a 1-day streak")
    let quiet = ActivityStats(activity: sample.activity, now: at(9, day: 1), calendar: weekCalendar)
    check(quiet.today == 0 && quiet.streak == 1, "an empty today does not break the streak")
    check(ActivityStats(activity: WidgetSnapshot.Activity(streak: 3, today: 1), now: now, calendar: weekCalendar).streak == 3,
          "without published days the app's totals are used")

    let week = SummaryWeek.days(activity: sample.activity, now: now, calendar: weekCalendar)
    check(week.map(\.letter) == ["M", "T", "W", "T", "F", "S", "S"], "the week starts on the app's first weekday")
    check(week.map(\.count) == [0, 0, 2, nil, nil, nil, nil] && week[2].isToday, "this week's counts, with days to come empty")
}

// MARK: - Agenda layout

do {
    let day = AgendaLayout.day(now, snapshot: sample, now: now, calendar: calendar)
    check(day.meetingCount == 4 && day.plannedCount == 5 && day.isToday, "today's column holds its meetings and blocks")
    check(day.events.prefix(4).allSatisfy { $0.kind == .meeting }, "meetings come first so blocks draw on top")
    check(AgendaLayout.summary(for: day) == "Wed 23 · 4 meetings · 5 planned", "the day's summary line")

    let window = AgendaLayout.window(for: day.events, calendar: calendar)
    check(window == AgendaWindow(startHour: 9, endHour: 19), "the day spans at least nine to seven")
    let hour = window.hourHeight(in: 290)
    check(window.hourHeight(in: 299) == 29 && window.hourHeight(in: 5) == 1, "hours snap down to whole points, and never vanish")
    let draft = window.frame(for: day.events.first { $0.id == "block-q1" }!, hourHeight: hour, calendar: calendar)
    check(hour == 29 && draft.top == 30 && draft.height == 41.5, "a block's frame matches the design")
    let standup = window.frame(for: day.events.first { $0.title == "Standup" }!, hourHeight: hour, calendar: calendar)
    check(standup.top == 15.5 && standup.height == 13, "short events keep one line of height")
    check(abs(window.nowOffset(now, hourHeight: hour, calendar: calendar)! - 48.333) < 0.001, "the now line sits at 10:40")
    check(window.nowOffset(at(21), hourHeight: hour, calendar: calendar) == nil, "the now line hides outside the window")
    check(window.labelHours() == [10, 12, 14, 16, 18], "hour labels every two hours inside the window")

    let week = AgendaLayout.week(snapshot: sample, now: now, calendar: sample.calendar(base: calendar))
    check(week.map(\.label) == ["Mon 21", "Tue 22", "Wed 23", "Thu 24", "Fri 25", "Sat 26", "Sun 27"], "the week runs Monday to Sunday")
    check(week.firstIndex(where: \.isToday) == 2 && week[6].events.isEmpty, "today is the third column; Sunday is empty")
    check(AgendaLayout.summary(for: week[6]) == "Sun 27 · Nothing planned" && AgendaLayout.summary(for: week[5]) == "Sat 26 · 1 meeting",
          "the summary leaves out counts that are zero")
    let plannedOnly = AgendaDay(date: at(0, day: 4), isToday: false, label: "Sun 27", events: week[3].events.filter { $0.kind == .task })
    check(AgendaLayout.summary(for: plannedOnly) == "Sun 27 · 1 planned", "a day of planned work only")
    var stale = sample
    stale.weekStart = at(0, day: -9)
    check(AgendaLayout.weekStart(snapshot: stale, now: now, calendar: sample.calendar(base: calendar)) == at(0, day: -2),
          "a week that no longer covers today falls back to this week")

    func event(_ id: String, _ start: Date, _ end: Date) -> WidgetSnapshot.AgendaEvent {
        WidgetSnapshot.AgendaEvent(id: id, kind: .meeting, title: id, start: start, end: end)
    }
    let columns = AgendaLayout.columns(for: [event("a", at(10), at(11)), event("b", at(10, 30), at(11, 30)), event("c", at(11), at(12)), event("d", at(13), at(14))])
    check(columns["a"] == AgendaColumn(index: 0, count: 2) && columns["b"] == AgendaColumn(index: 1, count: 2) && columns["c"] == AgendaColumn(index: 0, count: 2),
          "overlapping events share the width; touching ones share a column")
    check(columns["d"] == AgendaColumn(index: 0, count: 1), "an event on its own takes the full width")
    let wide = AgendaLayout.window(for: [event("early", at(7, 30), at(8)), event("late", at(20), at(21, 15))], including: at(22, 30), calendar: calendar)
    check(wide == AgendaWindow(startHour: 7, endHour: 23), "the window widens for early and late events and for now")

    // Blocks in a day column 280 points wide, 5 in from either side.
    func blocks(_ events: [WidgetSnapshot.AgendaEvent], in window: AgendaWindow, hourHeight: CGFloat) -> [String: CGRect] {
        Dictionary(uniqueKeysWithValues: window.blocks(for: events, hourHeight: hourHeight, width: 280, inset: 5, calendar: calendar).map { ($0.id, $0.rect) })
    }
    func meets(_ upper: CGRect?, _ lower: CGRect?) -> Bool {
        guard let upper, let lower else { return false }
        return abs(upper.maxY - lower.minY) < 0.001
    }
    // On the design's nine-to-seven grid nothing is cut short or moved aside,
    // so the widget still draws the mockup.
    for hourHeight: CGFloat in [26, 27, 28, 29] {
        for column in week {
            let placed = window.blocks(for: column.events, hourHeight: hourHeight, width: 280, inset: 5, calendar: calendar)
            check(placed.allSatisfy { block in
                let frame = window.frame(for: block.event, hourHeight: hourHeight, calendar: calendar)
                return block.rect == CGRect(x: 5, y: frame.top, width: 270, height: frame.height)
            }, "at \(hourHeight) points an hour, \(column.label)'s blocks are the full width and their own height")
        }
    }
    // A 07:00 gym session and a 19:00 dinner make a thirteen-hour grid, whose
    // half-hours are shorter than a line of title. Back to back they still
    // share the full width; the earlier one stops at the later one's top.
    let standupID = day.events.first { $0.title == "Standup" }!.id
    let priya = day.events.first { $0.title == "Priya debrief" }!.id
    let coffee = day.events.first { $0.title == "Coffee with Leo" }!.id
    let longDay = AgendaWindow(startHour: 7, endHour: 20)
    for hourHeight: CGFloat in [22, 21, 20, 18] {
        let placed = blocks(day.events, in: longDay, hourHeight: hourHeight)
        check(placed.count == day.events.count && placed.values.allSatisfy { $0.minX == 5 && $0.width == 270 },
              "at \(hourHeight) points an hour, the sample day's back-to-back half-hours keep the full width")
        check(meets(placed[standupID], placed["block-q1"]) && meets(placed[priya], placed[coffee]) && meets(placed[coffee], placed["block-h2"]),
              "at \(hourHeight) points an hour, a half-hour that would run into the next block stops at its top")
        check(placed[standupID]!.height == hourHeight / 2, "a half-hour cut short keeps its own half hour of height")
    }
    // Cut to less than that, a block would lose its title, so it moves aside.
    let tooClose = blocks([event("x", at(10), at(10, 10)), event("y", at(10, 20), at(10, 30))], in: longDay, hourHeight: 21)
    check(tooClose["x"] == CGRect(x: 5, y: 64, width: 134, height: 13) && tooClose["y"]?.minX == 141,
          "a ten-minute block ten minutes before another still moves aside on a long day")
    let backToBack = blocks([event("x", at(16, 40), at(16, 50)), event("y", at(16, 50), at(17))], in: window, hourHeight: 29)
    check(backToBack["x"]?.width == 134 && backToBack["y"]?.width == 134, "back-to-back ten-minute blocks sit side by side")
    // Whatever the hour's height, no block is drawn under another, and none
    // is cut shorter than its title's capitals.
    var crowded = week
    crowded[2].events += [
        event("gym", at(7), at(8)), event("dinner", at(19), at(20)), event("call", at(10, 30), at(11, 15)),
        event("ten", at(16, 40), at(16, 50)), event("ten-more", at(16, 50), at(17)), event("gap", at(17, 10), at(17, 20)),
    ]
    let crowdedWindow = AgendaLayout.window(for: crowded.flatMap(\.events), calendar: calendar)
    for hourHeight in stride(from: CGFloat(8), through: 30, by: 1) {
        for column in crowded {
            let placed = crowdedWindow.blocks(for: column.events, hourHeight: hourHeight, width: 280, inset: 5, calendar: calendar)
            let apart = placed.allSatisfy { a in
                placed.allSatisfy { b in
                    let overlap = a.rect.intersection(b.rect)
                    return a.id == b.id || overlap.isNull || overlap.width * overlap.height < 0.001
                }
            }
            check(apart, "at \(hourHeight) points an hour, no block on \(column.label) is drawn under another")
            check(placed.allSatisfy { $0.rect.height >= 9 - 0.001 }, "at \(hourHeight) points an hour, no block on \(column.label) is cut below nine points")
        }
    }
}

// MARK: - Timeline dates

do {
    var quietInbox = sample
    quietInbox.inboxItems = []
    check(TimelineSchedule.snapshotDates(for: quietInbox, now: now, calendar: calendar) == [now, at(11, 30), at(18)],
          "Today gets an entry when each timed task turns late")
    let hourly = TimelineSchedule.snapshotDates(for: sample, now: now, calendar: calendar)
    check(hourly.contains(at(11, 40)) && hourly.contains(at(23, 40)) && hourly.contains(at(11, 30)) && !hourly.contains(at(11)),
          "Inbox ages get an entry on each capture's own hour marks, not the clock's")
    check(TimelineSchedule.nextDay(after: now, calendar: calendar) == at(0, 1, day: 1), "timelines reload a minute past midnight")
    check(TimelineSchedule.reload(after: hourly, now: now, calendar: calendar) == at(0, 1, day: 1), "a day that fits in the timeline reloads after midnight")
    var fresh = quietInbox
    fresh.inboxItems = [WidgetSnapshot.InboxItem(id: UUID(), title: "Fresh", createdAt: at(10, 38))]
    let freshDates = TimelineSchedule.snapshotDates(for: fresh, now: now, calendar: calendar)
    check([at(10, 43), at(10, 48), at(11, 33), at(11, 38), at(12, 38), at(23, 38)].allSatisfy(freshDates.contains) && freshDates.count == 1 + 2 + 11 + 13,
          "a fresh capture gets an entry every five minutes for its first hour, then hourly")

    // Every task due today turns late on time, including those past the
    // snapshot's row cap: here 14 late tasks fill the rows, and the one due at
    // 15:00 exists only in `dueToday`.
    var crowdedRows = quietInbox
    crowdedRows.todayItems.removeAll { !$0.isOverdue(at: now, calendar: calendar) }
    for index in crowdedRows.lists.indices { crowdedRows.lists[index].openItems.removeAll { $0.dueDate.map { $0 >= today } ?? false } }
    crowdedRows.overdueCount = 14
    crowdedRows.dueTodayCount = 1
    crowdedRows.dueToday = [WidgetSnapshot.Due(date: at(15), includesTime: true)]
    let atFour = WidgetState(snapshot: crowdedRows, now: at(16), calendar: calendar)
    check(atFour.snapshot.overdueCount == 15 && atFour.snapshot.dueTodayCount == 0 && atFour.snapshot.dueToday.isEmpty,
          "a task past the row cap moves to late when its time passes")
    check(TimelineSchedule.snapshotDates(for: crowdedRows, now: now, calendar: calendar) == [now, at(15)], "and gets an entry at that moment")

    // Ticks and unticks keep `dueToday` in step with the count, so entries
    // before and after a task's time agree.
    let tickedP1 = WidgetState(snapshot: sample, pending: [tap(.complete, "p1")], now: now, calendar: calendar)
    check(tickedP1.snapshot.dueTodayCount == 2 && !tickedP1.snapshot.dueToday.contains { $0.date == at(11, 30) }
          && !TimelineSchedule.snapshotDates(for: tickedP1.snapshot, now: now, calendar: calendar).contains(at(11, 30)),
          "a task ticked off leaves the due-today dates")
    let tickedLater = WidgetState(snapshot: sample, pending: [tap(.complete, "p1")], now: at(11, 31), calendar: calendar)
    check(tickedP1.todayProgress == (3, 9) && tickedLater.todayProgress == (3, 9) && tickedLater.snapshot.overdueCount == 4,
          "a pending tick counts the same once its time has passed")
    var doneAtThree = sample
    let kyotoIndex = doneAtThree.lists.firstIndex { $0.id == kyoto }!
    doneAtThree.lists[kyotoIndex].doneItems[0].dueDate = at(15)
    doneAtThree.lists[kyotoIndex].doneItems[0].includesTime = true
    let untickedAtThree = WidgetState(snapshot: doneAtThree, pending: [tap(.reopen, "k6")], now: now, calendar: calendar)
    check(untickedAtThree.snapshot.dueTodayCount == 4 && untickedAtThree.snapshot.dueToday.map(\.date) == [today, at(11, 30), at(15), at(18)]
          && TimelineSchedule.snapshotDates(for: untickedAtThree.snapshot, now: now, calendar: calendar).contains(at(15)),
          "a task unticked before its time is due today again, with an entry when it turns late")
    let untickedLater = WidgetState(snapshot: doneAtThree, pending: [tap(.reopen, "k6")], now: at(15, 30), calendar: calendar)
    check(untickedLater.snapshot.overdueCount == 6 && untickedLater.snapshot.dueTodayCount == 2, "and late once its time has passed")

    // A tap waiting for the app is drawn until the app would drop it, so the
    // timelines have an entry at that moment.
    let waiting = [tap(.complete, "q4", at: at(8)), tap(.pauseWork, "q1")]
    check(TimelineSchedule.snapshotDates(for: quietInbox, pending: waiting, now: now, calendar: calendar)
          == [now, now.addingTimeInterval(121), at(11, 30), at(14), at(18)], "a waiting tap gets an entry when it expires")
    check(TimelineSchedule.upNextDates(for: WidgetSnapshot.sample(now: now, work: .paused, calendar: calendar), pending: waiting, now: now, calendar: calendar)
          .contains(now.addingTimeInterval(121)), "including while Up Next holds still")
    check(TimelineSchedule.agendaDates(for: sample, pending: [tap(.complete, "q4", at: at(8, 7))], now: now, calendar: calendar).contains(at(14, 7)),
          "and on the agenda")

    let upNext = TimelineSchedule.upNextDates(for: sample, now: now, calendar: calendar)
    check(upNext.first == now && upNext[1] == at(10, 41) && upNext.last == at(12, 10) && upNext.count == 91, "Up Next steps a minute at a time for 90 minutes")
    check(upNext.contains(at(11, 30)) && upNext.contains(at(11, 50)) && upNext == upNext.sorted(), "block boundaries are included, in order")
    check(TimelineSchedule.upNextReload(after: upNext, now: now, calendar: calendar) == at(12, 10), "Up Next reloads when its steps run out")
    let evening = TimelineSchedule.upNextDates(for: sample, now: at(18, 20), calendar: calendar)
    check(evening == [at(18, 20)] && TimelineSchedule.upNextReload(after: evening, now: at(18, 20), calendar: calendar) == at(0, 1, day: 1),
          "with the plan over, Up Next waits for tomorrow")
    let recording = WidgetSnapshot.sample(now: now, work: .working, calendar: calendar)
    check(TimelineSchedule.upNextDates(for: recording, now: at(23), calendar: calendar).count == 91, "running work fills its bar a minute at a time")
    let holding = WidgetSnapshot.sample(now: now, work: .paused, calendar: calendar)
    let overnight = TimelineSchedule.upNextDates(for: holding, now: at(23), calendar: calendar)
    check(overnight == [at(23)] && TimelineSchedule.upNextReload(after: overnight, now: at(23), calendar: calendar) == at(0, 1, day: 1),
          "paused work adds no minute steps, so it does not reload through the night")
    let pausedDay = TimelineSchedule.upNextDates(for: holding, now: now, calendar: calendar)
    check(pausedDay.first == now && pausedDay[1] == at(11, 30) && TimelineSchedule.upNextReload(after: pausedDay, now: now, calendar: calendar) == at(18, 15),
          "while paused, only the day's boundaries step")

    let agenda = TimelineSchedule.agendaDates(for: sample, now: now, calendar: calendar)
    check(agenda.first == now && agenda[1] == at(10, 45) && agenda.last == at(0, day: 1), "the agenda steps every quarter hour until midnight")
    check(agenda.contains(at(11, 50)) && agenda.contains(at(16, 40)) && agenda.count == 57, "the agenda adds boundaries between quarters")
    check(agenda.count <= TimelineSchedule.maximumEntries && upNext.count <= TimelineSchedule.maximumEntries, "timelines stay within the entry budget")
    check(TimelineSchedule.reload(after: agenda, now: now, calendar: calendar) == at(0, 1, day: 1), "the agenda reloads after midnight")
    var busyDay = quietInbox
    busyDay.agenda = (0..<14).map { hour in
        WidgetSnapshot.AgendaEvent(id: "busy-\(hour)", kind: .meeting, title: "Busy", start: at(8 + hour, 5), end: at(8 + hour, 40))
    }
    let busyDates = TimelineSchedule.agendaDates(for: busyDay, now: at(0, 5), calendar: calendar)
    check(busyDates.count == TimelineSchedule.maximumEntries && busyDates.last == at(22, 45)
          && TimelineSchedule.reload(after: busyDates, now: at(0, 5), calendar: calendar) == at(22, 45),
          "a day cut short by the entry cap reloads at its last entry instead of freezing until midnight")
}

print("✅ \(checks) widget checks passed")
