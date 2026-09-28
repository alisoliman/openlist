//
//  TodayAgenda.swift
//  openlist
//

import Foundation

extension Block {
    /// Whether the task is planned for the day of `now`: Plan for Today, or
    /// starting work, picked it for that day or an earlier one it's still on.
    func isPlanned(on now: Date, calendar: Calendar = .current) -> Bool {
        selectedForDay.map { calendar.startOfDay(for: $0) <= calendar.startOfDay(for: now) } ?? false
    }
}

/// Today's tasks: overdue, due today, planned for today and starred, open or
/// still in their completion dwell, and those done today. The rules read
/// plain task fields, so the Mac's Today and the phone's show the same set
/// and count; only the order they draw it in differs (`Order`).
struct TodayAgenda {
    enum Order {
        /// Each group in the order its tasks came, the lists' outline order,
        /// as the Mac design's groups are plain filters of its tasks.
        case outline
        /// The phone design's: overdue first, most late first, then the rest
        /// by the time of day they're placed or due, then the untimed, ties
        /// in the order the tasks came.
        case schedule
    }

    /// Due on an earlier day. By day, as the design: a timed task whose time
    /// has passed today is still due today.
    private(set) var overdue: [Block] = []
    private(set) var due: [Block] = []
    /// Planned for today with no due date, or one after today.
    private(set) var planned: [Block] = []
    /// Starred with no due date, or one after today, and not planned.
    private(set) var starred: [Block] = []
    /// Completed today, most recently first.
    private(set) var doneToday: [Block] = []
    /// Overdue, due today and planned for today as one run, in the agenda's
    /// order: the phone's untitled card above Starred.
    private(set) var scheduled: [Block] = []

    var openCount: Int { overdue.count + due.count + planned.count + starred.count }
    /// Done today out of everything Today holds, as the header's progress
    /// and the "N done today" row count it.
    var progress: (done: Int, total: Int) { (doneToday.count, doneToday.count + openCount) }
    /// Nothing is overdue, due, planned or starred.
    var isClear: Bool { openCount == 0 }

    /// - Parameters:
    ///   - tasks: every task Today may show, open and done, in the lists'
    ///     outline order (`NextLibrary.tasksInOutlineOrder`).
    ///   - closing: tasks in their completion dwell, which keep their place
    ///     until the completion is written.
    ///   - isPlanned: whether a task is planned for today; by default
    ///     `Block.isPlanned(on: now)`.
    ///   - time: where a task is placed on today's calendar, which `schedule`
    ///     orders it by ahead of a timed due date today.
    init(tasks: [Block], closing: Set<UUID> = [], now: Date = .now, calendar: Calendar = .current,
         order: Order = .outline, isPlanned: ((Block) -> Bool)? = nil, time: (Block) -> Date? = { _ in nil }) {
        let isPlanned = isPlanned ?? { $0.isPlanned(on: now, calendar: calendar) }
        let today = calendar.startOfDay(for: now)
        func dayOffset(_ date: Date) -> Int {
            calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: date)).day ?? 0
        }
        func offset(_ task: Block) -> Int? { task.dueDate.map(dayOffset) }
        let visible = tasks.filter { !$0.isCompleted || closing.contains($0.id) }
        overdue = visible.filter { (offset($0) ?? 0) < 0 }
        due = visible.filter { offset($0) == 0 }
        planned = visible.filter { isPlanned($0) && (offset($0) ?? 1) > 0 }
        starred = visible.filter { $0.isStarred && (offset($0) ?? 1) > 0 && !isPlanned($0) }
        doneToday = tasks
            .filter { $0.isCompleted && $0.completedAt.map { dayOffset($0) == 0 } == true }
            .sorted(by: Block.byCompletionDate)
        guard order == .schedule else {
            scheduled = overdue + due + planned
            return
        }
        let position = Dictionary(tasks.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        func place(_ task: Block) -> Int { position[task.id] ?? .max }
        // A calendar slot today first, then a timed due date today.
        func clock(_ task: Block) -> Date? {
            if let slot = time(task), dayOffset(slot) == 0 { return slot }
            guard task.includesTime, let due = task.dueDate, dayOffset(due) == 0 else { return nil }
            return due
        }
        func byTime(_ lhs: Block, _ rhs: Block) -> Bool {
            switch (clock(lhs), clock(rhs)) {
            case let (left?, right?) where left != right: left < right
            case (_?, nil): true
            case (nil, _?): false
            default: place(lhs) < place(rhs)
            }
        }
        overdue.sort { (offset($0) ?? 0, place($0)) < (offset($1) ?? 0, place($1)) }
        due.sort(by: byTime)
        planned.sort(by: byTime)
        starred.sort(by: byTime)
        scheduled = overdue + (due + planned).sorted(by: byTime)
    }
}
