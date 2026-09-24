//
//  WidgetModels.swift
//  OpenlistWidget
//
//  What each widget shows, worked out from the snapshot at a timeline entry's
//  date. Ported from `model()` and `renderVals()` in the design; pure, so the
//  widget checks can run them.
//

import Foundation

/// The entry's moment and the settings calendar every relative word uses.
struct WidgetClock {
    let now: Date
    let calendar: Calendar
    let locale: Locale

    init(now: Date, firstWeekday: Int = 1, calendar base: Calendar = .current, locale: Locale = .current) {
        var calendar = base
        if (1...7).contains(firstWeekday) { calendar.firstWeekday = firstWeekday }
        self.now = now
        self.calendar = calendar
        self.locale = locale
    }

    var today: Date { calendar.startOfDay(for: now) }

    func day(offset: Int, from day: Date? = nil) -> Date {
        calendar.date(byAdding: .day, value: offset, to: day ?? today) ?? today
    }

    /// Whole days from today to `date`'s day.
    func dayOffset(_ date: Date) -> Int {
        calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: date)).day ?? 0
    }

    /// The first day of the settings week containing `date`.
    func weekStart(_ date: Date? = nil) -> Date {
        let day = calendar.startOfDay(for: date ?? now)
        let offset = (calendar.component(.weekday, from: day) - calendar.firstWeekday + 7) % 7
        return self.day(offset: -offset, from: day)
    }

    /// "09:30", as the design's `hm`.
    func hm(_ date: Date) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// Hours since the start of `day`, fractional.
    func hours(_ date: Date, on day: Date) -> Double {
        date.timeIntervalSince(day) / 3600
    }

    var nowHours: Double { hours(now, on: today) }

    func format(_ date: Date, _ style: Date.FormatStyle) -> String {
        var style = style
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        style.locale = locale
        return date.formatted(style)
    }
}

// MARK: - Rows

/// A task line in Today and List.
struct WidgetRow: Identifiable, Equatable {
    var id: UUID
    var occurrenceID: UUID?
    var title: String
    var listIcon: String
    var listName: String
    var accent: String
    var priority: Int
    var isStarred: Bool
    var isLate: Bool
    var isDone: Bool
    /// "3d late", "10:00", "Repeats", "Today", "Tomorrow", "Sat 26", "Done".
    var dueText: String

    init(_ item: WidgetSnapshot.Item, clock: WidgetClock) {
        id = item.id
        occurrenceID = item.occurrenceID
        title = item.title.isEmpty ? "Untitled task" : item.title
        listIcon = item.listIcon
        listName = item.listName
        accent = item.accent
        priority = item.priority
        isStarred = item.isStarred
        isDone = item.isCompleted
        let offset = item.dueDate.map(clock.dayOffset)
        isLate = !item.isCompleted && (offset ?? 0) < 0
        dueText = Self.dueText(item, offset: offset, clock: clock)
    }

    static func dueText(_ item: WidgetSnapshot.Item, offset: Int?, clock: WidgetClock) -> String {
        if item.isCompleted { return "Done" }
        guard let due = item.dueDate, let offset else { return "" }
        switch offset {
        case ..<0: return "\(-offset)d late"
        case 0: return item.includesTime ? clock.hm(due) : item.hasRepeat ? "Repeats" : "Today"
        case 1: return "Tomorrow"
        case 2..<7: return clock.format(due, .dateTime.weekday(.abbreviated).day())
        default: return clock.format(due, .dateTime.day().month(.abbreviated))
        }
    }
}

// MARK: - Today

struct TodayModel: Equatable {
    /// Overdue first, then today's; timed before untimed, by time.
    var rows: [WidgetRow]
    var late: Int
    var dueToday: Int
    var done: Int
    /// "Wednesday", "23".
    var weekday: String
    var dayNumber: String

    var total: Int { done + late + dueToday }
    /// Every row Today could list; the snapshot carries only the first ones.
    var itemCount: Int { max(rows.count, late + dueToday) }
    var progress: Double { total > 0 ? Double(done) / Double(total) : 0 }
    var lateRows: [WidgetRow] { rows.filter(\.isLate) }
    var dueRows: [WidgetRow] { rows.filter { !$0.isLate } }

    init(_ snapshot: WidgetSnapshot, clock: WidgetClock) {
        let counts = DueCounts(snapshot, clock: clock)
        late = counts.overdue
        dueToday = counts.dueToday
        done = counts.done
        let indexed = snapshot.todayItems.enumerated().compactMap { index, item -> (Int, Int, WidgetSnapshot.Item)? in
            guard !item.isCompleted, let due = item.dueDate else { return nil }
            let offset = clock.dayOffset(due)
            return offset <= 0 ? (index, offset, item) : nil
        }
        rows = indexed.sorted { a, b in
            if a.1 != b.1 { return a.1 < b.1 }
            // The design's `(a.time || "99") < (b.time || "99")`.
            let at = a.2.includesTime ? a.2.dueDate : nil, bt = b.2.includesTime ? b.2.dueDate : nil
            switch (at, bt) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.0 < b.0
            }
        }.map { WidgetRow($0.2, clock: clock) }
        weekday = clock.format(clock.now, .dateTime.weekday(.wide))
        dayNumber = clock.format(clock.now, .dateTime.day())
    }
}

/// Overdue, due today and done today, at the entry's date.
struct DueCounts: Equatable {
    var overdue = 0
    var dueToday = 0
    var done = 0

    init(_ snapshot: WidgetSnapshot, clock: WidgetClock) {
        for due in snapshot.dueDays {
            let offset = clock.dayOffset(due.day)
            if offset < 0 { overdue += due.count } else if offset == 0 { dueToday += due.count }
        }
        done = snapshot.completedToday(on: clock)
    }
}

extension WidgetSnapshot {
    /// Tasks completed on the entry's day: the published count while it's the
    /// day it was counted on, nothing once that day is over.
    func completedToday(on clock: WidgetClock) -> Int {
        guard let day = completedTodayDay else { return completedTodayCount }
        return clock.calendar.isDate(day, inSameDayAs: clock.now) ? completedTodayCount : 0
    }
}

// MARK: - List

struct ListModel: Equatable {
    var id: UUID
    var emoji: String
    var name: String
    var accent: String
    var open: Int
    var done: Int
    var rows: [WidgetRow]
    /// Every row the widget could show, beyond the ones the snapshot carries.
    var rowCount: Int

    var progress: Double { open + done > 0 ? Double(done) / Double(open + done) : 0 }

    init(_ list: WidgetSnapshot.ListSummary, showsCompleted: Bool, clock: WidgetClock) {
        id = list.id
        emoji = list.icon
        name = list.title
        accent = list.accent
        open = list.openCount
        done = list.doneCount
        let items = list.openItems + (showsCompleted ? list.doneItems : [])
        rows = items.map { WidgetRow($0, clock: clock) }
        rowCount = max(rows.count, list.openCount + (showsCompleted ? list.doneCount : 0))
    }
}

// MARK: - Up Next

struct UpNextModel: Equatable {
    enum State: Equatable { case working, paused, now, next, clear }

    /// The elapsed clock: ticking from an anchor, or stopped.
    enum Clock: Equatable {
        case running(anchor: Date)
        case paused(seconds: Double)
    }

    struct Later: Equatable, Identifiable {
        var id: String
        var time: String
        var title: String
        var isMeeting: Bool
        var accent: String?
    }

    var state: State
    var time: String
    var title: String
    var listIcon: String
    var listName: String
    /// "50 min left" or "in 20 min"; the clock replaces it while working.
    var note: String
    var progress: Double
    var timer: Clock?
    var taskID: UUID?
    var occurrenceID: UUID?
    var later: [Later]

    var label: String {
        switch state {
        case .working: "Working"
        case .paused: "Paused"
        case .now: "Now"
        case .next: "Next"
        case .clear: "Clear"
        }
    }

    init(_ snapshot: WidgetSnapshot, clock: WidgetClock, heartbeatLimit: Date? = nil) {
        let now = clock.now
        let span = { (start: Date, end: Date) in clock.hm(start) + "–" + clock.hm(end) }
        let day = snapshot.agenda.first { clock.calendar.isDate($0.day, inSameDayAs: now) }?.items ?? []
        let tasks = day.filter { $0.kind == .task && !$0.isCompleted && !$0.isActive }
        let meetings = day.filter { $0.kind == .meeting }
        func current(_ items: [WidgetSnapshot.AgendaItem]) -> (WidgetSnapshot.AgendaItem, State)? {
            if let block = items.first(where: { $0.start <= now && now < $0.end }) { return (block, .now) }
            if let block = items.filter({ $0.start > now }).min(by: { $0.start < $1.start }) { return (block, .next) }
            return nil
        }

        var after = now
        if var work = snapshot.work {
            // A running timer whose heartbeat stopped belongs to an app that is
            // no longer running: show it paused where it was last recorded, as
            // the app itself does on its next launch.
            if work.isRunning, let limit = heartbeatLimit, let beat = snapshot.heartbeatAt, beat < limit {
                work.isRunning = false
                work.pausedElapsed = max(0, beat.timeIntervalSince(work.elapsedAnchor))
            }
            let elapsed = work.isRunning ? max(0, now.timeIntervalSince(work.elapsedAnchor)) : work.pausedElapsed
            state = work.isRunning ? .working : .paused
            title = work.title
            listIcon = work.listIcon
            listName = work.listName
            taskID = work.taskID
            occurrenceID = work.occurrenceID
            timer = work.isRunning ? .running(anchor: work.elapsedAnchor) : .paused(seconds: work.pausedElapsed)
            note = ""
            if let start = work.slotStart, let end = work.slotEnd, end > start {
                time = span(start, end)
                progress = min(1, elapsed / end.timeIntervalSince(start))
                after = max(end, now)
            } else {
                time = ""
                progress = min(1, elapsed / max(60, work.estimateMinutes * 60))
            }
        } else if let (block, found) = current(tasks.filter { !$0.isFlexible }) ?? current(tasks.filter(\.isFlexible)) {
            state = found
            title = block.title
            listIcon = block.listIcon ?? ""
            listName = block.listName ?? ""
            taskID = block.taskID
            occurrenceID = block.occurrenceID
            timer = nil
            time = span(block.start, block.end)
            if found == .now {
                progress = now.timeIntervalSince(block.start) / block.end.timeIntervalSince(block.start)
                note = Self.minutes(block.end.timeIntervalSince(now)) + " left"
            } else {
                progress = 0
                note = "in " + Self.minutes(block.start.timeIntervalSince(now))
            }
            after = block.end
        } else {
            state = .clear
            title = "Nothing else planned"
            listIcon = ""
            listName = "Your day is clear"
            note = ""
            time = ""
            progress = 0
            timer = nil
            later = []
            return
        }

        let current = taskID
        let upcoming = meetings.filter { $0.start >= after }
            + tasks.filter { !$0.isFlexible && $0.start >= after && $0.taskID != current }
        later = upcoming.sorted { $0.start == $1.start ? $0.kind == .meeting && $1.kind != .meeting : $0.start < $1.start }
            .prefix(4).map { item in
                Later(id: item.id, time: clock.hm(item.start), title: item.title, isMeeting: item.kind == .meeting, accent: item.accent)
            }
    }

    /// "50 min", and "140 min" past an hour: the design counts minutes only.
    static func minutes(_ seconds: TimeInterval) -> String {
        "\(max(0, Int((seconds / 60).rounded()))) min"
    }
}

// MARK: - Quick Add

struct CaptureModel: Equatable {
    struct Item: Equatable, Identifiable {
        var id: UUID
        var title: String
        var age: String
    }

    var count: Int
    var items: [Item]

    init(_ snapshot: WidgetSnapshot, clock: WidgetClock) {
        count = snapshot.inboxCount
        items = snapshot.inboxItems.prefix(4).map {
            Item(id: $0.id, title: $0.title.isEmpty ? "Untitled task" : $0.title, age: Self.age($0.createdAt, now: clock.now))
        }
    }

    /// "12m", "2h", "3d".
    static func age(_ date: Date, now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
        if minutes < 60 { return "\(max(1, minutes))m" }
        if minutes < 24 * 60 { return "\(minutes / 60)h" }
        return "\(minutes / (24 * 60))d"
    }
}

// MARK: - Summary

struct SummaryModel: Equatable {
    struct Bar: Equatable, Identifiable {
        var id: Int
        var day: String
        /// Nil for days still to come.
        var count: Int?
        var isToday: Bool
    }

    var due: Int
    var overdue: Int
    var inbox: Int
    var done: Int
    var week: [Bar]

    var weekTotal: Int { week.reduce(0) { $0 + ($1.count ?? 0) } }

    init(_ snapshot: WidgetSnapshot, clock: WidgetClock) {
        let counts = DueCounts(snapshot, clock: clock)
        due = counts.dueToday
        overdue = counts.overdue
        inbox = snapshot.inboxCount
        done = counts.done
        let days = ActivityDays(snapshot, clock: clock)
        let start = clock.weekStart()
        week = (0..<7).map { index in
            let day = clock.day(offset: index, from: start)
            let letter = String(clock.format(day, .dateTime.weekday(.narrow)))
            return Bar(id: index, day: letter, count: days.count(on: day), isToday: clock.calendar.isDate(day, inSameDayAs: clock.now))
        }
    }
}

/// Completions per day at the entry's date: the heatmap's counts for past days,
/// today's completions for today, nothing for days to come.
struct ActivityDays {
    let clock: WidgetClock
    let activity: WidgetSnapshot.Activity?
    let today: Int

    init(_ snapshot: WidgetSnapshot, clock: WidgetClock) {
        self.clock = clock
        activity = snapshot.activity
        today = snapshot.completedToday(on: clock)
    }

    func count(on day: Date) -> Int? {
        let offset = clock.dayOffset(day)
        if offset > 0 { return nil }
        if offset == 0 { return today }
        guard let activity else { return 0 }
        let index = clock.calendar.dateComponents([.day], from: clock.calendar.startOfDay(for: activity.start),
                                                  to: clock.calendar.startOfDay(for: day)).day ?? -1
        return activity.counts.indices.contains(index) ? activity.counts[index] : 0
    }
}

// MARK: - Activity

struct ActivityModel: Equatable {
    /// Columns of seven days, oldest first; nil for days still to come.
    var weeks: [[Int?]]
    /// Where today sits in the last column.
    var todayIndex: Int
    var streak: Int
    var today: Int
    var week: Int
    var month: Int
    var monthName: String

    init(_ snapshot: WidgetSnapshot, clock: WidgetClock, weeks count: Int) {
        let days = ActivityDays(snapshot, clock: clock)
        let first = clock.day(offset: -7 * (count - 1), from: clock.weekStart())
        weeks = (0..<count).map { week in
            (0..<7).map { index in days.count(on: clock.day(offset: week * 7 + index, from: first)) }
        }
        todayIndex = clock.dayOffset(clock.weekStart()) * -1
        today = days.today
        // As the app: an empty today doesn't break the streak.
        var streak = 0
        var offset = 0
        while let value = days.count(on: clock.day(offset: offset)), offset > -3660 {
            if value > 0 { streak += 1 } else if offset != 0 { break }
            offset -= 1
        }
        self.streak = streak
        week = (0...todayIndex).reduce(0) { $0 + (days.count(on: clock.day(offset: -$1)) ?? 0) }
        let dayOfMonth = clock.calendar.component(.day, from: clock.now)
        month = (0..<dayOfMonth).reduce(0) { $0 + (days.count(on: clock.day(offset: -$1)) ?? 0) }
        monthName = clock.format(clock.now, .dateTime.month(.wide))
    }

    /// The design's opacity steps, on the Activity screen heatmap's thresholds.
    static func opacity(_ count: Int) -> Double {
        switch count {
        case ...0: 0
        case 1: 0.28
        case 2...3: 0.5
        case 4...6: 0.75
        default: 1
        }
    }
}

// MARK: - Agenda

struct AgendaModel: Equatable {
    /// The hours the grid covers, as the design.
    static let firstHour = 9.0
    static let lastHour = 19.0

    struct Item: Equatable, Identifiable {
        var id: String
        var title: String
        var timeText: String
        /// Hours since the day's start.
        var start: Double
        var end: Double
        var isMeeting: Bool
        var isDone: Bool
        var accent: String?
    }

    struct Day: Equatable, Identifiable {
        var id: Date { day }
        var day: Date
        /// "Mon 21".
        var label: String
        var isToday: Bool
        var items: [Item]
    }

    var today: Day
    var week: [Day]
    var nowHour: Double
    /// "Wed 23 · 4 meetings · 5 planned".
    var daySubtitle: String
    /// "21 – 27 September".
    var range: String

    init(_ snapshot: WidgetSnapshot, clock: WidgetClock) {
        func day(_ date: Date) -> Day {
            let items = snapshot.agenda.first { clock.calendar.isDate($0.day, inSameDayAs: date) }?.items ?? []
            let start = clock.calendar.startOfDay(for: date)
            return Day(day: start, label: clock.format(start, .dateTime.weekday(.abbreviated).day()),
                       isToday: clock.calendar.isDate(start, inSameDayAs: clock.now),
                       items: items.filter { !$0.isFlexible }.map { item in
                           Item(id: item.id, title: item.title, timeText: clock.hm(item.start) + "–" + clock.hm(item.end),
                                start: clock.hours(item.start, on: start), end: clock.hours(item.end, on: start),
                                isMeeting: item.kind == .meeting, isDone: item.isCompleted, accent: item.accent)
                       })
        }
        today = day(clock.now)
        let start = clock.weekStart()
        week = (0..<7).map { day(clock.day(offset: $0, from: start)) }
        nowHour = clock.nowHours
        let meetings = today.items.filter(\.isMeeting).count
        let planned = today.items.count - meetings
        daySubtitle = "\(today.label) · \(meetings) meeting\(meetings == 1 ? "" : "s") · \(planned) planned"
        let end = clock.day(offset: 6, from: start)
        let sameMonth = clock.calendar.isDate(start, equalTo: end, toGranularity: .month)
        range = sameMonth
            ? "\(clock.format(start, .dateTime.day())) – \(clock.format(end, .dateTime.day())) \(clock.format(end, .dateTime.month(.wide)))"
            : "\(clock.format(start, .dateTime.day().month(.wide))) – \(clock.format(end, .dateTime.day().month(.wide)))"
    }

    /// Where an item sits in a grid `pxh` points per hour tall (`top`, `height`).
    static func frame(start: Double, end: Double, pxh: Double) -> (top: Double, height: Double) {
        let top = (max(start, firstHour) - firstHour) * pxh + 1
        let height = max(13, (min(end, lastHour) - max(start, firstHour)) * pxh - 2)
        return (top, height)
    }

    /// The now line's offset, or nil outside the grid's hours.
    static func nowOffset(_ hour: Double, pxh: Double) -> Double? {
        (firstHour...lastHour).contains(hour) ? (hour - firstHour) * pxh : nil
    }
}
