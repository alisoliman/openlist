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

extension Workbench {
    func describe(_ tasks: [Block]) -> String {
        tasks.count == 1 ? NXFormat.quoted(tasks[0].displayTitle) : "\(tasks.count) tasks"
    }

    func route(for list: TaskList) -> AppRoute { list.isSystemInbox ? .inbox : .list(list.id) }

    /// Mutates tasks through the Store, then registers an Undo that restores the fields.
    private func edit(_ tasks: [Block], label: String, icon: String, tone: TrayTone,
                      chip: Bool = true, _ change: (Block) -> Void) {
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
        guard let task = store.block(id: id) else { return }
        if closing[id] != nil { cancelClosing([id]) }
        else if task.isCompleted { reopen(id) }
        else { complete([id]) }
    }

    /// E and ⌘↩: reopens the tasks when every one is done, else completes the open ones.
    func toggleCompletion(_ ids: [UUID]) {
        let tasks = tasks(ids)
        guard !tasks.isEmpty else { return }
        if tasks.allSatisfy(\.isCompleted) { reopen(tasks.map(\.id)) }
        else { complete(tasks.filter { !$0.isCompleted }.map(\.id)) }
    }

    func complete(_ ids: [UUID]) {
        let candidates = tasks(ids).filter { !$0.isCompleted && closing[$0.id] == nil }
        guard !candidates.isEmpty else { return }
        let rolls = candidates.filter { $0.recurrence != nil }
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
        beginClosing(candidates, resuming: resume) {
            if candidates.count > 1 { return "\(candidates.count) tasks done" }
            if rolls.isEmpty { return describe(candidates) + " done" }
            return "\(NXFormat.quoted(rolls[0].displayTitle)) rolls to \(NXFormat.dueLabel(rolls[0].dueDate))"
        }
        if !rolls.isEmpty { flash(\.freshChip, rolls.map(\.id), for: 900) }
        selection = []
    }

    func reopen(_ id: UUID) { reopen([id]) }

    /// Reopens through the Store's bulk path, whose Undo restores each task's
    /// completion exactly instead of completing it afresh.
    func reopen(_ ids: [UUID]) {
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
            store.setDueDate(offset.map { NXFormat.day(offset: $0) }, includesTime: false, for: task)
        }
        selection = []
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
        case .medium: "med"
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

    func trash(_ ids: [UUID]) {
        let tasks = ids.compactMap { store.block(id: $0) }
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
                self.showTray(self.store.trashNotice ?? "This item could not be restored.", icon: "exclamationmark.triangle", tone: .red)
                return
            }
            if !entry.isList {
                let id = entry.id
                self.registerUndo(label, undo: { workbench in
                    if let block = workbench.store.block(id: id) { _ = workbench.store.trashBlocks([block]) }
                }, redo: { workbench in
                    _ = workbench.store.restoreTrash(ids: [id])
                })
            }
            let restoredList = self.store.block(id: entry.id).flatMap { self.store.list(id: $0.listID) }
                ?? (entry.isList ? self.store.list(id: entry.id) : nil)
            let destination = restoredList.map { TrayDestination(label: "Open \($0.displayTitle)", route: self.route(for: $0)) }
            self.snap(restoredList.map {
                let place = $0.isEffectivelyArchived ? "archived list \($0.displayTitle)" : $0.displayTitle
                return "Restored \(NXFormat.quoted(entry.title)) to \(place)"
            } ?? label,
                      icon: "arrow.uturn.backward.circle", tone: .accent, ids: [entry.id],
                      undoable: !entry.isList, destination: destination)
            self.markRestored([entry.id])
        }
    }

    func erase(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        guard store.permanentlyEraseTrash(ids: ids) else {
            showTray(store.trashNotice ?? "These items could not be erased.", icon: "exclamationmark.triangle", tone: .red)
            return
        }
        showTray(ids.count > 1 ? "Erased \(ids.count) items for good" : "Erased for good", icon: "trash.slash", tone: .red)
    }

    // MARK: Lists

    func createList() {
        let section = store.defaultSection()
        let list = store.createList(title: "Untitled list", in: section)
        let id = list.id
        let label = "Created “Untitled list” in \(section?.displayTitle ?? "Lists")"
        registerUndo(label, undo: { workbench in
            if let list = workbench.store.list(id: id) { _ = workbench.store.trashList(list) }
        }, redo: { workbench in
            _ = workbench.store.restoreTrash(ids: [id])
        })
        snap(label, icon: "plus.circle.fill", tone: .accent, ids: [])
        pulse(list: id)
        go(.list(id))
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

    /// The draft Return saves, which the capture card's chips preview. A time
    /// or repeat with no day of its own is due today, as long as dates are read
    /// from the text at all.
    func captureDraft(_ parse: CaptureParse) -> TaskCaptureDraft {
        var draft = TaskCaptureDraft(text: parse.schedulingText, parsesNaturalLanguage: settings.parsesNaturalLanguageDates)
        draft.dueTodayWhenUndated = captureForToday
            || (settings.parsesNaturalLanguageDates && (parse.first(.time) != nil || parse.first(.repeatRule) != nil))
        return draft
    }

    @discardableResult
    func createFromCapture(keepOpen: Bool) -> Block? {
        let parse = CaptureParse(captureText)
        guard !parse.title.isEmpty else { return nil }
        var preview = captureDraft(parse).preview
        let screenLabel = captureLabelID.flatMap { store.label(id: $0) }.map { [$0.name.lowercased()] } ?? []
        preview.labels = Array(Set(preview.labels.map { $0.lowercased() } + parse.labels + screenLabel)).sorted()
        let destinationID = captureListID ?? store.inboxList()?.id
        // Captured into the list whose Tasks view is showing, a task goes at the
        // end, where that view's add row sits; anywhere else it's prepended.
        let appendsToRoot = navigator.route.listID.map { $0 == destinationID && navigator.listViewMode(for: $0) == .tasks } ?? false
        let block: Block
        do {
            block = try store.saveCapture(preview, destinationID: destinationID,
                                          selectedForDay: capturePlansForToday ? .now : nil, appendToRoot: appendsToRoot)
        } catch {
            showTray(error.localizedDescription, icon: "exclamationmark.triangle", tone: .red)
            return nil
        }
        if let priority = parse.priority { store.setPriority(priority, for: block) }
        if let minutes = parse.estimateMinutes, minutes > 0 { store.setTaskEstimate(minutes, for: block) }
        let list = store.list(id: block.listID)
        let here: Bool = {
            switch navigator.route {
            case .inbox: list?.isSystemInbox == true
            case let .list(id): id == block.listID
            case .today: block.isDueOnOrBeforeToday || isPlanned(block)
            case let .label(id): block.labelIDs.contains(id)
            case .calendar: isPlanned(block)
            case .tasks: true
            default: false
            }
        }()
        let name = list?.displayTitle ?? "Inbox"
        // The closures keep the id, never the model, which Trash may erase.
        let id = block.id
        registerUndo("Added to \(name)", undo: { workbench in
            if let block = workbench.store.block(id: id) { _ = workbench.store.trashBlocks([block]) }
        }, redo: { workbench in
            _ = workbench.store.restoreTrash(ids: [id])
        })
        snap("Added to \(name)", icon: "plus.circle.fill", tone: .accent, ids: [block.id],
             destination: here || list == nil ? nil : TrayDestination(label: "Show", route: route(for: list!)))
        flash(\.fresh, [block.id], for: 1200)
        pulse(list: block.listID)
        if keepOpen { captureText = "" } else { closeCapture() }
        return block
    }

    /// Opens capture for the current screen. `forToday: true` makes an undated
    /// task due today; otherwise Today and the New tasks setting decide. On
    /// Calendar the task is planned for today instead, and on a label screen it
    /// gets that label.
    func openCapture(text: String = "", listID: UUID? = nil, forToday: Bool? = nil) {
        if case let .list(id) = navigator.route { captureListID = listID ?? id }
        else { captureListID = listID ?? store.inboxList()?.id }
        capturePlansForToday = navigator.route == .calendar
        captureForToday = !capturePlansForToday
            && (forToday == true || navigator.route == .today || settings.defaultDestination == .today)
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

    /// Tab and Shift-Tab step the destination through Inbox and every list.
    func cycleCaptureDestination(by delta: Int, among ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let index = ids.firstIndex { $0 == captureListID } ?? 0
        captureListID = ids[(index + delta + ids.count) % ids.count]
    }

    // MARK: Inbox triage

    func triage(_ task: Block, action: TriageExit, listID: UUID? = nil, offset: Int? = nil) {
        guard triageExit == nil else { return }
        withAnimation(style.ease(230)) { triageExit = action }
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
                    self.store.setDueDate(NXFormat.day(offset: offset ?? 0), includesTime: false, for: task)
                }
                keeps = true
            case .right:
                self.snap("Kept \(NXFormat.quoted(task.displayTitle)) for later", icon: "clock", tone: .neutral, ids: [id])
                keeps = true
            case .done:
                // A repeat rolls to its next date and stays in Inbox.
                keeps = task.recurrence != nil
                self.complete([id])
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

    /// The earliest free slot inside the list's hours in the week from now, or
    /// from the task's deferral, avoiding busy time.
    func fit(_ id: UUID) {
        guard let task = store.block(id: id), !task.isCompleted else { return }
        let minutes = task.schedulingEstimateMinutes > 0 ? task.schedulingEstimateMinutes : defaultEstimate
        let duration = TimeInterval(minutes * 60)
        let cal = settings.calendar
        let now = Date.now
        let category = store.list(id: task.listID).map { hours(for: $0) } ?? .work
        let pinned = store.placements().filter { $0.taskID != id }
        var busy: [(Date, Date)] = calendar.externalCalendars.busyTimes.map { ($0.start, $0.end) }
        busy += pinned.map { ($0.start, $0.end) }
        if let session = calendar.activeSession, session.taskID != id {
            busy.append((session.startedAt, now.addingTimeInterval(30 * 60)))
        }
        let quarter = TimeInterval(15 * 60)
        // On a quarter hour, not before a deferral, and only inside the list's hours:
        // the scheduler's windows already leave out breaks, overrides and days off,
        // and follow the wall clock across DST.
        let from = max(now, task.deferredUntil ?? now)
        let earliest = Date(timeIntervalSinceReferenceDate: (from.timeIntervalSinceReferenceDate / quarter).rounded(.up) * quarter)
        // A week of searching, counted from when the task may start.
        let weekEnd = cal.date(byAdding: .day, value: 7, to: cal.startOfDay(for: earliest)) ?? earliest
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
        let week = from > now ? "in the week from \(NXFormat.dueLabel(from))" : "this week"
        showTray("No free slot \(week) — try a shorter estimate", icon: "calendar.badge.exclamationmark", tone: .neutral)
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
            (taskID: calendar.activeSession?.taskID, notice: calendar.notice, grant: calendar.workExtension,
             conflict: calendar.workConflict, moved: calendar.rescheduleSummary?.id)
        } onChange: { [weak self] in
            Task { @MainActor in self?.watchWork() }
        }
        let last = workWatch
        workWatch = seen
        if let running = seen.taskID, let previous = last.taskID, running != previous {
            announceSwitch(from: previous, to: running)
        }
        if let grant = seen.grant, grant != last.grant { announceExtension(grant) }
        if let conflict = seen.conflict, conflict != last.conflict { announceConflict(conflict) }
        // Blocks read "rescheduled" for a minute after a move, not until the next one.
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
    /// the time recorded in between stays on the task it was recorded on.
    private func announceSwitch(from previousID: UUID, to currentID: UUID) {
        guard let previous = store.block(id: previousID), let current = store.block(id: currentID) else { return }
        let seconds = calendar.trackedMinutes(for: previous) * 60
        let label = "Switched to \(NXFormat.quoted(current.displayTitle)) — \(NXFormat.mmss(seconds)) recorded on \(NXFormat.quoted(previous.displayTitle))"
        let from = WorkTaskReference(previous)
        let to = WorkTaskReference(current)
        registerUndo(label, undo: { workbench in workbench.switchWork(to: from) },
                     redo: { workbench in workbench.switchWork(to: to) })
        snap(label, icon: "arrow.left.arrow.right", tone: .neutral, ids: [currentID, previousID])
    }

    /// Undo and Redo of a switch: work on `reference` again, which the watch
    /// then sees as the work it already knows rather than another switch.
    private func switchWork(to reference: WorkTaskReference) {
        guard let task = calendar.validWorkTask(reference), calendar.start(task: task) else { return }
        workWatch.taskID = task.id
    }

    /// Reports extra time the calendar gave the running work. Undo puts back the
    /// block it had and those of the tasks moved for it; work keeps recording.
    private func announceExtension(_ grant: CalendarWorkExtension) {
        guard let task = store.block(id: grant.taskID) else { return }
        let moved = grant.movedTaskIDs.count
        let label = "Extended \(NXFormat.quoted(task.displayTitle)) to \(NXFormat.clock(grant.end))"
            + (moved == 0 ? "" : " · moved \(moved) \(moved == 1 ? "task" : "tasks")")
        // Either way the watch already knows the extension it lands on.
        registerUndo(label, undo: { workbench in
            guard workbench.calendar.undoExtension(grant) else { return }
            workbench.workWatch.grant = workbench.calendar.workExtension
        }, redo: { workbench in
            guard workbench.calendar.redoExtension(grant) else { return }
            workbench.workWatch.grant = grant
        })
        snap(label, icon: "calendar.badge.plus", tone: .amber, ids: [grant.taskID] + grant.movedTaskIDs,
             destination: navigator.route == .calendar ? nil : TrayDestination(label: "Show", route: .calendar))
    }

    /// Reports the fixed event the running work ran into. It keeps recording.
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
    /// the design, a meeting is named bare and a task in quotes.
    func conflictName(_ conflict: CalendarWorkConflict, inSentence: Bool = false) -> String {
        switch conflict.kind {
        case .event: conflict.title.isEmpty ? (inSentence ? "busy time" : "Busy time") : conflict.title
        case .task: NXFormat.quoted(conflict.title)
        case .breakTime: inSentence ? "a break" : "Break"
        case .endOfHours: inSentence ? "the end of \(conflict.title) hours" : "End of \(conflict.title) hours"
        }
    }
}
