import SwiftData
import SwiftUI

/// Everyday task controls stay together and wrap within the inspector width.
struct TaskInspectorMetadata: View {
    let block: Block
    @Environment(AppEnvironment.self) private var env
    @State private var openPicker: DetailPicker?
    @FocusState private var focusedPicker: DetailPicker?

    var body: some View {
        // SwiftUI may update this child after a saved deletion, before its
        // parent removes it. Never read persisted fields on that old model.
        if block.modelContext != nil, !block.isDeleted { liveContent }
    }

    private var liveContent: some View {
        let labels = env.store.labels(for: block)
        let names = labels.map(\.name).joined(separator: ", ")
        let summary = labels.prefix(2).map(\.name).joined(separator: ", ")
            + (labels.count > 2 ? " +\(labels.count - 2)" : "")

        return MetadataFlowLayout(spacing: 7) {
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
                    .font(Theme.Font.metadata)
                    .foregroundStyle(Theme.secondaryText)
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
            .focused($focusedPicker, equals: .due)
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
                if block.priority == .none {
                    Image(systemName: "flag").chipStyle()
                } else {
                    Label(block.priority.title, systemImage: "flag.fill")
                        .chipStyle(accent: block.priority.accent?.color)
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .accessibilityLabel("Task priority")
            .accessibilityValue(block.priority.title)
            .help("Priority: \(block.priority.title)")

            Button { openPicker = .labels } label: {
                if labels.isEmpty {
                    Image(systemName: "tag").chipStyle()
                } else {
                    Label(summary, systemImage: "tag")
                        .lineLimit(1)
                        .chipStyle(accent: labels.count == 1 ? labels.first?.accent.color : nil)
                }
            }
            .buttonStyle(.plain)
            .focused($focusedPicker, equals: .labels)
            .accessibilityLabel("Edit labels")
            .accessibilityValue(labels.isEmpty ? "No labels" : names)
            .help(labels.isEmpty ? "Add labels (⌃L)" : "\(names) · Edit labels (⌃L)")
            .popover(isPresented: labelsBinding, arrowEdge: .bottom) {
                LabelPicker(block: block).environment(env)
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
        .onChange(of: openPicker) { previous, current in
            // Popovers must return focus to their source, not let AppKit select
            // the first task title in the document behind the inspector.
            if current == nil, let previous {
                focusedPicker = previous == .labels ? .labels : .due
            }
        }
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
