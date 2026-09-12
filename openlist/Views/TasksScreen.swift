//
//  TasksScreen.swift
//  openlist
//

import SwiftData
import SwiftUI

/// Every task across every list, with filtering and grouping.
struct TasksScreen: View {
    @Environment(AppEnvironment.self) private var env

    @Query(filter: #Predicate<Block> { $0.kindRaw == "task" })
    private var tasks: [Block]

    @Query(filter: #Predicate<TaskList> { $0.mergedIntoID == nil }, sort: [SortDescriptor(\TaskList.sortIndex)])
    private var allLists: [TaskList]

    @Query(sort: [SortDescriptor(\TaskLabel.name)])
    private var allLabels: [TaskLabel]

    @State private var filter: TaskFilter = .open
    @State private var grouping: TaskGrouping = .dueDate
    @State private var listFilter: UUID?

    enum TaskFilter: String, CaseIterable, Identifiable {
        case open, completed, all, starred, scheduled, unscheduled
        var id: String { rawValue }
        var title: String {
            switch self {
            case .open: "Open"
            case .completed: "Completed"
            case .all: "All"
            case .starred: "Starred"
            case .scheduled: "Scheduled"
            case .unscheduled: "No date"
            }
        }
    }

    enum TaskGrouping: String, CaseIterable, Identifiable {
        case dueDate, list, label, priority, none
        var id: String { rawValue }
        var title: String {
            switch self {
            case .dueDate: "Due date"
            case .list: "List"
            case .label: "Label"
            case .priority: "Priority"
            case .none: "Flat"
            }
        }
    }

    var body: some View {
        // One filter pass and one lookup build per render, shared by every
        // group and row below.
        let matching = filtered
        let context = TaskRowContext(tasks: tasks, lists: allLists, labels: allLabels)

        return ScreenScaffold {
            ScreenHeader(
                icon: "checklist",
                title: "Tasks",
                subtitle: "\(matching.count) \(matching.count == 1 ? "task" : "tasks")"
            ) {
                controls
            }
        } content: {
            activeConstraints
                .padding(.bottom, 12)

            if matching.isEmpty {
                EmptyStateView(
                    icon: "tray",
                    title: "No tasks match",
                    message: "Try a different filter, or add a task to an active list.",
                    actionTitle: hasCustomFilters ? "Reset filters" : nil,
                    action: { resetFilters() }
                )
            } else {
                ForEach(groups(for: matching)) { group in
                    TaskGroupSection(
                        title: group.title,
                        symbol: group.symbol,
                        accent: group.accent,
                        tasks: group.tasks,
                        context: context
                    )
                }
            }
        }
        .onChange(of: activeListIDs) { _, ids in
            if let selectedID = listFilter, !ids.contains(selectedID) { listFilter = nil }
        }
    }

    private var activeLists: [TaskList] { allLists.filter { !$0.isArchived } }
    private var activeListIDs: [UUID] { activeLists.map(\.id) }
    private var hasCustomFilters: Bool { filter != .open || listFilter != nil }

    private func resetFilters() {
        filter = .open
        listFilter = nil
    }

    /// Keep the constraints visible even when they produce an empty result.
    private var activeConstraints: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { constraintLabels }
            VStack(alignment: .leading, spacing: 6) { constraintLabels }
        }
        .font(Theme.Font.metadata)
    }

    @ViewBuilder
    private var constraintLabels: some View {
        HStack(spacing: 6) {
            Text(filter.title).chipStyle()
            if let listFilter, let list = allLists.first(where: { $0.id == listFilter }) {
                Text("\(list.icon) \(list.displayTitle)")
                    .lineLimit(1)
                    .chipStyle(accent: list.accent.color)
                    .help(list.displayTitle)
            } else {
                Text("Active lists").foregroundStyle(Theme.secondaryText)
            }
        }
        Text("Grouped by \(grouping.title.lowercased())")
            .foregroundStyle(Theme.secondaryText)
        if hasCustomFilters {
            Button("Reset filters", action: resetFilters)
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
        }
    }

    private var controls: some View {
        HStack(spacing: 4) {
            Menu {
                Section("Show") {
                    ForEach(TaskFilter.allCases) { option in
                        CheckmarkMenuItem(option.title, isSelected: filter == option) { filter = option }
                    }
                }

                Section("Group by") {
                    ForEach(TaskGrouping.allCases) { option in
                        CheckmarkMenuItem(option.title, isSelected: grouping == option) { grouping = option }
                    }
                }

                Section("List") {
                    CheckmarkMenuItem("All active lists", isSelected: listFilter == nil) { listFilter = nil }
                    ForEach(activeLists) { list in
                        CheckmarkMenuItem("\(list.icon)  \(list.displayTitle)", isSelected: listFilter == list.id) {
                            listFilter = list.id
                        }
                    }
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 15))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 26)
            .help("Filter and group")
            .accessibilityLabel("Filter and group tasks")
        }
    }

    // MARK: - Filtering

    private var filtered: [Block] {
        ActiveTaskPolicy(lists: allLists).tasks(in: tasks).filter { task in
            if let listFilter, task.listID != listFilter { return false }
            switch filter {
            case .open: return !task.isCompleted
            case .completed: return task.isCompleted
            case .all: return true
            case .starred: return task.isStarred && !task.isCompleted
            case .scheduled: return task.dueDate != nil && !task.isCompleted
            case .unscheduled: return task.dueDate == nil && !task.isCompleted
            }
        }
    }

    /// Identified by a stable key rather than the visible title: two lists can
    /// legitimately both be called "Untitled list".
    private struct Group: Identifiable {
        var id: String
        var title: String
        var symbol: String?
        var accent: ListAccent
        var tasks: [Block]
    }

    private func groups(for filtered: [Block]) -> [Group] {
        switch grouping {
        case .none:
            return [Group(id: "all", title: "All", symbol: nil, accent: .graphite, tasks: sortedByDate(filtered))]

        case .dueDate:
            return dueDateGroups(filtered)

        case .list:
            let byList = Dictionary(grouping: filtered) { $0.listID }
            return allLists.compactMap { list in
                guard let members = byList[list.id], !members.isEmpty else { return nil }
                return Group(
                    id: "list-\(list.id)",
                    title: "\(list.icon)  \(list.displayTitle)",
                    symbol: nil,
                    accent: list.accent,
                    tasks: sortedByDate(members)
                )
            }

        case .label:
            var byLabel: [UUID: [Block]] = [:]
            var unlabelled: [Block] = []
            for task in filtered {
                if task.labelIDs.isEmpty {
                    unlabelled.append(task)
                } else {
                    for labelID in task.labelIDs { byLabel[labelID, default: []].append(task) }
                }
            }

            var result: [Group] = allLabels.compactMap { label in
                guard let members = byLabel[label.id], !members.isEmpty else { return nil }
                return Group(id: "label-\(label.id)", title: label.name, symbol: "tag.fill", accent: label.accent, tasks: sortedByDate(members))
            }
            if !unlabelled.isEmpty {
                result.append(Group(id: "label-none", title: "No label", symbol: nil, accent: .graphite, tasks: sortedByDate(unlabelled)))
            }
            return result

        case .priority:
            return TaskPriority.allCases.reversed().compactMap { priority in
                let members = filtered.filter { $0.priority == priority }
                guard !members.isEmpty else { return nil }
                let accent: ListAccent = switch priority {
                case .high: .red
                case .medium: .orange
                case .low: .blue
                case .none: .graphite
                }
                return Group(
                    id: "priority-\(priority.rawValue)",
                    title: priority.title,
                    symbol: priority == .none ? nil : "flag.fill",
                    accent: accent,
                    tasks: sortedByDate(members)
                )
            }
        }
    }

    private func dueDateGroups(_ filtered: [Block]) -> [Group] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: today) else { return [] }

        var overdue: [Block] = []
        var todayTasks: [Block] = []
        var thisWeek: [Block] = []
        var later: [Block] = []
        var someday: [Block] = []
        var done: [Block] = []

        for task in filtered {
            if task.isCompleted {
                done.append(task)
                continue
            }
            guard let due = task.dueDate else {
                someday.append(task)
                continue
            }
            if task.isOverdue {
                overdue.append(task)
            } else if calendar.isDateInToday(due) {
                todayTasks.append(task)
            } else if due < weekEnd {
                thisWeek.append(task)
            } else {
                later.append(task)
            }
        }

        var result: [Group] = []
        if !overdue.isEmpty {
            result.append(Group(id: "overdue", title: "Overdue", symbol: "exclamationmark.circle.fill", accent: .red, tasks: sortedByDate(overdue)))
        }
        if !todayTasks.isEmpty {
            result.append(Group(id: "today", title: "Today", symbol: "sun.max.fill", accent: .violet, tasks: sortedByDate(todayTasks)))
        }
        if !thisWeek.isEmpty {
            result.append(Group(id: "week", title: "Next 7 days", symbol: "calendar", accent: .blue, tasks: sortedByDate(thisWeek)))
        }
        if !later.isEmpty {
            result.append(Group(id: "later", title: "Later", symbol: "calendar.badge.clock", accent: .teal, tasks: sortedByDate(later)))
        }
        if !someday.isEmpty {
            result.append(Group(id: "nodate", title: "No date", symbol: nil, accent: .graphite, tasks: someday))
        }
        if !done.isEmpty {
            result.append(Group(id: "done", title: "Completed", symbol: "checkmark.circle.fill", accent: .green, tasks: sortedByCompletion(done)))
        }
        return result
    }

    private func sortedByDate(_ input: [Block]) -> [Block] {
        input.sorted(by: Block.byDueDate)
    }

    private func sortedByCompletion(_ input: [Block]) -> [Block] {
        input.sorted(by: Block.byCompletionDate)
    }
}

/// Every task carrying one label.
struct LabelScreen: View {
    let label: TaskLabel

    @Environment(AppEnvironment.self) private var env

    @Query(filter: #Predicate<Block> { $0.kindRaw == "task" })
    private var tasks: [Block]

    @Query(filter: #Predicate<TaskList> { $0.mergedIntoID == nil }, sort: [SortDescriptor(\TaskList.sortIndex)])
    private var allLists: [TaskList]

    @Query(sort: [SortDescriptor(\TaskLabel.name)])
    private var allLabels: [TaskLabel]

    var body: some View {
        let context = TaskRowContext(tasks: tasks, lists: allLists, labels: allLabels)

        return ScreenScaffold {
            ScreenHeader(
                icon: "tag",
                title: label.name,
                subtitle: "\(open.count) open",
                accent: label.accent
            ) {
                Menu {
                    Section("Colour") {
                        ForEach(ListAccent.allCases) { accent in
                            CheckmarkMenuItem(accent.title, isSelected: label.accent == accent) {
                                env.store.setAccent(accent, for: label)
                            }
                        }
                    }
                    Divider()
                    Button("Delete Label", role: .destructive) {
                        env.navigator.replace(with: .tasks)
                        env.store.deleteLabel(label)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 15))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 26)
                .accessibilityLabel("Options for label \(label.name)")
            }
        } content: {
            if open.isEmpty && done.isEmpty {
                EmptyStateView(
                    icon: "tag",
                    title: "Nothing labelled “\(label.name)”",
                    message: "Type #\(label.name) in a task to tag it."
                )
            } else {
                if !open.isEmpty {
                    TaskGroupSection(title: "Open", accent: label.accent, tasks: open, context: context)
                }
                if !done.isEmpty {
                    TaskGroupSection(
                        title: "Completed",
                        symbol: "checkmark.circle.fill",
                        accent: .green,
                        tasks: done,
                        context: context,
                        isInitiallyExpanded: false
                    )
                }
            }
        }
    }

    private var tagged: [Block] {
        ActiveTaskPolicy(lists: allLists).tasks(in: tasks).filter { $0.labelIDs.contains(label.id) }
    }
    private var open: [Block] { tagged.filter { !$0.isCompleted } }
    private var done: [Block] {
        tagged.filter(\.isCompleted).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }
}

/// An archive of finished work, grouped by the day it was ticked off.
struct CompletedScreen: View {
    @Environment(AppEnvironment.self) private var env

    @Query(filter: #Predicate<Block> { $0.kindRaw == "task" && $0.isCompleted })
    private var tasks: [Block]

    @Query(filter: #Predicate<TaskList> { $0.mergedIntoID == nil }, sort: [SortDescriptor(\TaskList.sortIndex)])
    private var allLists: [TaskList]

    @Query(sort: [SortDescriptor(\TaskLabel.name)])
    private var allLabels: [TaskLabel]

    var body: some View {
        let visibleTasks = ActiveTaskPolicy(lists: allLists).tasks(in: tasks)
        let context = TaskRowContext(tasks: tasks, lists: allLists, labels: allLabels)

        return ScreenScaffold {
            ScreenHeader(
                icon: "checkmark.circle",
                title: "Completed",
                subtitle: "\(visibleTasks.count) finished in active lists"
            )
        } content: {
            if visibleTasks.isEmpty {
                EmptyStateView(
                    icon: "checkmark.circle",
                    title: "Nothing completed yet",
                    message: "Finished tasks collect here."
                )
            } else {
                ForEach(days, id: \.id) { day in
                    TaskGroupSection(
                        title: day.title,
                        symbol: "checkmark.circle.fill",
                        accent: .green,
                        tasks: day.tasks,
                        context: context
                    )
                }
            }
        }
    }

    /// Keyed on the day itself: two groups can share a relative title across a
    /// midnight boundary, which would collide if the title were the identity.
    private struct Day: Identifiable {
        var id: Date
        var title: String
        var tasks: [Block]
    }

    private var days: [Day] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: ActiveTaskPolicy(lists: allLists).tasks(in: tasks)) { task in
            calendar.startOfDay(for: task.completedAt ?? task.updatedAt)
        }
        return grouped.keys.sorted(by: >).map { date in
            Day(
                id: date,
                title: Store.dayHeading(for: date),
                tasks: (grouped[date] ?? []).sorted(by: Block.byCompletionDate)
            )
        }
    }
}
