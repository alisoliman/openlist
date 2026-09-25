//
//  SampleData.swift
//  OpenlistWidget
//
//  The design's own data (`LISTS`, `TASKS`, `INBOX`, `EVENTS`, `PLAN` in
//  widgets.jsx), laid out around a chosen moment. The widget gallery and the
//  placeholder show it; the preview harness and the widget checks use it to
//  compare against the design. Its `SHORT` names are left out, as lists have
//  none: the List footer names the whole list.
//

import Foundation

enum WidgetSampleData {
    /// The design's fixture states.
    enum Fixture: String, CaseIterable, Sendable {
        /// The design as it loads: nothing ticked, no timer.
        case `default`
        /// After a short session: "Close out Q2 retro actions" ticked off, and
        /// "Draft Q3 OKRs" paused at 00:18, as in the design's screenshots.
        case session
    }

    private struct List {
        var key: String, icon: String, title: String, accent: String
    }

    private struct Task {
        var key: String, list: String, title: String
        /// Days from today; nil for undated.
        var due: Int?
        var priority = 0, isStarred = false, time: String? = nil, repeats = false, isDone = false
    }

    private static let lists: [List] = [
        List(key: "inbox", icon: "📥", title: "Inbox", accent: "#3A7BD8"),
        List(key: "kyoto", icon: "🗻", title: "Weekend in Kyoto", accent: "violet"),
        List(key: "home", icon: "🏡", title: "Home", accent: "green"),
        List(key: "reading", icon: "📚", title: "Reading", accent: "#C2532B"),
        List(key: "q3", icon: "💼", title: "Q3 planning", accent: "blue"),
        List(key: "hiring", icon: "🎯", title: "Hiring loop", accent: "pink"),
    ]

    private static let tasks: [Task] = [
        Task(key: "q4", list: "q3", title: "Close out Q2 retro actions", due: -3, priority: 2),
        Task(key: "k3", list: "kyoto", title: "Reserve the Nishiki market tour", due: -2),
        Task(key: "h1", list: "home", title: "Fix the dripping bathroom tap", due: -1),
        Task(key: "q1", list: "q3", title: "Draft Q3 OKRs", due: 0, priority: 3, time: "10:00"),
        Task(key: "p1", list: "hiring", title: "Write interview feedback for Priya", due: 0, isStarred: true, time: "11:30"),
        Task(key: "k4", list: "kyoto", title: "Ask Mika to water the planters", due: 0, repeats: true),
        Task(key: "k2", list: "kyoto", title: "Pay the ryokan deposit", due: 0, time: "18:00"),
        Task(key: "k1", list: "kyoto", title: "Renew passports", due: 3, priority: 3),
        Task(key: "k5", list: "kyoto", title: "Pick up JR passes at Kyoto Station", due: 4),
        Task(key: "k6", list: "kyoto", title: "Reply to Kasuga about the tatami room", due: nil, isDone: true),
        Task(key: "h2", list: "home", title: "Order new water filters", due: nil),
        Task(key: "h3", list: "home", title: "Book the boiler service", due: 6),
        Task(key: "r1", list: "reading", title: "Finish The Overstory", due: nil, isStarred: true),
        Task(key: "r2", list: "reading", title: "Notes on Working in Public", due: nil),
        Task(key: "q2", list: "q3", title: "Review hiring budget with Sam", due: 1),
        Task(key: "q5", list: "q3", title: "Prep board update slides", due: 2),
        Task(key: "q6", list: "q3", title: "Standup notes", due: nil, isDone: true),
        Task(key: "p2", list: "hiring", title: "Schedule the onsite for Leo", due: 3),
        Task(key: "p3", list: "hiring", title: "Update the design role scorecard", due: nil),
    ]

    /// Title and age in hours.
    private static let inbox: [(String, Double)] = [
        ("Send Jun the photos from Nara", 2), ("Cancel the gym trial before it renews", 5),
        ("Call the dentist back about the crown", 24), ("Look into a standing desk", 48),
        ("Return the library books", 72), ("Gift ideas for Mika’s birthday", 96),
    ]

    /// Meetings for each day of the week, from its first day: start, end, title.
    private static let events: [[(Double, Double, String)]] = [
        [(9.5, 10, "Standup"), (13, 14, "Design review")],
        [(9.5, 10, "Standup"), (11, 12, "1:1 with Sam"), (15, 16.5, "Hiring sync")],
        [(9.5, 10, "Standup"), (14, 15, "Board prep"), (15.5, 16, "Priya debrief"), (16, 16.5, "Coffee with Leo")],
        [(9.5, 10, "Standup"), (10, 12, "Offsite planning")],
        [(9.5, 10, "Standup"), (12, 13, "Team lunch")],
        [(10, 11.5, "Pottery class")],
        [],
    ]

    /// Planned task slots: task, day of the design's week (today is its
    /// Wednesday, 2), start hour, minutes.
    private static let plan: [(String, Int, Double, Double)] = [
        ("q4", 1, 14, 30), ("q1", 2, 10, 90), ("p1", 2, 11.5, 20), ("p3", 2, 13, 30),
        ("h2", 2, 16.5, 10), ("k2", 2, 18, 15), ("q2", 3, 13, 45), ("q5", 4, 10, 60),
    ]

    /// The design's clock: Wednesday 23 September 2026, 10:40, weeks from Monday.
    static var referenceDate: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 10, minute: 40))!
    }

    static let firstWeekday = 2

    /// A stable identity per design key, so rows keep their ids across builds.
    static func id(_ key: String) -> UUID {
        var bytes = Array(key.utf8.prefix(12))
        bytes += Array(repeating: 0, count: 16 - bytes.count)
        return UUID(uuid: (0x0D, 0xE5, 0x16, 0x00, bytes[0], bytes[1], bytes[2], bytes[3],
                           bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11]))
    }

    /// The design's data around `now`, in the week `now` falls in. Today has
    /// the design's day, its Wednesday; the week's other days have the
    /// design's meetings for their weekday, and its planned slots as many
    /// days from today as the design's are from its Wednesday, so on a
    /// Wednesday it is the design's own week.
    static func snapshot(now: Date = referenceDate, fixture: Fixture = .default, calendar base: Calendar = .current) -> WidgetSnapshot {
        let clock = WidgetClock(now: now, firstWeekday: firstWeekday, calendar: base)
        let calendar = clock.calendar
        let today = clock.today
        let completed: Set<String> = fixture == .session ? ["q4"] : []
        func isDone(_ task: Task) -> Bool { task.isDone || completed.contains(task.key) }
        func list(_ key: String) -> List { lists.first { $0.key == key }! }
        func at(_ day: Date, hour: Double) -> Date { clock.date(hour: hour, on: day) }
        func hour(_ time: String) -> Double {
            let parts = time.split(separator: ":").compactMap { Double($0) }
            return parts[0] + parts[1] / 60
        }
        func item(_ task: Task) -> WidgetSnapshot.Item {
            let owner = list(task.list)
            let dueDay = task.due.map { clock.day(offset: $0) }
            let due = dueDay.map { day in task.time.map { at(day, hour: hour($0)) } ?? day }
            let done = isDone(task)
            return WidgetSnapshot.Item(id: id(task.key), occurrenceID: id(task.key), title: task.title, listID: id(owner.key),
                                       listName: owner.title, listIcon: owner.icon, accent: owner.accent, dueDate: due,
                                       includesTime: task.time != nil, isCompleted: done,
                                       completedAt: done ? (completed.contains(task.key) ? now.addingTimeInterval(-600) : clock.day(offset: -1)) : nil,
                                       isStarred: task.isStarred, hasRepeat: task.repeats, priority: task.priority)
        }

        var snapshot = WidgetSnapshot()
        snapshot.generatedAt = now
        snapshot.libraryID = id("library")
        snapshot.firstWeekday = firstWeekday
        let open = tasks.filter { !isDone($0) }
        snapshot.todayItems = open.filter { ($0.due ?? 2) <= 1 }.map(item)
        snapshot.dueDays = WidgetSnapshot.dueDays(open.compactMap { item($0).dueDate }, calendar: calendar)
        snapshot.completedTodayCount = 2 + completed.count
        snapshot.completedTodayDay = today
        snapshot.inboxCount = inbox.count
        snapshot.inboxItems = inbox.map { title, hours in
            WidgetSnapshot.InboxItem(id: id("in-" + title), title: title, createdAt: now.addingTimeInterval(-hours * 3600))
        }
        snapshot.totalOpenCount = open.count + inbox.count
        snapshot.lists = lists.filter { $0.key != "inbox" }.map { owner in
            let owned = tasks.filter { $0.list == owner.key }
            // Completed newest first, as the publisher sorts them.
            let done = owned.filter(isDone).sorted { completed.contains($0.key) && !completed.contains($1.key) }
            return WidgetSnapshot.ListSummary(id: id(owner.key), title: owner.title, icon: owner.icon, accent: owner.accent,
                                              openCount: owned.count - done.count, doneCount: done.count,
                                              openItems: owned.filter { !isDone($0) }.prefix(WidgetSnapshot.ListSummary.openRows).map(item),
                                              doneItems: done.prefix(6).map(item))
        }

        // The week the Agenda and Summary draw, from its first day. Each day
        // has the design's meetings for its weekday, and today its Wednesday's;
        // on a weekday today's own move to Wednesday so none is lost, and on a
        // weekend every weekday still has its standup.
        let weekStart = clock.weekStart()
        let todayIndex = -clock.dayOffset(weekStart)
        snapshot.agenda = (0..<7).map { column in
            let day = clock.day(offset: column, from: weekStart)
            let index = column == todayIndex ? 2 : column == 2 && todayIndex < 5 ? todayIndex : column
            let meetings = events[index].enumerated().map { number, event in
                WidgetSnapshot.AgendaItem(id: "m\(column)-\(number)", kind: .meeting, title: event.2, start: at(day, hour: event.0),
                                          end: at(day, hour: event.1), isCompleted: false, isActive: false, isFlexible: false)
            }
            // Slots on their tasks' due days, as the design's; one that meets
            // the day's meetings starts as they end, as the app plans around
            // them. The design's own week needs no moving.
            let slots = plan.filter { $0.1 - 2 == column - todayIndex }.map { key, _, planned, minutes -> WidgetSnapshot.AgendaItem in
                let task = tasks.first { $0.key == key }!
                let owner = list(task.list)
                var start = planned
                for event in events[index] where event.0 < start + minutes / 60 && start < event.1 { start = event.1 }
                return WidgetSnapshot.AgendaItem(id: "p-\(key)", kind: .task, title: task.title, start: at(day, hour: start),
                                                 end: at(day, hour: start + minutes / 60), taskID: id(key), occurrenceID: id(key),
                                                 listIcon: owner.icon, listName: owner.title, accent: owner.accent,
                                                 isCompleted: isDone(task), isActive: false, isFlexible: false)
            }
            return WidgetSnapshot.AgendaDay(day: day, items: meetings + slots)
        }

        // The design's `cnt(i)`: a fixed pseudo-random count per day of a
        // 21-week grid that ends in today's week, lighter at weekends.
        let gridStart = clock.day(offset: -140, from: weekStart)
        let gridToday = calendar.dateComponents([.day], from: gridStart, to: today).day ?? 0
        snapshot.activity = WidgetSnapshot.Activity(start: gridStart, counts: (0..<gridToday).map { day in
            let value = sin(Double(day + 1) * 12.9898) * 43758.5453
            let rr = abs(value).truncatingRemainder(dividingBy: 1)
            return Int((rr * rr * (day % 7 >= 5 ? 4 : 9)).rounded(.down))
        } + [snapshot.completedTodayCount])

        if fixture == .session, let task = tasks.first(where: { $0.key == "q1" }) {
            let owner = list(task.list)
            snapshot.work = WidgetSnapshot.Work(taskID: id("q1"), occurrenceID: id("q1"), title: task.title, listName: owner.title,
                                                listIcon: owner.icon, accent: owner.accent, isRunning: false,
                                                elapsedAnchor: Date(timeIntervalSinceReferenceDate: 0), pausedElapsed: 18,
                                                slotStart: at(today, hour: 10), slotEnd: at(today, hour: 11.5), estimateMinutes: 90,
                                                item: item(task))
        }
        return snapshot
    }
}
