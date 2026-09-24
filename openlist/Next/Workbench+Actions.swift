//
//  Workbench+Actions.swift
//  openlist
//

import AppKit
import Foundation
import Observation
import SwiftUI

/// The fields a design action can change, captured so Undo can put them back.
private struct TaskFields {
    var id: UUID
    var dueDate: Date?
    var includesTime: Bool
    var reminderAt: Date?
    var isStarred: Bool
    var priorityRaw: Int
    var labelIDs: [UUID]
    var selectedForDay: Date?
    var deferredUntil: Date?
    var estimate: Int

    init(_ block: Block) {
        id = block.id
        dueDate = block.dueDate
        includesTime = block.includesTime
        reminderAt = block.reminderAt
        isStarred = block.isStarred
        priorityRaw = block.priorityRaw
        labelIDs = block.labelIDs
        selectedForDay = block.selectedForDay
        deferredUntil = block.deferredUntil
        estimate = block.schedulingEstimateMinutes
    }

    func apply(to block: Block) {
        block.dueDate = dueDate
        block.includesTime = includesTime
        block.reminderAt = reminderAt
        block.isStarred = isStarred
        block.priorityRaw = priorityRaw
        block.labelIDs = labelIDs
        block.selectedForDay = selectedForDay
        block.deferredUntil = deferredUntil
        block.schedulingEstimateMinutes = estimate
        block.touch()
    }
}

/// A calendar placement, kept by value so Undo and Redo can rebuild a task's set.
private struct PlacementSpan {
    var start: Date
    var end: Date
    var isPinned: Bool
}

/// What Undo erased of a new task or list, shared with the Redo that brings it back.
private final class CreationUndo {
    var task: BackupBlock?
    var list: BackupTaskList?
}

extension Workbench {
    func describe(_ tasks: [Block]) -> String {
        tasks.count == 1 ? NXFormat.quoted(tasks[0].displayTitle) : "\(tasks.count) tasks"
    }

    func route(for list: TaskList) -> AppRoute { list.isSystemInbox ? .inbox : .list(list.id) }

    /// Mutates tasks through the Store, then registers an Undo that restores the fields.
    private func edit(_ tasks: [Block], label: String, icon: String, tone: TrayTone,
                      chip: Bool = true, _ change: (Block) -> Void) {
        // After the list document's line being written, as its own step.
        document?.commitLine()
        let before = tasks.map(TaskFields.init)
        // One save for the whole selection, not one per task.
        store.batch { for task in tasks { change(task) } }
        let after = tasks.compactMap { store.block(id: $0.id) }.map(TaskFields.init)
        registerUndo(label, undo: { $0.restore(before) }, redo: { $0.restore(after) })
        snap(label, icon: icon, tone: tone, ids: tasks.map(\.id))
        if chip { flash(\.freshChip, tasks.map(\.id), for: 700) }
    }

    private func restore(_ fields: [TaskFields]) {
        for field in fields {
            guard let block = store.block(id: field.id) else { continue }
            field.apply(to: block)
            store.scheduleReminderIfNeeded(for: block)
        }
        store.save()
        markRestored(fields.map(\.id))
    }

    // MARK: Completion

    func toggle(_ id: UUID) {
        document?.commitLine()
        guard let task = store.block(id: id) else { return }
        if closing[id] != nil { cancelClosing([id]) }
        else if task.isCompleted { reopen(id) }
        else { complete([id]) }
    }

    /// Task › Complete / Reopen (⌘D): reopens the tasks when every one is done,
    /// else completes the open ones. E only completes, as in the design.
    func toggleCompletion(_ ids: [UUID]) {
        let tasks = tasks(ids)
        guard !tasks.isEmpty else { return }
        if tasks.allSatisfy(\.isCompleted) { reopen(tasks.map(\.id)) }
        else { complete(tasks.filter { !$0.isCompleted }.map(\.id)) }
    }

    /// Completes `ids` and their open subtasks, which close with them, as the
    /// design's complete does. `settleNow` writes the completion without the
    /// dwell, for a tick made outside the window, like a widget's, whose reload
    /// must already see the task done. `date` is when the tick was made.
    func complete(_ ids: [UUID], settleNow: Bool = false, at date: Date? = nil, clearsSelection: Bool = true) {
        document?.commitLine()
        let candidates = tasks(withSubtasksOf: ids, openOnly: true).filter { !$0.isCompleted && closing[$0.id] == nil }
        guard !candidates.isEmpty else { return }
        if let session = calendar.activeSession, candidates.contains(where: { $0.id == session.taskID }) {
            calendar.pause(reason: "Completed")
        }
        // Finished work leaves the notch now, not once the dwell settles. The
        // batch keeps it, so Undo offers it again.
        let resume = calendar.resumableTask.flatMap { paused in
            candidates.contains { $0.id == paused.id } ? WorkTaskReference(paused) : nil
        }
        if let paused = calendar.resumeTaskID, candidates.contains(where: { $0.id == paused }) {
            calendar.dismissResume()
        }
        // Named for what closes and what rolls: a repeat resets its subtasks
        // for its next date rather than closing them.
        var rolled: [UUID] = []
        beginClosing(candidates, resuming: resume, settleNow: settleNow, at: date) { rolls, closes in
            rolled = rolls.map(\.id)
            let count = rolls.count + closes.count
            if count > 1 { return "\(count) tasks done" }
            if let roll = rolls.first { return "\(NXFormat.quoted(roll.displayTitle)) rolls to \(NXFormat.dueLabel(roll.dueDate))" }
            return describe(closes) + " done"
        }
        if !rolled.isEmpty { flash(\.freshChip, rolled, for: 900) }
        if clearsSelection { selection = [] }
    }

    func reopen(_ id: UUID) { reopen([id]) }

    /// Reopens through the Store's bulk path, whose Undo restores each task's
    /// completion exactly instead of completing it afresh.
    func reopen(_ ids: [UUID]) {
        document?.commitLine()
        let tasks = tasks(ids).filter(\.isCompleted)
        guard !tasks.isEmpty else { return }
        let label = "Reopened \(describe(tasks))"
        completionLabel = label
        do {
            try store.setBulkCompletion(false, ids: tasks.map(\.id))
        } catch {
            completionLabel = nil
            showTray(error.localizedDescription, icon: "exclamationmark.triangle", tone: .red)
            return
        }
        completionLabel = nil
        snap(label, icon: "arrow.uturn.backward", tone: .neutral, ids: tasks.map(\.id))
        markRestored(tasks.map(\.id))
    }

    /// Routes the Store's completion Undo onto this window, named after the design
    /// action, or onto the batch a completion is writing.
    func installCompletionUndo() {
        store.onCompletionUndoAvailable = { [weak self] action in
            guard let self, let manager = self.completionUndoTarget ?? self.undoManager else { return }
            self.store.registerCompletionUndo(action, with: manager)
            if let label = self.completionLabel { manager.setActionName(label) }
            self.bumpUndo()
        }
    }

    // MARK: Dates & flags

    func schedule(_ ids: [UUID], offset: Int?) {
        let tasks = tasks(ids)
        guard !tasks.isEmpty else { return }
        let label = offset == nil ? "Cleared date on \(describe(tasks))"
            : "\(describe(tasks)) → \(NXFormat.dueLabel(NXFormat.day(offset: offset!)))"
        edit(tasks, label: label, icon: "calendar", tone: .accent) { task in
            guard let offset else { store.setDueDate(nil, for: task); return }
            let due = dueDate(for: task, offset: offset)
            store.setDueDate(due.date, includesTime: due.includesTime, for: task)
        }
        selection = []
    }

    /// `task` moved to the day `offset` from today. A timed task keeps its time
    /// of day, as the design moves `due` and leaves `time` alone.
    private func dueDate(for task: Block, offset: Int) -> (date: Date, includesTime: Bool) {
        let day = NXFormat.day(offset: offset)
        guard task.includesTime, let due = task.dueDate else { return (day, false) }
        return (NXFormat.day(day, at: due), true)
    }

    func star(_ ids: [UUID]) {
        let tasks = tasks(ids)
        guard !tasks.isEmpty else { return }
        let on = !tasks.allSatisfy(\.isStarred)
        edit(tasks, label: (on ? "Starred " : "Unstarred ") + describe(tasks), icon: "star.fill", tone: .amber) { task in
            if task.isStarred != on { store.toggleStar(task) }
        }
    }

    func isPlanned(_ task: Block) -> Bool {
        task.selectedForDay.map { Calendar.current.startOfDay(for: $0) <= Calendar.current.startOfDay(for: .now) } ?? false
    }

    func plan(_ ids: [UUID]) {
        let tasks = tasks(ids).filter { !$0.isCompleted }
        guard !tasks.isEmpty else { return }
        let on = !tasks.allSatisfy(isPlanned)
        edit(tasks, label: (on ? "Planned for today: " : "Unplanned: ") + describe(tasks),
             icon: "calendar.badge.clock", tone: .accent) { task in
            if on { store.selectForToday(task) } else { store.deselectForToday(task) }
        }
        selection = []
    }

    func setPriority(_ id: UUID, _ priority: TaskPriority) {
        guard let task = store.block(id: id) else { return }
        let word = switch priority {
        case .none: "none"
        case .low: "low"
        case .medium: "medium"
        case .high: "high"
        }
        edit([task], label: "Priority \(word) · \(describe([task]))", icon: "flag.fill", tone: .red, chip: false) { task in
            store.setPriority(priority, for: task)
        }
    }

    func toggleLabel(_ id: UUID, labelID: UUID) {
        guard let task = store.block(id: id),
              let label = store.allLabels().first(where: { $0.id == labelID }) else { return }
        let has = task.labelIDs.contains(labelID)
        edit([task], label: (has ? "Removed #" : "Added #") + label.name + " · " + describe([task]),
             icon: "tag", tone: .accent) { task in
            store.toggleLabel(id: labelID, on: task)
        }
    }

    func setEstimate(_ id: UUID, delta: Int) {
        guard let task = store.block(id: id) else { return }
        let current = task.schedulingEstimateMinutes > 0 ? task.schedulingEstimateMinutes : defaultEstimate
        store.setTaskEstimate(min(240, max(5, current + delta)), for: task)
    }

    // MARK: Moving

    func move(_ ids: [UUID], to listID: UUID, quiet: Bool = false) {
        document?.commitLine()
        let tasks = tasks(ids)
        guard !tasks.isEmpty, let list = store.list(id: listID) else { return }
        let label = "Moved \(describe(tasks)) to \(list.displayTitle)"
        do {
            _ = try store.moveSelection(tasks.map(\.id), to: listID, undoManager: undoManager)
        } catch {
            showTray(error.localizedDescription, icon: "exclamationmark.triangle", tone: .red)
            return
        }
        undoManager?.setActionName(label)
        snap(label, icon: "folder", tone: .accent, ids: tasks.map(\.id),
             destination: quiet ? nil : TrayDestination(label: "Open \(list.displayTitle)", route: route(for: list)))
        flash(\.freshChip, tasks.map(\.id), for: 700)
        pulse(list: listID)
        selection = []
    }

    // MARK: Trash

    /// `ids`' tasks, each followed by the tasks nested under it in document
    /// order, once each.
    private func tasks(withSubtasksOf ids: [UUID], openOnly: Bool) -> [Block] {
        var indexes: [UUID: [UUID?: [Block]]] = [:]
        var seen = Set<UUID>()
        var result: [Block] = []
        func add(_ block: Block) {
            guard seen.insert(block.id).inserted else { return }
            if block.isTask { result.append(block) }
        }
        for root in ids.compactMap({ store.block(id: $0) }) {
            add(root)
            guard let listID = root.listID else { continue }
            let index = indexes[listID] ?? BlockTree.childIndex(of: store.blocks(inList: listID))
            indexes[listID] = index
            var stack = (index[root.id] ?? []).reversed().map { $0 }
            while let block = stack.popLast() {
                if !(openOnly && block.isTask && block.isCompleted) { add(block) }
                stack += (index[block.id] ?? []).reversed()
            }
        }
        return result
    }

    /// Moves `ids` to Trash with everything nested under them, as the
    /// design's trash does: their subtasks fly out and count with them.
    func trash(_ ids: [UUID]) {
        document?.commitLine()
        let roots = ids.compactMap { store.block(id: $0) }
        let subtasks = tasks(withSubtasksOf: ids, openOnly: false).filter { !ids.contains($0.id) }
        let tasks = roots + subtasks
        guard !tasks.isEmpty else { return }
        let taskIDs = tasks.map(\.id)
        // A row still in its dwell goes to Trash instead of completing.
        cancelClosing(taskIDs, restoresWork: false)
        // The Undo the tray offers is on the stack from the start; the rows fly
        // out before the Store writes the trash.
        beginTrash(taskIDs, label: "Moved \(describe(tasks)) to Trash")
        selection = []
        focusID = nil
        if let open = navigator.openTaskID, taskIDs.contains(open) { navigator.closeTask() }
    }

    func restore(_ entry: TrashEntry) {
        let title = entry.metadata?.listTitle ?? "its list"
        let label = "Restored \(NXFormat.quoted(entry.title)) to \(title)"
        withAnimation(style.ease(300)) { _ = flying.insert(entry.id) }
        let delay = Int(ms(300))
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(delay))
            guard let self else { return }
            self.flying.remove(entry.id)
            guard self.store.restoreTrash(ids: [entry.id]) else {
                self.showTray(self.store.trashError ?? "This item could not be restored.", icon: "exclamationmark.triangle", tone: .red)
                return
            }
            let restoredList = self.store.block(id: entry.id).flatMap { self.store.list(id: $0.listID) }
                ?? (entry.isList ? self.store.list(id: entry.id) : nil)
            let destination = restoredList.map { TrayDestination(label: "Open \($0.displayTitle)", route: self.route(for: $0)) }
            let text = restoredList.map {
                let place = $0.isEffectivelyArchived ? "archived list \($0.displayTitle)" : $0.displayTitle
                return "Restored \(NXFormat.quoted(entry.title)) to \(place)"
            } ?? label
            if entry.isList {
                self.snap(text, icon: "arrow.uturn.backward.circle", tone: .accent, ids: [entry.id],
                          undoable: false, destination: destination)
            } else {
                self.snapRestore(text, id: entry.id, icon: "arrow.uturn.backward.circle", tone: .accent, destination: destination)
            }
            self.markRestored([entry.id])
        }
    }

    func erase(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        guard store.permanentlyEraseTrash(ids: ids) else {
            showTray(store.trashError ?? "These items could not be erased.", icon: "exclamationmark.triangle", tone: .red)
            return
        }
        forgetErasedTrashes()
        showTray(ids.count > 1 ? "Erased \(ids.count) items for good" : "Erased for good", icon: "trash.slash", tone: .red)
    }

    // MARK: Lists

    func createList() {
        let section = store.defaultSection()
        let list = makeUntitledList(in: section)
        let id = list.id
        let label = "Created “Untitled list” in \(section?.displayTitle ?? "Lists")"
        registerListCreationUndo(label, listID: id)
        snap(label, icon: "plus.circle.fill", tone: .accent, ids: [])
        pulse(list: id)
        namingListID = id
        go(.list(id))
    }

    /// Undo takes a new list back with no Trash entry while it's still empty,
    /// and Redo brings back the same list. Once it holds anything it goes to
    /// Trash instead, so nothing added to it is lost.
    func registerListCreationUndo(_ label: String, listID id: UUID) {
        let taken = CreationUndo()
        registerUndo(label, undo: { workbench in
            let store = workbench.store
            if let list = store.discardCreatedList(id: id) {
                taken.list = list
            } else if let list = store.list(id: id) {
                _ = store.trashList(list)
            }
        }, redo: { workbench in
            if let list = taken.list {
                taken.list = nil
                _ = workbench.store.restoreDiscardedList(list)
            } else {
                _ = workbench.store.restoreTrash(ids: [id])
            }
        })
    }

    /// The hours Plan and Start working use for a list's tasks.
    func hours(for list: TaskList) -> AvailabilityCategory {
        AvailabilityCategory(rawValue: list.availabilityCategoryRaw) ?? .work
    }

    func setHours(_ category: AvailabilityCategory, for listID: UUID) {
        guard let list = store.list(id: listID) else { return }
        let previous = hours(for: list)
        guard previous != category else { return }
        let apply: @MainActor (Workbench, AvailabilityCategory) -> Void = { workbench, category in
            guard let list = workbench.store.list(id: listID) else { return }
            workbench.store.setAvailabilityCategory(category.rawValue, for: list)
            workbench.calendar.storeDidChange()
        }
        apply(self, category)
        let label = "“\(list.displayTitle)” uses \(category.title) hours"
        registerUndo(label, undo: { apply($0, previous) }, redo: { apply($0, category) })
        snap(label, icon: "clock", tone: .accent, ids: [])
    }

    // MARK: Capture

    // Reading and saving the draft (`captureParse`, `capturePreview`,
    // `saveCapture`) is `NXCaptureDraft`'s, shared with the Quick Add panel.

    @discardableResult
    func createFromCapture(keepOpen: Bool) -> Block? {
        let parse = captureParse()
        guard !parse.title.isEmpty else { return nil }
        let destinationID = captureListID ?? store.inboxList()?.id
        // Captured into the list on show, a task goes at the end of its
        // document, where the add row sits; anywhere else it's prepended.
        let appendsToRoot = navigator.documentListID.map { $0 == destinationID } ?? false
        let block: Block
        do {
            block = try saveCapture(parse, appendToRoot: appendsToRoot)
        } catch {
            showTray(error.localizedDescription, icon: "exclamationmark.triangle", tone: .red)
            return nil
        }
        let list = store.list(id: block.listID)
        let here: Bool = {
            switch navigator.route {
            case .inbox: list?.isSystemInbox == true
            case let .list(id): id == block.listID
            case .today: block.isDueOnOrBeforeToday || isPlanned(block)
            case let .label(id): block.labelIDs.contains(id)
            case .tasks: true
            default: false
            }
        }()
        let name = list?.displayTitle ?? "Inbox"
        registerCreationUndo("Added to \(name)", taskID: block.id)
        snap("Added to \(name)", icon: "plus.circle.fill", tone: .accent, ids: [block.id],
             destination: here || list == nil ? nil : TrayDestination(label: "Show", route: route(for: list!)))
        flash(\.fresh, [block.id], for: 1200)
        pulse(list: block.listID)
        // At the end of the document on show, under a folded last heading, it opens.
        if appendsToRoot, document?.document.listID == block.listID { document?.unfold(toShow: block.id) }
        if keepOpen { captureText = "" } else { closeCapture() }
        return block
    }

    /// Undo takes a capture back as though it was never added: no Trash
    /// entry, reminder or history. Redo brings back the same task. One that
    /// has since gained subtasks, files, a plan or work goes to Trash instead,
    /// so nothing added to it is lost. The closures keep the id, never the model.
    private func registerCreationUndo(_ label: String, taskID id: UUID) {
        let taken = CreationUndo()
        registerUndo(label, undo: { workbench in
            let store = workbench.store
            if let task = store.discardCapturedTask(id: id) {
                taken.task = task
            } else if let block = store.block(id: id) {
                _ = store.trashBlocks([block])
            }
        }, redo: { workbench in
            if let task = taken.task {
                taken.task = nil
                _ = workbench.store.restoreDiscardedTask(task)
            } else {
                _ = workbench.store.restoreTrash(ids: [id])
            }
        })
    }

    /// Opens capture for the current screen. `forToday: true` makes an undated
    /// task due today; otherwise Today and the New tasks setting decide. On a
    /// label screen the task gets that label.
    func openCapture(text: String = "", listID: UUID? = nil, forToday: Bool? = nil) {
        if case let .list(id) = navigator.route { captureListID = listID ?? id }
        else { captureListID = listID ?? store.inboxList()?.id }
        captureForToday = forToday == true || navigator.route == .today || settings.defaultDestination == .today
        if case let .label(id) = navigator.route { captureLabelID = id } else { captureLabelID = nil }
        captureText = text
        navigator.isCommandPaletteOpen = false
        navigator.isSearchOpen = false
        withAnimation(style.spring(260)) { captureOpen = true }
    }

    func closeCapture() {
        withAnimation(style.ease(180)) { captureOpen = false }
        captureText = ""
    }

    // MARK: Inbox triage

    func triage(_ task: Block, action: TriageExit, listID: UUID? = nil, offset: Int? = nil) {
        guard triageExit == nil else { return }
        withAnimation(style.standard(230)) { triageExit = action }
        let id = task.id
        let delay = Int(ms(230))
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(delay))
            guard let self, let task = self.store.block(id: id) else { self?.triageExit = nil; return }
            let logged = self.latestBatch
            // Whether the card stays in Inbox, so the stack has to skip it.
            var keeps = false
            switch action {
            case .left:
                if let listID { self.move([id], to: listID) }
            case .up:
                let label = "\(NXFormat.quoted(task.displayTitle)) → \(NXFormat.dueLabel(NXFormat.day(offset: offset ?? 0))) · still in Inbox"
                self.edit([task], label: label, icon: "calendar", tone: .accent) { task in
                    let due = self.dueDate(for: task, offset: offset ?? 0)
                    self.store.setDueDate(due.date, includesTime: due.includesTime, for: task)
                }
                keeps = true
            case .right:
                self.snap("Kept \(NXFormat.quoted(task.displayTitle)) for later", icon: "clock", tone: .neutral, ids: [id])
                keeps = true
            case .done:
                // A repeat rolls to its next date and stays in Inbox.
                keeps = task.recurrence != nil
                // Triaging the card leaves the rows' selection alone, as in the
                // design; complete() on its own clears it.
                let selection = self.selection
                self.complete([id])
                self.selection = selection.subtracting([id])
            case .down:
                let label = "Discarded \(NXFormat.quoted(task.displayTitle))"
                if self.store.trashBlocks([task], undoManager: self.undoManager) {
                    self.undoManager?.setActionName(label)
                    self.snap(label, icon: "trash", tone: .red, ids: [id],
                              destination: TrayDestination(label: "Open Trash", route: .trash))
                }
            }
            // Only a change that happened counts; a refused one leaves the card on top.
            if self.latestBatch != logged, let label = self.log.first?.label {
                self.review(id, keeps: keeps, label: label)
            }
            withAnimation(self.style.spring(320)) { self.triageExit = nil }
        }
    }

    /// Counts a triaged card, in the same Undo entry as the change it made.
    private func review(_ id: UUID, keeps: Bool, label: String) {
        let wasKept = kept.contains(id)
        if keeps { kept.insert(id) }
        reviewed += 1
        registerUndo(label, undo: { workbench in
            if keeps && !wasKept { workbench.kept.remove(id) }
            workbench.reviewed = max(0, workbench.reviewed - 1)
        }, redo: { workbench in
            if keeps { workbench.kept.insert(id) }
            workbench.reviewed += 1
        })
    }

    // MARK: Calendar

    /// The earliest free slot inside the list's hours, avoiding busy time: in
    /// the week the Calendar shows, or in the week from a deferral past it.
    func fit(_ id: UUID) {
        guard let task = store.block(id: id), !task.isCompleted else { return }
        let minutes = task.schedulingEstimateMinutes > 0 ? task.schedulingEstimateMinutes : defaultEstimate
        let duration = TimeInterval(minutes * 60)
        let cal = settings.calendar
        let now = Date.now
        let category = store.list(id: task.listID).map { hours(for: $0) } ?? .work
        // Around meetings and whatever the calendar shows for other tasks:
        // their placements, running work and done blocks.
        var busy: [(Date, Date)] = calendar.externalCalendars.busyTimes.map { ($0.start, $0.end) }
        busy += calendar.visibleBlocks.filter { $0.taskID != id }.map { ($0.start, $0.end) }
        let quarter = TimeInterval(15 * 60)
        // On a quarter hour, not before a deferral, and only inside the list's hours:
        // the scheduler's windows already leave out breaks, overrides and days off,
        // and follow the wall clock across DST.
        let from = max(now, task.deferredUntil ?? now)
        let earliest = Date(timeIntervalSinceReferenceDate: (from.timeIntervalSinceReferenceDate / quarter).rounded(.up) * quarter)
        // As far as the Week view's last day, as the design's Plan, so the block
        // is never out of sight; a deferral past it gets a week of its own.
        let shown = CalendarWeek.span(from: now, calendar: cal)
        let inShownWeek = earliest < shown.end
        let weekEnd = inShownWeek ? shown.end : cal.date(byAdding: .day, value: 7, to: cal.startOfDay(for: earliest)) ?? earliest
        let windows = AdaptiveScheduler.availabilityIntervals(for: category, preferences: calendar.preferences,
                                                              from: earliest, to: weekEnd, calendar: cal)
        for window in windows {
            var start = window.start
            while start.addingTimeInterval(duration) <= window.end {
                let end = start.addingTimeInterval(duration)
                if !busy.contains(where: { start < $0.1 && $0.0 < end }) {
                    place(task, start: start, end: end, dayOffset: NXFormat.dayOffset(start, now: now))
                    return
                }
                start = start.addingTimeInterval(quarter)
            }
        }
        let week = inShownWeek ? "this week" : "in the week from \(NXFormat.dueLabel(from))"
        showTray("No free slot \(week) — try a shorter estimate", icon: "calendar.badge.exclamationmark", tone: .neutral)
    }

    /// The tasks the Calendar gives a block, which "Not planned yet" and
    /// Today's Fit into calendar leave out.
    func placedTaskIDs(now: Date = .now) -> Set<UUID> {
        CalendarWeek.placedTaskIDs(calendar.visibleBlocks, now: now, calendar: settings.calendar)
    }

    private func place(_ task: Block, start: Date, end: Date, dayOffset: Int) {
        guard task.isTask, !task.isCompleted, end > start else { return }
        let id = task.id
        let occurrenceID = task.occurrenceID
        let fields = [TaskFields(task)]
        let previous = store.placements(taskID: id).filter { $0.occurrenceID == occurrenceID }
            .map { PlacementSpan(start: $0.start, end: $0.end, isPinned: $0.isPinned) }
        let planned = [PlacementSpan(start: start, end: end, isPinned: true)]
        setPlacements(of: id, occurrenceID: occurrenceID, to: planned)
        let label = "Planned \(NXFormat.quoted(task.displayTitle)) · \(dayOffset == 0 ? "Today" : NXFormat.dueLabel(start)) \(NXFormat.clock(start))"
        // Both directions rebuild the occurrence's whole placement set, so any
        // number of Undo and Redo steps leaves exactly one set.
        registerUndo(label, undo: { workbench in
            workbench.setPlacements(of: id, occurrenceID: occurrenceID, to: previous)
            workbench.restore(fields)
            workbench.calendar.replan()
        }, redo: { workbench in
            workbench.setPlacements(of: id, occurrenceID: occurrenceID, to: planned)
            workbench.calendar.replan()
        })
        snap(label, icon: "sparkles", tone: .accent, ids: [id],
             destination: navigator.route == .calendar ? nil : TrayDestination(label: "Show", route: .calendar))
        flashBlock(id)
        calendar.replan()
    }

    /// Replaces the occurrence's placements with `spans`, in one save.
    private func setPlacements(of id: UUID, occurrenceID: UUID, to spans: [PlacementSpan]) {
        guard let task = store.block(id: id), task.occurrenceID == occurrenceID else { return }
        store.batch {
            for placement in store.placements(taskID: id) where placement.occurrenceID == occurrenceID {
                store.removePlacement(placement)
            }
            for span in spans { store.setPlacement(for: task, start: span.start, end: span.end, isPinned: span.isPinned) }
        }
    }

    /// A done block's check. Reopens its task in the slots the block took, as
    /// one Undo step, so it turns open (or missed) where it was drawn instead
    /// of leaving the calendar. A repeat that has moved on stays done.
    func reopen(block: PlannedBlock) {
        guard let completionID = block.completionID, let task = store.block(id: block.taskID),
              task.isCompleted, task.occurrenceID == block.occurrenceID else { return }
        let id = task.id
        let spans = calendar.visibleBlocks.filter { $0.completionID == completionID && $0.end > $0.start }
            .map { PlacementSpan(start: $0.start, end: $0.end, isPinned: true) }
        reopen(id)
        // Reopening gives the task a new occurrence, with no slot of its own yet.
        guard let reopened = store.block(id: id), !reopened.isCompleted, !spans.isEmpty else { return }
        let occurrenceID = reopened.occurrenceID
        let fields = [TaskFields(reopened)]
        setPlacements(of: id, occurrenceID: occurrenceID, to: spans)
        // Grouped with the reopen, so Undo takes the slots back before the task closes again.
        registerUndo("Reopened \(describe([reopened]))", undo: { workbench in
            workbench.setPlacements(of: id, occurrenceID: occurrenceID, to: [])
            workbench.restore(fields)
            workbench.calendar.replan()
        }, redo: { workbench in
            workbench.setPlacements(of: id, occurrenceID: occurrenceID, to: spans)
            workbench.calendar.replan()
        })
        calendar.replan()
    }

    /// Starts recording `id` now, as the design's Start working does: outside
    /// the list's hours and during busy time too. Other running work is
    /// replaced, and the work watch reports the switch with Undo.
    func startWork(_ id: UUID) {
        guard let task = store.block(id: id) else { return }
        if !calendar.start(task: task) { reportStartFailure() }
    }

    /// Shows why work did not start: saving failed, or the task or its list went away.
    private func reportStartFailure() {
        showTray(calendar.notice ?? "Work could not be started.", icon: "calendar.badge.exclamationmark", tone: .neutral)
        calendar.notice = nil
    }

    /// The task shown in the work notch: the running session, or paused work that
    /// can still resume, whoever paused it — you, time away from the Mac, or
    /// Openlist quitting.
    var workTask: Block? {
        if let session = calendar.activeSession { return store.block(id: session.taskID) }
        return calendar.resumableTask
    }

    var isWorkPaused: Bool { calendar.activeSession == nil && workTask != nil }

    /// Time recorded on the notch's task occurrence, across every pause and
    /// however each session was started.
    func workElapsed(at now: Date = .now) -> Double {
        guard let task = workTask else { return 0 }
        return calendar.trackedMinutes(for: task, now: now) * 60
    }

    func toggleWorkPause() {
        if calendar.activeSession != nil {
            calendar.pause(reason: "Paused")
            reportPauseFailure()
        } else if let task = workTask, !calendar.start(task: task) {
            reportStartFailure()
        }
    }

    func finishWork() {
        guard let task = workTask else { return }
        complete([task.id])
    }

    func stopWork() {
        guard let task = workTask else { return }
        if calendar.activeSession != nil {
            calendar.stopWorking()
            guard !reportPauseFailure() else { return }
        }
        let seconds = calendar.trackedMinutes(for: task) * 60
        calendar.dismissResume()
        showTray("Stopped — \(NXFormat.mmss(seconds)) recorded", icon: "timer", tone: .neutral)
    }

    /// Shows why the running work could not be paused. True while it still runs.
    @discardableResult
    private func reportPauseFailure() -> Bool {
        guard calendar.activeSession != nil else { return false }
        showTray(calendar.notice ?? "Work could not be paused. Try again.", icon: "calendar.badge.exclamationmark", tone: .red)
        calendar.notice = nil
        return true
    }

    // MARK: Work watch

    /// Follows the running work so what happens to it reaches the tray, from
    /// whichever surface started it: a switch from other work, a pause the
    /// calendar made, work it paused when Openlist last quit, extra time along
    /// with the tasks moved for it, and a fixed event it ran into. Runs from
    /// init, then again after each change it sees.
    func watchWork() {
        let seen = withObservationTracking {
            // Also follows whatever decides that an Undo entry about the work still applies.
            (taskID: calendar.activeSession?.taskID, notice: calendar.notice, grant: calendar.workExtension,
             conflict: calendar.workConflict, moved: calendar.rescheduleSummary?.id,
             undos: workUndos.map { $0.applies(self) })
        } onChange: { [weak self] in
            Task { @MainActor in self?.watchWork() }
        }
        let last = workWatch
        workWatch = (seen.taskID, seen.notice, seen.grant, seen.conflict, seen.moved)
        pruneWorkUndos()
        if let running = seen.taskID, let previous = last.taskID, running != previous {
            announceSwitch(from: previous, to: running)
        }
        if let grant = seen.grant, grant != last.grant { announceExtension(grant) }
        if let conflict = seen.conflict, conflict != last.conflict { announceConflict(conflict) }
        // The Work panel's move summary lasts a minute after a move, not until the next one.
        if let moved = seen.moved, moved != last.moved {
            after(60_000, key: "rescheduled") { workbench in
                if workbench.calendar.rescheduleSummary?.id == moved { workbench.calendar.dismissRescheduleSummary() }
            }
        }
        if seen.taskID != nil {
            awayPause = nil
            awaitsLaunchNotice = false
            return
        }
        // A pause made by hand leaves no new notice; one the calendar made says why.
        let notice = seen.notice != last.notice ? seen.notice : nil
        // The calendar's first notice after launch says why work that was running
        // when Openlist quit comes back paused.
        if awaitsLaunchNotice, let notice {
            awaitsLaunchNotice = false
            if last.taskID == nil, !calendar.isWorkPanelPresented, calendar.resumableTask != nil {
                showPauseTray(notice)
                return
            }
        }
        // The Work panel shows its own notice. The calendar's notice stays set:
        // the panel and the toolbar's VoiceOver announcement read it too.
        guard let running = last.taskID, !calendar.isWorkPanelPresented,
              let task = calendar.resumableTask, task.id == running, let notice else { return }
        // Told again when you come back to the Mac: a lock or sleep pauses work
        // just as you leave, while the tray is still up.
        awayPause = (task.id, notice, nil)
        showPauseTray(notice)
    }

    /// The Mac reports you back. Work the calendar paused while you were away
    /// says why again: waking, the screen and unlocking each report, so for a
    /// few minutes after the first.
    func macDidReturn() {
        guard var away = awayPause else { return }
        let now = Date.now
        guard calendar.activeSession == nil, calendar.resumableTask?.id == away.taskID,
              now.timeIntervalSince(away.returnedAt ?? now) < 300 else {
            awayPause = nil
            return
        }
        if away.returnedAt == nil {
            away.returnedAt = now
            awayPause = away
        }
        guard !calendar.isWorkPanelPresented else { return }
        showPauseTray(away.text)
    }

    private func showPauseTray(_ text: String) {
        showTray(text, icon: "calendar.badge.exclamationmark", tone: .amber,
                 destination: navigator.route == .calendar ? nil : TrayDestination(label: "Show", route: .calendar))
    }

    /// Reports work that replaced other running work. Undo switches back, and
    /// the time recorded in between stays on the task it was recorded on. The
    /// entry lasts while the work it would switch away from still runs.
    private func announceSwitch(from previousID: UUID, to currentID: UUID) {
        guard let previous = store.block(id: previousID), let current = store.block(id: currentID) else { return }
        let seconds = calendar.trackedMinutes(for: previous) * 60
        let label = "Switched to \(NXFormat.quoted(current.displayTitle)) — \(NXFormat.mmss(seconds)) recorded on \(NXFormat.quoted(previous.displayTitle))"
        let from = WorkTaskReference(previous)
        let to = WorkTaskReference(current)
        let entry = WorkUndo { $0.canSwitchWork(from: to, to: from) }
        registerUndo(label, owner: entry, undo: { workbench in
            guard workbench.canSwitchWork(from: to, to: from), workbench.switchWork(to: from) else { workbench.dropStale(entry); return }
            entry.applies = { $0.canSwitchWork(from: from, to: to) }
        }, redo: { workbench in
            guard workbench.canSwitchWork(from: from, to: to), workbench.switchWork(to: to) else { workbench.dropStale(entry); return }
            entry.applies = { $0.canSwitchWork(from: to, to: from) }
        })
        snap(label, icon: "arrow.left.arrow.right", tone: .neutral, ids: [currentID, previousID], owner: entry)
        workUndos.append(entry)
    }

    /// Whether `current` is still the running work and `target` can take over.
    private func canSwitchWork(from current: WorkTaskReference, to target: WorkTaskReference) -> Bool {
        calendar.activeSession?.occurrenceID == current.occurrenceID && calendar.validWorkTask(target) != nil
    }

    /// Undo and Redo of a switch: work on `reference` again, which the watch
    /// then sees as the work it already knows rather than another switch.
    private func switchWork(to reference: WorkTaskReference) -> Bool {
        guard let task = calendar.validWorkTask(reference), calendar.start(task: task) else { return false }
        workWatch.taskID = task.id
        return true
    }

    /// Reports extra time the calendar gave the running work. Undo puts back the
    /// block it had and those of the tasks moved for it; work keeps recording.
    /// The entry lasts while that session runs and keeps the extension.
    private func announceExtension(_ grant: CalendarWorkExtension) {
        guard let task = store.block(id: grant.taskID) else { return }
        let moved = grant.movedTaskIDs.count
        let label = "Extended \(NXFormat.quoted(task.displayTitle)) to \(NXFormat.clock(grant.end))"
            + (moved == 0 ? "" : " · moved \(moved) \(moved == 1 ? "task" : "tasks")")
        let entry = WorkUndo { $0.calendar.canUndoExtension(grant) }
        // Either way the watch already knows the extension it lands on.
        registerUndo(label, owner: entry, undo: { workbench in
            guard workbench.calendar.undoExtension(grant) else { workbench.dropStale(entry); return }
            workbench.workWatch.grant = workbench.calendar.workExtension
            entry.applies = { $0.calendar.canRedoExtension(grant) }
        }, redo: { workbench in
            guard workbench.calendar.redoExtension(grant) else { workbench.dropStale(entry); return }
            workbench.workWatch.grant = grant
            entry.applies = { $0.calendar.canUndoExtension(grant) }
        })
        snap(label, icon: "calendar.badge.plus", tone: .amber, ids: [grant.taskID] + grant.movedTaskIDs,
             destination: navigator.route == .calendar ? nil : TrayDestination(label: "Show", route: .calendar), owner: entry)
        workUndos.append(entry)
    }

    /// Takes Undo entries about the running work off the stack once it has moved
    /// on, so Undo never claims to take back what it no longer can.
    private func pruneWorkUndos() {
        let stale = workUndos.filter { !$0.applies(self) }
        guard !stale.isEmpty else { return }
        workUndos.removeAll { entry in stale.contains { $0 === entry } }
        for entry in stale { undoManager?.removeAllActions(withTarget: entry) }
        bumpUndo()
    }

    /// An entry that got past pruning and found nothing to take back. The tray
    /// says so in place of "Undid", and the entry leaves the stack once this
    /// Undo or Redo has finished.
    private func dropStale(_ entry: WorkUndo) {
        entry.applies = { _ in false }
        showTray("Nothing to undo — the plan has changed", icon: "arrow.uturn.backward", tone: .neutral)
        Task { @MainActor [weak self] in self?.pruneWorkUndos() }
    }

    /// Reports the meeting or break the running work ran into. It keeps recording.
    private func announceConflict(_ conflict: CalendarWorkConflict) {
        guard let task = store.block(id: conflict.taskID) else { return }
        showTray("\(NXFormat.quoted(task.displayTitle)) is running into \(conflictLabel(conflict, inSentence: true))",
                 icon: "calendar.badge.exclamationmark", tone: .red,
                 destination: navigator.route == .calendar ? nil : TrayDestination(label: "Show", route: .calendar))
    }

    /// What running work ran into and when, as the notch chip and the tray
    /// name it: "Standup at 09:30".
    func conflictLabel(_ conflict: CalendarWorkConflict, inSentence: Bool = false) -> String {
        "\(conflictName(conflict, inSentence: inSentence)) at \(NXFormat.clock(conflict.start))"
    }

    /// What running work ran into, for the working block's "runs into". As in
    /// the design, a meeting is named bare.
    func conflictName(_ conflict: CalendarWorkConflict, inSentence: Bool = false) -> String {
        switch conflict.kind {
        case .event: conflict.title.isEmpty ? (inSentence ? "busy time" : "Busy time") : conflict.title
        case .breakTime: inSentence ? "a break" : "Break"
        }
    }
}

/// An Undo entry about the running work, and the target its actions share, so
/// the work watch can take it off the stack once it no longer applies.
final class WorkUndo {
    /// Whether the entry's next Undo, or Redo once undone, can still do what it says.
    var applies: @MainActor (Workbench) -> Bool

    init(applies: @escaping @MainActor (Workbench) -> Bool) {
        self.applies = applies
    }
}
