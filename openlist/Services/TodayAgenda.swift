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

/// Today's display rows. Each eligible root carries its task outline;
/// additional subtasks here don't change the agenda's counts or actions.
struct TodayAgendaRows {
    var overdue: [BlockRow]
    var due: [BlockRow]
    var planned: [BlockRow]
    var starred: [BlockRow]
    var doneToday: [BlockRow]
}

extension TodayAgenda {
    /// Nests tasks beneath their eligible ancestors, even when their own
    /// dates would put them in another group. An eligible task with no
    /// eligible ancestor remains a root in its own group. Roots keep the
    /// agenda's order; their subtasks keep the list's outline order.
    ///
    /// `outline` is every task row, open and done, from `taskOutline` of the
    /// whole documents flattened without respecting collapse. Missing or
    /// disconnected tasks should be appended by the caller at depth zero.
    /// Today draws these outlines expanded without changing stored folds.
    func nestedRows(in outline: [BlockRow]) -> TodayAgendaRows {
        let positions = Dictionary(outline.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        var ends = Array(repeating: outline.count, count: outline.count)
        var path: [Int] = []
        for (index, row) in outline.enumerated() {
            while let ancestor = path.last, outline[ancestor].depth >= row.depth {
                ends[path.removeLast()] = index
            }
            path.append(index)
        }

        func roots(in selected: Set<UUID>) -> Set<UUID> {
            var result: Set<UUID> = []
            var path: [(depth: Int, selectedAbove: Bool)] = []
            for row in outline {
                while let ancestor = path.last, ancestor.depth >= row.depth { path.removeLast() }
                let selectedAbove = path.last?.selectedAbove ?? false
                let isSelected = selected.contains(row.id)
                if isSelected && !selectedAbove { result.insert(row.id) }
                path.append((row.depth, selectedAbove || isSelected))
            }
            return result
        }

        let openIDs = Set((overdue + due + planned + starred).map(\.id))
        let openRoots = roots(in: openIDs)
        var drawn: Set<UUID> = []
        func expanding(_ tasks: [Block]) -> [BlockRow] {
            var rows: [BlockRow] = []
            for task in tasks where openRoots.contains(task.id) {
                guard let start = positions[task.id] else { continue }
                for var row in outline[start..<ends[start]] where drawn.insert(row.id).inserted {
                    row.depth -= outline[start].depth
                    row.isCollapsed = false
                    rows.append(row)
                }
            }
            return rows
        }

        let overdueRows = expanding(overdue)
        let dueRows = expanding(due)
        let plannedRows = expanding(planned)
        let starredRows = expanding(starred)

        // Done subtasks already drawn under an open root stay there. The
        // remaining done tasks nest only among other tasks done today;
        // their unrelated open or older completed descendants stay out.
        let doneIDs = Set(doneToday.map(\.id)).subtracting(drawn)
        let doneRoots = roots(in: doneIDs)
        var doneRows: [BlockRow] = []
        for task in doneToday where doneRoots.contains(task.id) {
            guard let start = positions[task.id] else { continue }
            var path: [(depth: Int, doneDepth: Int)] = []
            for var row in outline[start..<ends[start]] {
                while let ancestor = path.last, ancestor.depth >= row.depth { path.removeLast() }
                guard doneIDs.contains(row.id) else { continue }
                let doneDepth = path.last.map { $0.doneDepth + 1 } ?? 0
                path.append((row.depth, doneDepth))
                guard drawn.insert(row.id).inserted else { continue }
                row.depth = doneDepth
                row.isCollapsed = false
                doneRows.append(row)
            }
        }
        return TodayAgendaRows(overdue: overdueRows, due: dueRows, planned: plannedRows,
                               starred: starredRows, doneToday: doneRows)
    }
}
