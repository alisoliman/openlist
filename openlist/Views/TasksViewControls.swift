import SwiftUI

/// Constraints stay available above results, including when there are none.
struct TasksViewControls: View {
    @Binding var options: TasksViewOptions
    let lists: [TaskList]
    var onTitleFilterFocus: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TaskTitleFilter(query: $options.titleQuery, onFocus: onTitleFilterFocus)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { constraintMenus }
                VStack(alignment: .leading, spacing: 8) { constraintMenus }
            }
            .font(Theme.Font.metadata)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    TaskSortMenu(options: $options)
                    Spacer(minLength: 12)
                    resetButton
                }
                VStack(alignment: .leading, spacing: 8) {
                    TaskSortMenu(options: $options)
                    resetButton
                }
            }
        }
    }

    private var resetButton: some View {
        Button("Reset filters") { options.resetFilters() }
            .buttonStyle(.borderless)
            .disabled(!options.hasCustomFilters)
            .help("Show open tasks from all active lists and clear the title filter. Keep grouping and sorting.")
            .accessibilityIdentifier("tasks-reset-filters")
    }

    @ViewBuilder
    private var constraintMenus: some View {
        Menu {
            Picker("Show tasks", selection: $options.filter) {
                ForEach(TaskFilter.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label(options.filter.title, systemImage: "line.3.horizontal.decrease")
                .chipStyle(accent: options.filter == .open ? nil : Theme.accent)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Show tasks")
        .accessibilityValue(options.filter.title)

        HStack(spacing: 4) {
            Menu {
                Picker("Filter by list", selection: $options.listID) {
                    Text("All active lists").tag(nil as UUID?)
                    ForEach(lists) { list in
                        Text(list.displayTitle).tag(Optional(list.id))
                    }
                }
                .pickerStyle(.inline)
            } label: {
                let list = lists.first { $0.id == options.listID }
                Text(list.map { "\($0.icon) \($0.displayTitle)" } ?? "All active lists")
                    .lineLimit(1)
                    .chipStyle(accent: list?.accent.color)
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Filter by list")
            .accessibilityValue(lists.first { $0.id == options.listID }?.displayTitle ?? "All active lists")
            if options.listID != nil {
                Button("Clear list filter", systemImage: "xmark.circle.fill") { options.listID = nil }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            }
        }

        Menu {
            Picker("Group tasks by", selection: $options.grouping) {
                ForEach(TaskGrouping.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Text("Group: \(options.grouping.title)")
                .chipStyle()
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Group tasks by")
        .accessibilityValue(options.grouping.title)
    }
}
