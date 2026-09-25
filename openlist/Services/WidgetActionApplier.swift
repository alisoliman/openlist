//
//  WidgetActionApplier.swift
//  openlist
//

import AppKit
import Foundation

/// Applies what widget checkboxes and buttons asked for, through the workbench,
/// so the tray, the change log and Undo treat a tick in a widget like one in
/// the window.
///
/// Intents that run in the app hand their action straight over. Intents that
/// run in the widget extension leave a file in the shared queue; this drains it
/// at launch, on activation and whenever a file lands while the app runs.
@MainActor
final class WidgetActionApplier {
    private let store: Store
    private let workbench: Workbench
    private let calendar: CalendarCoordinator
    private let publisher: WidgetSnapshotPublisher
    /// Readies the store and the calendar first; safe to call repeatedly.
    var bootstrap: () -> Void = {}
    private var watcher: DispatchSourceFileSystemObject?
    private var pendingDrain: Task<Void, Never>?
    private var isDraining = false

    /// Start, Pause and Resume answer the timer as it was; older than this,
    /// they're dropped. Done completes the task however long it waited.
    static let workActionLifetime: TimeInterval = 120

    init(store: Store, workbench: Workbench, calendar: CalendarCoordinator, publisher: WidgetSnapshotPublisher) {
        self.store = store
        self.workbench = workbench
        self.calendar = calendar
        self.publisher = publisher
    }

    /// Applies one action and publishes before returning, so the reload the
    /// system makes after the intent already shows the result.
    func apply(_ action: WidgetAction) async {
        bootstrap()
        perform(action)
        publisher.refreshNow(forcingReload: true)
    }

    /// Applies every queued action, oldest first, but a tick and its untick,
    /// which take each other back, then removes their files.
    ///
    /// The files go only once the snapshot shows what they did: until then the
    /// widget lays them over the old snapshot, so a reload in between doesn't
    /// show a ticked row open again, and a crash part way loses nothing. The
    /// overlay ignores a file whose row the snapshot already shows done.
    func drainQueue() {
        guard !isDraining else { return }
        isDraining = true
        defer { isDraining = false }
        let pending = WidgetActionQueue.pending()
        WidgetActionQueue.removeUnreadable(keeping: Set(pending.map(\.url)))
        guard !pending.isEmpty else { return }
        bootstrap()
        let actions = pending.map(\.action)
        var takenBack: Set<Int> = []
        var late: WidgetAction?
        for (index, action) in actions.enumerated() where !takenBack.contains(index) {
            if action.kind.answersTimer, Date.now.timeIntervalSince(action.createdAt) > Self.workActionLifetime {
                late = action
                continue
            }
            // A tick and its untick, either way round, that the widget has
            // been showing as neither: skipped together, the task keeps its
            // place, its slot and its completion. Applied, a reopen would
            // take the slot away, or give the task a new occurrence the tick
            // after it no longer names.
            if let task = shownTask(action),
               let undo = WidgetAction.takingBack(index, in: actions, whileCompleted: task.isCompleted) {
                takenBack.insert(undo)
                continue
            }
            perform(action)
        }
        // The widget hid these rows until now; it reloads even if nothing changed.
        publisher.refreshNow(forcingReload: true)
        for (url, _) in pending { WidgetActionQueue.remove(url) }
        if let late { reportLate(late) }
    }

    /// A Start, Pause or Resume that waited for Openlist longer than the
    /// timer it answered is dropped, and says so rather than vanish.
    private func reportLate(_ action: WidgetAction) {
        let button = switch action.kind {
        case .pauseWork: "Pause"
        case .resumeWork: "Resume"
        default: "Start"
        }
        let title = store.block(id: action.taskID).map { " for \(NXFormat.quoted($0.displayTitle))" } ?? ""
        workbench.showTray("A widget’s \(button)\(title) reached Openlist too late to apply",
                           icon: "calendar.badge.exclamationmark", tone: .neutral)
    }

    /// Drains the queue whenever the extension adds a file to it.
    func startWatching() {
        guard watcher == nil, let directory = WidgetActionQueue.directoryURL else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .extend, .rename], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scheduleDrain() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
    }

    /// An atomic write lands as several events; drain once they settle.
    private func scheduleDrain() {
        pendingDrain?.cancel()
        pendingDrain = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            self?.drainQueue()
        }
    }

    /// The task `action` names, while it's still the one the widget showed:
    /// not trashed, on the same occurrence, and not in a dwell.
    private func shownTask(_ action: WidgetAction) -> Block? {
        guard let task = store.block(id: action.taskID), task.isTask, task.trashID == nil,
              action.occurrenceID.map({ $0 == task.occurrenceID }) != false,
              workbench.closing[task.id] == nil else { return nil }
        return task
    }

    /// Applies `action` if its task is still the one the widget showed, in the
    /// state the widget showed it in.
    private func perform(_ action: WidgetAction) {
        guard let task = shownTask(action) else { return }
        switch action.kind {
        case .complete:
            guard !task.isCompleted else { return }
            workbench.complete([task.id], settleNow: true, at: action.createdAt, clearsSelection: false)
        case .reopen:
            guard task.isCompleted else { return }
            workbench.reopen([task.id])
        case .startWork:
            guard calendar.activeSession?.taskID != task.id,
                  calendar.validWorkTask(WorkTaskReference(task)) != nil else { return }
            workbench.startWork(task.id)
        case .pauseWork, .resumeWork:
            // Only from the state the widget showed: a Pause from a widget
            // still showing work the app has since paused mustn't resume it.
            guard workbench.workTask?.id == task.id,
                  workbench.isWorkPaused == (action.kind == .resumeWork) else { return }
            workbench.toggleWorkPause()
        case .finishWork:
            // Completing the work task stops its timer too, as Done does.
            guard !task.isCompleted else { return }
            workbench.complete([task.id], settleNow: true, at: action.createdAt, clearsSelection: false)
        }
    }
}
