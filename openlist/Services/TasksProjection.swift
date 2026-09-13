import Foundation

/// Reads live models once per render. Sorting happens before grouping so every
/// group, including Completed and No date, follows the same selected order.
struct TasksProjection {
    let matching: [Block]
    let groups: [TasksGroup]

    /// Label grouping may show a task more than once; the page count never does.
    var uniqueTaskCount: Int { Set(matching.map(\.id)).count }

    init(
        tasks: [Block],
        lists: [TaskList],
        labels: [TaskLabel],
        options: TasksViewOptions,
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        let query = options.normalizedTitleQuery
        let filtered = ActiveTaskPolicy(lists: lists).tasks(in: tasks).filter { task in
            if let listID = options.listID, task.listID != listID { return false }
            guard options.filter.includes(task) else { return false }
            return query.isEmpty || task.displayTitle.localizedStandardContains(query)
        }
        matching = options.sorting.sorted(filtered, ascending: options.ascending)
        groups = Self.groups(
            for: matching, lists: lists, labels: labels,
            grouping: options.grouping, now: now, calendar: calendar
        )
    }

    private static func groups(
        for tasks: [Block], lists: [TaskList], labels: [TaskLabel],
        grouping: TaskGrouping, now: Date, calendar: Calendar
    ) -> [TasksGroup] {
        switch grouping {
        case .none:
            return tasks.isEmpty ? [] : [TasksGroup(id: "all", title: "All", symbol: nil, accent: .graphite, tasks: tasks)]
        case .dueDate:
            return dueDateGroups(tasks, now: now, calendar: calendar)
        case .list:
            let byList = Dictionary(grouping: tasks, by: \.listID)
            return lists.compactMap { list in
                guard let members = byList[list.id], !members.isEmpty else { return nil }
                return TasksGroup(
                    id: "list-\(list.id)", title: "\(list.icon)  \(list.displayTitle)",
                    symbol: nil, accent: list.accent, tasks: members
                )
            }
        case .label:
            let knownLabels = Set(labels.map(\.id))
            var byLabel: [UUID: [Block]] = [:]
            var unlabelled: [Block] = []
            for task in tasks {
                let visibleLabels = Set(task.labelIDs).intersection(knownLabels)
                if visibleLabels.isEmpty {
                    unlabelled.append(task)
                } else {
                    for labelID in visibleLabels { byLabel[labelID, default: []].append(task) }
                }
            }
            var result: [TasksGroup] = labels.compactMap { label in
                guard let members = byLabel[label.id], !members.isEmpty else { return nil }
                return TasksGroup(
                    id: "label-\(label.id)", title: label.name, symbol: "tag.fill", accent: label.accent, tasks: members
                )
            }
            if !unlabelled.isEmpty {
                result.append(TasksGroup(id: "label-none", title: "No label", symbol: nil, accent: .graphite, tasks: unlabelled))
            }
            return result
        case .priority:
            return TaskPriority.allCases.reversed().compactMap { priority in
                let members = tasks.filter { $0.priority == priority }
                guard !members.isEmpty else { return nil }
                let accent: ListAccent = switch priority {
                case .high: .red
                case .medium: .orange
                case .low: .blue
                case .none: .graphite
                }
                return TasksGroup(
                    id: "priority-\(priority.rawValue)", title: priority.title,
                    symbol: priority == .none ? nil : "flag.fill", accent: accent, tasks: members
                )
            }
        }
    }

    private static func dueDateGroups(_ tasks: [Block], now: Date, calendar: Calendar) -> [TasksGroup] {
        let today = calendar.startOfDay(for: now)
        guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: today) else { return [] }
        var buckets: [String: [Block]] = [:]
        for task in tasks {
            let key: String
            if task.isCompleted {
                key = "done"
            } else if let due = task.dueDate {
                if due < (task.includesTime ? now : today) { key = "overdue" }
                else if calendar.isDate(due, inSameDayAs: now) { key = "today" }
                else if due < weekEnd { key = "week" }
                else { key = "later" }
            } else {
                key = "nodate"
            }
            buckets[key, default: []].append(task)
        }
        let headings: [(String, String, String?, ListAccent)] = [
            ("overdue", "Overdue", "exclamationmark.circle.fill", .red),
            ("today", "Today", "sun.max.fill", .violet),
            ("week", "Next 7 days", "calendar", .blue),
            ("later", "Later", "calendar.badge.clock", .teal),
            ("nodate", "No date", nil, .graphite),
            ("done", "Completed", "checkmark.circle.fill", .green)
        ]
        return headings.compactMap { id, title, symbol, accent in
            guard let members = buckets[id] else { return nil }
            return TasksGroup(id: id, title: title, symbol: symbol, accent: accent, tasks: members)
        }
    }
}
