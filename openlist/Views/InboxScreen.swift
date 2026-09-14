import SwiftData
import SwiftUI

/// A curated queue of task identities plus the retained rich capture document.
struct InboxScreen: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.undoManager) private var undoManager
    @Query private var blocks: [Block]
    @Query private var lists: [TaskList]
    @Query private var labels: [TaskLabel]
    @State private var selectionGroupID = UUID()

    var body: some View {
        @Bindable var navigator = env.navigator
        if let inbox = env.store.inboxList() {
            let live = blocks.filter { $0.modelContext != nil && !$0.isDeleted }
            let policy = InboxPolicy(lists: lists)
            let members = policy.ordered(live, showsCompleted: inbox.showsCompleted(default: env.settings.showsCompletedTasks))
            let context = TaskRowContext(tasks: live, lists: lists, labels: labels)
            ScreenScaffold {
                ScreenHeader(icon: "tray", title: "Inbox")
                Picker("Inbox view", selection: $navigator.showsUnfiledInbox) {
                    Text("Selected").tag(false).help("Selected tasks stay in their original lists")
                    Text("Unfiled").tag(true).help("Your original capture document, including tasks and notes")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityValue(navigator.showsUnfiledInbox ? "Unfiled content" : "Selected tasks")
                .padding(.top, 12)
            } content: {
                if navigator.showsUnfiledInbox {
                    HStack {
                        CompletedTasksControl(list: inbox)
                        Button(navigator.isReviewingUnfiledInbox ? "Done reviewing" : "Review unfiled") { navigator.isReviewingUnfiledInbox.toggle() }
                    }
                    .padding(.bottom, 12)
                    if navigator.isReviewingUnfiledInbox { InboxReviewView(inbox: inbox) }
                    else {
                        DocumentView(document: .init(listID: inbox.id), emptyPlaceholder: "Capture a task…",
                            showsCompleted: inbox.showsCompleted(default: env.settings.showsCompletedTasks))
                            .id(inbox.id)
                    }
                } else {
                    queueControls(inbox: inbox, count: policy.openCount(live))
                    if let issue = InboxPolicy.issue(in: live) {
                        Label(issue, systemImage: "exclamationmark.triangle")
                            .font(.callout).foregroundStyle(.secondary)
                            .padding(.vertical, 12)
                    }
                    if members.isEmpty {
                        EmptyStateView(icon: "tray", title: "Your Inbox is clear",
                            message: "Add a task, or choose Add to Inbox from any list.")
                    }
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(members) { task in
                            if task.modelContext != nil, !task.isDeleted {
                                queueRow(task, members: members, context: context)
                                    .id(TaskSelectionScrollID.first(task.id))
                            }
                        }
                    }
                    .preference(key: VisibleSelectionIDsKey.self,
                        value: [VisibleSelectionGroup(id: selectionGroupID, blockIDs: members.map(\.id))])
                    .modifier(TaskSelectionScope())
                    .onAppear { env.activeDocument = nil }
                }
            }
        } else { MissingContentView(message: "The Inbox could not be loaded.") }
    }

    private func queueControls(inbox: TaskList, count: Int) -> some View {
        HStack {
            Text("\(count) open").font(Theme.Font.metadata).foregroundStyle(.secondary)
                .help("Drag tasks to reorder this Inbox without changing their lists")
            Spacer()
            Menu("Completed") {
                ForEach(TaskList.CompletedVisibility.allCases) { preference in
                    CheckmarkMenuItem(preference.title, isSelected: inbox.completedVisibility == preference) {
                        env.store.setCompletedVisibility(preference, for: inbox)
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Completed task visibility for Inbox")
            .accessibilityValue(inbox.completedVisibility.title)
        }
        .padding(.bottom, 12)
    }

    private func queueRow(_ task: Block, members: [Block], context: TaskRowContext) -> some View {
        let index = members.firstIndex(where: { $0.id == task.id }) ?? 0
        return HStack(alignment: .top, spacing: 4) {
            SmartTaskRow(block: task, context: context)
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .frame(width: 20, height: 26)
                .draggable(InboxQueueDrag(taskID: task.id, sessionID: env.navigator.blockDragSessionID))
                .help("Reorder this task in Inbox. Its list stays the same.")
                .accessibilityLabel("Reorder \(task.displayTitle) in Inbox")
            Menu {
                InboxMembershipButton(block: task)
                if context.list(for: task)?.isSystemInbox == true {
                    Button("Show unfiled content") { env.navigator.showsUnfiledInbox = true }
                }
                Divider()
                Button("Move earlier in Inbox") {
                    move(task.id, before: members[index - 1].id)
                }.disabled(index == 0)
                Button("Move later in Inbox") {
                    move(task.id, before: index + 2 < members.count ? members[index + 2].id : nil)
                }.disabled(index + 1 >= members.count)
            } label: { Image(systemName: "ellipsis") }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .padding(.top, 9)
            .accessibilityLabel("Inbox actions for \(task.displayTitle)")
        }
        .dropDestination(for: InboxQueueDrag.self) { values, _ in
            guard values.count == 1, let value = values.first,
                  value.sessionID == env.navigator.blockDragSessionID,
                  value.taskID != task.id else { return false }
            return move(value.taskID, before: task.id)
        }
    }

    @discardableResult
    private func move(_ id: UUID, before target: UUID?) -> Bool {
        env.store.moveInboxTask(id, before: target, undoManager: undoManager ?? NSApp.keyWindow?.undoManager)
    }
}
