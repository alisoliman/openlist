//
//  TodayScreen.swift
//  openlist
//

import SwiftData
import SwiftUI

/// Everything due today or already overdue, plus starred work.
struct TodayScreen: View {
    @Environment(AppEnvironment.self) private var env

    @Query private var blocks: [Block]

    @AppStorage(TodaySorting.preferenceKey, store: ReviewSession.defaults)
    private var sorting: TodaySorting = .default

    @Query(filter: TaskList.availablePredicate, sort: [SortDescriptor(\TaskList.sortIndex)])
    private var lists: [TaskList]

    @Query(sort: [SortDescriptor(\TaskLabel.name)])
    private var labels: [TaskLabel]

    /// Seeded from the preference, then overridable per visit with the eye button.
    @State private var showsCompleted: Bool?

    var body: some View {
        // Bucketed once per render; each `body` read of a computed property
        // would otherwise re-scan every task.
        let buckets = TodayTaskBuckets(blocks: blocks, lists: lists, sorting: sorting)
        let context = TaskRowContext(tasks: blocks.filter(\.isTask), lists: lists, labels: labels)

        return ScreenScaffold {
            ScreenHeader(
                icon: "sun.max",
                title: "Today",
                subtitle: Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))
            ) {
                HStack(spacing: 12) {
                    TodaySortMenu(selection: $sorting)
                    Button {
                        showsCompleted = !showsCompletedNow
                    } label: {
                        Image(systemName: showsCompletedNow ? "eye" : "eye.slash")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(QuietButtonStyle())
                    .help(showsCompletedNow ? "Hide completed" : "Show completed")
                    .accessibilityLabel(showsCompletedNow ? "Hide completed tasks" : "Show completed tasks")
                }
            }
        } content: {
            if buckets.isEmpty(showsCompleted: showsCompletedNow) {
                EmptyStateView(
                    icon: "checkmark.circle",
                    title: "Nothing due today",
                    message: "Due, planned, and starred tasks appear here.",
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
        .modifier(TaskSelectionScope())
    }

    private var showsCompletedNow: Bool {
        showsCompleted ?? env.settings.showsCompletedTasks
    }
}
