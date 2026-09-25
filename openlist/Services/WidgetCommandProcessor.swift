//
//  WidgetCommandProcessor.swift
//  openlist
//

import Foundation
import WidgetKit

/// Applies what widget buttons ask for: ticking tasks off or reopening them,
/// and starting, pausing and finishing the work the toolbar timer shows.
///
/// A command names the task occurrence the widget drew, and is checked against
/// the library as it is now. A tap that no longer matches, because the task was
/// completed elsewhere, a repeat rolled forward or work moved on, changes
/// nothing; the snapshot rewritten afterwards shows the widget what is true.
/// Every widget button names both the task and the occurrence, so a command
/// missing either names nothing and is ignored, whatever its action. The
/// widget's overlay follows the same rule, so it never draws a tap the app
/// then drops.
///
/// A queued command can reach the app long after its tap, at the next launch.
/// A tick or a Done still applies, dated at the tap; a Start, Pause or Resume
/// that old is dropped.
@MainActor
final class WidgetCommandProcessor {
    private let store: Store
    private let calendar: CalendarCoordinator
    private let publisher: WidgetSnapshotPublisher
    /// Runs before anything is applied: an intent can be what launched the app.
    var prepare: () -> Void = {}
    /// Writes the main window's tick of a task straight away when the row is
    /// still in its completion dwell, so a widget tap on the same row finds it
    /// done instead of completing it a second time underneath the window.
    var settleWindowCompletion: (UUID) -> Void = { _ in }
    private var isListening = false

    init(store: Store, calendar: CalendarCoordinator, publisher: WidgetSnapshotPublisher) {
        self.store = store
        self.calendar = calendar
        self.publisher = publisher
    }

    deinit {
        CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                                Unmanaged.passUnretained(self).toOpaque())
    }

    /// An intent performed in the app. Anything the extension queued earlier
    /// goes first, so taps apply in the order they were made, and the snapshot
    /// is rewritten before the intent returns: the reload that follows shows
    /// the result, and drops whatever the widget drew while it waited.
    func handle(_ command: WidgetCommand, now: Date = .now) {
        prepare()
        let queued = WidgetCommandQueue.pending(now: now)
        for command in queued { apply(command, now: now) }
        apply(command, now: now)
        publisher.refreshNow(force: true)
        WidgetCommandQueue.remove(Set(queued.map(\.id)))
    }

    /// Applies the commands the extension queued while it could not reach the app.
    func drainQueue(now: Date = .now) {
        let queued = WidgetCommandQueue.pending(now: now)
        guard !queued.isEmpty else { return }
        prepare()
        for command in queued { apply(command, now: now) }
        publisher.refreshNow(force: true)
        // The widget draws queued taps over the snapshot, so they leave the
        // queue only once the snapshot shows their outcome. The second reload
        // is the one that finds the queue empty.
        WidgetCommandQueue.remove(Set(queued.map(\.id)))
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Drains the queue whenever the extension signals that it added to it.
    func listenForSignals() {
        guard !isListening else { return }
        isListening = true
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let processor = Unmanaged<WidgetCommandProcessor>.fromOpaque(observer).takeUnretainedValue()
                Task { @MainActor in processor.drainQueue() }
            },
            WidgetCommandSignal.name as CFString,
            nil,
            .deliverImmediately
        )
    }

    /// Applies one command if it still matches the library, and returns
    /// whether it changed anything. Stale commands are ignored silently: the
    /// widget has nowhere to explain them, and its next reload corrects it.
    @discardableResult
    func apply(_ command: WidgetCommand, now: Date = .now) -> Bool {
        // A clock set back since the tap would put it in the future: a tick
        // counts as made now, while work that far off is dropped by `isRecent`.
        let tappedAt = min(now, command.issuedAt)
        guard let taskID = command.taskID, let occurrenceID = command.occurrenceID else { return false }
        switch command.action {
        case .complete:
            settleWindowCompletion(taskID)
            guard let task = occurrence(taskID, occurrenceID), !task.isCompleted else { return false }
            complete(task, tappedAt: tappedAt, now: now)
        case .reopen:
            guard let task = occurrence(taskID, occurrenceID), task.isCompleted else { return false }
            store.toggleCompletion(task, now: now)
        case .startWork:
            guard isRecent(command, now: now), let task = occurrence(taskID, occurrenceID), !task.isCompleted else { return false }
            return start(task, now: now)
        case .pauseWork:
            // Only the work the widget drew: a stale Pause never stops work begun since.
            guard isRecent(command, now: now), let session = calendar.activeSession,
                  session.taskID == taskID, session.occurrenceID == occurrenceID else { return false }
            calendar.pause(reason: "Paused", now: now)
            return calendar.activeSession == nil
        case .resumeWork:
            guard isRecent(command, now: now), calendar.activeSession == nil, let task = calendar.resumableTask,
                  task.id == taskID, task.occurrenceID == occurrenceID else { return false }
            return start(task, now: now)
        case .finishWork:
            settleWindowCompletion(taskID)
            guard let task = occurrence(taskID, occurrenceID), !task.isCompleted, isWorkTask(task) else { return false }
            complete(task, tappedAt: tappedAt, now: now)
        }
        return true
    }

    // MARK: - Actions

    /// The occurrence a command names, while it is still a task in an active list.
    private func occurrence(_ taskID: UUID, _ occurrenceID: UUID) -> Block? {
        guard let task = store.block(id: taskID), task.occurrenceID == occurrenceID,
              ActiveTaskPolicy(hierarchy: store.listHierarchy()).includes(task) else { return nil }
        return task
    }

    /// Whether a Start, Pause or Resume was tapped recently enough to act on.
    private func isRecent(_ command: WidgetCommand, now: Date) -> Bool {
        command.isCurrent(at: now)
    }

    /// Whether `task` is the work the toolbar timer shows, running or paused.
    private func isWorkTask(_ task: Block) -> Bool {
        if let session = calendar.activeSession {
            return session.taskID == task.id && session.occurrenceID == task.occurrenceID
        }
        return calendar.resumableTask?.id == task.id
    }

    /// Completes without the window's dwell, which the widget draws for itself.
    ///
    /// The task is done as of the tap, so a tick queued late in the evening and
    /// applied at the next launch still counts on that day, and a repeat that
    /// runs from its completion rolls forward from the tap.
    private func complete(_ task: Block, tappedAt: Date, now: Date) {
        if let session = calendar.activeSession, session.taskID == task.id, session.occurrenceID == task.occurrenceID {
            // Closes the running segment and reports the recorded time in the
            // Work panel, as Complete Current Task does. At `now`, not the tap:
            // work only records while the app runs, and a running app applies
            // a tap within moments; completing also replans the day, which has
            // to start from the time it really is.
            calendar.complete(task: task, now: now)
            return
        }
        let wasPaused = calendar.resumeTaskID == task.id
        store.toggleCompletion(task, now: tappedAt)
        // Finished work leaves the toolbar timer, as it does when ticked in the window.
        if wasPaused { calendar.dismissResume() }
    }

    /// Starts or resumes recording without opening the Work panel.
    ///
    /// Taking over from other running work is a switch the app asks you to
    /// confirm, so a widget never makes it: a Start while something else runs
    /// comes from a stale widget and is ignored.
    private func start(_ task: Block, now: Date) -> Bool {
        guard calendar.activeSession == nil else { return false }
        let notice = calendar.notice
        // Work that stopped at its estimate resumes as the toolbar's Resume
        // does: the tap is the go-ahead for the extra time and the moves it needs.
        if let nudge = calendar.overrunNudge, nudge.needsConfirmation, nudge.occurrenceID == task.occurrenceID {
            calendar.acceptMoreTime(now: now)
        } else {
            calendar.start(task: task, now: now)
        }
        guard calendar.activeSession?.occurrenceID == task.occurrenceID else {
            // Refused: outside the list's hours or inside busy time. The Work
            // panel should not later explain a tap it never saw.
            calendar.notice = notice
            return false
        }
        return true
    }
}
