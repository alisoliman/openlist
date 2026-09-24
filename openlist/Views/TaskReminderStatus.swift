import AppKit
import SwiftData
import SwiftUI

/// Compare the visible model to saved intent before describing OS acceptance.
/// A failed save can leave a newer date/title in the live editor.
struct TaskReminderStatus: View {
    let block: Block
    /// The Next inspector only shows a reminder that needs the user, such as
    /// missing permission or a failed schedule, in its own type and buttons.
    var attentionOnly = false
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
            if attentionOnly {
                // Unsaved changes are left to the app's save notice.
                let status = recovery.statuses[block.id] ?? .checking
                if recovery.libraryReadError != nil || (matchesSaved && status.needsRecovery) {
                    // A read failure keeps the last good snapshot, whose status
                    // would contradict the error beneath it.
                    attentionNotice(status: recovery.libraryReadError == nil ? status : nil, date: date)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    if let error = recovery.libraryReadError {
                        Text(error).textSelection(.enabled)
                        Button("Retry reminder status", action: retryStatus)
                    }
                    if !matchesSaved {
                        Label(recovery.libraryReadError != nil ? "Reminder status unavailable"
                            : !recovery.hasSnapshot ? "Checking saved reminder…" : "Reminder changes are not yet saved",
                            systemImage: "exclamationmark.circle")
                        if let saved {
                            Text("Last saved reminder: \(NXFormat.dueAndClock(saved.date)).")
                        }
                    } else {
                        let status = recovery.statuses[block.id] ?? .checking
                        Label(recovery.title(for: status), systemImage: status.needsRecovery ? "bell.badge" : "bell")
                            .accessibilityValue(date.map { Store.absoluteDateText($0, includesTime: true) } ?? "")
                            .help(date.map { NXFormat.dueAndClock($0) } ?? "Reminder status")
                        if case .failed(let message) = status { Text(message).textSelection(.enabled) }
                        if let error = recovery.authorizationError { Text(error) }
                        ReminderRecoveryActions(taskID: block.id, status: status)
                        if recovery.isSimulated { Text("Review simulation only. No macOS notification is scheduled or displayed.") }
                        if status == .accepted && !recovery.isSimulated {
                            Text("Delivery depends on Focus and system settings.")
                        }
                    }
                }
                .font(.system(size: 11.5))
                .foregroundStyle(NX.ink(0.55))
                .buttonStyle(NXPanelButtonStyle(kind: .secondary, size: .small))
                .fixedSize(horizontal: false, vertical: true)
                .task { recovery.refresh() }
            }
        }
    }

    private func retryStatus() {
        env.store.refreshAllReminders()
        recovery.refresh(retryFailures: true)
    }

    /// `status` is nil when the library couldn't be read to compare against.
    private func attentionNotice(status: ReminderStatus?, date: Date?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "bell.badge").font(.system(size: 10.5, weight: .medium))
                Text(status.map { recovery.title(for: $0) } ?? "Reminder status unavailable")
                    .font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundStyle(NX.amberText)
            .help(date.map { NXFormat.dueAndClock($0) } ?? "Reminder status")
            Group {
                if let error = recovery.libraryReadError { Text(error).textSelection(.enabled) }
                if case .failed(let message) = status { Text(message).textSelection(.enabled) }
                if let error = recovery.authorizationError { Text(error) }
                if recovery.isSimulated { Text("Review simulation only. No macOS notification is scheduled or displayed.") }
            }
            .font(.system(size: 11))
            .foregroundStyle(NX.ink(0.5))
            HStack(spacing: 6) {
                // Retrying the status also retries this task's reminder.
                if recovery.libraryReadError != nil {
                    Button("Retry reminder status", action: retryStatus)
                } else if let status {
                    ReminderRecoveryActions(taskID: block.id, status: status)
                }
            }
            // The inspector's quiet text buttons.
            .buttonStyle(NXPanelButtonStyle(kind: .quiet, size: .small))
            .padding(.leading, -5)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NX.amber.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .task { recovery.refresh() }
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
