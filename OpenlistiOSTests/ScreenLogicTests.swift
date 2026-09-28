//
//  ScreenLogicTests.swift
//  OpenlistiOSTests
//

import Foundation
import SwiftData
import Testing
@testable import OpenlistiOS

/// What the screens read from the fixture, and the steps they take, against
/// the mockups' Wednesday 23 September, 10:40.
@MainActor
struct ScreenLogicTests {
    private func library(_ phone: TestPhone) throws -> NextLibrary {
        let task = BlockKind.task.rawValue
        let tasks = try phone.container.mainContext.fetch(FetchDescriptor<Block>(
            predicate: #Predicate { $0.trashID == nil && $0.kindRaw == task }))
        return NextLibrary(lists: phone.store.allLists(includeArchived: true), sections: phone.store.allSections(),
                           labels: phone.store.allLabels(), tasks: tasks)
    }

    private func blocks(_ phone: TestPhone) throws -> [Block] {
        try phone.container.mainContext.fetch(FetchDescriptor<Block>(predicate: #Predicate { $0.trashID == nil }))
    }

    // MARK: Today and the work in hand

    @Test func theWorkInHandIsTheFixturesSession() throws {
        let phone = try TestPhone(seeded: true)
        let work = PhoneWork(env: phone.env, now: phone.env.now)
        #expect(work.task?.displayTitle == "Draft Q3 OKRs")
        #expect(work.state == .working)
        #expect(work.leftText == "50 min left")
        #expect(work.card?.eyebrow == "Now · 10:00")
        let start = try #require(work.start), end = try #require(work.end)
        #expect(OLFormat.range(start, end) == "10:00–11:30")
        #expect(abs(work.progress(now: phone.env.now) - 40.0 / 90.0) < 0.01)
    }

    @Test func pausedWorkStaysInHand() throws {
        let phone = try TestPhone(seeded: true)
        phone.env.calendar.pause(now: phone.env.now)
        let work = PhoneWork(env: phone.env, now: phone.env.now)
        #expect(work.state == .paused)
        #expect(work.task?.displayTitle == "Draft Q3 OKRs")
        #expect(work.card?.state == .paused)
    }

    @Test func todaysRowsSayWhatTodayDoesnt() throws {
        let phone = try TestPhone(seeded: true)
        let now = phone.env.now, calendar = phone.env.settings.calendar
        func trailing(_ title: String, _ context: PhoneRowContext) throws -> OLTrailing? {
            PhoneTaskRow.trailing(for: try #require(phone.task(title)), context: context, now: now, calendar: calendar)
        }
        #expect(try trailing("Close out Q2 retro actions", .today) == .text("3d late", tone: .late))
        #expect(try trailing("Pay the ryokan deposit", .today) == .text("18:00", tone: .due))
        // Due today with no time: Today says only that it repeats.
        #expect(try trailing("Ask Mika to water the planters", .today)?.symbol == "repeat")
        #expect(try trailing("Ask Mika to water the planters", .today)?.text == nil)
        #expect(try trailing("Ask Mika to water the planters", .list)?.text == "Today")
        #expect(try trailing("Ask Mika to water the planters", .select) == .text("Today", tone: .due))
        #expect(try trailing("Book the ryokan", .list) == .star)
        #expect(try trailing("Book the ryokan", .select) == nil)
        #expect(try trailing("Renew passports", .list)?.text == "Sat")
        #expect(try trailing("Reply to Kasuga about the tatami room", .list) == .text("08:28"))
        #expect(try trailing("Compare Gion vs Arashiyama", .list) == .text("Yesterday", tone: .done))
    }

    @Test func todaysScheduleRunsByTime() throws {
        let phone = try TestPhone(seeded: true)
        let lib = try library(phone)
        let now = phone.env.now, calendar = phone.env.settings.calendar
        let slots = PhoneWork.slots(phone.env.calendar, on: now, calendar: calendar)
        let agenda = TodayAgenda(tasks: lib.tasksInOutlineOrder(blocks: try blocks(phone)), now: now, calendar: calendar,
                                 order: .schedule, time: { slots[$0.id] })
        #expect(agenda.scheduled.map(\.displayTitle) == [
            "Close out Q2 retro actions", "Reserve the Nishiki market tour", "Fix the dripping bathroom tap",
            "Draft Q3 OKRs", "Write interview feedback for Priya", "Update the design role scorecard",
            "Order new water filters", "Pay the ryokan deposit", "Ask Mika to water the planters",
        ])
        #expect(agenda.starred.map(\.displayTitle) == ["Book the ryokan", "Finish The Overstory"])
        #expect(agenda.progress == (2, 13))
    }

    // MARK: Timeline

    @Test func theTimelineDrawsTheMockupsDay() throws {
        let phone = try TestPhone(seeded: true)
        let now = phone.env.now
        let schedule = TimelineSchedule(env: phone.env, library: try library(phone),
                                        day: phone.env.settings.calendar.startOfDay(for: now), now: now)
        let drawn = Dictionary(schedule.items.map { ($0.title, $0) }, uniquingKeysWith: { first, _ in first })
        #expect(drawn["Standup notes"]?.kind == .done)
        #expect(drawn["Draft Q3 OKRs"]?.kind == .working)
        #expect(drawn["Draft Q3 OKRs"]?.detail == "Now · 50 min left")
        #expect(drawn["Write interview feedback for Priya"]?.detail == "20m")
        #expect(drawn["Update the design role scorecard"]?.detail == "30m")
        #expect(drawn["Order new water filters"]?.detail == "10m")
        #expect(drawn["Design sync"]?.kind == .event)
        #expect(drawn["Pay the ryokan deposit"]?.kind == .due)
        #expect(schedule.hours == 0...24)
        #expect(Set(schedule.toPlan.map(\.displayTitle)) == ["Close out Q2 retro actions", "Reserve the Nishiki market tour",
                                                              "Fix the dripping bathroom tap", "Ask Mika to water the planters"])
    }

    @Test func toPlanFitsTasksIntoFreeTimeWithUndo() throws {
        let phone = try TestPhone(seeded: true)
        let task = try #require(phone.task("Fix the dripping bathroom tap"))
        #expect(phone.store.placements(taskID: task.id).isEmpty)
        #expect(phone.env.actions.fit([task]) == 1)
        let placement = try #require(phone.store.placements(taskID: task.id).first)
        #expect(placement.start >= phone.env.now)
        // Clear of the meeting and the other slots.
        #expect(phone.env.calendar.visibleBlocks.filter { $0.taskID != task.id && !$0.isCompleted }
            .allSatisfy { $0.end <= placement.start || $0.start >= placement.end })
        #expect(phone.env.tray.message?.text.hasPrefix("Planned “Fix the dripping bathroom tap” · Today") == true)
        phone.env.tray.performAction()
        #expect(phone.store.placements(taskID: task.id).isEmpty)
    }

    // MARK: Inbox and triage

    @Test func theInboxListsNewestFirstAndTriageOldestFirst() throws {
        let phone = try TestPhone(seeded: true)
        let lib = try library(phone)
        #expect(InboxScreen.captures(in: lib, closing: []).map(\.displayTitle).first == "Send Jun the photos from Nara")
        let queue = lib.inboxQueue(kept: [], closing: [])
        #expect(queue.count == 6)
        #expect(queue.first?.displayTitle == "Gift ideas for Mika’s birthday")
        #expect(CompactText.captured(try #require(queue.first).createdAt, now: phone.env.now) == "Captured 4 days ago")
    }

    @Test func triageKeepsWhatItSetsAside() throws {
        let phone = try TestPhone(seeded: true)
        let session = phone.env.triage
        let gift = try #require(phone.task("Gift ideas for Mika’s birthday"))
        session.begin()
        session.keep(gift.id)
        var queue = try library(phone).inboxQueue(triage: session, closing: [])
        #expect(session.reviewed(queue: queue) == 1)
        #expect(queue.first?.displayTitle == "Return the library books")
        // Scheduled from the card, a task stays in the Inbox with its day.
        let books = try #require(phone.task("Return the library books"))
        phone.env.actions.schedule([books], on: PhoneDay.tomorrow.date(now: phone.env.now, calendar: phone.env.settings.calendar))
        session.schedule(books.id, due: try #require(books.dueDate))
        #expect(books.listID == phone.store.inboxList()?.id)
        #expect(CompactText.dayOffset(from: phone.env.now, to: try #require(books.dueDate)) == 1)
        #expect(phone.env.tray.message?.text == "“Return the library books” due tomorrow")
        queue = try library(phone).inboxQueue(triage: session, closing: [])
        #expect(session.reviewed(queue: queue) == 2)
        // Its Undo puts the card back on the queue, and out of the count.
        phone.env.tray.performAction()
        #expect(books.dueDate == nil)
        queue = try library(phone).inboxQueue(triage: session, closing: [])
        #expect(queue.first?.displayTitle == "Return the library books")
        #expect(session.reviewed(queue: queue) == 1)
        // A card filed and then taken back is on the queue again too.
        let desk = try #require(phone.task("Look into a standing desk for the study"))
        #expect(phone.env.actions.move([desk], to: try #require(phone.list("Home"))))
        session.finish(desk.id)
        #expect(session.reviewed(queue: try library(phone).inboxQueue(triage: session, closing: [])) == 2)
        phone.env.tray.performAction()
        #expect(session.reviewed(queue: try library(phone).inboxQueue(triage: session, closing: [])) == 1)
        session.reviewKept()
        #expect(session.kept { _ in nil }.isEmpty)
    }

    /// A late card given another day, and a repeat marked done, stay aside
    /// only while that holds: Undo brings either back to the queue.
    @Test func triageUndoBringsDatedAndRolledCardsBack() throws {
        let session = TriageSession()
        let late = UUID(), repeating = UUID()
        let monday = TestClock.mockupNow.addingTimeInterval(-2 * 86_400)
        let friday = TestClock.mockupNow.addingTimeInterval(2 * 86_400)
        var due: [UUID: Date] = [late: monday, repeating: monday]
        session.schedule(late, due: friday)
        session.rollOn(repeating, from: monday)
        // Before its date lands, and while the repeat hasn't rolled on, neither is aside.
        #expect(session.kept { due[$0] }.isEmpty)
        due[late] = friday
        due[repeating] = friday
        #expect(session.kept { due[$0] } == [late, repeating])
        // Undo: the old dates are back.
        due[late] = monday
        due[repeating] = monday
        #expect(session.kept { due[$0] }.isEmpty)
    }

    @Test func thisWeekendIsTheComingSaturday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let wednesday = TestClock.mockupNow
        let saturday = PhoneDay.weekend.date(now: wednesday, calendar: calendar)
        #expect(calendar.component(.weekday, from: saturday) == 7)
        #expect(CompactText.dayOffset(from: wednesday, to: saturday, calendar: calendar) == 3)
        let sunday = calendar.date(byAdding: .day, value: 4, to: wednesday)!
        #expect(calendar.isDate(PhoneDay.weekend.date(now: sunday, calendar: calendar), inSameDayAs: sunday))
    }

    /// Triage files a card into a list with a day as one step, with one Undo.
    @Test func triageFilesToAListWithADayInOneStep() throws {
        let phone = try TestPhone(seeded: true)
        let calendar = phone.env.settings.calendar
        let task = try #require(phone.task("Look into a standing desk for the study"))
        let home = try #require(phone.list("Home"))
        let (inbox, due) = (task.listID, task.dueDate)
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: phone.env.now)))
        #expect(phone.env.actions.file(task, to: home, due: tomorrow))
        let filed = try #require(phone.task("Look into a standing desk for the study"))
        #expect(filed.listID == home.id)
        #expect(filed.dueDate.map { calendar.isDate($0, inSameDayAs: tomorrow) } == true)
        #expect(phone.env.tray.message?.text == "Moved “Look into a standing desk for the study” to Home, due tomorrow")
        phone.env.tray.performAction()
        let back = try #require(phone.task("Look into a standing desk for the study"))
        #expect(back.listID == inbox && back.dueDate == due)
    }

    /// A day alone leaves the card in the Inbox, dated.
    @Test func triageDatesACardInPlace() throws {
        let phone = try TestPhone(seeded: true)
        let task = try #require(phone.task("Return the library books"))
        let inbox = task.listID
        let friday = TestClock.mockupNow.addingTimeInterval(2 * 86_400)
        #expect(phone.env.actions.file(task, to: nil, due: friday))
        #expect(task.listID == inbox && task.dueDate != nil)
        #expect(phone.env.tray.message?.text == "“Return the library books” due Fri")
        #expect(!phone.env.actions.file(task, to: nil, due: nil), "Nothing picked, nothing filed")
    }

    // MARK: Capture

    @Test func aCaptureAddsWithUndo() throws {
        let phone = try TestPhone(seeded: true)
        let parse = CaptureParse("Buy yen for the trip fri 6pm ~15m #travel", reference: phone.env.now)
        let snapshot = parse.snapshot()
        #expect(snapshot.title == "Buy yen for the trip")
        #expect(snapshot.estimateMinutes == 15)
        #expect(snapshot.labels == ["travel"])
        #expect(CompactText.captureWhen(try #require(snapshot.date), includesTime: snapshot.includesTime, now: phone.env.now)
            == "Fri 25, 18:00")
        let block = try phone.store.saveCapture(snapshot, destinationID: nil)
        phone.env.actions.reportCapture(block)
        #expect(phone.env.tray.message?.text == "Added to Inbox")
        let id = block.id
        phone.env.tray.performAction()
        #expect(phone.store.block(id: id) == nil)
    }

    // MARK: Lists

    @Test func listsAreMadeRenamedArchivedAndTrashedWithUndo() throws {
        let phone = try TestPhone(seeded: true)
        let actions = phone.env.actions
        let garden = try #require(actions.createList(named: "  Garden "))
        #expect(garden.displayTitle == "Garden")
        let id = garden.id
        phone.env.tray.performAction()
        #expect(phone.store.list(id: id) == nil)

        let home = try #require(phone.list("Home"))
        actions.rename(home, to: "House")
        #expect(home.title == "House")
        phone.env.tray.performAction()
        #expect(home.title == "Home")

        actions.setArchived(true, for: home)
        #expect(home.isArchived)
        phone.env.tray.performAction()
        #expect(!home.isArchived)

        #expect(actions.trashList(home))
        #expect(home.trashID != nil)
        phone.env.tray.performAction()
        #expect(phone.list("Home")?.trashID == nil)
    }

    @Test func aListPageFoldsItsDoneTasks() throws {
        let phone = try TestPhone(seeded: true)
        let kyoto = try #require(phone.list("Weekend in Kyoto"))
        let page = BlockTree.listPage(phone.store.blocks(inList: kyoto.id), sorting: kyoto.sorting)
        #expect(page.openCount == 7)
        #expect(page.completed.map(\.displayTitle) == ["Reply to Kasuga about the tatami room"])
        #expect(page.rows.map(\.block.displayTitle).contains("Compare Gion vs Arashiyama"))
        #expect(page.rows.first { $0.block.displayTitle == "Pay the ryokan deposit" }?.depth == 1)
    }

    // MARK: Find

    @Test func findReadsLabelsAndDone() throws {
        let phone = try TestPhone(seeded: true)
        let lib = try library(phone)
        let language = lib.findQuery
        let travel = FindScreen.results(for: "#travel ", language: language, library: lib, blocks: try blocks(phone),
                                        now: phone.env.now, calendar: phone.env.settings.calendar)
        #expect(travel.map(\.displayTitle) == ["Reserve the Nishiki market tour", "Renew passports",
                                               "Pick up JR passes at Kyoto Station", "Book the ryokan"])
        let withDone = FindScreen.results(for: "#travel done", language: language, library: lib, blocks: try blocks(phone),
                                          now: phone.env.now, calendar: phone.env.settings.calendar)
        #expect(withDone.count == 5)
        #expect(withDone.last?.displayTitle == "Reply to Kasuga about the tatami room")
    }

    // MARK: Activity, Settings, Trash

    @Test func recentChangesNameWhatHappened() throws {
        let phone = try TestPhone(seeded: true)
        let changes = ActivityChange.recent(in: phone.store, now: phone.env.now)
        #expect(changes.first?.text == "Started Draft Q3 OKRs")
        #expect(ActivityChange.ago(try #require(changes.first).date, now: phone.env.now) == "40 min ago")
        #expect(changes.contains { $0.text == "Completed Standup notes" })
        #expect(changes.contains { $0.text == "Trashed Prep board update slides (duplicate)" })
        let heatmap = try phone.store.activityHeatmap(now: phone.env.now, calendar: phone.env.settings.calendar)
        #expect(heatmap.total == 81)
        #expect(heatmap.streak == 6)
    }

    @Test func theLatestStepCanBeUndoneFromActivity() throws {
        let phone = try TestPhone(seeded: true)
        let task = try #require(phone.task("Start Piranesi"))
        phone.env.actions.edit([task], "Starred “Start Piranesi”") { phone.store.toggleStar($0) }
        #expect(task.isStarred)
        #expect(phone.env.actions.latest?.text == "Starred “Start Piranesi”")
        phone.env.actions.undoLatest()
        #expect(!task.isStarred)
        #expect(phone.env.actions.latest == nil)
    }

    @Test func planHoursReadAsTheMockupDoes() {
        #expect(PlanHours.summary(CalendarPreferences()) == "09–17 · 18–21")
        #expect(PlanHours.clock(9 * 60 + 30) == "09:30")
        var off = AvailabilityProfile.workDefault
        off.weekly = [:]
        #expect(PlanHours.summary(off) == "Off")
    }

    /// Saving without a change keeps the hours, breaks and a 24:00 end as
    /// they were; a change moves only the usual hours.
    @Test func planHoursChangeOnlyWhatWasChanged() {
        var profile = AvailabilityProfile.workDefault
        profile.weekly[6] = [AvailabilityWindow(startMinute: 10 * 60, endMinute: 24 * 60)]
        var draft = PlanHoursDraft(profile, default: AvailabilityWindow(startMinute: 9 * 60, endMinute: 17 * 60))
        #expect(draft.applied(to: profile, days: []) == profile)
        draft.end = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: .now)!
        let changed = draft.applied(to: profile, days: [])
        #expect(changed.weekly[2] == [AvailabilityWindow(startMinute: 9 * 60, endMinute: 18 * 60)])
        // Friday's own hours, and the lunch break, stay.
        #expect(changed.weekly[6] == [AvailabilityWindow(startMinute: 10 * 60, endMinute: 24 * 60)])
        #expect(changed.breaks == profile.breaks)
    }

    /// Planning a task moves its slot rather than adding a second, and Undo
    /// puts the old one back.
    @Test func planningReplacesATasksSlot() throws {
        let phone = try TestPhone(seeded: true)
        let task = try #require(phone.task("Update the design role scorecard"))
        let before = try #require(phone.store.placements(taskID: task.id).first)
        let (start, end) = (before.start, before.end)
        #expect(phone.env.actions.fit([task]) == 1)
        let after = phone.store.placements(taskID: task.id).filter { $0.occurrenceID == task.occurrenceID }
        #expect(after.count == 1)
        phone.env.tray.performAction()
        let restored = phone.store.placements(taskID: task.id)
        #expect(restored.count == 1)
        #expect(restored.first?.start == start)
        #expect(restored.first?.end == end)
    }

    @Test func aTaskComesOffTheCalendarWithUndo() throws {
        let phone = try TestPhone(seeded: true)
        let task = try #require(phone.task("Order new water filters"))
        #expect(phone.env.actions.unplace(task))
        #expect(phone.store.placements(taskID: task.id).isEmpty)
        #expect(!phone.env.actions.unplace(task))
        phone.env.tray.performAction()
        #expect(phone.store.placements(taskID: task.id).count == 1)
    }

    // MARK: Widgets

    /// The widgets count Today as the iPhone's Today does, planned and starred
    /// work too: "2 of 13 done", "11 open", in the order it draws the day.
    @Test func theWidgetsCountTodayAsTheAppDoes() throws {
        let phone = try TestPhone(seeded: true)
        let publisher = WidgetSnapshotPublisher(store: phone.store, sources: .live(
            calendar: phone.env.calendar, settings: phone.env.settings, libraryID: phone.env.libraryID, isAppActive: { true }))
        let snapshot = publisher.buildSnapshot(now: phone.env.now)
        // The widget's total: done, overdue, due and the rest of Today.
        let done = snapshot.completedTodayCount
        #expect(done == 2)
        #expect(done + snapshot.overdueCount + snapshot.dueTodayCount + snapshot.plannedTodayCount == 13)
        #expect(snapshot.overdueCount == 3)
        let titles: [String] = snapshot.todayPlan.prefix(5).map { $0.title }
        #expect(titles == [
            "Close out Q2 retro actions", "Reserve the Nishiki market tour", "Fix the dripping bathroom tap",
            "Draft Q3 OKRs", "Write interview feedback for Priya",
        ])
    }

    // MARK: Estimate and the view toggle

    @Test func estimatesReadAsTime() {
        #expect(OLEstimateSlider.label(45) == "45 min")
        #expect(OLEstimateSlider.label(60) == "1 h")
        #expect(OLEstimateSlider.label(90) == "1 h 30 min")
        #expect(OLEstimateSlider.spoken(90) == "1 hour 30 minutes")
        #expect(OLEstimateSlider.spoken(120) == "2 hours")
        #expect(OLEstimateSlider.stops.first == 5 && OLEstimateSlider.stops.last == 480)
        #expect(OLEstimateSlider.stops == OLEstimateSlider.stops.sorted())
    }

    /// The toggle slides from the view Today just left, once.
    @Test func theViewToggleKnowsWhereItCameFrom() throws {
        let phone = try TestPhone()
        #expect(phone.navigator.takeTodaySwitch() == nil)
        phone.navigator.openTimeline(on: nil)
        #expect(phone.navigator.takeTodaySwitch() == .list)
        #expect(phone.navigator.takeTodaySwitch() == nil)
    }

    // MARK: Work

    /// Done on running work stops it at once, as on the Mac; Undo in the
    /// dwell offers it again, paused.
    @Test func doneStopsTheWorkAndUndoOffersItAgain() throws {
        let phone = try TestPhone(seeded: true)
        let draft = try #require(phone.task("Draft Q3 OKRs"))
        #expect(phone.env.calendar.activeSession?.taskID == draft.id)
        phone.env.actions.complete([draft])
        #expect(phone.env.calendar.activeSession == nil)
        #expect(phone.env.calendar.resumableTask == nil)
        phone.env.tray.performAction()
        #expect(!draft.isCompleted)
        #expect(phone.env.calendar.resumableTask?.id == draft.id)
    }

    /// Starting work is a step Activity can take back: the work stops, its
    /// session goes, and what was running before is offered again.
    @Test func startingWorkCanBeUndone() throws {
        let phone = try TestPhone(seeded: true)
        let draft = try #require(phone.task("Draft Q3 OKRs"))
        let priya = try #require(phone.task("Write interview feedback for Priya"))
        #expect(phone.env.actions.startWork(priya))
        let session = try #require(phone.env.calendar.activeSession)
        #expect(session.taskID == priya.id)
        #expect(phone.env.actions.latest?.sessionID == session.id)
        phone.env.actions.undoLatest()
        #expect(phone.env.calendar.activeSession == nil)
        #expect(phone.store.workSessions(taskID: priya.id).isEmpty)
        #expect(phone.env.calendar.resumableTask?.id == draft.id)
    }

    /// The fixture's running work is the session's latest step, as the
    /// design's Activity draws it with Undo; Undo stops it and takes it out.
    @Test func theFixturesRunningWorkCanBeUndone() throws {
        let phone = try TestPhone(seeded: true)
        let draft = try #require(phone.task("Draft Q3 OKRs"))
        let session = try #require(phone.env.calendar.activeSession)
        #expect(session.taskID == draft.id)
        #expect(phone.env.actions.latest?.sessionID == session.id)
        #expect(phone.env.actions.latest?.text == "Started “Draft Q3 OKRs”")
        phone.env.actions.undoLatest()
        #expect(phone.env.calendar.activeSession == nil)
        #expect(phone.store.workSessions(taskID: draft.id).allSatisfy { $0.id != session.id })
        #expect(phone.env.actions.latest == nil)
    }

    // MARK: Timeline

    /// The timeline is the whole day, opening an hour before now, with the
    /// day's unplaced tasks to drag onto it.
    @Test func theTimelineIsTheWholeDay() throws {
        let phone = try TestPhone(seeded: true)
        let now = phone.env.now
        let day = phone.env.settings.calendar.startOfDay(for: now)
        let schedule = TimelineSchedule(env: phone.env, library: try library(phone), day: day, now: now)
        #expect(schedule.hours == 0...24)
        #expect(schedule.scrollHour == 9)
        #expect(schedule.toPlan.contains { $0.displayTitle == "Fix the dripping bathroom tap" })
        #expect(!schedule.toPlan.contains { $0.displayTitle == "Update the design role scorecard" })
    }

    /// A drop lands on the nearest quarter hour, ends by midnight, and on
    /// today never before the next quarter hour from now; a day gone, or too
    /// little of today left, takes none.
    @Test func aDropStartsOnTheQuarterHour() throws {
        let calendar = TestClock.calendar
        let now = TestClock.mockupNow
        let today = calendar.startOfDay(for: now)
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: today))
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: today))
        func y(_ hour: Double) -> CGFloat { OLTimeline.inset + CGFloat(hour) * 44 }
        func start(_ hour: Double, day: Date, minutes: Int = 30, now: Date = now) -> String {
            guard let date = TimelinePlanning.start(atContentY: y(hour), day: day, minutes: minutes, now: now,
                                                    hourHeight: 44, calendar: calendar) else { return "none" }
            return "\(calendar.isDate(date, inSameDayAs: day) ? "" : "other ")\(CompactText.clock(date, calendar: calendar))"
        }
        #expect(start(14 + 7 / 60, day: today) == "14:00")
        #expect(start(14 + 8 / 60, day: today) == "14:15")
        #expect(start(9, day: today) == "10:45")
        #expect(start(9, day: tomorrow) == "09:00")
        #expect(start(23.9, day: tomorrow, minutes: 90) == "22:30")
        #expect(start(-1, day: tomorrow) == "00:00")
        #expect(start(15, day: yesterday) == "none")
        let late = today.addingTimeInterval(23 * 3600 + 20 * 60)
        #expect(start(23.5, day: today, minutes: 30, now: late) == "23:30")
        #expect(start(23.5, day: today, minutes: 60, now: late) == "none")
    }

    /// Blocks that overlap share the width, each in the first free column.
    @Test func overlappingBlocksShareTheWidth() throws {
        let base = TestClock.calendar.startOfDay(for: TestClock.mockupNow)
        func at(_ hour: Double) -> Date { base.addingTimeInterval(hour * 3600) }
        let items = [
            OLTimelineItem(id: "a", kind: .event, title: "A", start: at(14), end: at(15)),
            OLTimelineItem(id: "b", kind: .planned, title: "B", start: at(14.5), end: at(16)),
            OLTimelineItem(id: "c", kind: .planned, title: "C", start: at(15.25), end: at(15.75)),
            OLTimelineItem(id: "d", kind: .planned, title: "D", start: at(17), end: at(17.5)),
        ]
        let frames = OLTimeline.frames(items, top: { CGFloat($0.timeIntervalSince(base) / 3600) * 44 }, minimum: 22)
        #expect(frames["a"]?.index == 0 && frames["a"]?.count == 2)
        #expect(frames["b"]?.index == 1 && frames["b"]?.count == 2)
        #expect(frames["c"]?.index == 0 && frames["c"]?.count == 2, "C takes A's column once A has ended")
        #expect(frames["d"]?.index == 0 && frames["d"]?.count == 1)
        #expect(frames["b"]?.height == 66)
    }

    /// Dropping a planned task moves its slot there, pinned, for its
    /// estimate; Undo puts it back.
    @Test func droppingAPlannedTaskMovesItsSlot() throws {
        let phone = try TestPhone(seeded: true)
        let task = try #require(phone.task("Update the design role scorecard"))
        let before = try #require(phone.store.placements(taskID: task.id).first)
        let (oldStart, oldEnd, wasPinned) = (before.start, before.end, before.isPinned)
        let start = oldStart.addingTimeInterval(2 * 3600)
        #expect(phone.env.actions.place(task, at: start))
        let after = phone.store.placements(taskID: task.id)
        #expect(after.count == 1 && after[0].id == before.id)
        #expect(after[0].start == start && after[0].isPinned)
        #expect(after[0].end == start.addingTimeInterval(TimeInterval(phone.env.actions.planMinutes(for: task) * 60)))
        #expect(phone.env.tray.message?.text == "Planned “Update the design role scorecard” · Today 15:00")
        phone.env.tray.performAction()
        let back = phone.store.placements(taskID: task.id)
        #expect(back.count == 1 && back[0].start == oldStart && back[0].end == oldEnd)
        #expect(back[0].id == before.id && back[0].isPinned == wasPinned)
    }

    /// A dragged slot moves alone and keeps its length; the task's other
    /// slots stay, and Undo puts it back.
    @Test func draggingOneOfSeveralSlotsMovesOnlyIt() throws {
        let phone = try TestPhone(seeded: true)
        let task = try #require(phone.task("Book the ryokan"))
        let today = TestClock.calendar.startOfDay(for: TestClock.mockupNow)
        let first = try #require(phone.store.setPlacement(for: task, start: today.addingTimeInterval(15 * 3600),
                                                         end: today.addingTimeInterval(15.5 * 3600), isPinned: true))
        let second = try #require(phone.store.setPlacement(for: task, start: today.addingTimeInterval(19 * 3600),
                                                          end: today.addingTimeInterval(20 * 3600), isPinned: true))
        let start = today.addingTimeInterval(21 * 3600)
        #expect(phone.env.actions.place(task, at: start, placementID: second.id))
        let slots = phone.store.placements(taskID: task.id)
        #expect(slots.count == 2)
        #expect(slots.first { $0.id == first.id }?.start == today.addingTimeInterval(15 * 3600))
        #expect(slots.first { $0.id == second.id }.map { ($0.start, $0.end) } ?? (.distantPast, .distantPast)
            == (start, start.addingTimeInterval(3600)))
        phone.env.tray.performAction()
        #expect(phone.store.placements(taskID: task.id).first { $0.id == second.id }?.start == today.addingTimeInterval(19 * 3600))
    }

    /// Dropping a task with no slot gives it one; Undo takes it away.
    @Test func droppingAnUnplacedTaskPlansIt() throws {
        let phone = try TestPhone(seeded: true)
        let task = try #require(phone.task("Book the ryokan"))
        #expect(phone.store.placements(taskID: task.id).isEmpty)
        let start = TestClock.mockupNow.addingTimeInterval(4 * 3600 + 20 * 60)
        #expect(phone.env.actions.place(task, at: start))
        #expect(phone.store.placements(taskID: task.id).map(\.start) == [start])
        phone.env.tray.performAction()
        #expect(phone.store.placements(taskID: task.id).isEmpty)
    }

    /// The slot follows the estimate: the same start, that long after.
    @Test func theSlotFollowsTheEstimate() throws {
        let phone = try TestPhone(seeded: true)
        let task = try #require(phone.task("Update the design role scorecard"))
        let before = try #require(phone.store.placements(taskID: task.id).first)
        let start = before.start
        phone.env.actions.setEstimate(45, for: task)
        #expect(task.schedulingEstimateMinutes == 45)
        let after = try #require(phone.store.placements(taskID: task.id).first)
        #expect(after.start == start)
        #expect(after.end == start.addingTimeInterval(45 * 60))
    }

    /// Already done on a repeating Inbox task rolls it on and moves triage to
    /// the next card, as the Mac's does.
    @Test func triageMovesOnFromARepeat() throws {
        let phone = try TestPhone(seeded: true)
        let gift = try #require(phone.task("Gift ideas for Mika’s birthday"))
        gift.dueDate = phone.env.settings.calendar.startOfDay(for: phone.env.now)
        gift.recurrence = .weekly
        phone.store.save()
        let session = phone.env.triage
        session.begin()
        phone.env.actions.complete([gift])
        session.keep(gift.id)
        let queue = try library(phone).inboxQueue(triage: session, closing: phone.env.actions.closing)
        #expect(queue.first?.displayTitle == "Return the library books")
        #expect(session.reviewed(queue: queue) == 1)
    }

    @Test func trashSaysHowLongAgo() {
        let now = TestClock.mockupNow
        #expect(TrashScreen.ago(now.addingTimeInterval(-3 * 3600), now: now) == "3h ago")
        #expect(TrashScreen.ago(now.addingTimeInterval(-86_400), now: now) == "yesterday")
        #expect(TrashScreen.ago(now.addingTimeInterval(-3 * 86_400), now: now) == "3 days ago")
    }
}
