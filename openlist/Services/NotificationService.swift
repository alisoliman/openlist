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

    static let calendarRequestPrefix = "openlist.calendar.nudge."
    static let calendarStartCategory = "openlist.calendar.start"
    static let calendarOverrunCategory = "openlist.calendar.overrun"
    static let calendarHeadsUpCategory = "openlist.calendar.heads-up"
    static let calendarStartAction = "openlist.calendar.start-task"
    static let calendarDoneAction = "openlist.calendar.done-task"
    static let calendarKeepGoingAction = "openlist.calendar.keep-going"

    private let center = UNUserNotificationCenter.current()
    private var hasRequestedAuthorization = false
    private var calendarCategoryInstallation: Task<Void, Never>?

    private init() {}

    /// Attaches the delegate that lets reminders show while the app is in front
    /// and makes a click on one open the task.
    @MainActor
    func install(delegate: UNUserNotificationCenterDelegate) {
        center.delegate = delegate
        guard ReviewSession.identifier == nil else { return }
        calendarCategoryInstallation = Task {
            let start = UNNotificationAction(identifier: Self.calendarStartAction, title: "Start", options: [])
            let done = UNNotificationAction(identifier: Self.calendarDoneAction, title: "Done", options: [])
            let keepGoing = UNNotificationAction(identifier: Self.calendarKeepGoingAction, title: "Keep going", options: [])
            let categories: Set<UNNotificationCategory> = [
                UNNotificationCategory(identifier: Self.calendarStartCategory, actions: [start], intentIdentifiers: [], options: []),
                UNNotificationCategory(identifier: Self.calendarOverrunCategory, actions: [done, keepGoing], intentIdentifiers: [], options: []),
                UNNotificationCategory(identifier: Self.calendarHeadsUpCategory, actions: [done], intentIdentifiers: [], options: [])
            ]
            let existing = await center.notificationCategories()
            let unrelated = existing.filter { !Self.isCalendarCategory($0.identifier) }
            center.setNotificationCategories(Set(unrelated).union(categories))
        }
    }

    // MARK: - Authorization

    /// Asks for permission the first time a reminder is actually needed.
    func requestAuthorizationIfNeeded() {
        guard ReviewSession.identifier == nil, !hasRequestedAuthorization else { return }
        hasRequestedAuthorization = true
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// Explicit prompt, used by the Settings screen.
    @discardableResult
    func requestAuthorization() async -> Bool {
        guard ReviewSession.identifier == nil else { return false }
        hasRequestedAuthorization = true
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    // MARK: - Scheduling

    func scheduleReminder(id: UUID, title: String, listName: String, at date: Date) {
        guard ReviewSession.identifier == nil, date > .now else { return }
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
        guard ReviewSession.identifier == nil else { return }
        center.removePendingNotificationRequests(withIdentifiers: [id.uuidString])
        center.removeDeliveredNotifications(withIdentifiers: [id.uuidString])
    }

    func cancelAll() {
        guard ReviewSession.identifier == nil else { return }
        center.removeAllPendingNotificationRequests()
    }

    // MARK: - Quiet calendar nudges

    static func isCalendarCategory(_ identifier: String) -> Bool {
        identifier == calendarStartCategory || identifier == calendarOverrunCategory || identifier == calendarHeadsUpCategory
    }

    /// Reuses the reminder authorization flow, but never retries a denied OS
    /// permission. Called only when a background nudge actually needs delivery.
    func authorizeCalendarNudgeIfNeeded() async -> Bool {
        guard ReviewSession.identifier == nil else { return false }
        switch await authorizationStatus() {
        case .authorized, .provisional: return true
        case .notDetermined:
            guard !hasRequestedAuthorization else { return false }
            return await requestAuthorization()
        default: return false
        }
    }

    /// Removes only calendar nudges. The retained identifier is returned as
    /// present so relaunches do not alert again for an already delivered nudge.
    @discardableResult
    func clearCalendarNudges(except retainedID: String? = nil) async -> Bool {
        guard ReviewSession.identifier == nil else { return false }
        let requests = await center.pendingNotificationRequests()
        let notifications = await center.deliveredNotifications()
        guard !Task.isCancelled else { return false }
        let identifiers = Set(requests.map(\.identifier) + notifications.map { $0.request.identifier })
            .filter { $0.hasPrefix(Self.calendarRequestPrefix) }
        let stale = identifiers.filter { $0 != retainedID }
        center.removePendingNotificationRequests(withIdentifiers: Array(stale))
        center.removeDeliveredNotifications(withIdentifiers: Array(stale))
        return retainedID.map { identifiers.contains($0) } ?? false
    }

    func removeCalendarNudge(identifier: String) {
        guard ReviewSession.identifier == nil, identifier.hasPrefix(Self.calendarRequestPrefix) else { return }
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    func postCalendarNudge(identifier: String, title: String, body: String,
                           category: String, taskID: UUID, occurrenceID: UUID) async -> Bool {
        guard ReviewSession.identifier == nil, !Task.isCancelled else { return false }
        await calendarCategoryInstallation?.value
        guard !Task.isCancelled else { return false }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = category
        content.threadIdentifier = "openlist.calendar"
        content.sound = nil
        content.userInfo = ["blockID": taskID.uuidString, "occurrenceID": occurrenceID.uuidString]
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        do {
            try await center.add(request)
            return true
        } catch { return false }
    }

}
