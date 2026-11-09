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

    // MARK: Adding and triaging

    @Test func whatAPasteInsertedIsFoundAroundTheTyping() throws {
        #expect(CaptureScreen.insertion(from: "Buy ", to: "Buy milk\neggs")?.text == "milk\neggs")
        #expect(CaptureScreen.insertion(from: "ab", to: "a\nb")?.text == "\n")
        #expect(CaptureScreen.insertion(from: "abc", to: "ab") == nil)
        let middle = try #require(CaptureScreen.insertion(from: "Call  today", to: "Call Mum\nDad today"))
        #expect(middle.before == "Call " && middle.text == "Mum\nDad" && middle.after == " today")
    }

    @Test func snoozeTakesACardOffTheQueueUntilItsDay() throws {
        let phone = try TestPhone(seeded: true)
        let gift = try #require(phone.task("Gift ideas for Mika’s birthday"))
        let now = phone.env.now
        let tomorrow = try #require(Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)))
        phone.env.actions.snooze([gift], until: tomorrow)
        #expect(gift.deferredUntil == tomorrow && gift.selectedForDay == nil)
        var lib = try library(phone)
        #expect(!lib.inboxQueue(triage: phone.env.triage, closing: [], now: now).contains { $0.id == gift.id })
        #expect(lib.snoozedInbox(now: now).map(\.id) == [gift.id])
        #expect(lib.inboxQueue(triage: phone.env.triage, closing: [], now: tomorrow).contains { $0.id == gift.id },
                "Back on its day")
        phone.env.actions.undoLatest()
        lib = try library(phone)
        #expect(gift.deferredUntil == nil && lib.inboxQueue(triage: phone.env.triage, closing: [], now: now).first?.id == gift.id)
    }

    @Test func theEditLineWritesTitleAndTokensWithOneUndo() throws {
        let phone = try TestPhone(seeded: true)
        let gift = try #require(phone.task("Gift ideas for Mika’s birthday"))
        let snapshot = CaptureParse("Gift ideas for Mika #travel !high ~20m", reference: phone.env.now).snapshot()
        #expect(phone.env.actions.write(snapshot, over: gift))
        #expect(gift.displayTitle == "Gift ideas for Mika" && gift.priority == .high && gift.schedulingEstimateMinutes == 20)
        #expect(phone.store.labels(for: gift).map(\.name) == ["travel"])
        phone.env.actions.undoLatest()
        #expect(gift.displayTitle == "Gift ideas for Mika’s birthday" && gift.priority == .none && gift.labelIDs.isEmpty)
    }

    @Test func theCardSuggestsTheListItsWordsPointTo() throws {
        let phone = try TestPhone(seeded: true)
        let kyoto = try #require(phone.store.allLists().first { $0.displayTitle == "Weekend in Kyoto" })
        let capture = try phone.store.saveCapture(CaptureSnapshot(title: "Book the ryokan dinner, travel day"), destinationID: nil)
        #expect(try library(phone).suggestedDestination(for: capture)?.id == kyoto.id)
        let gift = try #require(phone.task("Gift ideas for Mika’s birthday"))
        #expect(try library(phone).suggestedDestination(for: gift) == nil, "One name in common says too little")
    }

    // MARK: Today and the work in hand

    @Test func theWorkInHandIsTheFixturesSession() throws {
        let phone = try TestPhone(seeded: true)
        let work = PhoneWork(env: phone.env, now: phone.env.now)
        #expect(work.task?.displayTitle == "Draft Q3 OKRs")
        #expect(work.state == .working)
        #expect(work.leftText == "50 min left")
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
        let card = try nowNext(phone)
        #expect(card.lines.first?.kind == .work(.paused))
        #expect(card.lines.first?.detail == "Paused · 50 min left · Q3 planning")
        #expect(card.lines.first?.brief == "Paused")
    }

    // MARK: Today's Now card

    /// Today's Now card as the phone reads it, through the Mac's model.
    private func nowNext(_ phone: TestPhone, now: Date? = nil) throws -> TodayNowNext {
        let now = now ?? phone.env.now
        let lib = try library(phone)
        return TodayNowNext(schedule: PhoneSchedule.make(env: phone.env, now: now), work: PhoneWork(env: phone.env, now: now),
                            now: now, calendar: phone.env.settings.calendar, task: { phone.store.block(id: $0) },
                            list: { lib.list($0)?.displayTitle })
    }

    /// The work in hand leads, then the next thing to start: a session with
    /// its list, as the Mac's Today says them.
    @Test func theNowCardLeadsWithTheWorkThenWhatsNext() throws {
        let phone = try TestPhone(seeded: true)
        let card = try nowNext(phone)
        #expect(card.lines.map(\.role) == [.now, .next])
        #expect(card.lines.map(\.title) == ["Draft Q3 OKRs", "Write interview feedback for Priya"])
        #expect(card.lines[0].kind == .work(.working))
        #expect(card.lines[0].detail == "Working · 50 min left · Q3 planning")
        #expect(card.lines[1].kind == .session)
        #expect(card.lines[1].detail == "11:30 · in 50 min · Hiring loop")
        #expect(card.lines[1].listID == phone.list("Hiring loop")?.id)
        #expect(card.emptyText == nil)
        // Folded to one line, the card says the time alone.
        #expect(card.lines.map(\.brief) == ["50 min left", "11:30"])
    }

    /// A meeting under way is now beside the work, and one ahead is next,
    /// with its place.
    @Test func meetingsAreNowAndNextToo() throws {
        let calendar = TestClock.calendar
        let at1350 = try #require(calendar.date(bySettingHour: 13, minute: 50, second: 0, of: TestClock.mockupNow))
        let phone = try TestPhone(seeded: true, clock: .fixed(at1350))
        let card = try nowNext(phone)
        #expect(card.lines.map(\.title) == ["Draft Q3 OKRs", "Design sync"])
        #expect(card.lines[1].role == .next && card.lines[1].kind == .meeting)
        #expect(card.lines[1].detail == "14:00 · in 10 min · Studio, 3rd floor")
        #expect(card.lines[1].brief == "14:00")
        #expect(card.lines[1].meeting?.calendarTitle == "Work")

        let at1420 = at1350.addingTimeInterval(30 * 60)
        let later = try nowNext(phone, now: at1420)
        #expect(later.lines.map(\.role) == [.now, .alsoNow, .next])
        #expect(later.lines[1].title == "Design sync" && later.lines[1].detail == "Until 15:00 · Studio, 3rd floor")
        #expect(later.lines[1].brief == "Until 15:00")
        #expect(later.lines[2].title == "Order new water filters")
        #expect(later.lines[2].detail == "16:30 · in 2h 10m · Home")
    }

    /// With no work in hand, a slot on now leads, as the work the card's
    /// button starts.
    @Test func aSlotOnNowIsTheWorkToStart() throws {
        let phone = try TestPhone(seeded: true)
        phone.env.actions.undoLatest()
        #expect(phone.env.calendar.activeSession == nil)
        let card = try nowNext(phone)
        #expect(card.lines.first?.title == "Draft Q3 OKRs")
        #expect(card.lines.first?.kind == .work(.planned))
        #expect(card.lines.first?.detail == "Until 11:30 · Q3 planning")
        #expect(card.lines.first?.brief == "Until 11:30")
        #expect(card.lines.last?.role == .next)
    }

    /// An empty day says so, and a day with all of it over says nothing else
    /// is on.
    @Test func theNowCardSaysWhenNothingIsOn() throws {
        let empty = try TestPhone()
        let none = try nowNext(empty)
        #expect(none.lines.isEmpty && none.emptyText == "Nothing scheduled today.")

        let phone = try TestPhone(seeded: true)
        let evening = try #require(TestClock.calendar.date(bySettingHour: 23, minute: 30, second: 0, of: TestClock.mockupNow))
        phone.env.calendar.pause(now: phone.env.now)
        phone.env.calendar.dismissResume()
        let over = try nowNext(phone, now: evening)
        #expect(over.lines.isEmpty && over.emptyText == "Nothing else scheduled today.")
    }

    /// Today's tasks with no time yet are the ones the Timeline offers to
    /// plan: late, due or planned today, with no slot and no time of day.
    @Test func todayCountsTheTasksWithNoTimeYet() throws {
        let phone = try TestPhone(seeded: true)
        let lib = try library(phone)
        let now = phone.env.now, calendar = phone.env.settings.calendar
        let slots = PhoneWork.slots(phone.env.calendar, on: now, calendar: calendar)
        let agenda = TodayAgenda(tasks: lib.tasksInOutlineOrder(blocks: try blocks(phone)), now: now, calendar: calendar,
                                 order: .schedule, time: { slots[$0.id] })
        let work = PhoneWork(env: phone.env, now: now)
        let unplaced = PhoneSchedule.unplaced(agenda.scheduled, slotted: { slots[$0] != nil }, workID: work.task?.id,
                                              closing: phone.env.actions.closing)
        #expect(unplaced.map(\.displayTitle) == ["Close out Q2 retro actions", "Reserve the Nishiki market tour",
                                                  "Fix the dripping bathroom tap", "Ask Mika to water the planters"])
        let timeline = TimelineSchedule(env: phone.env, library: lib, day: calendar.startOfDay(for: now), now: now)
        #expect(Set(timeline.toPlan.map(\.id)) == Set(unplaced.map(\.id)))
        // A tick still settling leaves the count straight away.
        phone.env.actions.complete([unplaced[0]])
        #expect(PhoneSchedule.unplaced(agenda.scheduled, slotted: { slots[$0] != nil }, workID: work.task?.id,
                                       closing: phone.env.actions.closing).count == 3)
    }

    /// The fixture's calendar counts as connected; the device's own, never
    /// connected in a review session, doesn't, and one connected but no
    /// longer allowed is unavailable.
    @Test func theCalendarsConnection() {
        let defaults = TestDefaults.make()
        #expect(PhoneSchedule.connection(ExternalCalendarSource(defaults: defaults, fixtureBusyTimes: [])) == .connected)
        #expect(PhoneSchedule.connection(ExternalCalendarSource(defaults: defaults)) == .notConnected)
        defaults.set(true, forKey: "calendar.connected")
        #expect(PhoneSchedule.connection(ExternalCalendarSource(defaults: defaults)) == .unavailable)
    }

    /// `OpenlistReviewMeetings` gives a review session no calendar, or an
    /// empty one, for the empty states; otherwise the fixture's meetings.
    @Test func reviewSessionsChooseTheirMeetings() throws {
        let defaults = TestDefaults.make()
        let now = TestClock.mockupNow
        #expect(PhoneEnvironment.reviewMeetings(defaults: defaults, now: now, environment: ["OpenlistReviewMeetings": "NO"]) == nil)
        let none = try #require(PhoneEnvironment.reviewMeetings(defaults: defaults, now: now,
                                                                environment: ["OpenlistReviewMeetings": "none"]))
        #expect(none.isFixture && none.busyTimes(in: DateInterval(start: now.addingTimeInterval(-86_400), duration: 172_800)).isEmpty)
        let fixture = try #require(PhoneEnvironment.reviewMeetings(defaults: defaults, now: now, environment: [:]))
        #expect(fixture.busyTimes(in: DateInterval(start: now.addingTimeInterval(-86_400), duration: 172_800)).map(\.title)
                == ["Team standup", "Design sync"])
        // Online, their places are links, which the card names as the service.
        let links = try #require(PhoneEnvironment.reviewMeetings(defaults: defaults, now: now,
                                                                 environment: ["OpenlistReviewMeetings": "links"]))
        let online = links.busyTimes(in: DateInterval(start: now.addingTimeInterval(-86_400), duration: 172_800))
        #expect(online.map(\.title) == ["Team standup", "Design sync"])
        #expect(online.allSatisfy { $0.location?.hasPrefix("https://") == true })
        #expect(online.map(\.place) == ["Zoom", "Microsoft Teams"])
    }

    /// A meeting's details say how far off it is, in the schedule's words.
    @Test func aMeetingsDetailsSayWhen() throws {
        let calendar = TestClock.calendar
        let now = TestClock.mockupNow
        func at(_ hour: Int, _ minute: Int = 0, days: Int = 0) throws -> Date {
            let day = try #require(calendar.date(byAdding: .day, value: days, to: now))
            return try #require(calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day))
        }
        #expect(OLMeetingDetails.when(start: try at(14), end: try at(15), now: now, calendar: calendar) == "In 3h 20m")
        #expect(OLMeetingDetails.when(start: try at(10, 30), end: try at(11), now: now, calendar: calendar) == "Now · 20 min left")
        #expect(OLMeetingDetails.when(start: try at(9, 30), end: try at(9, 45), now: now, calendar: calendar) == "Ended 55 min ago")
        #expect(OLMeetingDetails.when(start: try at(9, days: 1), end: try at(10, days: 1), now: now, calendar: calendar)
                == CompactText.day(try at(9, days: 1), now: now, calendar: calendar))
        #expect(OLMeetingDetails.spoken(start: try at(14), end: try at(15), location: "Studio", calendarTitle: "Work",
                                        calendar: calendar) == "14:00 to 15:00, Studio, Work calendar")
    }

    @Test func todaysRowsSayWhatTodayDoesnt() throws {
        let phone = try TestPhone(seeded: true)
        let now = phone.env.now, calendar = phone.env.settings.calendar
        func trailing(_ title: String, _ context: PhoneRowContext) throws -> OLTrailing? {
            PhoneTaskRow.trailing(for: try #require(phone.task(title)), context: context, now: now, calendar: calendar)
        }
        /// A due date, which the row's date menu changes.
        func due(_ text: String, tone: OLTrailing.Tone) -> OLTrailing {
            var trailing = OLTrailing.text(text, tone: tone)
            trailing.isDue = true
            return trailing
        }
        #expect(try trailing("Close out Q2 retro actions", .today) == due("3d late", tone: .late))
        #expect(try trailing("Pay the ryokan deposit", .today) == due("18:00", tone: .due))
        // Due today with no time: Today says only that it repeats.
        #expect(try trailing("Ask Mika to water the planters", .today)?.symbol == "repeat")
        #expect(try trailing("Ask Mika to water the planters", .today)?.text == nil)
        #expect(try trailing("Ask Mika to water the planters", .list)?.text == "Today")
        #expect(try trailing("Ask Mika to water the planters", .select) == due("Today", tone: .due))
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
        #expect(agenda.tonight.map(\.displayTitle) == ["Pay the ryokan deposit"])
        #expect(!agenda.due.contains { $0.displayTitle == "Pay the ryokan deposit" })
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
        #expect(drawn["Draft Q3 OKRs"]?.emphasis == .now)
        // What comes next is a step heavier; the rest are plain cards in their lists' colours.
        #expect(drawn["Write interview feedback for Priya"]?.kind == .planned)
        #expect(drawn["Write interview feedback for Priya"]?.emphasis == .next)
        #expect(drawn["Write interview feedback for Priya"]?.listColor == ListAccent.pink.color)
        #expect(drawn["Update the design role scorecard"]?.emphasis == OLTimelineItem.Emphasis.none)
        #expect(drawn["Order new water filters"]?.movable == true)
        #expect(drawn["Design sync"]?.kind == .event)
        #expect(drawn["Design sync"]?.location == "Studio, 3rd floor" && drawn["Design sync"]?.isPast == false)
        #expect(drawn["Team standup"]?.kind == .event && drawn["Team standup"]?.isPast == true)
        #expect(drawn["Pay the ryokan deposit"]?.kind == .due)
        #expect(OLTimeline.spoken(try #require(drawn["Write interview feedback for Priya"]), calendar: TestClock.calendar)
                == "Write interview feedback for Priya, 11:30 to 11:50, next")
        #expect(OLTimeline.spoken(try #require(drawn["Design sync"]), calendar: TestClock.calendar)
                == "Design sync, meeting, 14:00 to 15:00, Studio, 3rd floor, Work calendar")
        #expect(schedule.hours == 0...24)
        #expect(Set(schedule.toPlan.map(\.displayTitle)) == ["Close out Q2 retro actions", "Reserve the Nishiki market tour",
                                                              "Fix the dripping bathroom tap", "Ask Mika to water the planters"])
    }

    /// A slot gone by without work is missed, dashed red, and can still be
    /// dragged to a new time; on another day nothing is now or next.
    @Test func aSlotGoneByIsMissed() throws {
        let phone = try TestPhone(seeded: true)
        let task = try #require(phone.task("Fix the dripping bathroom tap"))
        let today = TestClock.calendar.startOfDay(for: TestClock.mockupNow)
        _ = try #require(phone.store.setPlacement(for: task, start: today.addingTimeInterval(8 * 3600),
                                                  end: today.addingTimeInterval(8.5 * 3600), isPinned: true))
        phone.env.calendar.replan(now: phone.env.now)
        let schedule = TimelineSchedule(env: phone.env, library: try library(phone), day: today, now: phone.env.now)
        let missed = try #require(schedule.items.first { $0.title == "Fix the dripping bathroom tap" && $0.end <= phone.env.now })
        #expect(missed.kind == .missed && missed.movable && missed.emphasis == .none)
        #expect(OLTimeline.spoken(missed, calendar: TestClock.calendar) == "Fix the dripping bathroom tap, missed, carried forward, 08:00 to 08:30")
        let tomorrow = today.addingTimeInterval(86_400)
        let next = TimelineSchedule(env: phone.env, library: try library(phone), day: tomorrow, now: phone.env.now)
        #expect(next.items.allSatisfy { $0.emphasis == .none })
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
        var queue = try library(phone).inboxQueue(triage: session, closing: [], now: phone.env.now)
        #expect(session.reviewed(queue: queue) == 1)
        #expect(queue.first?.displayTitle == "Return the library books")
        // Scheduled from the card, a task stays in the Inbox with its day.
        let books = try #require(phone.task("Return the library books"))
        phone.env.actions.schedule([books], on: PhoneDay.tomorrow.date(now: phone.env.now, calendar: phone.env.settings.calendar))
        session.schedule(books.id, due: try #require(books.dueDate))
        #expect(books.listID == phone.store.inboxList()?.id)
        #expect(CompactText.dayOffset(from: phone.env.now, to: try #require(books.dueDate)) == 1)
        #expect(phone.env.tray.message?.text == "“Return the library books” due tomorrow")
        queue = try library(phone).inboxQueue(triage: session, closing: [], now: phone.env.now)
        #expect(session.reviewed(queue: queue) == 2)
        // Its Undo puts the card back on the queue, and out of the count.
        phone.env.tray.performAction()
        #expect(books.dueDate == nil)
        queue = try library(phone).inboxQueue(triage: session, closing: [], now: phone.env.now)
        #expect(queue.first?.displayTitle == "Return the library books")
        #expect(session.reviewed(queue: queue) == 1)
        // A card filed and then taken back is on the queue again too.
        let desk = try #require(phone.task("Look into a standing desk for the study"))
        #expect(phone.env.actions.move([desk], to: try #require(phone.list("Home"))))
        session.finish(desk.id)
        #expect(session.reviewed(queue: try library(phone).inboxQueue(triage: session, closing: [], now: phone.env.now)) == 2)
        phone.env.tray.performAction()
        #expect(session.reviewed(queue: try library(phone).inboxQueue(triage: session, closing: [], now: phone.env.now)) == 1)
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

    // MARK: Triage without a date

    /// No date deals the lists' open tasks with no day, in the lists' order:
    /// not the Inbox's, not Draft Q3 OKRs, planned for today, nor a subtask
    /// its open parent's card carries.
    @Test func noDateDealsTheListsUndatedTasksInTheirOrder() throws {
        let phone = try TestPhone(seeded: true)
        let lib = try library(phone)
        let queue = lib.undatedQueue(blocks: try blocks(phone), kept: [], closing: [])
        #expect(queue.map(\.displayTitle) == ["Book the ryokan", "Finish The Overstory", "Start Piranesi",
                                              "Share the OKR draft with leads"])
        #expect(lib.undatedCount(kept: [], closing: []) == 4)
        #expect(phone.env.triage(for: .undated) === phone.env.undatedTriage)
        #expect(phone.env.triage(for: .inbox) === phone.env.triage)
        // The card names where each one is.
        #expect(ListsTaskOverview.source(of: try #require(queue.first), in: lib) == "Weekend in Kyoto")
    }

    /// A day from a No date card dates it in one step, which takes it off the
    /// pass; Undo puts it back. Later sets a card aside until it's reviewed
    /// again, and Already done leaves the pass as it dwells.
    @Test func noDateDatesACardInOneStepWithUndo() throws {
        let phone = try TestPhone(seeded: true)
        let session = phone.env.undatedTriage
        func queue() throws -> [Block] {
            try library(phone).undatedQueue(blocks: try blocks(phone), triage: session, closing: phone.env.actions.closing, now: phone.env.now)
        }
        session.begin()
        let ryokan = try #require(phone.task("Book the ryokan"))
        let kyoto = ryokan.listID
        let tomorrow = PhoneDay.tomorrow.date(now: phone.env.now, calendar: phone.env.settings.calendar)
        #expect(phone.env.actions.file(ryokan, to: nil, due: tomorrow))
        session.finish(ryokan.id)
        #expect(phone.env.tray.message?.text == "“Book the ryokan” due tomorrow")
        #expect(ryokan.listID == kyoto && ryokan.dueDate.map { CompactText.dayOffset(from: phone.env.now, to: $0) } == 1)
        #expect(try queue().first?.displayTitle == "Finish The Overstory")
        #expect(session.reviewed(queue: try queue()) == 1)
        // Undo: no date again, so back on the pass and out of the count.
        phone.env.tray.performAction()
        #expect(ryokan.dueDate == nil)
        #expect(try queue().first?.displayTitle == "Book the ryokan")
        #expect(session.reviewed(queue: try queue()) == 0)
        // Later: aside for this session, in No date's pass only.
        session.keep(ryokan.id)
        #expect(try queue().first?.displayTitle == "Finish The Overstory")
        #expect(try library(phone).undatedCount(triage: session, closing: [], now: phone.env.now) == 3)
        #expect(phone.env.triage.kept { _ in nil }.isEmpty)
        // Done: off the pass while it dwells, and once it's written.
        let overstory = try #require(phone.task("Finish The Overstory"))
        phone.env.actions.complete([overstory])
        session.finish(overstory.id)
        #expect(try queue().first?.displayTitle == "Start Piranesi")
        phone.env.actions.settleAll()
        #expect(overstory.isCompleted)
        #expect(try queue().map(\.displayTitle) == ["Start Piranesi", "Share the OKR draft with leads"])
        #expect(session.reviewed(queue: try queue()) == 2)
        session.reviewKept()
        #expect(try queue().first?.displayTitle == "Book the ryokan")
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

    @Test func aPickedCaptureDayWorksWithoutDateParsing() throws {
        let phone = try TestPhone()
        let calendar = phone.env.settings.calendar
        let tomorrow = PhoneDay.tomorrow.date(now: phone.env.now, calendar: calendar)
        let picked = try #require(calendar.date(bySettingHour: 18, minute: 45, second: 30, of: tomorrow))
        let parse = CaptureParse("Buy yen tomorrow #travel !high ~15m", parsesDates: false, reference: phone.env.now)
        let snapshot = CaptureDueDate.chosen(picked, includesTime: false)
            .snapshot(parse, dueToday: false, now: phone.env.now, calendar: calendar)
        let task = try phone.store.saveCapture(snapshot, destinationID: nil)
        let reader = ModelContext(phone.container)
        let id = task.id
        let saved = try #require(reader.fetch(FetchDescriptor<Block>(predicate: #Predicate { $0.id == id })).first)
        #expect(saved.displayTitle == "Buy yen tomorrow")
        #expect(saved.dueDate == calendar.startOfDay(for: tomorrow))
        #expect(!saved.includesTime)
        #expect(saved.priority == .high && saved.schedulingEstimateMinutes == 15)
        #expect(phone.store.labels(for: task).map(\.name) == ["travel"])
    }

    @Test func aPickedCaptureTimeSavesWithUndo() throws {
        let phone = try TestPhone()
        let calendar = phone.env.settings.calendar
        let tomorrow = PhoneDay.tomorrow.date(now: phone.env.now, calendar: calendar)
        let picked = try #require(calendar.date(bySettingHour: 18, minute: 45, second: 0, of: tomorrow))
        let snapshot = CaptureDueDate.chosen(picked, includesTime: true)
            .snapshot(CaptureParse("Pay the deposit", reference: phone.env.now), dueToday: true,
                      now: phone.env.now, calendar: calendar)
        let task = try phone.store.saveCapture(snapshot, destinationID: nil)
        #expect(task.dueDate == picked && task.includesTime)
        let id = task.id
        phone.env.actions.reportCapture(task)
        phone.env.tray.performAction()
        #expect(phone.store.block(id: id) == nil)
    }

    @Test func clearingCaptureDueDateSuppressesTypedAndTodayDefaults() throws {
        let phone = try TestPhone()
        let calendar = phone.env.settings.calendar
        for text in ["Call mum", "Call mum tomorrow 6pm #home"] {
            let parse = CaptureParse(text, reference: phone.env.now)
            #expect(CaptureDueDate.automatic.snapshot(parse, dueToday: true, now: phone.env.now, calendar: calendar).date != nil)
            let snapshot = CaptureDueDate.cleared.snapshot(parse, dueToday: true, now: phone.env.now, calendar: calendar)
            let task = try phone.store.saveCapture(snapshot, destinationID: nil)
            #expect(task.dueDate == nil && !task.includesTime)
            #expect(task.displayTitle == "Call mum")
        }
    }

    @Test func editingCaptureTitleKeepsPickedDateWhileANewDateTakesOver() {
        let now = TestClock.mockupNow, calendar = TestClock.calendar
        let picked = CaptureDueDate.chosen(PhoneDay.tomorrow.date(now: now, calendar: calendar), includesTime: false)
        let old = CaptureParse("Pay deposit #travel", reference: now)
        let renamed = CaptureParse("Pay the ryokan deposit #home ~15m", reference: now)
        #expect(picked.afterEditing(from: old, to: renamed) == picked)
        #expect(CaptureDueDate.cleared.afterEditing(from: old, to: renamed) == .cleared)
        let superseded = CaptureParse("Pay deposit tomorrow 6pm #travel", reference: now)
        let withoutTime = CaptureParse("Pay deposit tomorrow #travel", reference: now)
        #expect(picked.afterEditing(from: superseded, to: withoutTime) == picked)
        #expect(picked.afterEditing(from: withoutTime, to: old) == picked)
        let cleared = CaptureDueDate.cleared.afterEditing(from: superseded, to: old)
        #expect(cleared == .cleared)
        #expect(cleared.snapshot(old, dueToday: true, now: now, calendar: calendar).date == nil)
        let dated = CaptureParse("Pay the ryokan deposit friday 6pm #home ~15m", reference: now)
        let choice = picked.afterEditing(from: renamed, to: dated)
        #expect(choice == .automatic)
        let snapshot = choice.snapshot(dated, dueToday: true, now: now, calendar: calendar)
        #expect(snapshot.date == dated.schedule?.date && snapshot.includesTime)
        let repeating = CaptureParse("Pay deposit every monday #travel", reference: now)
        #expect(CaptureDueDate.cleared.afterEditing(from: old, to: repeating) == .automatic)
    }

    @Test func overridingTypedCaptureDatePreservesDateWordsInTheTitleAndMetadata() throws {
        let phone = try TestPhone()
        let now = phone.env.now, calendar = phone.env.settings.calendar
        let parse = CaptureParse("Review Friday document tomorrow 6pm #work !high ~15m", reference: now)
        #expect(parse.title == "Review Friday document")
        let picked = PhoneDay.weekend.date(now: now, calendar: calendar)
        let snapshot = CaptureDueDate.chosen(picked, includesTime: false)
            .snapshot(parse, dueToday: false, now: now, calendar: calendar)
        let task = try phone.store.saveCapture(snapshot, destinationID: nil)
        #expect(task.displayTitle == "Review Friday document")
        #expect(task.dueDate == picked && !task.includesTime)
        #expect(task.priority == .high && task.schedulingEstimateMinutes == 15)
        #expect(phone.store.labels(for: task).map(\.name) == ["work"])
        let cleared = CaptureDueDate.cleared.snapshot(parse, dueToday: true, now: now, calendar: calendar)
        #expect(cleared.title == "Review Friday document" && cleared.date == nil && !cleared.includesTime)
        #expect(cleared.labels == ["work"] && cleared.priority == .high && cleared.estimateMinutes == 15)
    }

    @Test func aPickedCaptureDayAnchorsCadenceAndPreservesNamedWeekdays() throws {
        let phone = try TestPhone()
        let calendar = phone.env.settings.calendar
        let friday = try #require(calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: phone.env.now)))
        let choice = CaptureDueDate.chosen(friday, includesTime: false)
        let weekly = choice.snapshot(CaptureParse("Review every week", reference: phone.env.now), dueToday: false,
                                     now: phone.env.now, calendar: calendar)
        let task = try phone.store.saveCapture(weekly, destinationID: nil)
        #expect(task.dueDate == friday)
        #expect(task.recurrence?.weekdays == [calendar.component(.weekday, from: friday)])
        let named = choice.snapshot(CaptureParse("Review every monday", reference: phone.env.now), dueToday: false,
                                    now: phone.env.now, calendar: calendar)
        #expect(named.date == friday && named.recurrence?.weekdays == [2])
        let monthly = choice.snapshot(CaptureParse("Review monthly", reference: phone.env.now), dueToday: false,
                                      now: phone.env.now, calendar: calendar)
        let monthlyTask = try phone.store.saveCapture(monthly, destinationID: nil)
        #expect(monthlyTask.recurrence?.dayOfMonth == calendar.component(.day, from: friday))
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

    /// Start working on the task already running starts nothing, so it
    /// offers no Undo that could take its recorded time.
    @Test func startingTheRunningTaskOffersNoUndo() throws {
        let phone = try TestPhone(seeded: true)
        let draft = try #require(phone.task("Draft Q3 OKRs"))
        let running = try #require(phone.env.calendar.activeSession)
        let offered = try #require(phone.env.actions.latest)
        Thread.sleep(forTimeInterval: 0.02)
        #expect(phone.env.actions.startWork(draft))
        #expect(phone.env.calendar.activeSession?.id == running.id)
        #expect(phone.env.actions.latest?.at == offered.at, "No new step, so no new Undo")
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
        let queue = try library(phone).inboxQueue(triage: session, closing: phone.env.actions.closing, now: phone.env.now)
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
