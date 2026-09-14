import SwiftUI

/// One stable input row; only active constraints need a second line.
struct TasksViewControls: View {
    @Binding var options: TasksViewOptions
    let lists: [TaskList]
    var onTitleFilterFocus: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TaskTitleFilter(query: $options.titleQuery, onFocus: onTitleFilterFocus)
                filterMenu
                Menu {
                    Picker("Group tasks by", selection: $options.grouping) {
                        ForEach(TaskGrouping.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                    Divider()
                    TaskSortMenu(options: $options)
                } label: {
                    Label("View", systemImage: "slider.horizontal.3")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("Task view options")
                .accessibilityValue("Grouped by \(options.grouping.title), \(options.sorting.summary(ascending: options.ascending))")
                .help("Grouping and sorting")
            }

            if options.hasCustomFilters {
                HStack(spacing: 8) {
                    if options.filter != .open {
                        Text(options.filter.title).chipStyle(accent: Theme.accent)
                    }
                    if let list = lists.first(where: { $0.id == options.listID }) {
                        Button("Clear list filter", systemImage: "xmark.circle.fill") { options.listID = nil }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                        Text(list.displayTitle).lineLimit(1).foregroundStyle(Theme.secondaryText)
                    }
                    Spacer(minLength: 0)
                    resetButton
                }
            }
        }
        .font(Theme.Font.metadata)
    }

    private var resetButton: some View {
        Button("Reset filters") { options.resetFilters() }
            .buttonStyle(.borderless)
            .disabled(!options.hasCustomFilters)
            .help("Show open tasks from all active lists and clear the title filter. Keep grouping and sorting.")
            .accessibilityIdentifier("tasks-reset-filters")
    }

    private var filterMenu: some View {
        Menu {
            Picker("Show tasks", selection: $options.filter) {
                ForEach(TaskFilter.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.inline)
            Divider()
            Picker("Filter by list", selection: $options.listID) {
                Text("All active lists").tag(nil as UUID?)
                ForEach(lists) { list in
                    Text(list.displayTitle).tag(Optional(list.id))
                }
            }
        } label: {
            Label("Filter", systemImage: "line.3.horizontal.decrease")
                .foregroundStyle(options.hasCustomFilters ? Theme.accent : Theme.secondaryText)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Filter tasks")
        .accessibilityValue("\(options.filter.title), \(lists.first { $0.id == options.listID }?.displayTitle ?? "All active lists")")
        .help("Filter by status and list")
    }
}
