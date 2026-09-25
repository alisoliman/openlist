//
//  WidgetCommandProcessor.swift
//  openlist
//

import Foundation
import WidgetKit

/// The actions the main window's rows and work controls use. `Workbench`
/// provides them in the app, so a widget's tick, Start, Pause, Resume or Done
/// goes the window's way: the tray reports it, the change log lists it and
/// Undo takes it back.
@MainActor
protocol WidgetTaskActions: AnyObject {
    /// Completes the task and its open subtasks as of `date`, without the
    /// window's dwell, which the widget draws for itself. Completing the work
    /// in progress stops its timer and takes it off the toolbar, as Done does.
    func completeFromWidget(_ id: UUID, at date: Date, now: Date)
    func reopenFromWidget(_ id: UUID, now: Date)
    /// Starts recording `id`, or resumes it when it is the paused work,
    /// without opening the Work panel.
    func startWorkFromWidget(_ id: UUID, now: Date)
    /// Pauses the running work.
    func pauseWorkFromWidget(now: Date)
    /// Writes the window's tick of `id` straight away when the row is still
    /// in its completion dwell, so a widget tap on the same row finds it done
    /// instead of completing it a second time underneath the window.
    func settleCompletion(_ id: UUID)
}

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
    private let actions: any WidgetTaskActions
    /// Runs before anything is applied: an intent can be what launched the app.
    var prepare: () -> Void = {}
    private var isListening = false

    init(store: Store, calendar: CalendarCoordinator, publisher: WidgetSnapshotPublisher, actions: any WidgetTaskActions) {
        self.store = store
        self.calendar = calendar
        self.publisher = publisher
        self.actions = actions
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
            actions.settleCompletion(taskID)
            guard let task = occurrence(taskID, occurrenceID), !task.isCompleted else { return false }
            actions.completeFromWidget(task.id, at: tappedAt, now: now)
            return store.block(id: taskID).map { $0.isCompleted || $0.occurrenceID != occurrenceID } ?? false
        case .reopen:
            guard let task = occurrence(taskID, occurrenceID), task.isCompleted else { return false }
            actions.reopenFromWidget(task.id, now: now)
            return store.block(id: taskID)?.isCompleted == false
        case .startWork:
            guard isRecent(command, now: now), let task = occurrence(taskID, occurrenceID), !task.isCompleted else { return false }
            return start(task, now: now)
        case .pauseWork:
            // Only the work the widget drew: a stale Pause never stops work begun since.
            guard isRecent(command, now: now), let session = calendar.activeSession,
                  session.taskID == taskID, session.occurrenceID == occurrenceID else { return false }
            actions.pauseWorkFromWidget(now: now)
            return calendar.activeSession == nil
        case .resumeWork:
            guard isRecent(command, now: now), calendar.activeSession == nil, let task = calendar.resumableTask,
                  task.id == taskID, task.occurrenceID == occurrenceID else { return false }
            return start(task, now: now)
        case .finishWork:
            actions.settleCompletion(taskID)
            guard let task = occurrence(taskID, occurrenceID), !task.isCompleted, isWorkTask(task) else { return false }
            actions.completeFromWidget(task.id, at: tappedAt, now: now)
            return store.block(id: taskID).map { $0.isCompleted || $0.occurrenceID != occurrenceID } ?? false
        }
    }

    // MARK: - Actions

    /// The occurrence a command names, while it is still a task in an active list.
    private func occurrence(_ taskID: UUID, _ occurrenceID: UUID) -> Block? {
        guard let task = store.block(id: taskID), task.occurrenceID == occurrenceID, task.trashID == nil,
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

    /// Starts or resumes recording without opening the Work panel.
    ///
    /// A widget never takes over from other running work: a Start while
    /// something else runs comes from a widget drawn before that work began,
    /// and is ignored rather than switching what you are recording.
    private func start(_ task: Block, now: Date) -> Bool {
        guard calendar.activeSession == nil else { return false }
        actions.startWorkFromWidget(task.id, now: now)
        return calendar.activeSession?.occurrenceID == task.occurrenceID
    }
}
