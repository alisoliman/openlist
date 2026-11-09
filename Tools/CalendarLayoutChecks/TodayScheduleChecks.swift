import Foundation

/// Today's schedule: what the Today screen draws beside its tasks, read from
/// the Calendar's blocks and the calendars' busy time on the day of `now`.
@MainActor
func todayScheduleChecks() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
    func at(_ hour: Int, _ minute: Int = 0, day: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }
    let now = at(10, 40)
    func meeting(_ id: String, _ start: Date, _ end: Date) -> FixedBusyTime {
        FixedBusyTime(id: id, title: id, start: start, end: end)
    }
    func block(_ id: String, _ start: Date, _ end: Date, active: Bool = false, done: Bool = false) -> PlannedBlock {
        PlannedBlock(id: id, taskID: UUID(), occurrenceID: UUID(), start: start, end: end, isPinned: true,
                     placementID: active ? nil : UUID(), conflicts: [], isActive: active,
                     completionID: done ? UUID() : nil, titleSnapshot: id)
    }
    func ids(_ items: [TodaySchedule.Item]) -> [String] { items.map(\.title) }

    let busy = [
        meeting("standup", at(9, 30), at(9, 45)),
        meeting("review", at(10, 30), at(11, 30)),
        meeting("lunch talk", at(12), at(13)),
        meeting("yesterday", at(15, day: 8), at(16, day: 8)),
        meeting("tomorrow", at(9, day: 10), at(10, day: 10)),
        meeting("Out of office", at(0, day: 9), at(0, day: 10)),
    ]
    let blocks = [
        block("night shift", at(23, day: 8), at(1, day: 9)),
        block("missed", at(8), at(8, 30)),
        block("working", at(10), at(10, 45), active: true),
        block("done early", at(11, 30), at(12), done: true),
        block("draft", at(12), at(12, 45)),
        block("next week", at(9, day: 16), at(10, day: 16)),
    ]
    let schedule = TodaySchedule(blocks: blocks, busy: busy, now: now, calendar: calendar)

    expect(ids(schedule.items) == ["night shift", "missed", "standup", "working", "review", "done early", "lunch talk", "draft"],
           "Today's meetings and sessions, in time order, a meeting first at the same time; other days' left out")
    expect(schedule.holds.map(\.title) == ["Out of office"], "Busy time of 20 hours or more is a hold, not a meeting")
    expect(schedule.items.first { $0.title == "standup" }?.kind == .meeting
           && schedule.items.first { $0.title == "draft" }?.kind == .session, "Meetings and sessions keep their kind")
    expect(ids(schedule.current) == ["working", "review"], "Running work leads what's under way, then the meeting on now")
    expect(schedule.next?.title == "lunch talk", "Next is the first still to start, a done session passed over, a meeting first")
    expect(!schedule.current.contains { $0.title == "missed" } && schedule.next?.title != "missed",
           "A slot gone by without work is neither now nor next")
    expect(schedule.hasRest && !schedule.isEmpty, "A day with something on has the rest of it to show")

    // The hours drawn: from the hour before now, or from where what's under
    // way began, to the end of the last thing today.
    expect(schedule.hours(showsEarlier: false) == 9...13, "From an hour before now to the end of the day's last item")
    let earlier = schedule.earlier(than: schedule.hours(showsEarlier: false))
    expect(ids(earlier) == ["night shift", "missed"], "What ended before those hours is folded away as earlier")
    expect(!ids(schedule.shown(in: 9...13)).contains("missed") && ids(schedule.shown(in: 9...13)).contains("standup"),
           "The hours drawn show what overlaps them")
    expect(schedule.hours(showsEarlier: true) == 0...13, "Earlier reaches back to the first item, from before midnight at 00:00")
    let started = TodaySchedule(blocks: [block("long", at(8, 15), at(11))], busy: [], now: now, calendar: calendar)
    expect(started.hours(showsEarlier: false) == 8...12, "Work under way since 08:15 is drawn from 08:00, two hours past now at least")

    // Late at night the hours stop at midnight; a meeting into tomorrow
    // reaches to the day's end.
    let late = TodaySchedule(blocks: [], busy: [meeting("late call", at(23, 15), at(0, 30, day: 10))], now: at(23, 30),
                             calendar: calendar)
    expect(late.hours(showsEarlier: false) == 22...24, "Late at night the hours end at midnight")
    expect(ids(late.current) == ["late call"] && late.next == nil, "A meeting into tomorrow is on now, with nothing next")

    // Nothing left: done and gone by, so nothing is now or next.
    let evening = TodaySchedule(blocks: [block("done", at(9), at(10), done: true)], busy: [meeting("sync", at(14), at(15))],
                                now: at(20), calendar: calendar)
    expect(!evening.hasRest && !evening.isEmpty, "Once everything's over, the day has nothing more to come")
    expect(evening.shown(in: evening.hours(showsEarlier: false)).isEmpty
           && evening.earlier(than: evening.hours(showsEarlier: false)).count == 2, "All of it folds away as earlier")
    let empty = TodaySchedule(blocks: [block("tomorrow", at(9, day: 10), at(10, day: 10))], busy: [], now: now, calendar: calendar)
    expect(empty.isEmpty && !empty.hasRest && empty.next == nil, "A day with nothing on is empty, tomorrow's slot not counted")
    let clipped = TodaySchedule(blocks: [], busy: [meeting("", at(10), at(11))], now: now, calendar: calendar)
    expect(clipped.items.first?.title == "Busy", "A meeting with no title reads Busy, as the Calendar's does")
    expect(clipped.items.first?.isCurrent(at: now) == true, "A meeting on now is current")
    let done = TodaySchedule(blocks: [block("ticked", at(10, 30), at(11))], busy: [], now: now, calendar: calendar,
                             isDone: { _ in true })
    expect(done.current.isEmpty && done.next == nil, "A session done, or settling as done, is neither now nor next")

    // Another day, as the iPhone's Timeline reads its week: that day's items,
    // with now and next still today's.
    let tomorrow = TodaySchedule(blocks: blocks, busy: busy, now: now, day: at(15, day: 10), calendar: calendar)
    expect(ids(tomorrow.items) == ["tomorrow"] && tomorrow.day == calendar.startOfDay(for: at(9, day: 10)),
           "Another day reads that day's meetings and sessions only")
    expect(tomorrow.current.isEmpty && tomorrow.next?.title == "tomorrow", "Nothing is under way on a day to come")
    let yesterday = TodaySchedule(blocks: blocks, busy: busy, now: now, day: at(12, day: 8), calendar: calendar)
    expect(ids(yesterday.items) == ["yesterday", "night shift"] && yesterday.current.isEmpty && yesterday.next == nil,
           "A day gone by has nothing now or next, and a slot into today still shows on it")
}

/// A meeting's place as Today's lines name it, on the Mac and the iPhone: a
/// link as the service it opens, or its bare domain; a room as it is.
@MainActor
func meetingPlaceChecks() {
    func name(_ location: String) -> String { MeetingPlace.name(location) }
    expect(name("https://teams.microsoft.com/meet/38291045672?p=Xk2Lm9Qw") == "Microsoft Teams",
           "A Teams link reads Microsoft Teams")
    expect(name("https://teams.microsoft.com/l/meetup-join/19%3ameeting_Zm%40thread.v2/0?context=%7b%7d") == "Microsoft Teams",
           "A Teams join link reads Microsoft Teams")
    expect(name("https://us02web.zoom.us/j/81234567890?pwd=Q2F0Y2g") == "Zoom", "A Zoom link on a subdomain reads Zoom")
    expect(name("zoommtg://zoom.us/join?confno=81234567890") == "Zoom", "Zoom's app link reads Zoom")
    expect(name("https://meet.google.com/abc-defg-hij") == "Google Meet", "A Meet link reads Google Meet")
    expect(name("meet.google.com/abc-defg-hij") == "Google Meet", "A link without its scheme is named too")
    expect(name("https://acme.webex.com/meet/sam") == "Webex", "A Webex link reads Webex")
    expect(name("https://www.example.com/events/1?ref=cal") == "example.com", "Another link reads as its bare domain")
    expect(name("http://events.example.org") == "events.example.org", "A subdomain stays, only www goes")
    expect(name("<https://zoom.us/j/1>") == "Zoom", "A link in angle brackets is named")
    expect(name("https://maps.app.goo.gl/Xy12") == "Google Maps" && name("https://www.google.com/maps/place/Amsterdam") == "Google Maps",
           "Google Maps' links read Google Maps")

    // Places that aren't links stay as the calendar has them.
    for place in ["Studio, 3rd floor", "Microsoft Teams Meeting", "Room 4.12", "St.Mary", "Café Lumen", "Amsterdam.NL",
                  "sam@example.com", "Video call", "example.com"] {
        expect(name(place) == place, "\(place) stays as it is")
    }

    // A place with words and a link keeps the words, naming the link only
    // where they don't already.
    expect(name("Microsoft Teams Meeting; https://teams.microsoft.com/l/meetup-join/19") == "Microsoft Teams Meeting",
           "A link the words already name adds nothing")
    expect(name("Zoom Meeting https://zoom.us/j/1") == "Zoom Meeting", "So does one named in the same part")
    expect(name("Teams https://teams.microsoft.com/l/1") == "Microsoft Teams", "A service's full name replaces a shorter one")
    expect(name("Room 4.12 / https://zoom.us/j/1") == "Room 4.12, Zoom", "A room and a link read as the room, then the service")
    expect(name("https://zoom.us/j/1\nhttps://zoom.us/j/2") == "Zoom", "Two links to one service name it once")
    expect(name("Online (https://meet.google.com/abc-defg-hij)") == "Online, Google Meet", "A link in brackets is named")

    // The model reads a meeting's place through it; a session has none.
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
    let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 17))!
    let meeting = FixedBusyTime(id: "sql", title: "SQL Enablement", start: start, end: start.addingTimeInterval(3600),
                                location: "https://teams.microsoft.com/meet/38291045672?p=Xk2Lm9Qw")
    let session = PlannedBlock(id: "s", taskID: UUID(), occurrenceID: UUID(), start: start.addingTimeInterval(3600),
                               end: start.addingTimeInterval(5400), isPinned: true, placementID: UUID(), conflicts: [])
    let schedule = TodaySchedule(blocks: [session], busy: [meeting], now: start.addingTimeInterval(-6360), calendar: calendar)
    expect(schedule.next?.place == "Microsoft Teams", "Next names a meeting's linked place")
    expect(schedule.items.last?.kind == .session && schedule.items.last?.place == nil, "A session has no place of its own")
    expect(FixedBusyTime(id: "x", title: "x", start: start, end: start).place == nil, "No place stays no place")
}
