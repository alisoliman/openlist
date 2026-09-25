//
//  SampleSnapshot.swift
//  OpenlistWidget
//

import Foundation

extension WidgetSnapshot {
    /// The design mockup's data placed around `now`, for the widget gallery,
    /// placeholders and the render harness.
    ///
    /// Everything is relative: tasks keep their day offsets and clock times,
    /// and the week is laid out with today as its third day, as in the
    /// mockup. Counters are derived from the rows with the app's own rules
    /// (a timed task is late once its time passes), so the sample is always
    /// self-consistent, whatever the time.
    nonisolated static func sample(now: Date = .now, work: Work.State? = nil, calendar: Calendar = .current) -> WidgetSnapshot {
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today) ?? today }
        func time(_ hours: Double, on date: Date) -> Date {
            calendar.date(byAdding: .minute, value: Int((hours * 60).rounded()), to: date) ?? date
        }

        var snapshot = WidgetSnapshot()
        snapshot.generatedAt = now
        snapshot.libraryID = SampleData.id(0x1)
        snapshot.accentHex = 0x7C4DF0
        snapshot.serifTitles = true
        let weekStart = day(-2)
        snapshot.weekStart = weekStart
        snapshot.firstWeekday = calendar.component(.weekday, from: weekStart)

        // Tasks.
        var items: [String: Item] = [:]
        for (index, task) in SampleData.tasks.enumerated() {
            let list = SampleData.list(task.list)
            let due = task.due.map { offset in task.time.map { time($0, on: day(offset)) } ?? day(offset) }
            items[task.key] = Item(
                id: sampleTaskID(task.key),
                occurrenceID: sampleOccurrenceID(task.key),
                title: task.title,
                listID: sampleListID(task.list),
                listName: list.name,
                listIcon: list.icon,
                accentHex: list.hex,
                dueDate: due,
                includesTime: task.time != nil,
                isCompleted: task.isDone,
                completedAt: task.isDone ? time(9 + Double(index % 3) * 0.25, on: today) : nil,
                isStarred: task.isStarred,
                hasRepeat: task.repeats,
                priority: task.priority,
                createdAt: day(-14 + index % 9)
            )
        }
        let tasks = SampleData.tasks.compactMap { items[$0.key] }
        let open = tasks.filter { !$0.isCompleted }
        // By day; within a day timed work first, then untimed, as the
        // mockup's Today orders it.
        let dated = open
            .compactMap { item in
                item.dueDate.map { (item: item, day: WidgetFormat.dayOffset(from: now, to: $0, calendar: calendar), due: $0) }
            }
            .sorted { ($0.day, $0.item.includesTime ? 0 : 1, $0.due) < ($1.day, $1.item.includesTime ? 0 : 1, $1.due) }
        snapshot.todayItems = dated.filter { $0.day <= 0 }.map(\.item)
        snapshot.overdueCount = snapshot.todayItems.count { $0.isOverdue(at: now, calendar: calendar) }
        snapshot.dueTodayCount = snapshot.todayItems.count - snapshot.overdueCount
        snapshot.dueToday = snapshot.todayItems
            .filter { !$0.isOverdue(at: now, calendar: calendar) }
            .compactMap { item in item.dueDate.map { Due(date: $0, includesTime: item.includesTime) } }
            .sorted { $0.date < $1.date }
        // Tomorrow's work, as the app publishes it for a widget to start the
        // next day with.
        snapshot.tomorrowItems = dated.filter { $0.day == 1 }.map(\.item)
        snapshot.dueTomorrow = snapshot.tomorrowItems
            .compactMap { item in item.dueDate.map { Due(date: $0, includesTime: item.includesTime) } }
            .sorted { $0.date < $1.date }
        snapshot.completedTodayCount = tasks.count { $0.completedAt.map { calendar.isDate($0, inSameDayAs: now) } ?? false }

        // Inbox.
        snapshot.inboxItems = SampleData.inbox.enumerated().map { index, capture in
            InboxItem(id: SampleData.id(0x300 + index), title: capture.title, createdAt: now.addingTimeInterval(-capture.age))
        }
        snapshot.inboxCount = snapshot.inboxItems.count
        snapshot.totalOpenCount = open.count + snapshot.inboxCount

        // Lists, Inbox first.
        let inbox = SampleData.list("inbox")
        let inboxRows = snapshot.inboxItems.enumerated().map { index, capture in
            Item(id: capture.id, occurrenceID: SampleData.id(0x500 + index), title: capture.title, listID: sampleListID("inbox"),
                 listName: inbox.name, listIcon: inbox.icon, accentHex: inbox.hex, dueDate: nil, includesTime: false,
                 isCompleted: false, completedAt: nil, isStarred: false, hasRepeat: false, priority: 0, createdAt: capture.createdAt)
        }
        snapshot.lists = SampleData.lists.map { list in
            let rows = list.key == "inbox" ? inboxRows : tasks.filter { $0.listID == sampleListID(list.key) }
            let openRows = rows.filter { !$0.isCompleted }
            let doneRows = rows.filter(\.isCompleted)
            return ListSummary(
                id: sampleListID(list.key), title: list.name, path: list.name, icon: list.icon, accentHex: list.hex,
                isInbox: list.key == "inbox", openCount: openRows.count, doneCount: doneRows.count,
                openItems: openRows, doneItems: doneRows
            )
        }

        // The week: meetings, then planned blocks.
        var agenda: [AgendaEvent] = []
        for (weekday, meetings) in SampleData.meetings.enumerated() {
            let date = day(weekday - 2)
            for (index, meeting) in meetings.enumerated() {
                agenda.append(AgendaEvent(id: "meeting-\(weekday)-\(index)", kind: .meeting, title: meeting.title,
                                          start: time(meeting.start, on: date), end: time(meeting.end, on: date)))
            }
        }
        for block in SampleData.plan {
            guard let item = items[block.task] else { continue }
            let start = time(block.start, on: day(block.weekday - 2))
            agenda.append(AgendaEvent(
                id: "block-\(block.task)", kind: .task, title: item.title, start: start,
                end: start.addingTimeInterval(block.minutes * 60), taskID: item.id, occurrenceID: item.occurrenceID,
                listName: item.listName, listIcon: item.listIcon, accentHex: item.accentHex, isCompleted: item.isCompleted
            ))
        }

        // The session in the app's toolbar, when asked for.
        if let work, let item = items["q1"], let index = agenda.firstIndex(where: { $0.id == "block-q1" }) {
            let block = agenda[index]
            agenda[index].isActive = work == .working
            snapshot.work = Work(
                state: work, taskID: item.id, occurrenceID: item.occurrenceID, title: item.title,
                listName: item.listName, listIcon: item.listIcon, accentHex: item.accentHex,
                segmentStartedAt: work == .working ? now.addingTimeInterval(-4) : nil,
                priorSeconds: work == .working ? 0 : 14,
                estimateMinutes: block.end.timeIntervalSince(block.start) / 60,
                blockStart: block.start, blockEnd: block.end
            )
        }
        snapshot.agenda = agenda.sorted { $0.start < $1.start }

        snapshot.activity = SampleData.activity(weekStart: weekStart, today: today, doneToday: snapshot.completedTodayCount,
                                                calendar: snapshot.calendar(base: calendar))
        return snapshot
    }

    /// 10:40 on Wednesday 23 September 2026, the mockup's "now".
    nonisolated static func mockupNow(calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 10, minute: 40)) ?? .now
    }

    /// Stable IDs, so tests and render cases can refer to sample rows by the
    /// mockup's keys ("q1", "kyoto").
    nonisolated static func sampleTaskID(_ key: String) -> UUID {
        SampleData.id(0x200 + (SampleData.tasks.firstIndex { $0.key == key } ?? 0xFF))
    }

    /// The sample row's occurrence, which every widget command must name.
    nonisolated static func sampleOccurrenceID(_ key: String) -> UUID {
        SampleData.id(0x400 + (SampleData.tasks.firstIndex { $0.key == key } ?? 0xFF))
    }

    nonisolated static func sampleListID(_ key: String) -> UUID {
        SampleData.id(0x100 + (SampleData.lists.firstIndex { $0.key == key } ?? 0xFF))
    }
}

extension SnapshotEntry {
    /// An entry over the sample snapshot.
    nonisolated static func sample(
        now: Date = .now,
        work: WidgetSnapshot.Work.State? = nil,
        pending: [WidgetCommand] = [],
        list: ListSelection? = nil,
        calendar: Calendar = .current
    ) -> SnapshotEntry {
        SnapshotEntry(date: now, snapshot: .sample(now: now, work: work, calendar: calendar), pending: pending, list: list, calendar: calendar)
    }
}

/// The mockup's tables (`mockup-logic.js`), kept as data.
private nonisolated enum SampleData {
    struct List { var key: String; var icon: String; var name: String; var hex: UInt32 }
    struct Task {
        var key: String
        var list: String
        var title: String
        /// Days from today; `nil` for undated.
        var due: Int?
        var time: Double? = nil
        var priority = 0
        var isStarred = false
        var repeats = false
        var isDone = false
    }
    struct Meeting { var start: Double; var end: Double; var title: String }
    struct Block { var task: String; var weekday: Int; var start: Double; var minutes: Double }

    static let lists = [
        List(key: "inbox", icon: "📥", name: "Inbox", hex: 0x3A7BD8),
        List(key: "kyoto", icon: "🗻", name: "Weekend in Kyoto", hex: 0x7C4DF0),
        List(key: "home", icon: "🏡", name: "Home", hex: 0x2F9E6E),
        List(key: "reading", icon: "📚", name: "Reading", hex: 0xC2532B),
        List(key: "q3", icon: "💼", name: "Q3 planning", hex: 0x2F6FE0),
        List(key: "hiring", icon: "🎯", name: "Hiring loop", hex: 0xB8479A),
    ]

    static let tasks = [
        Task(key: "q4", list: "q3", title: "Close out Q2 retro actions", due: -3, priority: 2),
        Task(key: "k3", list: "kyoto", title: "Reserve the Nishiki market tour", due: -2),
        Task(key: "h1", list: "home", title: "Fix the dripping bathroom tap", due: -1),
        Task(key: "q1", list: "q3", title: "Draft Q3 OKRs", due: 0, time: 10, priority: 3),
        Task(key: "p1", list: "hiring", title: "Write interview feedback for Priya", due: 0, time: 11.5, isStarred: true),
        Task(key: "k4", list: "kyoto", title: "Ask Mika to water the planters", due: 0, repeats: true),
        Task(key: "k2", list: "kyoto", title: "Pay the ryokan deposit", due: 0, time: 18),
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

    /// Title and age in seconds.
    static let inbox: [(title: String, age: TimeInterval)] = [
        ("Send Jun the photos from Nara", 2 * 3600),
        ("Cancel the gym trial before it renews", 5 * 3600),
        ("Call the dentist back about the crown", 86_400),
        ("Look into a standing desk", 2 * 86_400),
        ("Return the library books", 3 * 86_400),
        ("Gift ideas for Mika’s birthday", 4 * 86_400),
    ]

    /// Monday to Sunday; today is Wednesday.
    static let meetings: [[Meeting]] = [
        [Meeting(start: 9.5, end: 10, title: "Standup"), Meeting(start: 13, end: 14, title: "Design review")],
        [Meeting(start: 9.5, end: 10, title: "Standup"), Meeting(start: 11, end: 12, title: "1:1 with Sam"), Meeting(start: 15, end: 16.5, title: "Hiring sync")],
        [Meeting(start: 9.5, end: 10, title: "Standup"), Meeting(start: 14, end: 15, title: "Board prep"),
         Meeting(start: 15.5, end: 16, title: "Priya debrief"), Meeting(start: 16, end: 16.5, title: "Coffee with Leo")],
        [Meeting(start: 9.5, end: 10, title: "Standup"), Meeting(start: 10, end: 12, title: "Offsite planning")],
        [Meeting(start: 9.5, end: 10, title: "Standup"), Meeting(start: 12, end: 13, title: "Team lunch")],
        [Meeting(start: 10, end: 11.5, title: "Pottery class")],
        [],
    ]

    static let plan = [
        Block(task: "q4", weekday: 1, start: 14, minutes: 30),
        Block(task: "q1", weekday: 2, start: 10, minutes: 90),
        Block(task: "p1", weekday: 2, start: 11.5, minutes: 20),
        Block(task: "p3", weekday: 2, start: 13, minutes: 30),
        Block(task: "h2", weekday: 2, start: 16.5, minutes: 10),
        Block(task: "k2", weekday: 2, start: 18, minutes: 15),
        Block(task: "q2", weekday: 3, start: 13, minutes: 45),
        Block(task: "q5", weekday: 4, start: 10, minutes: 60),
    ]

    static func list(_ key: String) -> List {
        lists.first { $0.key == key } ?? lists[0]
    }

    static func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "0E1D0000-0000-4000-8000-%012X", value))!
    }

    /// 21 weeks ending with this one, filled with the mockup's pseudo-random
    /// counts (fewer at weekends) and today's real completions.
    static func activity(weekStart: Date, today: Date, doneToday: Int, calendar: Calendar) -> WidgetSnapshot.Activity {
        let todayIndex = 20 * 7 + (calendar.dateComponents([.day], from: weekStart, to: today).day ?? 0)
        func count(_ index: Int) -> Int {
            if index == todayIndex { return doneToday }
            let seed = abs(sin(Double(index + 1) * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1)
            return Int(seed * seed * (index % 7 >= 5 ? 4 : 9))
        }
        let first = calendar.date(byAdding: .day, value: -20 * 7, to: weekStart) ?? weekStart
        var activity = WidgetSnapshot.Activity()
        activity.days = (0...todayIndex).compactMap { index in
            calendar.date(byAdding: .day, value: index, to: first).map { WidgetSnapshot.ActivityDay(date: $0, count: count(index)) }
        }
        let stats = ActivityStats(activity: activity, now: today, calendar: calendar)
        activity.streak = stats.streak
        activity.today = stats.today
        activity.week = stats.week
        activity.month = stats.month
        activity.monthName = stats.monthName
        return activity
    }
}
