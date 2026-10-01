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
    /// Runs after any Undo, so screens on what it took away (a list just
    /// made, say) move on. The environment repairs the navigator here.
    @ObservationIgnored var afterUndo: (() -> Void)?

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

    // MARK: The latest step

    /// This session's newest step that can still be taken back, which
    /// Activity offers Undo on, as the Mac's Recent changes does.
    struct LatestChange {
        let text: String
        /// When it was taken, on the clock the Store stamps history with (the
        /// system's), so Activity can find its row.
        let at: Date
        /// The work session a start made, whose "Started" row it is.
        var sessionID: UUID?
        fileprivate let undo: () -> Void
    }

    private(set) var latest: LatestChange?

    /// Takes back the newest step, as its tray's Undo would.
    func undoLatest() {
        guard let latest else { return }
        self.latest = nil
        latest.undo()
    }

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
        // Finished work stops now, not once the dwell settles, as on the Mac;
        // the batch keeps it, so Undo offers it again.
        if let session = calendar.activeSession, open.contains(where: { $0.id == session.taskID }) {
            calendar.pause(reason: "Completed", now: date ?? clock.now)
        }
        batch.resume = calendar.resumableTask.flatMap { paused in
            open.contains { $0.id == paused.id } ? WorkTaskReference(paused) : nil
        }
        if batch.resume != nil { calendar.dismissResume() }
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
            if let resume = batch.resume { calendar.restoreResume(resume) }
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
        if let resume = batch.resume { calendar.restoreResume(resume) }
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

    // MARK: Work

    /// Starts recording `task`, or resumes it, pausing any other work, as the
    /// Mac's Start does. It's this session's latest step until another: its
    /// Undo, from Activity or a shake, stops the work, takes the session it
    /// made back out and offers the work that was paused before again.
    @discardableResult
    func startWork(_ task: Block) -> Bool {
        let now = clock.now
        let before = calendar.activeSession.flatMap { store.block(id: $0.taskID) } ?? calendar.resumableTask
        let previous = before.map(WorkTaskReference.init)
        let resumes = calendar.resumableTask?.id == task.id
        let running = calendar.activeSession?.id
        guard calendar.start(task: task, now: now), let session = calendar.activeSession else {
            fail(calendar.notice ?? "Work could not be started.")
            return false
        }
        haptics.play(.impact)
        // Already running: nothing started, so there's nothing to take back.
        guard session.id != running else { return true }
        let sessionID = session.id
        let text = "\(resumes ? "Resumed" : "Started") “\(task.displayTitle)”"
        let offered = Date.now
        offerToScene(text, sessionID: sessionID) { [weak self] in
            self?.undoStart(sessionID, of: task, previous: previous, offered: offered)
        }
        return true
    }

    /// How long a start can be taken back whole. After it, Undo only stops
    /// the work: the time recorded in it stays.
    static let startUndoWindow: TimeInterval = 10 * 60

    /// Work already running when the app opened on a review session's
    /// fixture, taken as this session's latest step, so Activity offers its
    /// Undo as the design draws it.
    func adoptStart(of session: WorkSession, task: Block) {
        let sessionID = session.id
        let offered = Date.now
        offerToScene("Started “\(task.displayTitle)”", sessionID: sessionID) { [weak self] in
            self?.undoStart(sessionID, of: task, previous: nil, offered: offered)
        }
    }

    /// Takes a start back: stops the work, deletes the session it made, and
    /// hands resuming back to the work before it. Past `startUndoWindow` it
    /// only stops the work, so time worked is never deleted.
    private func undoStart(_ sessionID: UUID, of task: Block, previous: WorkTaskReference?, offered: Date) {
        if calendar.activeSession?.id == sessionID { calendar.pause(reason: "Undone", now: clock.now) }
        guard Date.now.timeIntervalSince(offered) <= Self.startUndoWindow else {
            latest = nil
            haptics.play(.soft)
            afterUndo?()
            return
        }
        if let made = store.workSessions(taskID: task.id).first(where: { $0.id == sessionID }) {
            store.context.delete(made)
            store.save()
        }
        calendar.dismissResume()
        if let previous { calendar.restoreResume(previous) }
        calendar.replan(now: clock.now)
        latest = nil
        haptics.play(.soft)
        afterUndo?()
    }

    // MARK: Today

    /// Today only includes tasks in active source lists, including their
    /// ancestors. Rows use the current library snapshot; commits recheck the
    /// live store so an archive or deletion arriving during a swipe wins.
    func canAddToToday(_ task: Block, hierarchy: ListHierarchy? = nil) -> Bool {
        guard task.isTask, !task.isDeleted, task.trashID == nil, !task.isCompleted, !isClosing(task.id),
              let listID = task.listID else { return false }
        return (hierarchy ?? store.listHierarchy()).activeIDs.contains(listID)
    }

    /// Adds an open task to the Today set without changing its due date.
    /// Repeating a full swipe never removes it, and Undo restores membership.
    func addToToday(_ task: Block) {
        guard canAddToToday(task) else { return }
        let now = clock.now
        // A second swipe leaves the original Undo available.
        guard !task.isPlanned(on: now, calendar: settings.calendar) else { return }
        edit([task], "Added “\(task.displayTitle)” to Today", icon: "sun.max") { [store] in
            store.selectForToday($0, now: now)
        }
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
        // What each entry said about where it came from and when, which Undo
        // gives back, so it returns to Trash as it was rather than as new.
        var metadata: [UUID: Data] = [:]
        for id in ids {
            if let data = store.blockIncludingTrash(id: id)?.trashMetadataData { metadata[id] = data }
        }
        for list in Self.trashedLists(in: store) where ids.contains(list.id) {
            if let data = list.trashMetadataData { metadata[list.id] = data }
        }
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
                for (id, data) in metadata {
                    if let block = store.blockIncludingTrash(id: id), block.trashID != nil { block.trashMetadataData = data }
                    if let list = PhoneActions.trashedLists(in: store).first(where: { $0.id == id }) { list.trashMetadataData = data }
                }
                store.save()
            }
        }
        changes.endUndoGrouping()
        report(restoredLabel(ids), icon: "arrow.uturn.backward", tone: .success, changes: changes)
        return true
    }

    /// Lists in Trash, which `store.list(id:)` doesn't find.
    private static func trashedLists(in store: Store) -> [TaskList] {
        (try? store.context.fetch(FetchDescriptor<TaskList>(predicate: #Predicate { $0.trashID != nil }))) ?? []
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

    // MARK: Lists

    /// A new list: "Created “Garden”" with Undo, which takes it back out
    /// while nothing has been put in it. Each new list gets the next colour.
    @discardableResult
    func createList(named title: String, under parent: TaskList? = nil) -> TaskList? {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let accents: [ListAccent] = [.violet, .green, .amber, .blue, .pink, .teal, .orange, .indigo]
        let count = store.allLists(includeArchived: true).count { !$0.isSystemInbox }
        let list: TaskList
        if let parent {
            guard let child = store.createChildList(in: parent) else {
                fail(store.persistenceError ?? "That list could not be made here.")
                return nil
            }
            store.rename(child, to: name)
            list = child
        } else {
            list = store.createList(title: name, icon: "📋", accent: accents[count % accents.count])
        }
        let id = list.id
        let changes = Self.makeUndoManager()
        changes.beginUndoGrouping()
        changes.registerUndo(withTarget: store) { store in
            MainActor.assumeIsolated { _ = store.discardCreatedList(id: id) }
        }
        changes.endUndoGrouping()
        report("Created “\(name)”", icon: "plus.square", tone: .accent, changes: changes)
        return list
    }

    func rename(_ list: TaskList, to title: String) {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let old = list.title
        guard !name.isEmpty, name != old else { return }
        perform("Renamed to “\(name)”", icon: "pencil", tone: .accent) { [store] changes in
            store.rename(list, to: name)
            changes.registerUndo(withTarget: store) { store in MainActor.assumeIsolated { store.rename(list, to: old) } }
            return true
        }
    }

    func setArchived(_ archived: Bool, for list: TaskList) {
        let title = list.displayTitle
        perform(archived ? "Archived “\(title)”" : "Unarchived “\(title)”", icon: "archivebox", tone: .accent) { [store] changes in
            store.setArchived(archived, for: list)
            changes.registerUndo(withTarget: store) { store in
                MainActor.assumeIsolated { store.setArchived(!archived, for: list) }
            }
            return true
        }
    }

    /// Moves a list to Trash with everything in it: "Moved “X” to Trash",
    /// with Undo, which puts it back.
    @discardableResult
    func trashList(_ list: TaskList) -> Bool {
        let id = list.id
        store.trashError = nil
        return perform("Moved “\(list.displayTitle)” to Trash", icon: "trash", tone: .danger) { [store] changes in
            guard store.trashList(list) else { return false }
            changes.registerUndo(withTarget: store) { store in
                MainActor.assumeIsolated { _ = store.restoreTrashRecoveries(ids: [id]) }
            }
            return true
        } failure: { [store] in
            store.trashError ?? "That list could not be moved to Trash."
        }
    }

    // MARK: Capture

    /// A capture saved: "Added to Inbox" with Undo, which takes the task back
    /// out as though it was never typed.
    func reportCapture(_ block: Block) {
        reportCapture([block])
    }

    /// Tasks captured together, by voice or Siri: one tray and one Undo for all.
    func reportCapture(_ blocks: [Block]) {
        guard !blocks.isEmpty else { return }
        let ids = blocks.map(\.id)
        let lists = Set(blocks.map(\.listID))
        let place = lists.count == 1 ? store.list(id: blocks[0].listID)?.displayTitle ?? "Inbox" : "\(lists.count) lists"
        let changes = Self.makeUndoManager()
        changes.beginUndoGrouping()
        changes.registerUndo(withTarget: store) { store in
            MainActor.assumeIsolated {
                for id in ids.reversed() { _ = store.discardCapturedTask(id: id) }
            }
        }
        changes.endUndoGrouping()
        report(blocks.count == 1 ? "Added to \(place)" : "Added \(blocks.count) tasks to \(place)",
               icon: "plus.circle", tone: .accent, changes: changes)
        haptics.play(.success)
    }

    // MARK: Planning

    /// Puts each task in the first free quarter hour of its list's hours, clear
    /// of meetings and everything else the calendar shows, as the Mac's Plan
    /// does: in place of any slot the task had, with "Planned “X” · Today
    /// 11:45" and Undo, which puts the old slots back. Returns how many found
    /// a slot.
    @discardableResult
    func fit(_ tasks: [Block]) -> Int {
        let now = clock.now
        let dates = settings.calendar
        let open = tasks.filter { $0.isTask && !$0.isCompleted && $0.trashID == nil && !closing.contains($0.id) }
        guard !open.isEmpty else { return 0 }
        let meetings = calendar.externalCalendars.busyTimes.map { DateInterval(start: $0.start, end: $0.end) }
        var claimed: [DateInterval] = []
        /// A slot's times, to put back.
        typealias Slot = (start: Date, end: Date, isPinned: Bool)
        var replaced: [UUID: [Slot]] = [:]
        var placed: [(task: Block, placement: SchedulePlacement)] = []
        for task in open {
            let minutes = planMinutes(for: task)
            let list = store.list(id: task.listID)
            let category = list.flatMap { AvailabilityCategory(rawValue: $0.availabilityCategoryRaw) } ?? .work
            // Around everything but the task's own blocks, which it's leaving.
            let others = calendar.visibleBlocks.filter { $0.taskID != task.id && $0.end > $0.start }
                .map { DateInterval(start: $0.start, end: $0.end) }
            let slot = CalendarWeek.slot(duration: TimeInterval(minutes * 60), deferredUntil: task.deferredUntil,
                                         category: category, preferences: calendar.preferences,
                                         busy: meetings + others + claimed, now: now, calendar: dates)
            guard case let .found(interval) = slot else { continue }
            let old = store.placements(taskID: task.id).filter { $0.occurrenceID == task.occurrenceID }
            replaced[task.id] = old.map { ($0.start, $0.end, $0.isPinned) }
            for placement in old { store.removePlacement(placement) }
            guard let placement = store.setPlacement(for: task, start: interval.start, end: interval.end, isPinned: true)
            else { continue }
            claimed.append(interval)
            placed.append((task, placement))
        }
        calendar.replan(now: now)
        guard let first = placed.first else {
            fail(open.count == 1 ? "No free slot this week — try a shorter estimate" : "No free slots this week")
            return 0
        }
        let changes = Self.makeUndoManager()
        let ids = placed.map(\.placement.id)
        let tasks = placed.map(\.task)
        changes.beginUndoGrouping()
        changes.registerUndo(withTarget: store) { [calendar, clock] store in
            MainActor.assumeIsolated {
                for placement in store.placements() where ids.contains(placement.id) { store.removePlacement(placement) }
                for task in tasks {
                    for slot in replaced[task.id] ?? [] {
                        store.setPlacement(for: task, start: slot.start, end: slot.end, isPinned: slot.isPinned)
                    }
                }
                calendar.replan(now: clock.now)
            }
        }
        changes.endUndoGrouping()
        let start = first.placement.start
        let day = CompactText.dayOffset(from: now, to: start, calendar: dates) == 0 ? "Today" : CompactText.day(start, now: now, calendar: dates)
        let text = placed.count == 1
            ? "Planned “\(first.task.displayTitle)” · \(day) \(CompactText.clock(start, calendar: dates))"
            : "Planned \(placed.count) tasks"
        report(text, icon: "calendar", tone: .accent, changes: changes)
        return placed.count
    }

    /// A new estimate, which the task's current or next slot follows: it keeps
    /// its start and ends that long after, "10:00–11:35" for 95 min. Direct,
    /// as the Mac's stepper is, with no tray.
    func setEstimate(_ minutes: Int, for task: Block) {
        store.setTaskEstimate(minutes, for: task)
        let now = clock.now
        guard let slot = store.placements(taskID: task.id)
            .filter({ $0.occurrenceID == task.occurrenceID && $0.end > now })
            .min(by: { $0.start < $1.start }) else { return }
        store.setPlacement(for: task, start: slot.start, end: slot.start.addingTimeInterval(TimeInterval(minutes * 60)),
                           isPinned: slot.isPinned, placementID: slot.id)
        calendar.replan(now: now)
    }

    /// Takes the task's occurrence off the calendar, every slot it has there,
    /// with Undo. False when it had none.
    @discardableResult
    func unplace(_ task: Block) -> Bool {
        let placements = store.placements(taskID: task.id).filter { $0.occurrenceID == task.occurrenceID }
        guard !placements.isEmpty else { return false }
        let saved = placements.map { (start: $0.start, end: $0.end, isPinned: $0.isPinned) }
        return perform("Took “\(task.displayTitle)” off the calendar", icon: "calendar", tone: .accent) { [store, calendar, clock] changes in
            for placement in placements { store.removePlacement(placement) }
            calendar.replan(now: clock.now)
            changes.registerUndo(withTarget: store) { store in
                MainActor.assumeIsolated {
                    for slot in saved { store.setPlacement(for: task, start: slot.start, end: slot.end, isPinned: slot.isPinned) }
                    calendar.replan(now: clock.now)
                }
            }
            return true
        }
    }

    /// How long a slot for `task` runs: its estimate, else the calendar's
    /// default.
    func planMinutes(for task: Block) -> Int {
        task.schedulingEstimateMinutes > 0 ? task.schedulingEstimateMinutes : max(5, Int(calendar.preferences.defaultEstimateMinutes))
    }

    /// Puts a task on the calendar at `start`, pinned, as a drop on the
    /// timeline does. A dragged slot (`placementID`) moves alone, keeping its
    /// length; a task dropped from the row gets its estimate, in place of the
    /// occurrence's slots, or moves its one slot. Undo puts them back.
    @discardableResult
    func place(_ task: Block, at start: Date, placementID: UUID? = nil) -> Bool {
        guard task.isTask, !task.isCompleted, task.trashID == nil, !closing.contains(task.id) else { return false }
        let all = store.placements(taskID: task.id).filter { $0.occurrenceID == task.occurrenceID }
        let dragged = all.filter { $0.id == placementID }
        let old = dragged.isEmpty ? all : dragged
        let length = dragged.first.map { $0.end.timeIntervalSince($0.start) } ?? TimeInterval(planMinutes(for: task) * 60)
        let end = start.addingTimeInterval(length)
        if old.count == 1, old[0].start == start, old[0].end == end, old[0].isPinned { return false }
        let saved = old.map { (id: $0.id, start: $0.start, end: $0.end, isPinned: $0.isPinned) }
        let dates = settings.calendar
        let now = clock.now
        let day = CompactText.dayOffset(from: now, to: start, calendar: dates) == 0 ? "Today" : CompactText.day(start, now: now, calendar: dates)
        let text = "Planned “\(task.displayTitle)” · \(day) \(CompactText.clock(start, calendar: dates))"
        return perform(text, icon: "calendar", tone: .accent) { [store, calendar, clock] changes in
            // One slot moves, keeping its identity; several give way to one.
            let moved = old.count == 1 ? old[0].id : nil
            for placement in old where placement.id != moved { store.removePlacement(placement) }
            guard let placement = store.setPlacement(for: task, start: start, end: end, isPinned: true, placementID: moved) else {
                return false
            }
            let placed = placement.id
            calendar.replan(now: clock.now)
            changes.registerUndo(withTarget: store) { store in
                MainActor.assumeIsolated {
                    for placement in store.placements(taskID: task.id) where placement.id == placed && placed != moved {
                        store.removePlacement(placement)
                    }
                    for slot in saved {
                        store.setPlacement(for: task, start: slot.start, end: slot.end, isPinned: slot.isPinned,
                                           placementID: slot.id == moved ? moved : nil)
                    }
                    calendar.replan(now: clock.now)
                }
            }
            return true
        } failure: {
            "“\(task.displayTitle)” could not be planned there."
        }
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

    /// Moves tasks to a day, or clears their date: "“X” due tomorrow" with Undo.
    /// A timed task keeps its clock when only the day is given.
    func schedule(_ tasks: [Block], on date: Date?, includesTime: Bool? = nil, label: String? = nil) {
        let open = tasks.filter { $0.isTask && !$0.isCompleted }
        guard !open.isEmpty else { return }
        let now = clock.now
        let calendar = settings.calendar
        let what = open.count == 1 ? "“\(open[0].displayTitle)”" : "\(open.count) tasks"
        let text = label ?? date.map { "\(what) due \(CompactText.day($0, now: now, calendar: calendar).lowercasedDay)" }
            ?? "Cleared the date of \(what)"
        edit(open, text, icon: "calendar") { task in setDue(date, includesTime: includesTime, for: task) }
    }

    /// Gives a task a day, or clears it. A timed task keeps its clock when
    /// only the day is given.
    private func setDue(_ date: Date?, includesTime: Bool?, for task: Block) {
        guard var day = date else { return store.setDueDate(nil, for: task) }
        let timed = includesTime ?? task.includesTime
        if includesTime == nil, timed, let due = task.dueDate {
            let clock = settings.calendar.dateComponents([.hour, .minute], from: due)
            day = settings.calendar.date(bySettingHour: clock.hour ?? 9, minute: clock.minute ?? 0, second: 0, of: day) ?? day
        }
        store.setDueDate(day, includesTime: timed, for: task)
    }

    /// Files a task from triage in one step: into `list` and due `date`,
    /// either or both, "Moved “X” to Home, due tomorrow" with one Undo.
    @discardableResult
    func file(_ task: Block, to list: TaskList?, due date: Date?, includesTime: Bool? = nil) -> Bool {
        guard task.isTask, !task.isCompleted, task.trashID == nil else { return false }
        let moves = list.map { $0.id != task.listID } ?? false
        guard moves || date != nil else { return false }
        NotificationCenter.default.post(name: .commitPendingEditorDrafts, object: nil)
        cancelClosing([task.id])
        let now = clock.now
        let day = date.map { "due \(CompactText.day($0, now: now, calendar: settings.calendar).lowercasedDay)" }
        let text = if moves, let list {
            ["Moved “\(task.displayTitle)” to \(list.displayTitle)", day].compactMap(\.self).joined(separator: ", ")
        } else {
            "“\(task.displayTitle)” \(day ?? "")"
        }
        var failure = "“\(task.displayTitle)” could not be filed."
        return perform(text, icon: moves ? "arrow.right.circle" : "calendar", tone: .accent) { [store] changes in
            if moves, let list {
                do {
                    guard try !store.moveSelection([task.id], to: list.id, undoManager: changes).isEmpty else { return false }
                } catch {
                    failure = store.actionError ?? "That could not be moved. \(error.localizedDescription)"
                    return false
                }
            }
            if let date, let moved = store.block(id: task.id) {
                let before = TaskFields(moved)
                store.batch { setDue(date, includesTime: includesTime, for: moved) }
                registerRestore([before], over: [TaskFields(moved)], on: changes)
            }
            return true
        } failure: { failure }
    }

    /// Offers an action's undo to shake-to-undo as well, under its tray text.
    /// Taking it back from the tray first leaves this entry with nothing to do.
    private func offerToScene(_ name: String, sessionID: UUID? = nil, _ undo: @escaping () -> Void) {
        latest = LatestChange(text: name, at: .now, sessionID: sessionID, undo: undo)
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
        latest = nil
        // Its saved history is one change, as the step's was.
        store.withActivityBatch(UUID()) {
            while changes.canUndo { changes.undo() }
        }
        haptics.play(.soft)
        afterUndo?()
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
        /// The work the completion stopped, which Undo offers again.
        var resume: WorkTaskReference?

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

private extension String {
    /// "Today" and "Tomorrow" in a sentence; weekdays and dates keep their capitals.
    var lowercasedDay: String { self == "Today" || self == "Tomorrow" || self == "Yesterday" ? lowercased() : self }
}
