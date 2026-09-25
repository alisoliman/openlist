//
//  NextSettingsNotifications.swift
//  openlist
//
//  Settings' Notifications group: permission, reminder scheduling and its
//  recovery, and planned-work nudges.
//

import SwiftUI

struct NXNotificationSettings: View {
    @Environment(AppEnvironment.self) private var env
    private var recovery: ReminderRecovery { NotificationService.shared.reminders }

    var body: some View {
        @Bindable var calendar = env.calendar
        let accepted = recovery.statuses.values.filter { $0 == .accepted }.count
        let expired = recovery.statuses.values.filter { $0 == .expired }.count
        NXSettingsGroup(title: "Notifications",
                        footer: "Saved reminder times are kept even when scheduling fails. Expired reminders are never replayed. macOS acceptance does not guarantee visible presentation through Focus or system notification settings.") {
            NXSettingRow(label: "Notifications", hint: recovery.isSimulated ? "Simulated authorization" : recovery.authorization.title) {
                if recovery.authorization == .denied {
                    Button("Open notification settings…", action: openNotificationSettings)
                } else if recovery.authorization == .notDetermined {
                    Button("Allow notifications") { Task { _ = await recovery.requestPermission() } }
                        .disabled(recovery.isRequestingAuthorization)
                }
            }
            if let error = recovery.libraryReadError ?? recovery.authorizationError ?? recovery.recoveryError {
                NXSettingRow(label: "Reminders need attention", hint: error, hintColor: NX.amberText, selectable: true)
            }
            NXSettingRow(label: "Reminders",
                         hint: recovery.isSimulated
                             ? "\(accepted) simulated pending reminders. \(expired) expired. No macOS notifications are scheduled or displayed."
                             : "\(accepted) pending \(accepted == 1 ? "reminder" : "reminders") accepted by macOS. \(expired) expired.") {
                Button(recovery.isRefreshing ? "Checking…" : "Retry future reminders") {
                    env.store.refreshAllReminders()
                    recovery.refresh(retryFailures: true)
                }
                .disabled(recovery.isRefreshing)
            }
            ForEach(recovery.intents.values.filter { recovery.statuses[$0.id]?.needsRecovery == true }
                .sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date }) { intent in
                let status = recovery.statuses[intent.id]
                let failure: String? = if case .failed(let message) = status { message } else { nil }
                let hint = ["\(intent.listName) · \(NXFormat.moment(intent.date))",
                            status.map(recovery.title(for:)), failure].compactMap { $0 }.joined(separator: "\n")
                NXSettingRow(label: intent.title, hint: hint, selectable: true) {
                    if let status { ReminderRecoveryActions(taskID: intent.id, status: status) }
                }
            }
            NXSettingToggle(label: "Notify me about planned work",
                            hint: "While Openlist is in the background. Suggestions stay quiet in the app, and time never starts automatically.",
                            isOn: $calendar.workNotificationsEnabled)
        }
        .task { env.store.refreshAllReminders(); recovery.refresh() }
    }
}
