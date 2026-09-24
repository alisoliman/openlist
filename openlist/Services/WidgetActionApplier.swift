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

    /// Work actions answer the timer as it was; older than this, they're dropped.
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

    /// Applies every queued action, oldest first, and removes its file.
    func drainQueue() {
        guard !isDraining else { return }
        isDraining = true
        defer { isDraining = false }
        let pending = WidgetActionQueue.pending()
        WidgetActionQueue.removeUnreadable(keeping: Set(pending.map(\.url)))
        guard !pending.isEmpty else { return }
        bootstrap()
        for (url, action) in pending {
            WidgetActionQueue.remove(url)
            let isWork = action.kind == .startWork || action.kind == .togglePause || action.kind == .finishWork
            if isWork, Date.now.timeIntervalSince(action.createdAt) > Self.workActionLifetime { continue }
            perform(action)
        }
        // The widget hid these rows until now; it reloads even if nothing changed.
        publisher.refreshNow(forcingReload: true)
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

    /// Applies `action` if its task is still the one the widget showed, in the
    /// state the widget showed it in.
    private func perform(_ action: WidgetAction) {
        guard let task = store.block(id: action.taskID), task.isTask, task.trashID == nil,
              action.occurrenceID.map({ $0 == task.occurrenceID }) != false,
              workbench.closing[task.id] == nil else { return }
        switch action.kind {
        case .complete:
            guard !task.isCompleted else { return }
            workbench.complete([task.id], settleNow: true, at: action.createdAt, clearsSelection: false)
        case .reopen:
            guard task.isCompleted else { return }
            workbench.reopen([task.id])
        case .startWork:
            guard calendar.validWorkTask(WorkTaskReference(task)) != nil else { return }
            workbench.startWork(task.id)
        case .togglePause:
            guard workbench.workTask?.id == task.id else { return }
            workbench.toggleWorkPause()
        case .finishWork:
            guard !task.isCompleted else { return }
            if workbench.workTask?.id == task.id {
                workbench.finishWork(settleNow: true)
            } else {
                workbench.complete([task.id], settleNow: true, at: action.createdAt, clearsSelection: false)
            }
        }
    }
}
