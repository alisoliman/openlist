//
//  Workbench+Actions.swift
//  openlist
//

import AppKit
import Foundation
import Observation
import SwiftData
import SwiftUI

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

/// A deleted label, shared by the Undo that brings it back and the Redo that
/// deletes it again, each leaving what the other needs.
private final class LabelDeletion {
    var deleted: DeletedLabel
    /// The label the tasks carry once Undo has put it back.
    var labelID: UUID

    init(_ deleted: DeletedLabel) {
        self.deleted = deleted
        labelID = deleted.label.id
    }
}

/// A label merge, as Redo last made it, for the Undo after it.
private final class LabelMerge {
    var plan: LabelMergePlan
    init(_ plan: LabelMergePlan) { self.plan = plan }
}

/// A label Settings made: what Undo deleted of it, for the Redo that brings
/// it back, and the id the Undo after that deletes.
private final class LabelCreation {
    var labelID: UUID
    var deleted: DeletedLabel?
    init(_ labelID: UUID) { self.labelID = labelID }
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
        registerUndo(label, undo: { $0.restore(before, over: after) }, redo: { $0.restore(after, over: before) })
        snap(label, icon: icon, tone: tone, ids: tasks.map(\.id))
        if chip { flash(\.freshChip, tasks.map(\.id), for: 700) }
    }

    /// Puts back `fields` where they differ from `replaced`, as the step being
    /// undone or redone left them, so only what the step changed goes back.
    private func restore(_ fields: [TaskFields], over replaced: [TaskFields]) {
        for field in fields {
            guard let block = store.block(id: field.id) else { continue }
            field.apply(to: block, replacing: replaced.first { $0.id == field.id })
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

    /// Task › Mark as Done / Reopen (⌘D): reopens the tasks when every one is
    /// done or closing, taking the closing ones back as the row menu's Reopen
    /// does, else completes the open ones. E only completes, as in the design.
    func toggleCompletion(_ ids: [UUID]) {
        let tasks = tasks(ids)
        guard !tasks.isEmpty else { return }
        if tasks.allSatisfy(isDoneOrClosing) {
            let pending = tasks.filter { closing[$0.id] != nil }.map(\.id)
            if !pending.isEmpty { cancelClosing(pending) }
            reopen(tasks.filter(\.isCompleted).map(\.id))
        } else {
            complete(tasks.filter { !$0.isCompleted }.map(\.id))
        }
    }

    /// Whether a task counts as done for Reopen: completed, or in its dwell.
    func isDoneOrClosing(_ task: Block) -> Bool { task.isCompleted || closing[task.id] != nil }

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
            // Neither a batch writing nor a reopen naming it: the tick came from
            // outside Next's rows.
            let outside = self.completionUndoTarget == nil && self.completionLabel == nil
            self.store.registerCompletionUndo(action, with: manager)
            if let label = self.completionLabel { manager.setActionName(label) }
            self.bumpUndo()
            if outside { self.reportOutsideCompletion(action) }
        }
    }

    /// A completion or reopen from the menu bar, the calendar, a notification
    /// or MCP reports in the tray as the design's do, logged and named on the
    /// window entry just registered, so the tray's Undo takes it back.
    private func reportOutsideCompletion(_ action: CompletionUndoAction) {
        guard let change = store.completionUndoChanges[action.id], !isReported(action, change) else { return }
        let ids = [change.rootTaskID] + change.additionalRootTaskIDs
        let tasks = ids.compactMap { store.block(id: $0) }
        guard !tasks.isEmpty else { return }
        if action.isReopening {
            snap("Reopened \(describe(tasks))", icon: "arrow.uturn.backward", tone: .neutral, ids: ids)
        } else if tasks.count == 1, let task = tasks.first, !task.isCompleted {
            // A repeat that rolled on to its next date.
            snap("\(NXFormat.quoted(task.displayTitle)) rolls to \(NXFormat.dueLabel(task.dueDate))",
                 icon: "repeat", tone: .green, ids: ids)
        } else {
            snap(describe(tasks) + " done", icon: "checkmark.circle", tone: .green, ids: ids)
        }
        if let batch = latestBatch { outsideCompletionBatches.insert(batch) }
    }

    /// Whether the change log already holds this completion or reopen of the
    /// same tasks, as when one of Next's own is saved late. Next writes a
    /// completion once its dwell ends, so the Store's action arrives up to the
    /// dwell (plus the row stagger) after its entry. An outside completion's
    /// own report never counts: ticked, unticked and ticked again from the
    /// menu bar, the second tick reports too.
    private func isReported(_ action: CompletionUndoAction, _ change: CompletionUndoChange) -> Bool {
        let roots = Set([change.rootTaskID] + change.additionalRootTaskIDs)
        let window = style.dwell + 5 + Double(roots.count) * style.ms(75) / 1000
        let since = action.createdAt.addingTimeInterval(-window)
        // Newest first, so only the recent entries are read.
        return log.lazy.prefix { $0.at >= since }.contains { entry in
            guard let id = entry.taskID, roots.contains(id), !outsideCompletionBatches.contains(entry.batch) else { return false }
            return action.isReopening ? entry.icon == "arrow.uturn.backward" : entry.tone == .green
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
        edit(tasks, label: (on ? "Starred " : "Unstarred ") + describe(tasks), icon: "star", tone: .amber) { task in
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

    // The plan card's Clear, like its Defer work (`deferWork`, with the
    // calendar's slots below), is a native extra that changes what plan
    // does, so it snaps as plan does, with its tray, Undo and chip flash.

    /// "Deferred until …"'s Clear: the task stops waiting for that day; see
    /// `Store.clearDeferral`.
    func clearDeferral(_ id: UUID) {
        guard let task = store.block(id: id), task.isTask, task.deferredUntil != nil else { return }
        edit([task], label: "Cleared deferral on \(describe([task]))", icon: "arrow.uturn.forward", tone: .accent) { task in
            store.clearDeferral(task)
        }
    }

    func setPriority(_ id: UUID, _ priority: TaskPriority) {
        guard let task = store.block(id: id) else { return }
        let word = switch priority {
        case .none: "none"
        case .low: "low"
        case .medium: "medium"
        case .high: "high"
        }
        edit([task], label: "Priority \(word) · \(describe([task]))", icon: "flag", tone: .red, chip: false) { task in
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

    // The Schedule and label popovers are native extras; their changes go
    // through here like the design's pills, each with its tray and Undo.

    /// A day picked in the month, a time, or a typed phrase, which may also
    /// set the repeat. Named for where the task lands, as `schedule` is, and
    /// by the rule Changes names the saved change with after a relaunch.
    func setDue(_ id: UUID, date: Date, includesTime: Bool, recurrence: Recurrence? = nil) {
        guard let task = store.block(id: id), task.isTask else { return }
        var label = "\(describe([task])) → "
            + NXFormat.dueChange(date, includesTime: includesTime, from: task.dueDate, oldIncludesTime: task.includesTime)
        if let recurrence { label += " · \(recurrence.displayText)" }
        edit([task], label: label, icon: "calendar", tone: .accent) { task in
            store.setDueDate(date, includesTime: includesTime, for: task)
            if let recurrence { store.setRecurrence(recurrence, for: task) }
        }
    }

    func setReminder(_ id: UUID, at date: Date?) {
        guard let task = store.block(id: id), task.isTask, task.reminderAt != date else { return }
        let label = date.map { "Reminder \(NXFormat.dueLabel($0)) \(NXFormat.clock($0)) · \(describe([task]))" }
            ?? "Removed reminder · \(describe([task]))"
        edit([task], label: label, icon: "bell", tone: .accent) { task in
            store.setReminder(date, for: task)
        }
    }

    /// A repeat rule, or none. Choosing the rule the task already has changes nothing.
    func setRecurrence(_ id: UUID, _ rule: Recurrence?) {
        guard let task = store.block(id: id), task.isTask else { return }
        // Stored anchored to the due date, which a repeat without one gets today.
        let stored = rule?.anchored(to: task.dueDate ?? NXFormat.day(offset: 0))
        guard stored != task.recurrence || (rule != nil && task.dueDate == nil) else { return }
        let label = stored.map { rule in
            "Repeats \(rule.displayText.prefix(1).lowercased() + rule.displayText.dropFirst()) · \(describe([task]))"
        } ?? "Stopped repeating · \(describe([task]))"
        edit([task], label: label, icon: "repeat", tone: .accent) { task in
            store.setRecurrence(rule, for: task)
        }
    }

    /// The label picker's Return: adds the label named `name`, making it
    /// first when there's none. Undo takes back a label it made, while
    /// nothing else uses it, and Redo brings back the same one.
    func addLabel(named name: String, to id: UUID) {
        let name = TaskLabel.normalize(name)
        guard !name.isEmpty, let task = store.block(id: id), task.isTask else { return }
        if let existing = store.matchingLabels(named: name).first {
            if !task.labelIDs.contains(existing.id) { toggleLabel(id, labelID: existing.id) }
            return
        }
        document?.commitLine()
        let label = "Added #\(name) · \(describe([task]))"
        let add = {
            guard let created = self.store.findOrCreateLabel(named: name) else { return }
            self.store.addLabel(created, to: task)
        }
        guard let listID = task.listID else { add(); return }
        store.undoableEditorEdit(in: listID, name: label, undoManager: undoManager, includingNewLabels: true,
                                 didRegister: { self.snap(label, icon: "tag", tone: .accent, ids: [id]) }, add)
        flash(\.freshChip, [id], for: 700)
    }

    // MARK: Inspector text

    /// The inspector's title and note, written as the list document writes
    /// a line: one Undo step, logged with the design's name and no tray.
    /// `task` may be in Trash, where what was typed goes with it, no step.
    func setTitle(_ text: String, of task: Block) {
        guard task.text != text else { return }
        let label = "Edited \(NXFormat.quoted(text))"
        recordEdit(label, of: task) { store.setText(text, for: task) }
    }

    /// The design's note commit, for the list document's note and the
    /// inspector's alike: trailing space goes, an emptied note closes under
    /// its task, and a change is one step, logged.
    func setNote(_ note: String, of task: Block) {
        let note = Self.committedNote(note)
        if note.isEmpty { openNotes.remove(task.id) }
        guard task.note != note else { return }
        let label = "Edited note on \(describe([task]))"
        recordEdit(label, of: task) { store.setNote(note, for: task) }
    }

    /// A note as it's saved: without the space and line breaks it ends in.
    static func committedNote(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
    }

    private func recordEdit(_ label: String, of task: Block, _ change: () -> Void) {
        guard task.trashID == nil, let listID = task.listID else { return change() }
        let id = task.id
        store.undoableEditorEdit(in: listID, name: label, undoManager: undoManager,
                                 didRegister: { self.logEdit(label, ids: [id]) }, change)
    }

    func setEstimate(_ id: UUID, delta: Int) {
        guard let task = store.block(id: id) else { return }
        let current = task.schedulingEstimateMinutes > 0 ? task.schedulingEstimateMinutes : defaultEstimate
        store.setTaskEstimate(min(240, max(5, current + delta)), for: task)
    }

    // MARK: Files

    /// Files kept with a task in the inspector's Files, a native extra, as
    /// one change the tray can undo, as taking one off is: Undo takes them
    /// off again. Those that can't be read are named in one red card,
    /// however many, and only the files kept are counted; with none kept,
    /// nothing changes.
    func attachFiles(_ urls: [URL], to taskID: UUID) {
        guard !urls.isEmpty else { return }
        document?.commitLine()
        guard let task = store.block(id: taskID) else { return }
        var kept: [ImportedMedia] = []
        var failures: [(name: String, error: Error)] = []
        for url in urls {
            do { kept.append(try MediaStore.shared.importFile(at: url)) } catch { failures.append((url.lastPathComponent, error)) }
        }
        if let notice = NXFormat.attachFailures(failures) { store.actionError = notice }
        guard !kept.isEmpty else { return }
        let label = NXFormat.attached(kept.map(\.displayName), to: describe([task]))
        store.addAttachments(kept, to: task, name: label, undoManager: undoManager) {
            self.snap(label, icon: "paperclip", tone: .accent, ids: [taskID])
        }
    }

    /// A file taken off its task in the inspector's Files, a native extra, as
    /// one change the tray can undo, so nothing is lost there for good: Undo
    /// puts the file back, its bytes and all.
    func removeAttachment(_ attachment: Attachment) {
        guard attachment.modelContext != nil, !attachment.isDeleted else { return }
        document?.commitLine()
        let taskID = attachment.blockID
        let label = "Removed \(NXFormat.quoted(attachment.displayName))"
            + (store.block(id: taskID).map { " from \(describe([$0]))" } ?? "")
        store.removeAttachment(attachment, name: label, undoManager: undoManager) {
            self.snap(label, icon: "paperclip", tone: .red, ids: taskID.map { [$0] } ?? [])
        }
    }

    // MARK: Moving

    /// The design's move: the tasks go to the list, each keeping everything
    /// under it. `lines` takes any line, as a list document's grip drags one
    /// onto the sidebar, a heading or text too. As the design's move only
    /// sets the list, what's already in it stays where it is; with nothing
    /// left to move, only the design's tray shows, with no Undo to take. The
    /// tray names every row, as the design's does; only the rows that moved
    /// log it.
    func move(_ ids: [UUID], to listID: UUID, quiet: Bool = false, lines: Bool = false) {
        document?.commitLine()
        let blocks = lines ? ids.compactMap { store.block(id: $0) } : tasks(ids)
        guard !blocks.isEmpty, let list = store.list(id: listID) else { return }
        let moving = blocks.filter { $0.listID != listID }
        let label = "Moved \(describeMoved(blocks)) to \(list.displayTitle)"
        let destination = quiet ? nil : TrayDestination(label: "Open \(list.displayTitle)", route: route(for: list))
        if !moving.isEmpty {
            do {
                _ = try store.moveSelection(moving.map(\.id), to: listID, undoManager: undoManager)
            } catch {
                // A refusal that changed nothing passes in the tray; a move that
                // failed to save is the red card, as for one dragged in a list.
                if error is BulkActionError { store.refuse(error.localizedDescription) }
                else { store.actionError = error.localizedDescription }
                return
            }
            undoManager?.setActionName(label)
            snap(label, icon: "folder", tone: .accent, ids: moving.map(\.id), destination: destination)
        } else {
            showTray(label, icon: "folder", tone: .accent, destination: destination)
        }
        flash(\.freshChip, blocks.map(\.id), for: 700)
        pulse(list: listID)
        selection = []
    }

    /// A move's rows as its tray names them: tasks as `describe` does, and
    /// any other line by its text, or its kind where it has none.
    private func describeMoved(_ blocks: [Block]) -> String {
        if blocks.allSatisfy(\.isTask) { return describe(blocks) }
        guard blocks.count == 1, let block = blocks.first else { return "\(blocks.count) lines" }
        return NXFormat.quoted(block.kind.isVoid ? block.kind.title : block.displayTitle)
    }

    // MARK: Copies

    /// The task menu's Duplicate: a copy of the task and everything under it,
    /// right after it, as one change the tray can undo.
    func duplicate(_ id: UUID) {
        document?.commitLine()
        guard let task = store.block(id: id), task.isTask, let listID = task.listID else { return }
        let label = "Duplicated \(describe([task]))"
        var copyID: UUID?
        store.undoableEditorEdit(in: listID, name: label, undoManager: undoManager) {
            let copy = store.duplicateBlock(task)
            // A copy that failed leaves the original, and says why in a notice.
            if copy.id != task.id { copyID = copy.id }
        }
        guard let copyID else { return }
        announceCopy(label, copyID: copyID, listID: listID)
    }

    /// Use as Template…'s copy of a task: its subtasks, notes and files, reset
    /// to start again, right after it, as one change the tray can undo. The
    /// copy opens in the inspector, ready for a new date.
    func copyAsTemplate(_ id: UUID, keepingRecurrence: Bool) throws {
        document?.commitLine()
        guard let task = store.block(id: id), task.isTask, let listID = task.listID else { throw CopyError.unavailable }
        let label = "Copied \(describe([task])) as a template"
        let outcome = store.undoableEditorEdit(in: listID, name: label, undoManager: undoManager) {
            Result { try store.copyBlock(task, mode: .template(keepingRecurrence: keepingRecurrence)) }
        }
        let copyID = try outcome.get()
        announceCopy(label, copyID: copyID, listID: listID)
        navigator.openTask(copyID)
    }

    private func announceCopy(_ label: String, copyID: UUID, listID: UUID) {
        let list = store.list(id: listID)
        let here = list.map { navigator.route == route(for: $0) } ?? true
        snap(label, icon: "plus.square.on.square", tone: .accent, ids: [copyID],
             destination: here ? nil : list.map { TrayDestination(label: "Show", route: route(for: $0)) })
        flash(\.fresh, [copyID], for: 1200)
        pulse(list: listID)
    }

    /// The task menu's Copy Text: the task's text, as written, on the
    /// pasteboard, said in the tray as Copy Content and Subtasks says its own.
    func copyText(_ id: UUID) {
        guard let task = store.block(id: id) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(task.text, forType: .string)
        showTray("Copied \(describe([task]))", icon: "doc.on.clipboard")
    }

    /// The task menu's Copy Content and Subtasks: the task with everything
    /// under it, notes, formatting and files included, which Paste in a list
    /// document line with nothing selected puts back as lines after it, under
    /// the document's rules. Over a selection it goes in as its lines' text,
    /// and elsewhere as Markdown.
    func copyContent(_ id: UUID) {
        document?.commitLine()
        guard let task = store.block(id: id) else { return }
        do {
            try FragmentClipboard.copy([id], store: store)
            showTray("Copied \(describe([task])) with its subtasks", icon: "list.bullet.clipboard")
        } catch {
            // The red card, as for Copy as Markdown and a paste of it that fails.
            store.actionError = error.localizedDescription
        }
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
        // The Undo the tray offers is on the stack from the start, as a step of
        // its own after the line or inspector draft saved for it; the rows fly
        // out before the Store writes the trash.
        separateUndoStep()
        beginTrash(taskIDs, label: "Moved \(describe(tasks)) to Trash")
        selection = []
        focusID = nil
        if let open = navigator.openTaskID, taskIDs.contains(open) { navigator.closeTask() }
    }

    /// Trash's Restore, as the design's: the tray says where the entry goes
    /// back to the moment it's clicked, with Undo, and the row flies out.
    func restore(_ entry: TrashEntry) {
        let place = restoredPlace(of: entry)
        beginRestore(entry, label: place.text, destination: place.destination)
    }

    /// What the tray says of a restore about to be written, and where its
    /// Open goes, read from the entry as Trash holds it, as the Store will
    /// put it back: a task in its list, or in Recovered items once that
    /// list or the task it sat under is gone; a list under its parent, or at
    /// the top level once the parent is gone.
    private func restoredPlace(of entry: TrashEntry) -> (text: String, destination: TrayDestination?) {
        let id = entry.id
        let title = NXFormat.quoted(entry.title)
        if entry.isList {
            guard let list = try? store.context.fetch(FetchDescriptor<TaskList>(predicate: #Predicate { $0.id == id })).first
            else { return ("Restored \(title)", nil) }
            let place = store.restoredPlace(of: list, parentGone: list.parentListID.map { store.list(id: $0) == nil } ?? false)
            return (place.isEmpty ? "Restored \(title)" : "Restored \(title) \(place)",
                    TrayDestination(label: "Open \(list.displayTitle)", route: .list(id)))
        }
        guard let root = store.blockIncludingTrash(id: id) else {
            return ("Restored \(title) to \(entry.metadata?.listTitle ?? "its list")", nil)
        }
        let owner = store.list(id: root.listID)
        let parent = store.block(id: root.parentID)
        guard let owner, root.parentID == nil || parent?.listID == owner.id else {
            // Where it was, which Recovered items itself doesn't show.
            let from = entry.metadata.map { " — from \($0.formerLocation)" } ?? ""
            return ("Restored \(title) to Recovered items\(from)", nil)
        }
        let place = owner.isEffectivelyArchived ? "archived list \(owner.displayTitle)" : owner.displayTitle
        return ("Restored \(title) to \(place)", TrayDestination(label: "Open \(owner.displayTitle)", route: route(for: owner)))
    }

    func erase(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        guard store.permanentlyEraseTrash(ids: ids) else {
            // The shell's Trash notice says why; the tray only when the Store gave no reason.
            if store.trashError == nil {
                showTray("These items could not be erased.", icon: "exclamationmark.triangle", tone: .red)
            }
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
        snap(label, icon: "plus.circle", tone: .accent, ids: [id])
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

    /// A list's title renamed in place, in its header or the sidebar: one
    /// Undo step, logged as an edit is.
    func renameList(_ id: UUID, to title: String) {
        guard let list = store.list(id: id), list.title != title else { return }
        let previous = list.title
        let apply: @MainActor (Workbench, String) -> Void = { workbench, title in
            guard let list = workbench.store.list(id: id) else { return }
            workbench.store.rename(list, to: title)
        }
        apply(self, title)
        let label = "Renamed list to \(NXFormat.quoted(title))"
        registerUndo(label, undo: { apply($0, previous) }, redo: { apply($0, title) })
        logEdit(label, ids: [id])
    }

    /// A list's description, written under its title: one Undo step, logged.
    func setListDescription(_ id: UUID, to summary: String) {
        guard let list = store.list(id: id), list.summary != summary else { return }
        let previous = list.summary
        let apply: @MainActor (Workbench, String) -> Void = { workbench, summary in
            guard let list = workbench.store.list(id: id) else { return }
            workbench.store.setSummary(summary, for: list)
        }
        apply(self, summary)
        let label = "Edited description on \(NXFormat.quoted(list.displayTitle))"
        registerUndo(label, undo: { apply($0, previous) }, redo: { apply($0, summary) })
        logEdit(label, ids: [id])
    }

    // MARK: Labels

    /// Deletes a label from every task as one change, with Undo in the tray:
    /// it comes back where it was on the tasks that had it. Steps off the
    /// label's page first.
    func deleteLabel(_ label: TaskLabel) {
        document?.commitLine()
        let text = "Deleted #\(label.name)"
        if navigator.route == .label(label.id) { navigator.replace(with: .tasks) }
        guard let deleted = store.deleteLabel(label) else { return }
        let taken = LabelDeletion(deleted)
        snap(text, icon: "tag.slash", tone: .red, ids: Array(deleted.positions.keys), undo: { workbench in
            guard let id = workbench.store.restoreDeletedLabel(taken.deleted) else { return false }
            taken.labelID = id
            return true
        }, redo: { workbench in
            // Deleted again meanwhile, it's gone already.
            guard let label = workbench.store.label(id: taken.labelID) else { return true }
            if workbench.navigator.route == .label(label.id) { workbench.navigator.replace(with: .tasks) }
            guard let deleted = workbench.store.deleteLabel(label) else { return false }
            taken.deleted = deleted
            return true
        })
    }

    /// Settings' Merge labels as one change, with Undo in the tray and on ⌘Z
    /// rather than in a notice of its own, taken in turn with the window's
    /// other changes. Redo merges again from the labels as they are by then.
    func mergeLabels(_ plan: LabelMergePlan) throws {
        try store.mergeLabels(plan)
        let text = "Merged #\(plan.source.name) into #\(plan.destination.name)"
        let merged = LabelMerge(plan)
        snap(text, icon: "arrow.triangle.merge", tone: .accent, ids: [plan.destination.id], undo: { workbench in
            workbench.store.undoLabelMerge(merged.plan)
        }, redo: { workbench in
            let store = workbench.store
            do {
                let plan = try store.labelMergePlan(sourceID: merged.plan.source.id, destinationID: merged.plan.destination.id)
                try store.mergeLabels(plan)
                merged.plan = plan
                return true
            } catch {
                store.labelMaintenanceError = "The labels were not merged again. \(error.localizedDescription)"
                return false
            }
        })
    }

    /// Settings' Add: a label on nothing yet, as one change the tray can
    /// undo, which takes it off whatever has it by then. A name another
    /// label already has says so instead. True once the name is dealt with.
    @discardableResult
    func createLabel(named rawName: String) -> Bool {
        let name = TaskLabel.normalize(rawName)
        guard !name.isEmpty else { return false }
        if let existing = store.matchingLabels(named: name).first {
            showTray("#\(existing.name) already exists", icon: "tag", tone: .neutral)
            return true
        }
        guard let label = store.findOrCreateLabel(named: name) else { return false }
        store.save()
        let created = LabelCreation(label.id)
        snap("Created #\(label.name)", icon: "tag", tone: .accent, ids: [label.id], undo: { workbench in
            // Deleted meanwhile, it's gone already.
            guard let label = workbench.store.label(id: created.labelID) else { return true }
            if workbench.navigator.route == .label(label.id) { workbench.navigator.replace(with: .tasks) }
            guard let deleted = workbench.store.deleteLabel(label) else { return false }
            created.deleted = deleted
            return true
        }, redo: { workbench in
            guard let deleted = created.deleted else { return true }
            guard let id = workbench.store.restoreDeletedLabel(deleted) else { return false }
            created.labelID = id
            created.deleted = nil
            return true
        })
        return true
    }

    /// Settings' rename in place, which every task's #chip shows at once, as
    /// one change the tray can undo. Throws, changing nothing, when the
    /// Store refuses the name.
    func renameLabel(_ label: TaskLabel, to rawName: String) throws {
        let id = label.id
        let previous = label.name
        try store.renameLabel(id: id, to: rawName)
        guard let name = store.label(id: id)?.name, name != previous else { return }
        snap("Renamed #\(previous) to #\(name)", icon: "tag", tone: .accent, ids: [id], undo: { workbench in
            workbench.renameLabel(id: id, to: previous)
        }, redo: { workbench in
            workbench.renameLabel(id: id, to: name)
        })
    }

    /// Undo and Redo of a rename, which a label named so since refuses.
    private func renameLabel(id: UUID, to name: String) -> Bool {
        do {
            try store.renameLabel(id: id, to: name)
            return true
        } catch {
            store.labelMaintenanceError = "The label was not renamed. \(error.localizedDescription)"
            return false
        }
    }

    /// A label's colour dot in Settings, like a list's Icon & Colour…: each
    /// pick one change the tray can undo.
    func setLabelAccent(_ accent: ListAccent, for label: TaskLabel) {
        guard label.accent != accent else { return }
        let id = label.id
        let previous = label.accent
        let apply: @MainActor (Workbench, ListAccent) -> Void = { workbench, accent in
            guard let label = workbench.store.label(id: id) else { return }
            workbench.store.setAccent(accent, for: label)
        }
        apply(self, accent)
        let text = "#\(label.name) colour → \(accent.title)"
        registerUndo(text, undo: { apply($0, previous) }, redo: { apply($0, accent) })
        snap(text, icon: "paintpalette", tone: .accent, ids: [id])
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
        // The task goes at the end of its list's document, where the add row
        // sits, wherever it was captured from, as the design's does. A folded
        // heading it goes under opens, and folds again on Undo.
        let saved: (block: Block, opened: [UUID])
        do {
            saved = try saveCapture(parse)
        } catch {
            showTray(error.localizedDescription, icon: "exclamationmark.triangle", tone: .red)
            return nil
        }
        let block = saved.block
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
        registerCreationUndo("Added to \(name)", taskID: block.id, opened: saved.opened)
        snap("Added to \(name)", icon: "plus.circle", tone: .accent, ids: [block.id],
             destination: here || list == nil ? nil : TrayDestination(label: "Show", route: route(for: list!)))
        flash(\.fresh, [block.id], for: 1200)
        pulse(list: block.listID)
        // The document on show lets go of the rows it drew without the task.
        if navigator.documentListID == block.listID, document?.document.listID == block.listID {
            document?.unfold(toShow: block.id)
        }
        if keepOpen { captureText = "" } else { closeCapture() }
        return block
    }

    /// A task Quick Add saved, over this window or another app, taken in as
    /// the window's own capture is: a window Undo entry that takes it back and
    /// folds again the headings the capture `opened`, its line in Changes, and
    /// the fresh row and list pulse. Quick Add's card says what it added, so
    /// the tray stays down.
    func didQuickAdd(_ block: Block, opened: [UUID]) {
        let name = store.list(id: block.listID)?.displayTitle ?? "Inbox"
        let undoable = undoManager != nil
        if undoable { registerCreationUndo("Added to \(name)", taskID: block.id, opened: opened) }
        snap("Added to \(name)", icon: "plus.circle", tone: .accent, ids: [block.id], undoable: undoable, showsTray: false)
        flash(\.fresh, [block.id], for: 1200)
        pulse(list: block.listID)
    }

    /// Undo takes a capture back as though it was never added: no Trash
    /// entry, reminder or history. Redo brings back the same task. One that
    /// has since gained subtasks, files, a plan or work goes to Trash instead,
    /// so nothing added to it is lost. The headings the capture `opened`
    /// fold again, and open again on Redo. The closures keep the id, never the model.
    private func registerCreationUndo(_ label: String, taskID id: UUID, opened headings: [UUID] = []) {
        let taken = CreationUndo()
        let fold: @MainActor (Store, Bool) -> Void = { store, folded in
            for heading in headings.compactMap({ store.block(id: $0) }) where BlockTree.sectionLevel(of: heading.kind) != nil {
                store.setCollapsed(folded, for: heading)
            }
        }
        registerUndo(label, undo: { workbench in
            let store = workbench.store
            if let task = store.discardCapturedTask(id: id) {
                taken.task = task
            } else if let block = store.block(id: id) {
                _ = store.trashBlocks([block])
            }
            fold(store, true)
        }, redo: { workbench in
            if let task = taken.task {
                taken.task = nil
                _ = workbench.store.restoreDiscardedTask(task)
            } else {
                _ = workbench.store.restoreTrash(ids: [id])
            }
            fold(workbench.store, false)
        })
    }

    /// Opens capture for the current screen. `forToday: true` makes an undated
    /// task due today; otherwise Today and the New tasks setting decide. On a
    /// label screen the task gets that label. Nothing opens it again over its
    /// own draft, as in the design, whose keys stand down while it's open:
    /// File ▸ New Task… (⌘N) there keeps the text and destination typed.
    func openCapture(text: String = "", listID: UUID? = nil, forToday: Bool? = nil) {
        guard !captureOpen else { return }
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
    /// the week around today, or the next once this one has no hours left
    /// long enough, or in the week from a deferral past it.
    func fit(_ id: UUID) {
        guard let task = store.block(id: id), !task.isCompleted else { return }
        let minutes = task.schedulingEstimateMinutes > 0 ? task.schedulingEstimateMinutes : defaultEstimate
        let now = Date.now
        let category = store.list(id: task.listID).map { hours(for: $0) } ?? .work
        // Around meetings and whatever the calendar shows for other tasks:
        // their placements, running work and done blocks.
        let busy = calendar.externalCalendars.busyTimes.map { DateInterval(start: $0.start, end: $0.end) }
            + calendar.visibleBlocks.filter { $0.taskID != id && $0.end > $0.start }.map { DateInterval(start: $0.start, end: $0.end) }
        let slot = CalendarWeek.slot(duration: TimeInterval(minutes * 60), deferredUntil: task.deferredUntil, category: category,
                                     preferences: calendar.preferences, busy: busy, now: now, calendar: settings.calendar)
        switch slot {
        case let .found(slot):
            place(task, start: slot.start, end: slot.end, dayOffset: NXFormat.dayOffset(slot.start, now: now))
        case let .none(reach):
            let week = switch reach {
            case .thisWeek: "this week"
            case .nextWeek: "this week or next"
            case let .weekFrom(day): "in the week from \(NXFormat.dueLabel(day))"
            }
            showTray("No free slot \(week) — try a shorter estimate", icon: "calendar.badge.exclamationmark", tone: .neutral)
        }
    }

    /// The day the Calendar builds its range from at `now`: the anchor on the
    /// day it was set, else today.
    func calendarStart(now: Date) -> Date {
        CalendarWeek.start(anchor: calendarAnchor, setAt: calendarAnchorSetAt, now: now, calendar: settings.calendar)
    }

    /// Whether the Calendar's range at `now` has `day` in it.
    func calendarShows(_ day: Date, now: Date = .now) -> Bool {
        CalendarWeek.shows(day, count: calendarDays, from: calendarStart(now: now), calendar: settings.calendar)
    }

    /// Moves the Calendar's range to one that shows `day`, unless it does already.
    func revealOnCalendar(_ day: Date, now: Date = .now) {
        let cal = settings.calendar
        let anchor = CalendarWeek.anchor(revealing: day, anchor: calendarAnchor, setAt: calendarAnchorSetAt,
                                         count: calendarDays, now: now, calendar: cal)
        // The same anchor again needs setting only when the one there, set on
        // an earlier day, has lapsed.
        guard anchor != calendarAnchor || anchor != nil && !cal.isDate(calendarAnchorSetAt, inSameDayAs: now) else { return }
        calendarAnchor = anchor
    }

    /// Opens the Calendar on a range that shows `day`, whichever range it was
    /// stepped or moved to, so a tray's Show or a Work panel link lands on what
    /// it points at, as the design's Calendar, always around today, does.
    func showOnCalendar(_ day: Date = .now) {
        go(.calendar)
        revealOnCalendar(day)
    }

    /// Opens the Calendar on the day of the occurrence's slot, as a calendar
    /// nudge's click and the Work panel's View plan do: the one
    /// `CalendarWeek.nudgedDay` names.
    func showOnCalendar(slotOf taskID: UUID, occurrenceID: UUID) {
        showOnCalendar(CalendarWeek.nudgedDay(of: taskID, occurrenceID: occurrenceID, in: calendar.visibleBlocks,
                                              now: .now, calendar: settings.calendar))
    }

    /// The tasks the Calendar gives a block, which "Not planned yet" and
    /// Today's Fit into calendar leave out.
    func placedTaskIDs(now: Date = .now) -> Set<UUID> {
        CalendarWeek.placedTaskIDs(calendar.visibleBlocks, now: now, calendar: settings.calendar)
    }

    private func place(_ task: Block, start: Date, end: Date, dayOffset: Int) {
        guard task.isTask, !task.isCompleted, end > start else { return }
        let label = "Planned \(NXFormat.quoted(task.displayTitle)) · \(dayOffset == 0 ? "Today" : NXFormat.dueLabel(start)) \(NXFormat.clock(start))"
        replacePlacements(of: task, with: [PlacementSpan(start: start, end: end, isPinned: true)], label: label,
                          icon: "sparkles", showing: start)
    }

    /// The Work panel's Move planned time…: the block's slot, as long as it
    /// was, at `start`, one step with the tray and Undo as Plan's is. The
    /// occurrence's other slots stay where they are.
    func movePlacement(_ block: PlannedBlock, to start: Date) {
        guard let placementID = block.placementID, !block.isActive, let task = store.block(id: block.taskID),
              task.isTask, !task.isCompleted, task.occurrenceID == block.occurrenceID else { return }
        let placements = store.placements(taskID: task.id).filter { $0.occurrenceID == task.occurrenceID }
        guard let moved = placements.first(where: { $0.id == placementID }), moved.start != start else { return }
        let end = start.addingTimeInterval(moved.end.timeIntervalSince(moved.start))
        let spans = placements.map { placement in
            placement.id == placementID ? PlacementSpan(start: start, end: end, isPinned: true)
                : PlacementSpan(start: placement.start, end: placement.end, isPinned: placement.isPinned)
        }
        let label = "Moved \(NXFormat.quoted(task.displayTitle)) · \(NXFormat.dueLabel(start)) \(NXFormat.clock(start))"
        replacePlacements(of: task, with: spans, label: label, icon: "calendar", showing: start)
    }

    /// Puts the occurrence's placements at `spans` as one step, announced as
    /// `label` with Show off the Calendar, whose range moves to `start`.
    private func replacePlacements(of task: Block, with spans: [PlacementSpan], label: String, icon: String, showing start: Date) {
        let id = task.id
        let occurrenceID = task.occurrenceID
        let fields = [TaskFields(task)]
        let previous = store.placements(taskID: id).filter { $0.occurrenceID == occurrenceID }
            .map { PlacementSpan(start: $0.start, end: $0.end, isPinned: $0.isPinned) }
        setPlacements(of: id, occurrenceID: occurrenceID, to: spans)
        // Planning also selects the task for its day when no day is; Undo puts back only what it changed.
        let placed = store.block(id: id).map { [TaskFields($0)] } ?? fields
        // Both directions rebuild the occurrence's whole placement set, so any
        // number of Undo and Redo steps leaves exactly one set.
        registerUndo(label, undo: { workbench in
            workbench.setPlacements(of: id, occurrenceID: occurrenceID, to: previous)
            workbench.restore(fields, over: placed)
            workbench.calendar.replan()
        }, redo: { workbench in
            workbench.setPlacements(of: id, occurrenceID: occurrenceID, to: spans)
            workbench.calendar.replan()
        })
        // Show finds the block there even once the range has been stepped away.
        snap(label, icon: icon, tone: .accent, ids: [id],
             destination: navigator.route == .calendar ? nil : TrayDestination(label: "Show", route: .calendar, day: start))
        // A block past the days the Calendar shows, next week or after a
        // deferral, moves its range there, so the block is never out of sight.
        revealOnCalendar(start)
        flashBlock(id)
        calendar.replan()
    }

    /// The inspector's Defer work: the task's remaining work waits for `day`
    /// and its slots come off the calendar, one step with the tray and Undo.
    /// Work on it, running or paused, stops and leaves the notch; Undo puts
    /// the slots and the task's day back, and the work, paused, to resume.
    func deferWork(_ id: UUID, to day: Date) {
        // After the list document's line being written, as its own step.
        document?.commitLine()
        guard let task = store.block(id: id), task.isTask, !task.isCompleted else { return }
        let occurrenceID = task.occurrenceID
        let fields = [TaskFields(task)]
        let previous = store.placements(taskID: id).filter { $0.occurrenceID == occurrenceID }
            .map { PlacementSpan(start: $0.start, end: $0.end, isPinned: $0.isPinned) }
        let resume = calendar.deferTask(task: task, to: day)
        guard let deferred = store.block(id: id), deferred.deferredUntil != nil else { return }
        let after = [TaskFields(deferred)]
        let label = "Deferred \(NXFormat.quoted(task.displayTitle)) until \(NXFormat.dueLabel(day))"
        registerUndo(label, undo: { workbench in
            workbench.setPlacements(of: id, occurrenceID: occurrenceID, to: previous)
            workbench.restore(fields, over: after)
            // Offered again unless other work has taken the notch since.
            if let resume { workbench.calendar.restoreResume(resume) }
            workbench.calendar.replan()
        }, redo: { workbench in
            guard let task = workbench.store.block(id: id), task.occurrenceID == occurrenceID else { return }
            workbench.calendar.deferTask(task: task, to: day)
        })
        snap(label, icon: "arrow.uturn.forward", tone: .accent, ids: [id])
        // As plan's, the row's chips flash.
        flash(\.freshChip, [id], for: 700)
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
        let placed = store.block(id: id).map { [TaskFields($0)] } ?? fields
        // Grouped with the reopen, so Undo takes the slots back before the task closes again.
        registerUndo("Reopened \(describe([reopened]))", undo: { workbench in
            workbench.setPlacements(of: id, occurrenceID: occurrenceID, to: [])
            workbench.restore(fields, over: placed)
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
        showTray(text, icon: "calendar.badge.exclamationmark", tone: .amber, destination: workTrayDestination)
    }

    /// The Show of the trays about the running or paused work, which is
    /// today's: none on the Calendar, as the design's, while its range shows
    /// today, which the design's always does.
    private var workTrayDestination: TrayDestination? {
        navigator.route == .calendar && calendarShows(.now) ? nil : TrayDestination(label: "Show", route: .calendar)
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
    /// The entry lasts while that session runs and keeps the extension, and
    /// once the work stops, while the slot or tasks it moved are still where
    /// it left them.
    private func announceExtension(_ grant: CalendarWorkExtension) {
        guard let task = store.block(id: grant.taskID) else { return }
        let moved = grant.movedTaskIDs.count
        let label = "Extended \(NXFormat.quoted(task.displayTitle)) to \(NXFormat.clock(grant.end))"
            + (moved == 0 ? "" : " · moved \(moved) \(moved == 1 ? "task" : "tasks")")
        let entry = WorkUndo { $0.calendar.canUndoExtension(grant) }
        // Either way the watch already knows the extension it lands on: this
        // one, the one before it, or, once the work has stopped, whatever runs now.
        registerUndo(label, owner: entry, undo: { workbench in
            guard workbench.calendar.undoExtension(grant) else { workbench.dropStale(entry); return }
            workbench.workWatch.grant = workbench.calendar.workExtension
            entry.applies = { $0.calendar.canRedoExtension(grant) }
        }, redo: { workbench in
            guard workbench.calendar.redoExtension(grant) else { workbench.dropStale(entry); return }
            workbench.workWatch.grant = workbench.calendar.workExtension
            entry.applies = { $0.calendar.canUndoExtension(grant) }
        })
        snap(label, icon: "calendar.badge.plus", tone: .amber, ids: [grant.taskID] + grant.movedTaskIDs,
             destination: workTrayDestination, owner: entry)
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
                 icon: "calendar.badge.exclamationmark", tone: .red, destination: workTrayDestination)
    }

    /// What running work ran into and when, as the notch chip and the tray
    /// name it: "Standup at 09:30".
    func conflictLabel(_ conflict: CalendarWorkConflict, inSentence: Bool = false) -> String {
        "\(conflictName(conflict, inSentence: inSentence)) at \(NXFormat.clock(conflict.start))"
    }

    /// What running work ran into, for the working block's "runs into". As in
    /// the design, a meeting is named bare, and so is the midday break, Lunch.
    func conflictName(_ conflict: CalendarWorkConflict, inSentence: Bool = false) -> String {
        switch conflict.kind {
        case .event: conflict.title.isEmpty ? (inSentence ? "busy time" : "Busy time") : conflict.title
        case .breakTime: conflict.title.isEmpty ? (inSentence ? "a break" : "Break") : conflict.title
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
