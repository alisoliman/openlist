//
//  PhoneActions.swift
//  OpenlistiOS
//

import Foundation
import Observation
import SwiftData

/// The iPhone's rules for acting on tasks, which the Mac keeps in its
/// AppKit-bound `Workbench`: the completion dwell ("Undo window"), the tray
/// and its Undo, trash and field edits as undoable steps, and widget buttons
/// applied the way a row's own are.
///
/// Every screen acts through this, never by calling a completion or trash
/// Store API itself, so a tick on Today, a swipe on a list page and a tick in
/// the widget dwell, report and undo alike.
///
/// A tick doesn't write straight away. The row shows done for the undo window
/// (`AppSettings.undoDwellSeconds`) and the completion is written when it
/// ends; Undo within the window writes nothing at all, so the Mac never sees a
/// completion and its undo. Repeats roll forward at once, as on the Mac. Each
/// action records its Store changes on an undo manager of its own, so the
/// tray's Undo takes back exactly that action.
@Observable
@MainActor
final class PhoneActions {
    let tray: TrayCenter
    let haptics: PhoneHaptics
    private let store: Store
    private let settings: AppSettings
    private let calendar: CalendarCoordinator
    private let clock: AppClock

    /// The scene's undo manager, which shake-to-undo reads. Completions made
    /// outside an action (a notification's Complete, say) register there.
    @ObservationIgnored weak var sceneUndoManager: UndoManager?

    /// Tasks ticked and dwelling: drawn done where they are until written.
    private(set) var closing: Set<UUID> = []
    @ObservationIgnored private var batches: [CompletionBatch] = []
    /// The action writing completions now, whose manager takes their undo.
    @ObservationIgnored private var completionUndoTarget: UndoManager?

    init(store: Store, settings: AppSettings, calendar: CalendarCoordinator, clock: AppClock,
         tray: TrayCenter = TrayCenter(), haptics: PhoneHaptics? = nil) {
        self.store = store
        self.settings = settings
        self.calendar = calendar
        self.clock = clock
        self.tray = tray
        self.haptics = haptics ?? PhoneHaptics(settings: settings)
        store.onCompletionUndoAvailable = { [weak self] action in
            guard let self, let manager = completionUndoTarget ?? sceneUndoManager else { return }
            self.store.registerCompletionUndo(action, with: manager)
        }
        // A one-off refusal ("That task is in Trash") belongs in the tray,
        // not in the sticky notice the Mac's editor shows.
        store.onRefusal = { [weak self] message in
            self?.tray.show(message, icon: "exclamationmark.circle", tone: .neutral, seconds: 4)
        }
    }

    /// The undo window, in seconds: how long a ticked row dwells.
    var dwell: Double { Double(min(8, max(2, settings.undoDwellSeconds))) }

    /// How long a message with Undo stays: the dwell, and a beat after the write.
    private var traySeconds: Double { dwell + 0.3 }

    func isClosing(_ id: UUID) -> Bool { closing.contains(id) }

    // MARK: Completion

    /// A checkbox: completes an open task, reopens a done one, and takes a
    /// dwelling one back, as its Undo would.
    func toggle(_ task: Block) {
        guard task.isTask else { return }
        if closing.contains(task.id) {
            cancelClosing([task.id])
            haptics.play(.soft)
        } else if task.isCompleted {
            reopen([task])
        } else {
            complete([task])
        }
    }

    /// Completes `tasks` as one action. Repeats roll forward now; the rest
    /// dwell, then are written together. `date` is when it happened, for a
    /// widget tap; `settleNow` writes at once, with no dwell.
    func complete(_ tasks: [Block], at date: Date? = nil, settleNow: Bool = false, label: String? = nil) {
        let open = tasks.filter { $0.isTask && !$0.isCompleted && !closing.contains($0.id) }
        guard !open.isEmpty else { return }
        // A parent covers its subtasks ticked with it: a repeat resets them
        // for its next date, the rest complete with their parent.
        let rolls = uncovered(open.filter { $0.recurrence != nil }, by: Set(open.map(\.id)))
        let rolled = Set(rolls.map(\.id))
        let closes = uncovered(open.filter { !rolled.contains($0.id) }, by: rolled)
        let batch = CompletionBatch(pending: closes.map(\.id), date: date)
        write(rolls, in: batch)
        let text = label ?? completionLabel(rolls: rolls, closes: closes)
        let icon = !rolls.isEmpty && closes.isEmpty ? "repeat" : "checkmark.circle"
        batch.trayID = tray.show(text, icon: icon, tone: .success, seconds: traySeconds) { [weak self, batch] in
            self?.undo(batch)
        }.id
        offerToScene(text) { [weak self, batch] in self?.undo(batch) }
        haptics.play(.success)
        guard !batch.pending.isEmpty else { return }
        closing.formUnion(batch.pending)
        batches.append(batch)
        if settleNow { return settle(batch) }
        let delay = traySeconds
        batch.settleTask = Task { [weak self, batch] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.settle(batch)
        }
    }

    /// Reopens done tasks as one action, with Undo.
    func reopen(_ tasks: [Block]) {
        let done = tasks.filter { $0.isTask && $0.isCompleted }
        guard !done.isEmpty else { return }
        let changes = Self.makeUndoManager()
        changes.beginUndoGrouping()
        completionUndoTarget = changes
        do {
            _ = try store.setBulkCompletion(false, ids: done.map(\.id), now: clock.now)
        } catch {
            completionUndoTarget = nil
            changes.endUndoGrouping()
            return fail(store.actionError ?? "The task could not be reopened. \(error.localizedDescription)")
        }
        completionUndoTarget = nil
        changes.endUndoGrouping()
        let text = done.count == 1 ? "Reopened “\(done[0].displayTitle)”" : "Reopened \(done.count) tasks"
        tray.show(text, icon: "arrow.uturn.backward.circle", tone: .accent, seconds: traySeconds,
                  action: changes.canUndo ? { [weak self] in self?.undo(changes) } : nil)
        if changes.canUndo { offerToScene(text) { [weak self] in self?.undo(changes) } }
    }

    /// Takes rows back out of the dwell before they're written. A batch with
    /// nothing left to write or undo leaves the tray.
    func cancelClosing(_ ids: [UUID]) {
        let ids = Set(ids)
        closing.subtract(ids)
        for batch in batches where batch.pending.contains(where: ids.contains) {
            batch.pending.removeAll(where: ids.contains)
            guard batch.pending.isEmpty else { continue }
            batch.settleTask?.cancel()
            batches.removeAll { $0 === batch }
            if !batch.changes.canUndo { tray.dismiss(batch.trayID) }
        }
    }

    /// Writes the completion `id` is dwelling in now, its batch with it, as
    /// the dwell ending would.
    func settle(_ id: UUID) {
        guard let batch = batches.first(where: { $0.pending.contains(id) }) else { return }
        settle(batch)
    }

    /// Writes every dwelling completion now: before the app goes to the
    /// background, so a row that showed done is saved done.
    func settleAll() {
        for batch in batches { settle(batch) }
    }

    private func settle(_ batch: CompletionBatch) {
        batch.settleTask?.cancel()
        batch.settleTask = nil
        batches.removeAll { $0 === batch }
        let ids = batch.pending
        batch.pending = []
        closing.subtract(ids)
        write(ids.compactMap { store.block(id: $0) }, in: batch)
    }

    /// Completes through the Store on the batch's own undo manager, as one
    /// saved change in the history.
    private func write(_ tasks: [Block], in batch: CompletionBatch) {
        let open = tasks.filter { !$0.isCompleted }
        let roots = uncovered(open, by: Set(open.map(\.id)))
        guard !roots.isEmpty else { return }
        batch.changes.beginUndoGrouping()
        completionUndoTarget = batch.changes
        store.withActivityBatch(batch.activity) {
            for task in roots where !task.isCompleted {
                let now = batch.date ?? clock.now
                // Done on running work finishes the session with the task.
                if calendar.activeSession?.taskID == task.id { calendar.complete(task: task, now: now) }
                else { store.toggleCompletion(task, now: now) }
            }
        }
        completionUndoTarget = nil
        batch.changes.endUndoGrouping()
    }

    private func undo(_ batch: CompletionBatch) {
        batch.settleTask?.cancel()
        batch.settleTask = nil
        batches.removeAll { $0 === batch }
        closing.subtract(batch.pending)
        batch.pending = []
        undo(batch.changes)
    }

    private func completionLabel(rolls: [Block], closes: [Block]) -> String {
        let all = rolls + closes
        if all.count == 1, let task = all.first {
            if let roll = rolls.first, let next = roll.dueDate {
                return "Completed “\(task.displayTitle)” · next \(CompactText.day(next, now: clock.now))"
            }
            return "Completed “\(task.displayTitle)”"
        }
        return "Completed \(all.count) tasks"
    }

    // MARK: Trash

    /// Moves tasks to Trash as one action: "Moved “X” to Trash" with Undo.
    @discardableResult
    func trash(_ tasks: [Block], label: String? = nil) -> Bool {
        let tasks = tasks.filter { !$0.isDeleted && $0.trashID == nil }
        guard !tasks.isEmpty else { return false }
        NotificationCenter.default.post(name: .commitPendingEditorDrafts, object: nil)
        cancelClosing(tasks.map(\.id))
        store.trashError = nil
        let text = label ?? (tasks.count == 1 ? "Moved “\(tasks[0].displayTitle)” to Trash" : "Moved \(tasks.count) items to Trash")
        return perform(text, icon: "trash", tone: .danger) { [store] changes in
            store.trashBlocks(tasks, undoManager: changes)
        } failure: { [store] in
            store.trashError ?? "That could not be moved to Trash."
        }
    }

    /// Moves tasks, with what's under them, to the end of `list`: "Moved
    /// “X” to Home" with Undo.
    @discardableResult
    func move(_ tasks: [Block], to list: TaskList) -> Bool {
        let tasks = tasks.filter { $0.listID != list.id }
        guard !tasks.isEmpty else { return false }
        NotificationCenter.default.post(name: .commitPendingEditorDrafts, object: nil)
        cancelClosing(tasks.map(\.id))
        let what = tasks.count == 1 ? "“\(tasks[0].displayTitle)”" : "\(tasks.count) tasks"
        var failure = "That could not be moved."
        return perform("Moved \(what) to \(list.displayTitle)", icon: "arrow.right.circle", tone: .accent) { [store] changes in
            do {
                return try !store.moveSelection(tasks.map(\.id), to: list.id, undoManager: changes).isEmpty
            } catch {
                failure = store.actionError ?? "That could not be moved. \(error.localizedDescription)"
                return false
            }
        } failure: { failure }
    }

    /// Puts Trash entries back where they were: "Restored to Home" with Undo,
    /// which sends them back to Trash as they were.
    @discardableResult
    func restore(_ ids: [UUID]) -> Bool {
        guard !ids.isEmpty else { return false }
        store.trashError = nil
        guard let recoveries = store.restoreTrashRecoveries(ids: ids) else {
            fail(store.trashError ?? "That could not be restored; it remains in Trash.")
            return false
        }
        let changes = Self.makeUndoManager()
        changes.beginUndoGrouping()
        changes.registerUndo(withTarget: store) { store in
            MainActor.assumeIsolated {
                let blocks = ids.compactMap { store.block(id: $0) }
                if !blocks.isEmpty { _ = store.trashBlocks(blocks, puttingBack: recoveries) }
                for list in ids.compactMap({ store.list(id: $0) }) { _ = store.trashList(list) }
            }
        }
        changes.endUndoGrouping()
        report(restoredLabel(ids), icon: "arrow.uturn.backward", tone: .success, changes: changes)
        return true
    }

    private func restoredLabel(_ ids: [UUID]) -> String {
        if ids.count == 1, let id = ids.first {
            if let list = store.list(id: id) { return "Restored “\(list.displayTitle)”" }
            if let block = store.block(id: id), let list = store.list(id: block.listID) {
                return "Restored to \(list.displayTitle)"
            }
        }
        return ids.count == 1 ? "Restored" : "Restored \(ids.count) items"
    }

    // MARK: Any undoable step

    /// Runs `body`, which registers its Store changes on the manager it's
    /// given, and shows `text` with an Undo that takes back exactly those.
    /// `failure` names what went wrong when `body` returns false.
    @discardableResult
    func perform(_ text: String, icon: String? = nil, tone: TrayMessage.Tone = .success,
                 _ body: (UndoManager) -> Bool, failure: () -> String = { "That didn’t work. Try again." }) -> Bool {
        let changes = Self.makeUndoManager()
        changes.beginUndoGrouping()
        let succeeded = body(changes)
        changes.endUndoGrouping()
        guard succeeded else {
            fail(failure())
            return false
        }
        report(text, icon: icon, tone: tone, changes: changes)
        return true
    }

    /// The tray for an action done, with Undo when it recorded any, which
    /// shake-to-undo offers too.
    private func report(_ text: String, icon: String?, tone: TrayMessage.Tone, changes: UndoManager) {
        tray.show(text, icon: icon, tone: tone, seconds: max(5, traySeconds),
                  action: changes.canUndo ? { [weak self] in self?.undo(changes) } : nil)
        if changes.canUndo { offerToScene(text) { [weak self] in self?.undo(changes) } }
    }

    /// Changes fields of `tasks` in one save, with Undo that restores only the
    /// fields this step changed: star, due date, plan for today, labels…
    func edit(_ tasks: [Block], _ text: String?, icon: String? = nil, _ change: (Block) -> Void) {
        let tasks = tasks.filter(\.isTask)
        guard !tasks.isEmpty else { return }
        let before = tasks.map(TaskFields.init)
        store.batch { for task in tasks { change(task) } }
        let after = tasks.compactMap { store.block(id: $0.id) }.map(TaskFields.init)
        let changes = Self.makeUndoManager()
        changes.beginUndoGrouping()
        registerRestore(before, over: after, on: changes)
        changes.endUndoGrouping()
        if let text {
            tray.show(text, icon: icon, tone: .accent, seconds: max(5, traySeconds)) { [weak self] in self?.undo(changes) }
        }
        offerToScene(text ?? "Change") { [weak self] in self?.undo(changes) }
    }

    /// Offers an action's undo to shake-to-undo as well, under its tray text.
    /// Taking it back from the tray first leaves this entry with nothing to do.
    private func offerToScene(_ name: String, _ undo: @escaping () -> Void) {
        guard let manager = sceneUndoManager else { return }
        manager.registerUndo(withTarget: self) { _ in MainActor.assumeIsolated { undo() } }
        manager.setActionName(name)
    }

    private func registerRestore(_ fields: [TaskFields], over replaced: [TaskFields], on manager: UndoManager) {
        manager.registerUndo(withTarget: self) { [weak manager] actions in
            MainActor.assumeIsolated {
                actions.restore(fields, over: replaced)
                if let manager { actions.registerRestore(replaced, over: fields, on: manager) }
            }
        }
    }

    private func restore(_ fields: [TaskFields], over replaced: [TaskFields]) {
        for field in fields {
            guard let block = store.block(id: field.id) else { continue }
            field.apply(to: block, replacing: replaced.first { $0.id == field.id })
            store.scheduleReminderIfNeeded(for: block)
        }
        store.save()
    }

    private func undo(_ changes: UndoManager) {
        // Its saved history is one change, as the step's was.
        store.withActivityBatch(UUID()) {
            while changes.canUndo { changes.undo() }
        }
        haptics.play(.soft)
    }

    private func fail(_ message: String) {
        tray.show(message, icon: "exclamationmark.circle", tone: .danger, seconds: 5)
        haptics.play(.error)
    }

    // MARK: Helpers

    /// An action's own undo stack. Grouped by hand: each action is one group.
    private static func makeUndoManager() -> UndoManager {
        let manager = UndoManager()
        manager.groupsByEvent = false
        return manager
    }

    /// The tasks with no ancestor among `ids`.
    private func uncovered(_ tasks: [Block], by ids: Set<UUID>) -> [Block] {
        tasks.filter { task in
            var parentID = task.parentID
            var visited: Set<UUID> = [task.id]
            while let id = parentID, visited.insert(id).inserted {
                if ids.contains(id) { return false }
                parentID = store.block(id: id)?.parentID
            }
            return true
        }
    }

    /// One completion action: what still dwells, and the undo manager that
    /// holds what it wrote.
    private final class CompletionBatch {
        let changes = PhoneActions.makeUndoManager()
        let activity = UUID()
        var pending: [UUID]
        let date: Date?
        var settleTask: Task<Void, Never>?
        var trayID: UUID?

        init(pending: [UUID], date: Date?) {
            self.pending = pending
            self.date = date
        }
    }
}

// MARK: - Widget buttons

/// A widget's buttons act as a row's own do, so the tray, history and Undo
/// treat them alike (the Mac's rule, Workbench+Widgets.swift).
extension PhoneActions: WidgetTaskActions {
    func completeFromWidget(_ id: UUID, at date: Date, now: Date) {
        guard let task = store.block(id: id) else { return }
        complete([task], at: date, settleNow: true)
    }

    func reopenFromWidget(_ id: UUID, now: Date) {
        guard let task = store.block(id: id) else { return }
        reopen([task])
    }

    func startWorkFromWidget(_ id: UUID, now: Date) {
        guard let task = store.block(id: id) else { return }
        _ = calendar.start(task: task, now: now)
    }

    func pauseWorkFromWidget(now: Date) {
        guard calendar.activeSession != nil else { return }
        calendar.pause(now: now)
    }

    func settleCompletion(_ id: UUID) {
        settle(id)
    }
}
