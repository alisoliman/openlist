import SwiftUI

struct ReminderSettingsSection: View {
    @Environment(AppEnvironment.self) private var env
    private var recovery: ReminderRecovery { NotificationService.shared.reminders }

    var body: some View {
        Section("Reminders") {
            LabeledContent("Notifications", value: recovery.isSimulated ? "Simulated authorization" : recovery.authorization.title)
            if recovery.authorization == .denied {
                Button("Open Notification Settings…", action: openNotificationSettings)
            } else if recovery.authorization == .notDetermined {
                Button("Allow notifications") { Task { _ = await recovery.requestPermission() } }
                    .disabled(recovery.isRequestingAuthorization)
            }
            if let error = recovery.libraryReadError ?? recovery.authorizationError ?? recovery.recoveryError {
                Text(error).foregroundStyle(ListAccent.orange.color).textSelection(.enabled)
            }
            let accepted = recovery.statuses.values.filter { $0 == .accepted }.count
            let expired = recovery.statuses.values.filter { $0 == .expired }.count
            Text(recovery.isSimulated ? "\(accepted) simulated pending reminders. \(expired) expired. No macOS notifications are scheduled or displayed." : "\(accepted) pending \(accepted == 1 ? "reminder" : "reminders") accepted by macOS. \(expired) expired.")
                .font(Theme.Font.metadata)
            Text("Saved reminder times are kept even when scheduling fails. Expired reminders are never replayed. macOS acceptance does not guarantee visible presentation through Focus or system notification settings.")
                .font(Theme.Font.metadata).foregroundStyle(Theme.secondaryText)
            Button(recovery.isRefreshing ? "Checking reminders…" : "Retry future reminders") {
                env.store.refreshAllReminders()
                recovery.refresh(retryFailures: true)
            }
            .disabled(recovery.isRefreshing)
            ForEach(recovery.intents.values.filter { recovery.statuses[$0.id]?.needsRecovery == true }
                .sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date }) { intent in
                VStack(alignment: .leading, spacing: 4) {
                    Text(intent.title).fontWeight(.medium)
                    Text("\(intent.listName) · \(Store.absoluteDateText(intent.date, includesTime: true))")
                    if let status = recovery.statuses[intent.id] {
                        Text(recovery.title(for: status))
                        if case .failed(let message) = status { Text(message).textSelection(.enabled) }
                        ReminderRecoveryActions(taskID: intent.id, status: status)
                    }
                }
                .font(Theme.Font.metadata)
            }
        }
        .task { env.store.refreshAllReminders(); recovery.refresh() }
    }
}
