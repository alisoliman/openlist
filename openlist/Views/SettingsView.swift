//
//  SettingsView.swift
//  openlist
//

import AppKit
import SwiftData
import SwiftUI
import UserNotifications

/// ⌘, — preferences.
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettingsTab() }
            Tab("Tasks", systemImage: "checkmark.circle") { TasksSettingsTab() }
            Tab("Calendar", systemImage: "calendar") { CalendarSettingsView() }
            Tab("Labels", systemImage: "tag") { LabelsSettingsTab() }
            Tab("iCloud", systemImage: "icloud") { ICloudSettingsTab() }
            Tab("AI Agents", systemImage: "terminal") { MCPSettingsTab() }
            Tab("Data", systemImage: "externaldrive") { DataSettingsTab() }
        }
        .frame(minWidth: 580, idealWidth: 640, maxWidth: .infinity,
               minHeight: 500, idealHeight: 580, maxHeight: .infinity)
    }
}

struct ICloudSettingsTab: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Form {
            Section("Sync with iCloud") {
                Label(env.sync.state.title, systemImage: env.sync.state.isEnabled ? "icloud" : "icloud.slash")
                    .font(.headline)
                Text(env.sync.state.detail)
                    .font(Theme.Font.metadata)
                    .foregroundStyle(Theme.secondaryText)

                if let date = env.sync.state.lastUpload {
                    LabeledContent("Last upload", value: date.formatted(date: .abbreviated, time: .shortened))
                }
                if let date = env.sync.state.lastDownload {
                    LabeledContent("Last download", value: date.formatted(date: .abbreviated, time: .shortened))
                }

                Button("Check iCloud status") {
                    env.store.prepareForSync()
                    env.sync.checkAccount()
                    NSApplication.shared.registerForRemoteNotifications()
                }
                .disabled(!env.sync.state.isEnabled)
            }
            if let error = env.store.syncPreparationError {
                Section("Files need attention") {
                    Text(error).font(Theme.Font.metadata)
                }
            }
            if let error = env.sync.pushRegistrationError {
                Section("Background updates") {
                    Text(error).font(Theme.Font.metadata)
                }
            }
            DisclosureGroup("How iCloud sync works") {
                Text("Use the same Apple Account on each Mac. Transfers run automatically on Apple's schedule, not immediately. Deletions sync too.")
                Text("macOS can postpone background transfers on low battery, even while charging. Keep this Mac connected to power until its battery recovers if the initial sync is waiting.")
                Text("Appearance, shortcuts and other app preferences stay on each Mac. Attachments are imported copies; reattach a file to sync edits made in another app.")
            }
            .font(Theme.Font.metadata)
            .foregroundStyle(Theme.secondaryText)
        }
        .formStyle(.grouped)
        .task { env.sync.checkAccount() }
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

            Section("Confirmations") {
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
                Toggle("Show completed tasks by default", isOn: $settings.showsCompletedTasks)
                Text("Applies to lists, Inbox and Today. Use the Completed control in any list to choose Show, Hide or Use app default. Preferences stay on this Mac; list overrides sync with iCloud.")
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

                if notificationStatus == .denied {
                    Button("Open Notification Settings…") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Text("Select Openlist in System Settings, then turn on Allow Notifications.")
                        .font(Theme.Font.metadata)
                        .foregroundStyle(Theme.secondaryText)
                } else if notificationStatus == .notDetermined {
                    Button("Allow notifications") {
                        Task {
                            _ = await NotificationService.shared.requestAuthorization()
                            await refreshNotificationStatus()
                        }
                    }
                }

                DisclosureGroup("Troubleshooting") {
                    Button("Reschedule all reminders") {
                        env.store.refreshAllReminders()
                    }
                    Text("Rebuilds pending notifications from your current task reminders.")
                        .font(Theme.Font.metadata)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .formStyle(.grouped)
        .task { await refreshNotificationStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refreshNotificationStatus() }
        }
    }

    private func refreshNotificationStatus() async {
        let previous = notificationStatus
        notificationStatus = await NotificationService.shared.authorizationStatus()
        if notificationStatus != previous,
           [.authorized, .provisional].contains(notificationStatus) {
            env.store.refreshAllReminders()
        }
    }

    private var statusText: String {
        switch notificationStatus {
        case .authorized, .provisional: "Enabled"
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
    @State private var nameDraft = SyncedTextDraft()
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
            .accessibilityLabel("Color for label \(label.name)")
            .accessibilityValue(label.accent.title)
            .help("Change color for \(label.name)")

            TextField("Name", text: $nameDraft.value)
                .textFieldStyle(.plain)
                .focused($isEditing)
                .accessibilityLabel("Label name")
                .onSubmit(commit)
                .onChange(of: isEditing) { _, editing in
                    if editing {
                        nameDraft.reset(to: label.name)
                    } else {
                        commit()
                    }
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
            .accessibilityLabel("Delete label \(label.name)")
            .help("Delete label \(label.name)")
        }
        .onAppear {
            nameDraft.reset(to: label.name)
        }
        .onChange(of: label.name) { _, name in
            nameDraft.receive(name)
        }
    }

    private func commit() {
        guard !label.isDeleted, label.modelContext != nil else { return }
        guard let trimmed = nameDraft.editedValue(normalize: TaskLabel.normalize),
              !trimmed.isEmpty, trimmed != label.name else {
            nameDraft.reset(to: label.name)
            return
        }
        env.store.renameLabel(label, to: trimmed)
        nameDraft.reset(to: label.name)
    }
}

struct DataSettingsTab: View {
    @Environment(AppEnvironment.self) private var env

    @Query private var blocks: [Block]
    @Query(filter: #Predicate<TaskList> { $0.mergedIntoID == nil }) private var lists: [TaskList]

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
                Text("Writes one Markdown file per list, with images and attachments in sibling assets folders. Existing files are kept.")
                    .font(Theme.Font.metadata)
                    .foregroundStyle(Theme.tertiaryText)
            }

            Section("Activity") {
                Button("Clear the Updates history") {
                    env.store.clearActivity()
                }
                Text("Clears history on this Mac and, when connected, in iCloud.")
                    .font(Theme.Font.metadata)
                    .foregroundStyle(Theme.tertiaryText)
            }

            Section {
                Button("Delete everything…", role: .destructive) {
                    isConfirmingReset = true
                }
            } header: {
                Text("Reset")
            } footer: {
                Text("Removes all lists, tasks and labels. With iCloud enabled, this also deletes them on your other Macs. This cannot be undone.")
                    .font(Theme.Font.metadata)
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
        .formStyle(.grouped)
        .alert("Delete everything?", isPresented: $isConfirmingReset) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { reset() }
        } message: {
            Text("All lists, tasks, notes and labels will be permanently removed. These deletions also sync to iCloud and your other Macs when connected.")
        }
    }

    private func exportAll() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        var exported = 0
        do {
            for list in env.store.allLists(includeArchived: true) {
                let filename = MarkdownExportPackage.safeFilename(list.displayTitle) + ".md"
                let destination = MarkdownExportPackage.availableURL(in: folder, filename: filename)
                try MarkdownExporter.write(list: list, store: env.store, to: destination)
                exported += 1
            }
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Export stopped"
            alert.informativeText = "\(exported) list(s) were exported. The remaining lists were not exported.\n\n\(error.localizedDescription)"
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private func reset() {
        env.store.clearCalendarHistory()
        for list in env.store.allLists(includeArchived: true) where !list.isSystemInbox {
            env.store.deleteList(list)
        }
        if let inbox = env.store.inboxList() {
            // Through the store so attachment rows and their files go too.
            env.store.deleteBlocks(env.store.blocks(inList: inbox.id))
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
