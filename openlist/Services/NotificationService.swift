//
//  NotificationService.swift
//  openlist
//

import Foundation
import UserNotifications

/// Schedules local reminders for tasks that carry a time.
///
/// Requests are keyed by the task's id so rescheduling is idempotent: a task
/// that moves date simply replaces its own pending request.
final class NotificationService: @unchecked Sendable {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()
    private var hasRequestedAuthorization = false

    private init() {}

    /// Attaches the delegate that lets reminders show while the app is in front
    /// and makes a click on one open the task.
    @MainActor
    func install(delegate: UNUserNotificationCenterDelegate) {
        center.delegate = delegate
    }

    // MARK: - Authorization

    /// Asks for permission the first time a reminder is actually needed.
    func requestAuthorizationIfNeeded() {
        guard !hasRequestedAuthorization else { return }
        hasRequestedAuthorization = true
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// Explicit prompt, used by the Settings screen.
    @discardableResult
    func requestAuthorization() async -> Bool {
        hasRequestedAuthorization = true
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    // MARK: - Scheduling

    func scheduleReminder(id: UUID, title: String, listName: String, at date: Date) {
        guard date > .now else { return }
        requestAuthorizationIfNeeded()

        let content = UNMutableNotificationContent()
        content.title = title.isEmpty ? "Reminder" : title
        content.body = listName.isEmpty ? "Due now" : "Due now in \(listName)"
        content.sound = .default
        content.userInfo = ["blockID": id.uuidString]

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: id.uuidString, content: content, trigger: trigger)

        center.add(request) { _ in }
    }

    func cancelReminder(for id: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [id.uuidString])
        center.removeDeliveredNotifications(withIdentifiers: [id.uuidString])
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }
}
