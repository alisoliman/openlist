//
//  Workbench+Actions.swift
//  openlist
//

import AppKit
import Foundation
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

extension Workbench {
    func describe(_ tasks: [Block]) -> String {
        tasks.count == 1 ? NXFormat.quoted(tasks[0].displayTitle) : "\(tasks.count) tasks"
    }

    func route(for list: TaskList) -> AppRoute { list.isSystemInbox ? .inbox : .list(list.id) }

    /// Mutates tasks through the Store, then registers an Undo that restores the fields.
    private func edit(_ tasks: [Block], label: String, icon: String, tone: TrayTone,
                      chip: Bool = true, _ change: (Block) -> Void) {
        let before = tasks.map(TaskFields.init)
        for task in tasks { change(task) }
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

    func complete(_ ids: [UUID]) {
        let candidates = tasks(ids).filter { !$0.isCompleted && closing[$0.id] == nil }
        guard !candidates.isEmpty else { return }
        let rolls = candidates.filter { $0.recurrence != nil }
        let plain = candidates.filter { $0.recurrence == nil }
        if let session = calendar.activeSession, candidates.contains(where: { $0.id == session.taskID }) {
            calendar.pause(reason: "Completed")
        }
        for task in rolls {
            completionLabel = "Complete \(task.displayTitle)"
            store.toggleCompletion(task)
            completionLabel = nil
        }
        let count = candidates.count
        let label: String
        if count > 1 { label = "\(count) tasks done" }
        else if let task = plain.first { label = describe([task]) + " done" }
        else { label = "\(NXFormat.quoted(rolls[0].displayTitle)) rolls to \(NXFormat.dueLabel(rolls[0].dueDate))" }
        if !rolls.isEmpty {
            undoManager?.setActionName(label)
            flash(\.freshChip, rolls.map(\.id), for: 900)
        }
        let batchIcon = !rolls.isEmpty && plain.isEmpty ? "repeat" : "checkmark.circle.fill"
        snap(label, icon: batchIcon, tone: .green, ids: candidates.map(\.id))
        if let batch = latestBatch, !plain.isEmpty { beginClosing(plain, label: label, batch: batch) }
        else if let first = rolls.first { pulseCheck(first.id) }
        selection = []
    }

    func reopen(_ id: UUID) {
        guard let task = store.block(id: id), task.isCompleted else { return }
        let label = "Reopened \(NXFormat.quoted(task.displayTitle))"
        store.reopen(task)
        store.save()
        registerUndo(label, undo: { workbench in
            guard let task = workbench.store.block(id: id), !task.isCompleted else { return }
            workbench.suppressesStoreUndo = true
            workbench.store.toggleCompletion(task)
            workbench.suppressesStoreUndo = false
        }, redo: { workbench in
            guard let task = workbench.store.block(id: id), task.isCompleted else { return }
            workbench.store.reopen(task)
            workbench.store.save()
            workbench.markRestored([id])
        })
        snap(label, icon: "arrow.uturn.backward", tone: .neutral, ids: [id])
        markRestored([id])
    }

    /// Routes the Store's completion Undo onto this window, named after the design action.
    func installCompletionUndo() {
        store.onCompletionUndoAvailable = { [weak self] action in
            guard let self, !self.suppressesStoreUndo, let manager = self.undoManager else { return }
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
        let label = "Moved \(describe(tasks)) to Trash"
        let taskIDs = tasks.map(\.id)
        snap(label, icon: "trash", tone: .red, ids: taskIDs,
             destination: TrayDestination(label: "Open Trash", route: .trash))
        withAnimation(style.ease(320)) { flying.formUnion(taskIDs) }
        selection = []
        focusID = nil
        if let open = navigator.openTaskID, taskIDs.contains(open) { navigator.closeTask() }
        let delay = Int(ms(320))
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(delay))
            guard let self else { return }
            let blocks = taskIDs.compactMap { self.store.block(id: $0) }
            if !blocks.isEmpty, self.store.trashBlocks(blocks, undoManager: self.undoManager) {
                self.undoManager?.setActionName(label)
            }
            self.flying.subtract(taskIDs)
            self.bumpUndo()
        }
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

    @discardableResult
    func createFromCapture(keepOpen: Bool) -> Block? {
        let parse = CaptureParse(captureText)
        guard !parse.title.isEmpty else { return nil }
        var draft = TaskCaptureDraft(text: parse.schedulingText, parsesNaturalLanguage: settings.parsesNaturalLanguageDates)
        draft.dueTodayWhenUndated = captureForToday || parse.first(.time) != nil || parse.first(.repeatRule) != nil
        var preview = draft.preview
        preview.labels = Array(Set(preview.labels.map { $0.lowercased() } + parse.labels)).sorted()
        let destinationID = captureListID ?? store.inboxList()?.id
        let block: Block
        do {
            block = try store.saveCapture(preview, destinationID: destinationID)
        } catch {
            showTray(error.localizedDescription, icon: "exclamationmark.triangle", tone: .red)
            return nil
        }
        if parse.hasPriority { store.setPriority(.high, for: block) }
        if let minutes = parse.estimateMinutes, minutes > 0 { store.setTaskEstimate(minutes, for: block) }
        let list = store.list(id: block.listID)
        let here: Bool = {
            switch navigator.route {
            case .inbox: list?.isSystemInbox == true
            case let .list(id): id == block.listID
            case .today: block.dueDate.map { NXFormat.dayOffset($0) <= 0 } ?? false
            case .tasks: true
            default: false
            }
        }()
        let name = list?.displayTitle ?? "Inbox"
        registerUndo("Added to \(name)", undo: { workbench in
            if let block = workbench.store.block(id: block.id) { _ = workbench.store.trashBlocks([block]) }
        }, redo: { workbench in
            _ = workbench.store.restoreTrash(ids: [block.id])
        })
        snap("Added to \(name)", icon: "plus.circle.fill", tone: .accent, ids: [block.id],
             destination: here || list == nil ? nil : TrayDestination(label: "Show", route: route(for: list!)))
        flash(\.fresh, [block.id], for: 1200)
        pulse(list: block.listID)
        if keepOpen { captureText = "" } else { closeCapture() }
        return block
    }

    func openCapture(text: String = "", listID: UUID? = nil, forToday: Bool? = nil) {
        if case let .list(id) = navigator.route { captureListID = listID ?? id }
        else { captureListID = listID ?? store.inboxList()?.id }
        captureForToday = forToday ?? (navigator.route == .today)
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
            switch action {
            case .left:
                if let listID { self.move([id], to: listID) }
            case .up:
                let label = "\(NXFormat.quoted(task.displayTitle)) → \(NXFormat.dueLabel(NXFormat.day(offset: offset ?? 0))) · still in Inbox"
                self.edit([task], label: label, icon: "calendar", tone: .accent) { task in
                    self.store.setDueDate(NXFormat.day(offset: offset ?? 0), includesTime: false, for: task)
                }
                self.kept.insert(id)
            case .right:
                self.kept.insert(id)
                let label = "Kept \(NXFormat.quoted(task.displayTitle)) for later"
                self.registerUndo(label, undo: { $0.kept.remove(id); $0.reviewed = max(0, $0.reviewed - 1) },
                                  redo: { $0.kept.insert(id); $0.reviewed += 1 })
                self.snap(label, icon: "clock", tone: .neutral, ids: [id])
            case .done:
                let label = "\(NXFormat.quoted(task.displayTitle)) done"
                self.completionLabel = label
                self.store.toggleCompletion(task)
                self.completionLabel = nil
                self.snap(label, icon: "checkmark.circle.fill", tone: .green, ids: [id])
            case .down:
                let label = "Discarded \(NXFormat.quoted(task.displayTitle))"
                if self.store.trashBlocks([task], undoManager: self.undoManager) { self.undoManager?.setActionName(label) }
                self.snap(label, icon: "trash", tone: .red, ids: [id],
                          destination: TrayDestination(label: "Open Trash", route: .trash))
            }
            self.reviewed += 1
            withAnimation(self.style.spring(320)) {
                self.triageExit = nil
                self.triageFlip.toggle()
            }
        }
    }

    // MARK: Calendar

    /// The earliest free slot this week inside the list's hours, avoiding busy time.
    func fit(_ id: UUID) {
        guard let task = store.block(id: id), !task.isCompleted else { return }
        let minutes = task.schedulingEstimateMinutes > 0 ? task.schedulingEstimateMinutes : defaultEstimate
        let duration = TimeInterval(minutes * 60)
        let cal = Calendar.current
        let now = Date.now
        let category = AvailabilityCategory(rawValue: store.list(id: task.listID)?.availabilityCategoryRaw ?? "") ?? .work
        let profile = calendar.preferences.profile(for: category)
        let pinned = store.placements().filter { $0.taskID != id }
        var busy: [(Date, Date)] = calendar.externalCalendars.busyTimes.map { ($0.start, $0.end) }
        busy += pinned.map { ($0.start, $0.end) }
        if let session = calendar.activeSession, session.taskID != id {
            busy.append((session.startedAt, now.addingTimeInterval(30 * 60)))
        }
        let quarter = TimeInterval(15 * 60)
        let roundedNow = Date(timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate / quarter).rounded(.up) * quarter)
        for offset in 0..<7 {
            let day = NXFormat.day(offset: offset, now: now)
            let weekday = cal.component(.weekday, from: day)
            let windows = profile.weekly[weekday] ?? []
            var dayBusy = busy
            for gap in profile.breaks[weekday] ?? [] {
                dayBusy.append((day.addingTimeInterval(TimeInterval(gap.startMinute * 60)),
                                day.addingTimeInterval(TimeInterval(gap.endMinute * 60))))
            }
            for window in windows {
                let windowStart = day.addingTimeInterval(TimeInterval(window.startMinute * 60))
                let windowEnd = day.addingTimeInterval(TimeInterval(window.endMinute * 60))
                var start = offset == 0 ? max(windowStart, roundedNow) : windowStart
                while start.addingTimeInterval(duration) <= windowEnd {
                    let end = start.addingTimeInterval(duration)
                    if !dayBusy.contains(where: { start < $0.1 && $0.0 < end }) {
                        place(task, start: start, end: end, dayOffset: offset)
                        return
                    }
                    start = start.addingTimeInterval(quarter)
                }
            }
        }
        showTray("No free slot this week — try a shorter estimate", icon: "calendar.badge.exclamationmark", tone: .neutral)
    }

    private func place(_ task: Block, start: Date, end: Date, dayOffset: Int) {
        let id = task.id
        let fields = [TaskFields(task)]
        let previous = store.placements(taskID: id).filter { $0.occurrenceID == task.occurrenceID }
            .map { (start: $0.start, end: $0.end, isPinned: $0.isPinned) }
        for placement in store.placements(taskID: id) where placement.occurrenceID == task.occurrenceID {
            store.removePlacement(placement)
        }
        guard let placement = store.setPlacement(for: task, start: start, end: end, isPinned: true) else { return }
        let placementID = placement.id
        let label = "Planned \(NXFormat.quoted(task.displayTitle)) · \(dayOffset == 0 ? "Today" : NXFormat.dueLabel(start)) \(NXFormat.clock(start))"
        registerUndo(label, undo: { workbench in
            if let current = workbench.store.placements(taskID: id).first(where: { $0.id == placementID }) {
                workbench.store.removePlacement(current)
            }
            if let block = workbench.store.block(id: id) {
                for old in previous { workbench.store.setPlacement(for: block, start: old.start, end: old.end, isPinned: old.isPinned) }
            }
            workbench.restore(fields)
        }, redo: { workbench in
            if let block = workbench.store.block(id: id) {
                workbench.store.setPlacement(for: block, start: start, end: end, isPinned: true)
            }
        })
        snap(label, icon: "sparkles", tone: .accent, ids: [id],
             destination: navigator.route == .calendar ? nil : TrayDestination(label: "Show", route: .calendar))
        flashBlock(id)
        calendar.replan()
    }

    func startWork(_ id: UUID) {
        guard let task = store.block(id: id) else { return }
        if workPausedTaskID != id { workCarrySeconds = 0 }
        workPausedTaskID = nil
        if calendar.start(task: task) {
            workStartedAt = .now
        } else {
            showTray(workRefusal(for: task), icon: "calendar.badge.exclamationmark", tone: .neutral)
            calendar.notice = nil
        }
    }

    /// Why Start working was refused, short enough for the tray.
    private func workRefusal(for task: Block) -> String {
        let category = AvailabilityCategory(rawValue: store.list(id: task.listID)?.availabilityCategoryRaw ?? "work") ?? .work
        let cal = settings.calendar
        let day = cal.startOfDay(for: .now)
        let intervals = AdaptiveScheduler.availabilityIntervals(for: category, preferences: calendar.preferences, from: day,
                                                               to: cal.date(byAdding: .day, value: 1, to: day) ?? day, calendar: cal)
        if !intervals.contains(where: { $0.start <= .now && $0.end > .now }) {
            return "Outside \(category.title) hours · \(NXHours.summary(calendar.preferences.profile(for: category), calendar: cal))"
        }
        return calendar.notice ?? "Work could not be started."
    }

    /// The task shown in the work notch: the running session, or one paused from the notch.
    var workTask: Block? {
        if let session = calendar.activeSession { return store.block(id: session.taskID) }
        if let paused = calendar.resumableTask, paused.id == workPausedTaskID { return paused }
        return nil
    }

    var isWorkPaused: Bool { calendar.activeSession == nil && workTask != nil }

    func workElapsed(at now: Date = .now) -> Double {
        guard let session = calendar.activeSession else { return workCarrySeconds }
        return workCarrySeconds + max(0, now.timeIntervalSince(session.startedAt))
    }

    func toggleWorkPause() {
        if let session = calendar.activeSession {
            workCarrySeconds = workElapsed()
            workPausedTaskID = session.taskID
            calendar.pause(reason: "Paused")
        } else if let task = workTask {
            workPausedTaskID = task.id
            if calendar.start(task: task) { workPausedTaskID = nil }
        }
    }

    func finishWork() {
        guard let task = workTask else { return }
        complete([task.id])
        endWork()
    }

    func stopWork() {
        guard workTask != nil else { return }
        let seconds = workElapsed()
        if calendar.activeSession != nil { calendar.stopWorking() }
        endWork()
        showTray("Stopped — \(NXFormat.mmss(seconds)) recorded", icon: "timer", tone: .neutral)
    }

    private func endWork() {
        calendar.dismissResume()
        workPausedTaskID = nil
        workCarrySeconds = 0
        workStartedAt = nil
    }
}
