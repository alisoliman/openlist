//
//  PhonePlatform.swift
//  OpenlistiOS
//

import UIKit

/// What the environment asks of the running app and the OS, so tests can
/// build a whole `PhoneEnvironment` around an in-memory library without
/// registering for pushes, installing process-wide handlers or borrowing
/// background time.
struct PhonePlatform {
    /// Asks APNs for a token so CloudKit's silent pushes can wake the app.
    var registerForRemoteNotifications: () -> Void
    /// Starts background time to finish a save in; returns its end.
    var beginBackgroundTask: (_ name: String, _ expired: @escaping @MainActor @Sendable () -> Void) -> (() -> Void)
    /// Whether this environment owns the process-wide hooks: the notification
    /// centre's delegate, the widget intents' router and the widget signal.
    /// Only the app's own environment does; a test's never.
    var installsProcessHooks: Bool
    /// Whether the calendar runs its 15-second clock.
    var runsCalendarClock: Bool
    /// Whether the app is in front, for the widget snapshot's reload budget.
    var isAppActive: @MainActor @Sendable () -> Bool

    static var live: PhonePlatform {
        PhonePlatform(
            registerForRemoteNotifications: { UIApplication.shared.registerForRemoteNotifications() },
            beginBackgroundTask: { name, expired in
                let task = BackgroundTask()
                task.identifier = UIApplication.shared.beginBackgroundTask(withName: name) {
                    expired()
                    task.end()
                }
                return { task.end() }
            },
            installsProcessHooks: true,
            runsCalendarClock: true,
            isAppActive: { UIApplication.shared.applicationState == .active })
    }

    /// Nothing reaches the OS: for tests.
    static var inert: PhonePlatform {
        PhonePlatform(registerForRemoteNotifications: {}, beginBackgroundTask: { _, _ in {} },
                      installsProcessHooks: false, runsCalendarClock: false, isAppActive: { true })
    }
}

/// One stretch of background time, ended once whichever comes first, the
/// save finishing or the time running out.
@MainActor
private final class BackgroundTask {
    var identifier = UIBackgroundTaskIdentifier.invalid

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
