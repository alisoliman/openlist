import SwiftData
import SwiftUI

/// One list's task queue. Rows mutate their original blocks through the same
/// actions as other smart views; there is no outline drag or insertion target.
struct ListTasksView: View {
    let list: TaskList
    let showsCompleted: Bool

    @State private var selectionGroupID = UUID()
    @Environment(AppEnvironment.self) private var env
    @Query private var blocks: [Block]
    @Query(sort: [SortDescriptor(\TaskLabel.name)]) private var labels: [TaskLabel]

    init(list: TaskList, showsCompleted: Bool) {
        self.list = list
        self.showsCompleted = showsCompleted
        let listID = list.id
        _blocks = Query(filter: #Predicate<Block> { $0.trashID == nil && $0.listID == listID })
    }

    var body: some View {
        let projection = ListTasksProjection(blocks: blocks, listID: list.id, sorting: list.sorting,
                                             showsCompleted: showsCompleted)
        let context = TaskRowContext(tasks: blocks, lists: [list], labels: labels)

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(projection.hiddenContentCount > 0 ? "Notes hidden · Includes subtasks" : "Includes subtasks")
                    .font(Theme.Font.metadata)
                    .foregroundStyle(Theme.secondaryText)
                Spacer(minLength: 4)
                sortMenu
            }

            if projection.tasks.isEmpty {
                EmptyStateView(
                    icon: "checklist",
                    title: projection.completedCount > 0 && !showsCompleted ? "No open tasks" : "No tasks in this list",
                    message: projection.completedCount > 0 && !showsCompleted
                        ? "Show completed tasks above, or add a new task."
                        : "Add a task here, or return to Document to see your notes.",
                    actionTitle: "Add task",
                    action: { env.send(.newTask) }
                )
            } else {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(projection.tasks) { task in
                        SmartTaskRow(block: task, context: context, showsListBadge: false)
                            .id(TaskSelectionScrollID.first(task.id))
                    }
                }
                Button("Add task", systemImage: "plus") { env.send(.newTask) }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 8)
                    .help("New tasks are added at the end of this list's document")
            }
        }
        .preference(key: VisibleSelectionIDsKey.self,
            value: [VisibleSelectionGroup(id: selectionGroupID, blockIDs: projection.tasks.map(\.id))])
        .modifier(TaskSelectionScope())
    }

    private var sortMenu: some View {
        Menu {
            ForEach(ListSorting.allCases, id: \.self) { sorting in
                CheckmarkMenuItem(title(for: sorting), isSelected: list.sorting == sorting) {
                    env.store.setSorting(sorting, for: list)
                }
            }
        } label: {
            Label(title(for: list.sorting), systemImage: "arrow.up.arrow.down")
                .font(Theme.Font.metadata)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Sort tasks in this list")
        .accessibilityValue(title(for: list.sorting))
        .help("Sort every task across this list, including subtasks")
    }

    private func title(for sorting: ListSorting) -> String {
        sorting == .manual ? "Document order" : sorting.title
    }
}
