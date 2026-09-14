//
//  TasksScreen.swift
//  openlist
//

import SwiftData
import SwiftUI

/// Every task across active lists, with transient filtering, sorting and grouping.
struct TasksScreen: View {
    @Environment(AppEnvironment.self) private var env

    @Query(filter: #Predicate<Block> { $0.trashID == nil && $0.kindRaw == "task" })
    private var tasks: [Block]

    @Query(filter: TaskList.availablePredicate, sort: [SortDescriptor(\TaskList.sortIndex)])
    private var allLists: [TaskList]

    @Query(sort: [SortDescriptor(\TaskLabel.name)])
    private var allLabels: [TaskLabel]

    @State private var options = TasksViewOptions()

    var body: some View {
        let projection = TasksProjection(tasks: tasks, lists: allLists, labels: allLabels, options: options)
        let context = TaskRowContext(tasks: tasks, lists: allLists, labels: allLabels)

        return ScreenScaffold {
            ScreenHeader(
                icon: "checklist",
                title: "Tasks",
                subtitle: "\(projection.uniqueTaskCount) \(projection.uniqueTaskCount == 1 ? "task" : "tasks")"
            )
        } content: {
            TasksViewControls(options: $options, lists: activeLists, onTitleFilterFocus: focusTitleFilter)
                .padding(.bottom, 16)

            if projection.matching.isEmpty {
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "No tasks match",
                    message: options.normalizedTitleQuery.isEmpty
                        ? "Try a different filter, or add a task to an active list."
                        : "No task titles match in the selected status and list. Clear the title filter or reset filters to show open tasks.",
                    actionTitle: options.hasCustomFilters ? "Reset filters" : nil,
                    action: { options.resetFilters() }
                )
            } else {
                ForEach(projection.groups) { group in
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
        .modifier(TaskSelectionScope())
        .onChange(of: activeListIDs) { _, ids in
            if let selectedID = options.listID, !ids.contains(selectedID) { options.listID = nil }
        }
    }

    private var activeLists: [TaskList] {
        let ids = ListHierarchy(allLists).activeIDs
        return allLists.filter { ids.contains($0.id) }
    }
    private var activeListIDs: [UUID] { activeLists.map(\.id) }

    private func focusTitleFilter() {
        // The filter edits screen state, so shortcuts must not act on the row
        // or inspector document that was selected before focus moved here.
        env.navigator.clearSelection()
        env.activeDocument = nil
    }
}

/// Every task carrying one label.
struct LabelScreen: View {
    let label: TaskLabel

    @Environment(AppEnvironment.self) private var env

    @Query(filter: #Predicate<Block> { $0.trashID == nil && $0.kindRaw == "task" })
    private var tasks: [Block]

    @Query(filter: TaskList.availablePredicate, sort: [SortDescriptor(\TaskList.sortIndex)])
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
        .modifier(TaskSelectionScope())
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

    @Query(filter: #Predicate<Block> { $0.trashID == nil && $0.kindRaw == "task" && $0.isCompleted })
    private var tasks: [Block]

    @Query(filter: TaskList.availablePredicate, sort: [SortDescriptor(\TaskList.sortIndex)])
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
        .modifier(TaskSelectionScope())
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
