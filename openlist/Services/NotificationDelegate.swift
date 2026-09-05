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

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // A reminder is worth showing even while Openlist is in front — the
        // point is that you were doing something else.
        [.banner, .sound, .list]
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
        onOpenTask?(id)
    }
}
