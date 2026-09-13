import AppKit
import Foundation
import UserNotifications

/// Delivers only background nudges; foreground feedback stays in the calendar.
/// All mutation actions validate the whole current nudge and its occurrence.
@MainActor
final class CalendarNotificationBridge {
    private struct Nudge {
        let identifier: String
        let taskID: UUID
        let occurrenceID: UUID
        let category: String
        let title: String
        let body: String
    }

    private let store: Store
    private let calendar: CalendarCoordinator
    private let navigator: Navigator
    private let service: NotificationService
    private var updateTask: Task<Void, Never>?
    private var lastPostedID: String?
    private var observers: [NSObjectProtocol] = []

    init(store: Store, calendar: CalendarCoordinator, navigator: Navigator,
         service: NotificationService = .shared) {
        self.store = store
        self.calendar = calendar
        self.navigator = navigator
        self.service = service
        guard ReviewSession.identifier == nil else { return }
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            let observer = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.update() }
            }
            observers.append(observer)
        }
    }

    /// Call after coordinator nudge changes and once after bootstrap. The task
    /// yields once so a synchronous replan's intermediate nudges never escape.
    func update() {
        guard ReviewSession.identifier == nil else { return }
        updateTask?.cancel()
        updateTask = Task { [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled else { return }
            guard !NSApp.isActive, let nudge = currentNudge else {
                await service.clearCalendarNudges()
                return
            }
            let alreadyPresent = await service.clearCalendarNudges(except: nudge.identifier)
            guard !Task.isCancelled, !NSApp.isActive, currentNudge?.identifier == nudge.identifier else { return }
            if alreadyPresent { lastPostedID = nudge.identifier; return }
            guard lastPostedID != nudge.identifier, await service.authorizeCalendarNudgeIfNeeded() else { return }
            guard !Task.isCancelled, !NSApp.isActive, currentNudge?.identifier == nudge.identifier else { return }
            let posted = await service.postCalendarNudge(identifier: nudge.identifier, title: nudge.title, body: nudge.body,
                                                         category: nudge.category, taskID: nudge.taskID, occurrenceID: nudge.occurrenceID)
            // A response or replan can race notification delivery. Never leave
            // the old action available after its matching nudge disappeared.
            guard currentNudge?.identifier == nudge.identifier, !NSApp.isActive else {
                service.removeCalendarNudge(identifier: nudge.identifier)
                return
            }
            if posted { lastPostedID = nudge.identifier }
        }
    }

    /// The delegate passes only parsed values; no notification framework types
    /// enter the scheduling coordinator or its deterministic runtime checks.
    func handle(action: String, identifier: String, taskID: UUID, occurrenceID: UUID) {
        guard ReviewSession.identifier == nil else { return }
        service.removeCalendarNudge(identifier: identifier)
        guard action != UNNotificationDismissActionIdentifier else { return }
        if action == UNNotificationDefaultActionIdentifier {
            navigator.go(to: .calendar)
            if let task = store.block(id: taskID), task.occurrenceID == occurrenceID {
                navigator.openTask(taskID)
            }
            NSApp.activate(ignoringOtherApps: true)
            update()
            return
        }
        guard let nudge = currentNudge, nudge.identifier == identifier,
              nudge.taskID == taskID, nudge.occurrenceID == occurrenceID,
              let task = store.block(id: taskID), task.occurrenceID == occurrenceID, !task.isCompleted else {
            update()
            return
        }
        switch action {
        case NotificationService.calendarStartAction where nudge.category == NotificationService.calendarStartCategory:
            _ = calendar.start(task: task)
        case NotificationService.calendarDoneAction where nudge.category == NotificationService.calendarOverrunCategory || nudge.category == NotificationService.calendarHeadsUpCategory:
            calendar.complete(task: task)
        case NotificationService.calendarKeepGoingAction where nudge.category == NotificationService.calendarOverrunCategory && calendar.overrunNudge?.needsConfirmation == true:
            calendar.acceptMoreTime()
        default: break
        }
        update()
    }

    private var currentNudge: Nudge? {
        if let nudge = calendar.overrunNudge,
           let task = store.block(id: nudge.taskID), task.occurrenceID == nudge.occurrenceID, !task.isCompleted {
            let kind = nudge.needsConfirmation ? "confirmation" : "heads-up"
            let dates = "\(stamp(nudge.estimatedEnd)).\(stamp(nudge.proposedEnd))"
            let id = "\(NotificationService.calendarRequestPrefix)overrun.\(nudge.taskID).\(nudge.occurrenceID).\(kind).\(dates).\(nudge.movedTaskCount)"
            let count = nudge.movedTaskCount
            let impact = count == 0 ? "" : " Keeping going will move \(count) other \(count == 1 ? "task" : "tasks")."
            let minutes = max(0, nudge.proposedEnd.timeIntervalSince(nudge.estimatedEnd) / 60)
            let duration = minutes.formatted(.number.precision(.fractionLength(0...1)))
            let unit = minutes == 1 ? "minute" : "minutes"
            let body = nudge.needsConfirmation
                ? "Work is paused. Done, or keep going for \(duration) more \(unit)?\(impact)"
                : "Still working? I’ll allow \(duration) more \(unit)."
            return Nudge(identifier: id, taskID: nudge.taskID, occurrenceID: nudge.occurrenceID,
                         category: nudge.needsConfirmation ? NotificationService.calendarOverrunCategory : NotificationService.calendarHeadsUpCategory,
                         title: task.displayTitle, body: body)
        }
        if let nudge = calendar.startNudge,
           let task = store.block(id: nudge.taskID), task.occurrenceID == nudge.occurrenceID, !task.isCompleted {
            let dates = "\(stamp(nudge.scheduledStart)).\(stamp(nudge.graceEndsAt))"
            let id = "\(NotificationService.calendarRequestPrefix)start.\(nudge.taskID).\(nudge.occurrenceID).\(dates)"
            return Nudge(identifier: id, taskID: nudge.taskID, occurrenceID: nudge.occurrenceID,
                         category: NotificationService.calendarStartCategory, title: task.displayTitle,
                         body: "Your planned session is ready. Start when you are ready; tracking never starts automatically.")
        }
        return nil
    }

    /// Date's exact bit pattern avoids rounding two distinct nudge windows into
    /// the same notification identity or accepting a response for the old one.
    private func stamp(_ date: Date) -> String { String(date.timeIntervalSinceReferenceDate.bitPattern) }
}
