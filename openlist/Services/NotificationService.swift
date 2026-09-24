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
@MainActor
final class NotificationService {
    static let shared = NotificationService()

    static let calendarRequestPrefix = "openlist.calendar.nudge."
    static let calendarStartCategory = "openlist.calendar.start"
    static let calendarOverrunCategory = "openlist.calendar.overrun"
    static let calendarHeadsUpCategory = "openlist.calendar.heads-up"
    static let calendarStartAction = "openlist.calendar.start-task"
    static let calendarDoneAction = "openlist.calendar.done-task"
    static let calendarKeepGoingAction = "openlist.calendar.keep-going"
    static let calendarLaterAction = "openlist.calendar.later"
    static let calendarOpenPlanAction = "openlist.calendar.open-plan"

    private lazy var center = UNUserNotificationCenter.current()
    lazy var reminders: ReminderRecovery = {
        if ReviewSession.identifier != nil {
            if Bundle.main.object(forInfoDictionaryKey: "OpenlistReviewReminderSimulation") as? Bool == true {
                return ReminderRecovery(client: ReviewReminderClient(defaults: ReviewSession.defaults), isSimulated: true)
            }
            return ReminderRecovery(client: SystemReminderNotificationClient(center: nil, isEnabled: false))
        }
        return ReminderRecovery(client: SystemReminderNotificationClient(center: center, isEnabled: true))
    }()
    private var hasRequestedAuthorization = false
    private var calendarCategoryInstallation: Task<Void, Never>?

    private init() {}

    /// Attaches the delegate that lets reminders show while the app is in front
    /// and makes a click on one open the task.
    @MainActor
    func install(delegate: UNUserNotificationCenterDelegate) {
        guard ReviewSession.identifier == nil else { return }
        center.delegate = delegate
        calendarCategoryInstallation = Task {
            let start = UNNotificationAction(identifier: Self.calendarStartAction, title: "Start working", options: [.foreground])
            let done = UNNotificationAction(identifier: Self.calendarDoneAction, title: "Complete task", options: [])
            let keepGoing = UNNotificationAction(identifier: Self.calendarKeepGoingAction, title: "Review more time", options: [.foreground])
            let later = UNNotificationAction(identifier: Self.calendarLaterAction, title: "Remind in 15 minutes", options: [])
            let openPlan = UNNotificationAction(identifier: Self.calendarOpenPlanAction, title: "Open plan", options: [.foreground])
            let categories: Set<UNNotificationCategory> = [
                UNNotificationCategory(identifier: Self.calendarStartCategory, actions: [start, later, openPlan], intentIdentifiers: [], options: []),
                UNNotificationCategory(identifier: Self.calendarOverrunCategory, actions: [done, keepGoing], intentIdentifiers: [], options: []),
                UNNotificationCategory(identifier: Self.calendarHeadsUpCategory, actions: [done], intentIdentifiers: [], options: [])
            ]
            let existing = await center.notificationCategories()
            let unrelated = existing.filter { !Self.isCalendarCategory($0.identifier) }
            center.setNotificationCategories(Set(unrelated).union(categories))
        }
    }

    // MARK: - Authorization

    func authorizationStatus() async -> UNAuthorizationStatus {
        guard ReviewSession.identifier == nil else { return .notDetermined }
        return await center.notificationSettings().authorizationStatus
    }

    /// Explicit prompt, used by the Settings screen.
    @discardableResult
    func requestAuthorization() async -> Bool {
        guard ReviewSession.identifier == nil else { return false }
        hasRequestedAuthorization = true
        return await reminders.requestPermission()
    }

    // MARK: - Scheduling

    func reconcileReminders(_ intents: [ReminderIntent]) { reminders.reconcile(intents) }

    func reminderReadFailed(_ message: String) { reminders.recordReadFailure(message) }

    /// Fresh-process selection boundary, before any publisher is constructed.
    /// OS removals have no completion callback; the saved-state reconciliation
    /// after bootstrap verifies inventory. Review sessions never touch the OS.
    func beginLibraryRestoreAtStartup() {
        reminders.resetForLibraryRestore()
        if ReviewSession.identifier == nil {
            center.removeAllPendingNotificationRequests()
            center.removeAllDeliveredNotifications()
        }
    }

    /// In-process callers must additionally drain any old serialized add before
    /// publishing a replacement library. Startup has no previous-process tasks.
    func resetForLibraryRestore() async {
        beginLibraryRestoreAtStartup()
        await reminders.waitUntilIdle()
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
