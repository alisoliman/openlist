//
//  SettingsView.swift
//  openlist
//

import SwiftData
import SwiftUI
import UserNotifications

/// ⌘, — preferences.
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            TasksSettingsTab()
                .tabItem { Label("Tasks", systemImage: "checkmark.circle") }
            LabelsSettingsTab()
                .tabItem { Label("Labels", systemImage: "tag") }
            DataSettingsTab()
                .tabItem { Label("Data", systemImage: "externaldrive") }
        }
        .frame(width: 500, height: 420)
    }
}

struct GeneralSettingsTab: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        @Bindable var settings = env.settings

        Form {
            Section {
                Picker("Appearance", selection: $settings.appearance) {
                    ForEach(AppSettings.Appearance.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Week starts on", selection: $settings.firstWeekday) {
                    Text("System default").tag(0)
                    Text("Sunday").tag(1)
                    Text("Monday").tag(2)
                    Text("Saturday").tag(7)
                }
            }

            Section("Menu bar & capture") {
                Toggle("Show icon in the menu bar", isOn: $settings.showsMenuBarExtra)
                Toggle("Quick add with ⇧⌥Space", isOn: $settings.quickCaptureHotKeyEnabled)
                    .onChange(of: settings.quickCaptureHotKeyEnabled) { _, enabled in
                        if enabled {
                            QuickCaptureHotKey.shared.register()
                        } else {
                            QuickCaptureHotKey.shared.unregister()
                        }
                    }
                Toggle("Show unfinished count on the Dock icon", isOn: $settings.showsDockBadge)
            }

            Section("Feedback") {
                Toggle("Play a sound when completing a task", isOn: $settings.playsCompletionSound)
                Toggle("Confirm before deleting a list", isOn: $settings.confirmsBeforeDeletingLists)
            }
        }
        .formStyle(.grouped)
    }
}

struct TasksSettingsTab: View {
    @Environment(AppEnvironment.self) private var env
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        @Bindable var settings = env.settings

        Form {
            Section {
                Picker("New tasks go to", selection: $settings.defaultDestination) {
                    ForEach(AppSettings.DefaultDestination.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }

                Toggle("Read dates from what you type", isOn: $settings.parsesNaturalLanguageDates)
                Text("Typing “call mum tomorrow at 6pm” sets a due date and trims the phrase from the task.")
                    .font(Theme.Font.metadata)
                    .foregroundStyle(Theme.tertiaryText)
            }

            Section("Completed tasks") {
                Toggle("Show completed tasks in the Inbox and Today", isOn: $settings.showsCompletedTasks)
                Text("Every other list keeps its own setting, under the ⋯ menu in its header.")
                    .font(Theme.Font.metadata)
                    .foregroundStyle(Theme.tertiaryText)
            }

            Section("Reminders") {
                HStack {
                    Text("Notifications")
                    Spacer()
                    Text(statusText)
                        .foregroundStyle(Theme.secondaryText)
                }

                if notificationStatus != .authorized {
                    Button("Allow notifications") {
                        Task {
                            _ = await NotificationService.shared.requestAuthorization()
                            notificationStatus = await NotificationService.shared.authorizationStatus()
                        }
                    }
                }

                Button("Reschedule all reminders") {
                    env.store.refreshAllReminders()
                }
            }
        }
        .formStyle(.grouped)
        .task {
            notificationStatus = await NotificationService.shared.authorizationStatus()
        }
    }

    private var statusText: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: "Enabled"
        case .denied: "Turned off in System Settings"
        default: "Not requested yet"
        }
    }
}

struct LabelsSettingsTab: View {
    @Environment(AppEnvironment.self) private var env

    @Query(sort: [SortDescriptor(\TaskLabel.name)])
    private var labels: [TaskLabel]

    @State private var newLabelName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                TextField("New label name", text: $newLabelName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(create)
                Button("Add", action: create)
                    .disabled(TaskLabel.normalize(newLabelName).isEmpty)
            }
            .padding(14)

            Divider()

            if labels.isEmpty {
                EmptyStateView(
                    icon: "tag",
                    title: "No labels yet",
                    message: "Add one above, or type #something in any task."
                )
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(labels) { label in
                        LabelSettingsRow(label: label)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private func create() {
        guard let label = env.store.findOrCreateLabel(named: newLabelName) else { return }
        _ = label
        env.store.save()
        newLabelName = ""
    }
}

struct LabelSettingsRow: View {
    let label: TaskLabel
    @Environment(AppEnvironment.self) private var env
    @State private var draftName = ""
    @FocusState private var isEditing: Bool

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(ListAccent.allCases) { accent in
                    CheckmarkMenuItem(accent.title, isSelected: label.accent == accent) {
                        env.store.setAccent(accent, for: label)
                    }
                }
            } label: {
                Circle()
                    .fill(label.accent.color)
                    .frame(width: 11, height: 11)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 16)

            TextField("Name", text: $draftName)
                .textFieldStyle(.plain)
                .focused($isEditing)
                .onSubmit(commit)
                .onChange(of: isEditing) { _, editing in
                    if editing { draftName = label.name } else { commit() }
                }

            Spacer()

            Text("\(env.store.blockCount(for: label))")
                .font(Theme.Font.metadata)
                .foregroundStyle(Theme.tertiaryText)
                .monospacedDigit()

            Button {
                env.store.deleteLabel(label)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.tertiaryText)
            }
            .buttonStyle(.plain)
        }
        .onAppear { draftName = label.name }
    }

    private func commit() {
        let trimmed = TaskLabel.normalize(draftName)
        guard !trimmed.isEmpty, trimmed != label.name else {
            draftName = label.name
            return
        }
        env.store.renameLabel(label, to: trimmed)
    }
}

struct DataSettingsTab: View {
    @Environment(AppEnvironment.self) private var env

    @Query private var blocks: [Block]
    @Query private var lists: [TaskList]

    @State private var isConfirmingReset = false

    var body: some View {
        Form {
            Section("Your data") {
                LabeledContent("Lists", value: "\(lists.count)")
                LabeledContent("Tasks", value: "\(blocks.filter(\.isTask).count)")
                LabeledContent("Completed", value: "\(blocks.filter { $0.isTask && $0.isCompleted }.count)")
                LabeledContent("Other blocks", value: "\(blocks.filter { !$0.isTask }.count)")
            }

            Section("Export") {
                Button("Export every list as Markdown…") { exportAll() }
                Text("Writes one .md file per list into a folder you choose.")
                    .font(Theme.Font.metadata)
                    .foregroundStyle(Theme.tertiaryText)
            }

            Section("Activity") {
                Button("Clear the Updates history") {
                    env.store.clearActivity()
                }
            }

            Section {
                Button("Delete everything…", role: .destructive) {
                    isConfirmingReset = true
                }
            } header: {
                Text("Reset")
            } footer: {
                Text("Removes all lists, tasks and labels from this Mac. This cannot be undone.")
                    .font(Theme.Font.metadata)
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
        .formStyle(.grouped)
        .alert("Delete everything?", isPresented: $isConfirmingReset) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { reset() }
        } message: {
            Text("All lists, tasks, notes and labels will be permanently removed.")
        }
    }

    private func exportAll() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        // Two lists can share a title, so names are de-duplicated rather than
        // silently overwriting one another.
        var used: Set<String> = []
        for list in env.store.allLists(includeArchived: true) {
            let markdown = MarkdownExporter.markdown(for: list, store: env.store)
            let base = list.displayTitle.replacingOccurrences(of: "/", with: "-")
            var name = base
            var suffix = 2
            while used.contains(name.lowercased()) {
                name = "\(base) \(suffix)"
                suffix += 1
            }
            used.insert(name.lowercased())
            try? markdown.write(
                to: folder.appendingPathComponent("\(name).md"),
                atomically: true,
                encoding: .utf8
            )
        }
    }

    private func reset() {
        for list in env.store.allLists(includeArchived: true) where !list.isSystemInbox {
            env.store.deleteList(list)
        }
        if let inbox = env.store.inboxList() {
            // Through the store so attachment rows and their files go too.
            for block in env.store.blocks(inList: inbox.id) where block.parentID == nil {
                env.store.deleteBlock(block)
            }
        }
        for label in env.store.allLabels() {
            env.store.context.delete(label)
        }
        env.store.clearActivity()
        NotificationService.shared.cancelAll()
        env.store.save()
        env.navigator.replace(with: .today)
    }
}
