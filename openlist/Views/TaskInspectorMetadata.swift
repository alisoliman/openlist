import SwiftUI

/// Everyday task controls stay together and wrap within the inspector width.
struct TaskInspectorMetadata: View {
    let block: Block
    @Environment(AppEnvironment.self) private var env
    @State private var openPicker: DetailPicker?

    var body: some View {
        MetadataFlowLayout(spacing: 7) {
            Menu {
                ForEach(env.store.allLists()) { list in
                    Button("\(list.icon)  \(list.displayTitle)") {
                        env.store.moveToList(block, list: list)
                    }
                }
            } label: {
                let list = env.store.list(id: block.listID)
                Text("\(list?.icon ?? "") \(list?.displayTitle ?? "None")")
                    .lineLimit(1)
                    .chipStyle(accent: list?.accent.color)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .accessibilityLabel("Move task to list")
            .accessibilityValue(env.store.list(id: block.listID)?.displayTitle ?? "None")

            Button { openPicker = .due } label: {
                if block.dueDate != nil {
                    DueDateChip(block: block)
                } else {
                    Label("Add date", systemImage: "calendar").chipStyle()
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit task schedule")
            .accessibilityValue(block.dueDate.map { Store.absoluteDateText($0, includesTime: block.includesTime) } ?? "No due date")
            .help("Date, time, reminder and repeat (⌃D)")
            .popover(isPresented: scheduleBinding, arrowEdge: .bottom) {
                TaskSchedulePicker(block: block, initialSection: openPicker ?? .due)
                    .environment(env)
            }

            Menu {
                ForEach(TaskPriority.allCases, id: \.self) { priority in
                    CheckmarkMenuItem(priority.title, isSelected: block.priority == priority) {
                        env.store.setPriority(priority, for: block)
                    }
                }
            } label: {
                Label(block.priority == .none ? "Priority" : block.priority.title, systemImage: "flag")
                    .chipStyle(accent: block.priority.accent?.color)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .accessibilityLabel("Task priority")
            .accessibilityValue(block.priority.title)

            Button { openPicker = .labels } label: {
                Label("Labels", systemImage: "tag").chipStyle()
            }
            .buttonStyle(.plain)
            .help("Edit labels (⌃L)")
            .popover(isPresented: labelsBinding, arrowEdge: .bottom) {
                LabelPicker(block: block).environment(env)
            }

            ForEach(env.store.labels(for: block)) { label in
                Button { openPicker = .labels } label: {
                    Text(label.name).lineLimit(1).chipStyle(accent: label.accent.color)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit label \(label.name)")
            }

            if let recurrence = block.recurrence {
                Button { openPicker = .repeatRule } label: {
                    Label(recurrence.displayText, systemImage: "repeat")
                        .lineLimit(1).chipStyle(accent: Theme.accent)
                }
                .buttonStyle(.plain)
                .help(recurrence.displayText)
                .accessibilityLabel("Edit repeat: \(recurrence.displayText)")
            }

            if let reminder = block.reminderAt {
                Button { openPicker = .reminder } label: {
                    Label(reminder.formatted(date: .abbreviated, time: .shortened), systemImage: "bell")
                        .lineLimit(1).chipStyle()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit reminder")
                .accessibilityValue(Store.absoluteDateText(reminder, includesTime: true))
            }

            Button { env.store.toggleStar(block) } label: {
                Image(systemName: block.isStarred ? "star.fill" : "star")
                    .chipStyle(accent: block.isStarred ? ListAccent.amber.color : nil)
            }
            .buttonStyle(.plain)
            .help(block.isStarred ? "Unstar task" : "Star task")
            .accessibilityLabel(block.isStarred ? "Unstar task" : "Star task")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear(perform: adoptRequestedPicker)
        .onChange(of: env.requestedPicker) { _, _ in adoptRequestedPicker() }
    }

    private var scheduleBinding: Binding<Bool> {
        Binding(get: { openPicker != nil && openPicker != .labels }, set: { if !$0 { openPicker = nil } })
    }

    private var labelsBinding: Binding<Bool> {
        Binding(get: { openPicker == .labels }, set: { if !$0 { openPicker = nil } })
    }

    private func adoptRequestedPicker() {
        guard let requested = env.requestedPicker else { return }
        openPicker = requested
        env.requestedPicker = nil
    }
}
