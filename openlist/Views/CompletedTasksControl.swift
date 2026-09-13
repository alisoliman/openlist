import SwiftData
import SwiftUI

/// A visible control for finished work. Completed branches settle below pending
/// siblings without separating a task from its notes or children.
struct CompletedTasksControl: View {
    let list: TaskList

    @Environment(AppEnvironment.self) private var env
    @Query private var completed: [Block]

    init(list: TaskList) {
        self.list = list
        let listID = list.id
        _completed = Query(filter: #Predicate<Block> {
            $0.listID == listID && $0.kindRaw == "task" && $0.isCompleted
        })
    }

    private var showsCompleted: Bool {
        list.showsCompleted(default: env.settings.showsCompletedTasks)
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                env.store.setShowsCompleted(!showsCompleted, for: list)
            } label: {
                HStack(spacing: 6) {
                    if completed.isEmpty {
                        Text("No completed tasks")
                            .foregroundStyle(Theme.secondaryText)
                    } else {
                        Text("Completed (\(completed.count))")
                        Text(showsCompleted ? "Hide" : "Show")
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(completed.isEmpty)
            .accessibilityLabel(completed.isEmpty ? "No completed tasks" : "\(showsCompleted ? "Hide" : "Show") \(completed.count) completed tasks")
            .accessibilityValue(completed.isEmpty ? "" : (showsCompleted ? "Shown in outline" : "Hidden"))
            .help("Completed tasks appear below pending tasks, with their subtasks and notes")

            Spacer(minLength: 4)

            Menu {
                ForEach(TaskList.CompletedVisibility.allCases) { preference in
                    CheckmarkMenuItem(preference.title, isSelected: list.completedVisibility == preference) {
                        env.store.setCompletedVisibility(preference, for: list)
                    }
                }
            } label: {
                Text(list.completedVisibility == .inherit ? "App default" : "This list")
                    .foregroundStyle(Theme.secondaryText)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Completed task visibility for this list")
            .help("Use the app default, or override it for this list")
        }
        .font(Theme.Font.metadata)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.chipFill, in: RoundedRectangle(cornerRadius: 8))
    }
}
