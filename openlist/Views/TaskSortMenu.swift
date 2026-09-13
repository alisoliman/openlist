import SwiftUI

struct TaskSortMenu: View {
    @Binding var options: TasksViewOptions

    var body: some View {
        Menu {
            Picker("Sort tasks by", selection: $options.sorting) {
                ForEach(TaskSorting.allCases) { sorting in
                    Text(sorting.title).tag(sorting)
                }
            }
            .pickerStyle(.inline)

            Divider()
            Picker("Order", selection: $options.ascending) {
                Text(options.sorting.directionTitle(ascending: true)).tag(true)
                Text(options.sorting.directionTitle(ascending: false)).tag(false)
            }
            .pickerStyle(.inline)

            Divider()
            Button("Reset sort") { options.resetSorting() }
                .disabled(!options.hasCustomSorting)
        } label: {
            Label(options.sorting.summary(ascending: options.ascending), systemImage: "arrow.up.arrow.down")
                .font(.callout)
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Sort tasks")
        .accessibilityValue(options.sorting.summary(ascending: options.ascending))
        .accessibilityHint("Orders tasks within each group. Undated tasks stay last when sorting by due date.")
        .accessibilityIdentifier("tasks-sort-menu")
        .help("Sort within each group. Due date keeps undated tasks last in either direction.")
    }
}
