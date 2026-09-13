import AppKit

/// Workspace notifications cover sleep, display sleep and user-session changes.
/// Lock notifications supplement these when the screen locks without sleeping.
@MainActor
final class MacWorkMonitor {
    var onUnavailable: ((String) -> Void)?
    var onReturn: (() -> Void)?
    var onTerminate: (() -> Void)?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    func start() {
        guard observers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        for (name, reason) in [(NSWorkspace.willSleepNotification, "Mac slept"),
                               (NSWorkspace.screensDidSleepNotification, "Screen slept"),
                               (NSWorkspace.sessionDidResignActiveNotification, "Mac locked")] {
            observe(workspace, name: name) { [weak self] in self?.onUnavailable?(reason) }
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observe(workspace, name: name) { [weak self] in self?.onReturn?() }
        }
        observe(DistributedNotificationCenter.default(), name: Notification.Name("com.apple.screenIsLocked")) { [weak self] in
            self?.onUnavailable?("Mac locked")
        }
        observe(DistributedNotificationCenter.default(), name: Notification.Name("com.apple.screenIsUnlocked")) { [weak self] in
            self?.onReturn?()
        }
        observe(.default, name: NSApplication.willTerminateNotification) { [weak self] in self?.onTerminate?() }
    }

    private func observe(_ center: NotificationCenter, name: Notification.Name, action: @escaping @MainActor () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { action() }
        }
        observers.append((center, token))
    }
}
