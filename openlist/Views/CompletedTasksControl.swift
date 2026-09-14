import SwiftData
import SwiftUI

/// A visible control for finished work. Completed branches settle below pending
/// siblings without separating a task from its notes or children.
struct CompletedTasksControl: View {
    let list: TaskList
    var showsAsTaskQueue = false

    @Environment(AppEnvironment.self) private var env
    @Query private var completed: [Block]

    init(list: TaskList, showsAsTaskQueue: Bool = false) {
        self.list = list
        self.showsAsTaskQueue = showsAsTaskQueue
        let listID = list.id
        _completed = Query(filter: #Predicate<Block> {
            $0.trashID == nil && $0.listID == listID && $0.kindRaw == "task" && $0.isCompleted
        })
    }

    private var showsCompleted: Bool {
        list.showsCompleted(default: env.settings.showsCompletedTasks)
    }

    var body: some View {
        if completed.isEmpty {
            visibilityMenu {
                Image(systemName: "checkmark.circle")
                    .font(Theme.Font.metadata)
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 24, height: 24)
            }
            .help("No completed tasks. Choose how finished tasks appear in this list.")
        } else {
            populatedControl
        }
    }

    private var populatedControl: some View {
        HStack(spacing: 4) {
            Button {
                env.store.setShowsCompleted(!showsCompleted, for: list)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showsCompleted ? "checkmark.circle.fill" : "checkmark.circle")
                    Text("\(completed.count) completed")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(QuietButtonStyle())
            .foregroundStyle(Theme.secondaryText)
            .accessibilityLabel("\(showsCompleted ? "Hide" : "Show") \(completed.count) completed tasks")
            .accessibilityValue(showsCompleted ? (showsAsTaskQueue ? "Shown in task queue" : "Shown in outline") : "Hidden")
            .help(showsAsTaskQueue
                ? "Completed tasks follow the same sort order. Subtasks are filtered independently."
                : "Completed tasks appear below pending tasks, with their subtasks and notes")

            visibilityMenu {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 20, height: 24)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .font(Theme.Font.metadata)
    }

    private func visibilityMenu<Label: View>(@ViewBuilder label: () -> Label) -> some View {
        Menu {
            ForEach(TaskList.CompletedVisibility.allCases) { preference in
                CheckmarkMenuItem(preference.title, isSelected: list.completedVisibility == preference) {
                    env.store.setCompletedVisibility(preference, for: list)
                }
            }
        } label: {
            label()
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Completed task visibility for this list")
        .accessibilityValue(list.completedVisibility.title)
        .help("Use the app default, or override it for this list")
    }
}
