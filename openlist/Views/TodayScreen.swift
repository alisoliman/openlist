//
//  TodayScreen.swift
//  openlist
//

import SwiftData
import SwiftUI

/// Everything due today or already overdue, plus starred work.
struct TodayScreen: View {
    @Environment(AppEnvironment.self) private var env

    @Query(filter: #Predicate<Block> { $0.kindRaw == "task" })
    private var tasks: [Block]

    @Query(filter: #Predicate<TaskList> { $0.mergedIntoID == nil }, sort: [SortDescriptor(\TaskList.sortIndex)])
    private var lists: [TaskList]

    @Query(sort: [SortDescriptor(\TaskLabel.name)])
    private var labels: [TaskLabel]

    /// Seeded from the preference, then overridable per visit with the eye button.
    @State private var showsCompleted: Bool?

    var body: some View {
        // Bucketed once per render; each `body` read of a computed property
        // would otherwise re-scan every task.
        let buckets = Buckets(tasks: ActiveTaskPolicy(lists: lists).tasks(in: tasks))
        let context = TaskRowContext(tasks: tasks, lists: lists, labels: labels)

        return ScreenScaffold {
            ScreenHeader(
                icon: "sun.max",
                title: "Today",
                subtitle: Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))
            ) {
                HStack(spacing: 4) {
                    Button { env.navigator.go(to: .calendar) } label: { Image(systemName: "calendar") }
                        .buttonStyle(.borderless).help("Open adaptive calendar (⌘6)")
                    Button {
                        showsCompleted = !showsCompletedNow
                    } label: {
                        Image(systemName: showsCompletedNow ? "eye" : "eye.slash")
                    }
                    .buttonStyle(.borderless)
                    .help(showsCompletedNow ? "Hide completed" : "Show completed")

                    Button {
                        env.send(.newTask)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("New task (⌘N)")
                }
            }
        } content: {
            if buckets.isEmpty(showsCompleted: showsCompletedNow) {
                EmptyStateView(
                    icon: "checkmark.circle",
                    title: "Nothing due today",
                    message: "Scheduled and starred tasks from active lists land here. Add one, or schedule something from a list.",
                    actionTitle: "Add a task",
                    action: { env.send(.newTask) }
                )
            } else {
                if !buckets.overdue.isEmpty {
                    TaskGroupSection(
                        title: "Overdue",
                        symbol: "exclamationmark.circle.fill",
                        accent: .red,
                        tasks: buckets.overdue,
                        context: context
                    ) {
                        Button("Reschedule all to today") {
                            env.store.batch {
                                for task in buckets.overdue { env.store.setDueToday(task) }
                            }
                        }
                        .buttonStyle(.plain)
                        .font(Theme.Font.metadata)
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                    }
                }

                if !buckets.dueToday.isEmpty {
                    TaskGroupSection(
                        title: "Due today",
                        symbol: "calendar",
                        accent: .violet,
                        tasks: buckets.dueToday,
                        context: context
                    )
                }

                if !buckets.selected.isEmpty {
                    TaskGroupSection(
                        title: "Planned for today",
                        symbol: "calendar.badge.clock",
                        accent: .violet,
                        tasks: buckets.selected,
                        context: context
                    )
                }

                if !buckets.starred.isEmpty {
                    TaskGroupSection(
                        title: "Starred",
                        symbol: "star.fill",
                        accent: .amber,
                        tasks: buckets.starred,
                        context: context
                    )
                }

                if showsCompletedNow, !buckets.completedToday.isEmpty {
                    TaskGroupSection(
                        title: "Completed today",
                        symbol: "checkmark.circle.fill",
                        accent: .green,
                        tasks: buckets.completedToday,
                        context: context
                    )
                }
            }
        }
    }

    private var showsCompletedNow: Bool {
        showsCompleted ?? env.settings.showsCompletedTasks
    }

    /// Today's four groups, filled in one pass.
    private struct Buckets {
        var overdue: [Block] = []
        var dueToday: [Block] = []
        var starred: [Block] = []
        var selected: [Block] = []
        var completedToday: [Block] = []

        func isEmpty(showsCompleted: Bool) -> Bool {
            overdue.isEmpty && dueToday.isEmpty && starred.isEmpty && selected.isEmpty
                && (!showsCompleted || completedToday.isEmpty)
        }

        init(tasks: [Block]) {
            for task in tasks {
                if task.isCompleted {
                    if task.isCompletedToday { completedToday.append(task) }
                    continue
                }
                if task.isOverdue {
                    overdue.append(task)
                } else if task.isDueToday {
                    dueToday.append(task)
                } else if task.selectedForDay.map({ Calendar.current.startOfDay(for: $0) <= Calendar.current.startOfDay(for: .now) }) == true {
                    selected.append(task)
                } else if task.isStarred {
                    starred.append(task)
                }
            }

            overdue.sort(by: Block.byDueDate)
            dueToday.sort(by: Self.byTimeThenPriority)
            selected.sort(by: Self.byTimeThenPriority)
            starred.sort(by: Self.byTimeThenPriority)
            completedToday.sort(by: Block.byCompletionDate)
        }

        /// Timed tasks sort by clock; everything else falls back to priority.
        private static func byTimeThenPriority(_ lhs: Block, _ rhs: Block) -> Bool {
            switch (lhs.includesTime, rhs.includesTime) {
            case (true, false): true
            case (false, true): false
            case (true, true): (lhs.dueDate ?? .distantPast) < (rhs.dueDate ?? .distantPast)
            case (false, false): lhs.priorityRaw > rhs.priorityRaw
            }
        }
    }
}

/// Unfiled captures waiting to be sorted into a list.
struct InboxScreen: View {
    @Environment(AppEnvironment.self) private var env

    @State private var isReviewing = false

    var body: some View {
        if let inbox = env.store.inboxList() {
            ScreenScaffold(headerSpacing: 14) {
                ScreenHeader(
                    icon: "tray",
                    title: "Inbox",
                    subtitle: "Everything you capture without picking a list"
                ) {
                    HStack {
                        Button(isReviewing ? "Done reviewing" : "Review Inbox") { isReviewing.toggle() }
                        Button("New task", systemImage: "plus") { env.send(.newTask) }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .help("New task (⌘N)")
                    }
                }
            } content: {
                if isReviewing {
                    InboxReviewView(inbox: inbox)
                } else {
                    CompletedTasksControl(list: inbox)
                        .padding(.bottom, 12)
                    DocumentView(
                        document: DocumentContext(listID: inbox.id),
                        emptyPlaceholder: "Capture a task…",
                        showsCompleted: inbox.showsCompleted(default: env.settings.showsCompletedTasks)
                    )
                    .id(inbox.id)
                }
            }
        } else {
            MissingContentView(message: "The inbox could not be loaded.")
        }
    }
}
