import Foundation

/// Today's schedule as the Today screen draws it beside the day's tasks: the
/// meetings from connected calendars and the task sessions the Calendar
/// draws, on the day of `now`, with what is on now and what comes next.
///
/// It reads what the Calendar screen reads (`CalendarCoordinator.visibleBlocks`
/// and the calendars' busy time) and only picks out the day and its moment;
/// it never plans. Times are by the wall clock, as the day column's hour
/// labels and now line are (`CalendarOverlapLayout.hours`).
struct TodaySchedule {
    enum Kind: Equatable { case meeting, session }

    struct Item: Identifiable {
        let kind: Kind
        /// The meeting, for a meeting.
        let meeting: FixedBusyTime?
        /// The block the Calendar draws, for a session.
        let block: PlannedBlock?
        let id: String
        let title: String
        let start: Date
        let end: Date
        /// A session that's done, or whose completion is settling, which now
        /// and next pass over.
        let isDone: Bool

        var taskID: UUID? { block?.taskID }
        /// Running work, which is under way whatever its times say.
        var isActive: Bool { block?.isActive ?? false }

        /// Under way at `now`.
        func isCurrent(at now: Date) -> Bool { !isDone && (isActive || (start <= now && now < end)) }
    }

    /// The start of the day shown.
    let day: Date
    let now: Date
    /// Meetings and sessions overlapping the day, by start: at the same time,
    /// meetings first and longer first, as the Calendar's lanes order them.
    let items: [Item]
    /// Busy time of 20 hours or more, named beside the schedule, not drawn.
    let holds: [FixedBusyTime]
    /// What's under way now: running work first, then by start.
    let current: [Item]
    /// The first thing still to start today.
    let next: Item?
    private let calendar: Calendar

    /// - Parameters:
    ///   - blocks: the blocks the Calendar draws (`visibleBlocks`), any days.
    ///   - busy: the calendars' busy time, any days.
    ///   - title: a session's title, its task's as the Calendar names it.
    ///   - isDone: whether a session is done, as the Calendar draws it.
    init(blocks: [PlannedBlock], busy: [FixedBusyTime], now: Date, calendar: Calendar = .current,
         title: (PlannedBlock) -> String = { $0.titleSnapshot ?? "Task" },
         isDone: (PlannedBlock) -> Bool = \.isCompleted) {
        let day = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        func overlaps(_ start: Date, _ finish: Date) -> Bool { finish > day && start < end }
        let meetings = busy.filter { overlaps($0.start, $0.end) && !$0.isAllDayHold }.map {
            Item(kind: .meeting, meeting: $0, block: nil, id: "meeting-\($0.id)", title: $0.title.isEmpty ? "Busy" : $0.title,
                 start: $0.start, end: $0.end, isDone: false)
        }
        let sessions = blocks.filter { overlaps($0.start, $0.end) }.map {
            Item(kind: .session, meeting: nil, block: $0, id: "session-\($0.id)", title: title($0), start: $0.start,
                 end: $0.end, isDone: isDone($0))
        }
        let items = (meetings + sessions).sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            if $0.kind != $1.kind { return $0.kind == .meeting }
            if $0.end != $1.end { return $0.end > $1.end }
            return $0.id < $1.id
        }
        self.day = day
        self.now = now
        self.calendar = calendar
        self.items = items
        holds = busy.filter { overlaps($0.start, $0.end) && $0.isAllDayHold }.sorted { $0.start < $1.start }
        let under = items.filter { $0.isCurrent(at: now) }
        current = under.filter(\.isActive) + under.filter { !$0.isActive }
        next = items.first { !$0.isDone && !$0.isActive && $0.start > now }
    }

    /// Nothing scheduled today, meetings or sessions.
    var isEmpty: Bool { items.isEmpty }

    /// Whether anything is under way or still to come.
    var hasRest: Bool { !current.isEmpty || next != nil }

    /// `time` on the day's clock: 10:40 is 10.67, yesterday's is negative,
    /// and tomorrow's 24 and up.
    func hour(_ time: Date) -> Double { CalendarOverlapLayout.hours(time, on: day, calendar: calendar) }

    /// The whole hours worth drawing: from the hour before now, or from the
    /// start of what's under way, to the end of the day's last item and at
    /// least two hours past now, so the now line never sits on an edge.
    /// `showsEarlier` reaches back to the day's first item too.
    func hours(showsEarlier: Bool) -> ClosedRange<Int> {
        let nowHour = Int(hour(now).rounded(.down))
        var low = nowHour - 1
        for item in current { low = min(low, Int(hour(item.start).rounded(.down))) }
        if showsEarlier, let first = items.first { low = min(low, Int(hour(first.start).rounded(.down))) }
        low = min(23, max(0, low))
        var high = max(nowHour + 2, low + 3)
        for item in items where hour(item.end) > Double(low) {
            high = max(high, Int(hour(item.end).rounded(.up)))
        }
        return low...min(24, max(low + 1, high))
    }

    /// What ends before `hours` begins: the earlier part of the day, folded
    /// away until asked for.
    func earlier(than hours: ClosedRange<Int>) -> [Item] {
        items.filter { hour($0.end) <= Double(hours.lowerBound) }
    }

    /// What `hours` shows: anything overlapping them.
    func shown(in hours: ClosedRange<Int>) -> [Item] {
        items.filter { hour($0.end) > Double(hours.lowerBound) && hour($0.start) < Double(hours.upperBound) }
    }
}
