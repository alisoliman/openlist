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
    private let workbench: Workbench
    private let service: NotificationService
    /// Opens the main window again if it was closed, as a reminder's click
    /// does: the Calendar and the inspector a click opens are that window's.
    var openMainWindow: (() -> Void)?
    private var updateTask: Task<Void, Never>?
    private var lastPostedID: String?
    private var deliveredStarts: Set<String> = Set(ReviewSession.defaults.stringArray(forKey: "work.deliveredStarts") ?? [])
    private var observers: [NSObjectProtocol] = []

    init(store: Store, calendar: CalendarCoordinator, workbench: Workbench,
         service: NotificationService = .shared) {
        self.store = store
        self.calendar = calendar
        self.workbench = workbench
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
            guard calendar.workNotificationsEnabled, !NSApp.isActive, let nudge = currentNudge else {
                await service.clearCalendarNudges()
                return
            }
            let alreadyPresent = await service.clearCalendarNudges(except: nudge.identifier)
            guard !Task.isCancelled, !NSApp.isActive, currentNudge?.identifier == nudge.identifier else { return }
            if alreadyPresent { lastPostedID = nudge.identifier; return }
            if nudge.category == NotificationService.calendarStartCategory && deliveredStarts.contains(nudge.identifier) { return }
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
            if posted {
                lastPostedID = nudge.identifier
                if nudge.category == NotificationService.calendarStartCategory {
                    deliveredStarts.insert(nudge.identifier)
                    ReviewSession.defaults.set(Array(deliveredStarts), forKey: "work.deliveredStarts")
                }
            }
        }
    }

    /// The delegate passes only parsed values; no notification framework types
    /// enter the scheduling coordinator or its deterministic runtime checks.
    func handle(action: String, identifier: String, taskID: UUID, occurrenceID: UUID) {
        guard ReviewSession.identifier == nil else { return }
        service.removeCalendarNudge(identifier: identifier)
        guard action != UNNotificationDismissActionIdentifier else { return }
        if action == UNNotificationDefaultActionIdentifier || action == NotificationService.calendarOpenPlanAction {
            // In the main window, over whatever was up there, as a reminder
            // lands: the task opens as its block on the Calendar opens it.
            openMainWindow?()
            workbench.go(.calendar)
            workbench.navigator.isShortcutSheetOpen = false
            if let task = store.block(id: taskID), task.occurrenceID == occurrenceID {
                workbench.focusID = nil
                workbench.navigator.openTask(taskID)
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
            calendar.requestWork(WorkTaskReference(task))
        case NotificationService.calendarLaterAction where nudge.category == NotificationService.calendarStartCategory:
            calendar.quietWork(WorkTaskReference(task))
        case NotificationService.calendarDoneAction where nudge.category == NotificationService.calendarHeadsUpCategory:
            calendar.complete(task: task)
        default: break
        }
        update()
    }

    private var currentNudge: Nudge? {
        if let nudge = calendar.overrunNudge,
           let task = store.block(id: nudge.taskID), task.occurrenceID == nudge.occurrenceID, !task.isCompleted {
            let dates = "\(stamp(nudge.estimatedEnd)).\(stamp(nudge.proposedEnd))"
            let id = "\(NotificationService.calendarRequestPrefix)overrun.\(nudge.taskID).\(nudge.occurrenceID).heads-up.\(dates).\(nudge.movedTaskCount)"
            let count = nudge.movedTaskCount
            let impact = count == 0 ? "" : ", moving \(count) other \(count == 1 ? "task" : "tasks")"
            let body = "Estimate almost reached. Recording continues and the plan makes room\(impact)."
            return Nudge(identifier: id, taskID: nudge.taskID, occurrenceID: nudge.occurrenceID,
                         category: NotificationService.calendarHeadsUpCategory, title: task.displayTitle, body: body)
        }
        if let nudge = calendar.startNudge,
           let task = store.block(id: nudge.taskID), task.occurrenceID == nudge.occurrenceID, !task.isCompleted {
            let reminder = calendar.quietUntil[nudge.occurrenceID.uuidString] ?? 0
            let id = "\(NotificationService.calendarRequestPrefix)start.\(nudge.taskID).\(nudge.occurrenceID).\(reminder)"
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
