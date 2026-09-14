import AppKit
import SwiftData
import SwiftUI

/// Compare the visible model to saved intent before describing OS acceptance.
/// A failed save can leave a newer date/title in the live editor.
struct TaskReminderStatus: View {
    let block: Block
    @Environment(AppEnvironment.self) private var env
    private var recovery: ReminderRecovery { NotificationService.shared.reminders }

    var body: some View {
        if block.modelContext != nil, !block.isDeleted,
           block.reminderAt != nil || (block.includesTime && block.dueDate != nil) || recovery.intents[block.id] != nil {
            let saved = recovery.intents[block.id]
            let date = block.reminderAt ?? (block.includesTime ? block.dueDate : nil)
            let list = env.store.list(id: block.listID)
            let inactiveReason: String? = block.isCompleted ? "task completed"
                : list == nil ? "list unavailable" : list?.isEffectivelyArchived == true ? "list archived" : nil
            let matchesSaved = saved?.date == date && saved?.title == block.displayTitle
                && saved?.listName == list?.displayTitle && saved?.occurrenceID == block.occurrenceID
                && saved?.inactiveReason == inactiveReason
            VStack(alignment: .leading, spacing: 6) {
                if let error = recovery.libraryReadError {
                    Text(error).textSelection(.enabled)
                    Button("Retry reminder status") {
                        env.store.refreshAllReminders()
                        recovery.refresh(retryFailures: true)
                    }
                }
                if !matchesSaved {
                    Label(recovery.libraryReadError != nil ? "Reminder status unavailable"
                        : !recovery.hasSnapshot ? "Checking saved reminder…" : "Reminder changes are not yet saved",
                        systemImage: "exclamationmark.circle")
                    if let saved {
                        Text("Last saved reminder: \(Store.absoluteDateText(saved.date, includesTime: true)).")
                    }
                } else {
                    let status = recovery.statuses[block.id] ?? .checking
                    Label(recovery.title(for: status), systemImage: status.needsRecovery ? "bell.badge" : "bell")
                    if let date { Text(Store.absoluteDateText(date, includesTime: true)) }
                    if case .failed(let message) = status { Text(message).textSelection(.enabled) }
                    if let error = recovery.authorizationError { Text(error) }
                    ReminderRecoveryActions(taskID: block.id, status: status)
                    if recovery.isSimulated { Text("Review simulation only. No macOS notification is scheduled or displayed.") }
                    if status == .accepted && !recovery.isSimulated {
                        Text("macOS reports a pending request. Focus and system settings can affect when it is shown.")
                    }
                }
            }
            .font(Theme.Font.metadata)
            .foregroundStyle(Theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .task { recovery.refresh() }
        }
    }
}

struct ReminderRecoveryActions: View {
    @Environment(AppEnvironment.self) private var env
    let taskID: UUID
    let status: ReminderStatus
    private var recovery: ReminderRecovery { NotificationService.shared.reminders }

    var body: some View {
        switch status {
        case .permissionNeeded:
            Button("Allow notifications") { Task { _ = await recovery.requestPermission() } }
                .disabled(recovery.isRequestingAuthorization)
        case .denied:
            Button("Open Notification Settings…", action: openNotificationSettings)
        case .failed:
            Button("Retry reminder") { env.store.refreshAllReminders(); recovery.retry(taskID) }
                .accessibilityLabel("Retry reminder for \(recovery.intents[taskID]?.title ?? "task")")
                .disabled(recovery.isRefreshing)
        default: EmptyView()
        }
    }
}

@MainActor
func openNotificationSettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
        NSWorkspace.shared.open(url)
    }
}
