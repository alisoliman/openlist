//
//  NotificationDelegate.swift
//  openlist
//

import Foundation
import UserNotifications

/// Handles reminders that arrive while the app is running.
///
/// Without a delegate, macOS suppresses a notification whose app is frontmost —
/// so a reminder set for a task you are looking at would never appear — and a
/// click on a delivered one does nothing. This does both jobs: it asks the
/// system to show reminders anyway, and routes a click to the task.
@MainActor
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    /// Called with the tapped task's id, on the main actor.
    var onOpenTask: ((UUID) -> Void)?
    /// Action id, notification identity, task id and occurrence id. The bridge
    /// validates these against the live nudge before performing an action.
    var onCalendarAction: ((String, String, UUID, UUID) -> Void)?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Calendar nudges already have an in-app banner. Keep those quiet when
        // Openlist comes forward during delivery, without changing reminders.
        if NotificationService.isCalendarCategory(notification.request.content.categoryIdentifier) { return [] }
        // A reminder is worth showing even while Openlist is in front — the
        // point is that you were doing something else.
        return [.banner, .sound, .list]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard
            let raw = info["blockID"] as? String,
            let id = UUID(uuidString: raw)
        else { return }
        if NotificationService.isCalendarCategory(response.notification.request.content.categoryIdentifier) {
            guard ReviewSession.identifier == nil,
                  let rawOccurrence = info["occurrenceID"] as? String,
                  let occurrenceID = UUID(uuidString: rawOccurrence) else { return }
            onCalendarAction?(response.actionIdentifier, response.notification.request.identifier, id, occurrenceID)
            return
        }
        onOpenTask?(id)
    }
}
