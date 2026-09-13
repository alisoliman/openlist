import Foundation

/// Today's membership and section order stay fixed while each section can be
/// sorted independently. This projection only reads models, including positions
/// of prose ancestors needed to place nested tasks in stored document order.
struct TodayTaskBuckets {
    var overdue: [Block] = []
    var dueToday: [Block] = []
    var starred: [Block] = []
    var selected: [Block] = []
    var completedToday: [Block] = []

    init(
        blocks: [Block],
        lists: [TaskList],
        sorting: TodaySorting = .default,
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        let today = calendar.startOfDay(for: now)
        for task in ActiveTaskPolicy(lists: lists).tasks(in: blocks) {
            if task.isCompleted {
                if let completedAt = task.completedAt, calendar.isDate(completedAt, inSameDayAs: now) {
                    completedToday.append(task)
                }
                continue
            }
            if let dueDate = task.dueDate, dueDate < (task.includesTime ? now : today) {
                overdue.append(task)
            } else if let dueDate = task.dueDate, calendar.isDate(dueDate, inSameDayAs: now) {
                dueToday.append(task)
            } else if task.selectedForDay.map({ calendar.startOfDay(for: $0) <= today }) == true {
                selected.append(task)
            } else if task.isStarred {
                starred.append(task)
            }
        }

        // Build the outline once, and only when this ordering needs it.
        let positions = sorting == .listOrder ? Self.documentPositions(blocks: blocks, lists: lists) : [:]
        overdue = Self.sorted(overdue, by: sorting, positions: positions, defaultOrder: Block.byDueDate)
        dueToday = Self.sorted(dueToday, by: sorting, positions: positions, defaultOrder: Self.byTimeThenPriority)
        selected = Self.sorted(selected, by: sorting, positions: positions, defaultOrder: Self.byTimeThenPriority)
        starred = Self.sorted(starred, by: sorting, positions: positions, defaultOrder: Self.byTimeThenPriority)
        completedToday = Self.sorted(completedToday, by: sorting, positions: positions, defaultOrder: Block.byCompletionDate)
    }

    func isEmpty(showsCompleted: Bool) -> Bool {
        overdue.isEmpty && dueToday.isEmpty && starred.isEmpty && selected.isEmpty
            && (!showsCompleted || completedToday.isEmpty)
    }

    private static func sorted(
        _ tasks: [Block],
        by sorting: TodaySorting,
        positions: [UUID: Int],
        defaultOrder: (Block, Block) -> Bool
    ) -> [Block] {
        tasks.sorted { lhs, rhs in
            switch sorting {
            case .default:
                if defaultOrder(lhs, rhs) { return true }
                if defaultOrder(rhs, lhs) { return false }
            case .priority:
                if lhs.priorityRaw != rhs.priorityRaw { return lhs.priorityRaw > rhs.priorityRaw }
            case .dueDate:
                switch (lhs.dueDate, rhs.dueDate) {
                case let (left?, right?) where left != right: return left < right
                case (_?, nil): return true
                case (nil, _?): return false
                default: break
                }
            case .alphabetical:
                let order = lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle)
                if order != .orderedSame { return order == .orderedAscending }
            case .createdAt:
                break // The common tie-breaker is oldest creation first.
            case .listOrder:
                let left = positions[lhs.id] ?? .max
                let right = positions[rhs.id] ?? .max
                if left != right { return left < right }
            }
            // Equal values keep a deterministic order after edits and refetches,
            // even for tasks created at the same instant on different Macs.
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// The existing default: timed tasks first, then priority for untimed work.
    private static func byTimeThenPriority(_ lhs: Block, _ rhs: Block) -> Bool {
        switch (lhs.includesTime, rhs.includesTime) {
        case (true, false): true
        case (false, true): false
        case (true, true): (lhs.dueDate ?? .distantPast) < (rhs.dueDate ?? .distantPast)
        case (false, false): lhs.priorityRaw > rhs.priorityRaw
        }
    }

    private static func documentPositions(blocks: [Block], lists: [TaskList]) -> [UUID: Int] {
        let blocksByList = Dictionary(grouping: blocks, by: \.listID)
        let orderedLists = lists.sorted { lhs, rhs in
            if lhs.sortIndex != rhs.sortIndex { return lhs.sortIndex < rhs.sortIndex }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        var positions: [UUID: Int] = [:]
        for list in orderedLists {
            for row in BlockTree.flatten(blocksByList[list.id] ?? [], respectCollapse: false) {
                positions[row.id] = positions.count
            }
        }
        return positions
    }
}
