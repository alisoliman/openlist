//
//  Store+Tasks.swift
//  openlist
//

import Foundation
import SwiftData

/// A deleted label as it was, and where it sat among the labels of each task
/// that had it, so Undo can put it back.
struct DeletedLabel: Equatable {
    var label: LabelMergePlan.LabelState
    var positions: [UUID: Int]
    var deletedAt: Date
}

extension Store {
    // MARK: - Completion

    /// Toggles a task, rolling repeating tasks forward to their next occurrence.
    func toggleCompletion(_ block: Block, now: Date = .now) {
        guard block.isTask else { return }

        if block.isCompleted {
            reopen(block)
        } else {
            let before = captureCompletionUndo(for: block)
            complete(block, now: now)
            stageCompletionUndo(for: block, before: before, now: now)
        }
        save()
    }

    func complete(_ block: Block, now: Date) {
        recordCalendarCompletion(for: block, now: now)

        if var rule = block.recurrence,
           let next = RecurrenceEngine.nextDate(rule: rule, dueDate: block.dueDate, completedAt: now) {
            let completedCycleID = recurringCompletionCycle(for: block) ?? block.occurrenceID
            // Repeating tasks never sit in the completed state: they advance.
            rule.completedOccurrences += 1
            let previousDue = block.dueDate
            block.recurrence = rule.isFinished ? nil : rule
            block.dueDate = rule.isFinished ? nil : next
            block.isCompleted = false
            block.completedAt = nil
            block.occurrenceID = UUID()
            // Completing today's occurrence must not immediately fill today
            // again with a future repeat. An explicit Today choice clears this.
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!
            let nextEligible = !rule.isFinished && next >= tomorrow ? tomorrow : nil
            block.deferredUntil = nextEligible
            // The reminder has to travel with the occurrence, or it stays in
            // the past and every future repeat is silently unreminded.
            shiftReminder(on: block, fromDue: previousDue)

            // Subtasks reset so the next occurrence starts fresh.
            resetSubtasks(of: block, now: now, nextEligible: nextEligible, completedCycleID: completedCycleID)

            log(
                .completed,
                title: block.displayTitle,
                detail: rule.isFinished
                    ? "Finished repeating"
                    : "Repeats \(Self.relativeDateText(next))",
                block: block
            )
            scheduleReminderIfNeeded(for: block)
            block.touch()
            return
        }

        block.isCompleted = true
        block.completedAt = now
        block.touch()

        // Ticking a parent ticks everything under it.
        if let listID = block.listID {
            for descendant in BlockTree.descendants(of: block.id, in: blocks(inList: listID)) where descendant.isTask {
                if !descendant.isCompleted {
                    recordCalendarCompletion(for: descendant, now: now)
                    descendant.isCompleted = true
                    descendant.completedAt = now
                    descendant.touch()
                }
            }
        }

        log(.completed, title: block.displayTitle, block: block)
    }

    func reopen(_ block: Block) {
        let unadvancedCycle = block.recurrence == nil ? nil : recurringCompletionCycle(for: block)
        discardTaskSchedule(for: block, reason: "Reopened")
        block.occurrenceID = UUID()
        pendingReopenedCycleIDs[block.occurrenceID] = unadvancedCycle
        block.isCompleted = false
        block.completedAt = nil
        block.touch()
        scheduleReminderIfNeeded(for: block)
        log(.reopened, title: block.displayTitle, block: block)
    }

    private func resetSubtasks(of block: Block, now: Date, nextEligible: Date?, completedCycleID: UUID) {
        guard let listID = block.listID else { return }
        let descendants = BlockTree.descendants(of: block.id, in: blocks(inList: listID)).filter(\.isTask)
        // Capture the whole subtree before resetting any intermediate parent.
        let cycles = Dictionary(uniqueKeysWithValues: descendants.compactMap { descendant -> (UUID, UUID)? in
            recurringCompletionCycle(for: descendant, completingAncestor: (block.id, completedCycleID)).map { (descendant.id, $0) }
        })
        for descendant in descendants {
            if !descendant.isCompleted { recordCalendarCompletion(for: descendant, now: now, recurringCycleID: cycles[descendant.id]) }
            discardTaskSchedule(for: descendant, reason: "Next occurrence", now: now)
            descendant.occurrenceID = UUID()
            descendant.isCompleted = false
            descendant.completedAt = nil
            if let nextEligible, descendant.dueDate == nil || descendant.dueDate! >= nextEligible {
                descendant.deferredUntil = nextEligible
            }
            descendant.touch()
        }
    }

    // MARK: - Scheduling

    func setDueDate(_ date: Date?, includesTime: Bool = false, for block: Block) {
        let previousDue = block.dueDate
        block.dueDate = date
        block.includesTime = date == nil ? false : includesTime
        if date != nil { shiftReminder(on: block, fromDue: previousDue) }
        block.touch()

        if date == nil {
            block.reminderAt = nil
            log(.unscheduled, title: block.displayTitle, block: block)
        } else {
            log(.scheduled, title: block.displayTitle, detail: Self.relativeDateText(date!), block: block)
            scheduleReminderIfNeeded(for: block)
        }
        save()
    }

    func setDueToday(_ block: Block) {
        setDueDate(Calendar.current.startOfDay(for: .now), includesTime: false, for: block)
    }

    /// "Next week": the coming Monday, whichever day the week starts on here.
    /// When that Monday is tomorrow it's the one after, so it never repeats Tomorrow.
    static func nextWeekDay(from now: Date = .now, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        guard let monday = calendar.nextDate(after: today, matching: DateComponents(weekday: 2), matchingPolicy: .nextTime)
        else { return calendar.date(byAdding: .day, value: 7, to: today) ?? today }
        guard calendar.dateComponents([.day], from: today, to: monday).day == 1 else { return monday }
        return calendar.date(byAdding: .day, value: 7, to: monday) ?? monday
    }

    func setReminder(_ date: Date?, for block: Block) {
        block.reminderAt = date
        block.touch()
        save()
    }

    func setRecurrence(_ rule: Recurrence?, for block: Block) {
        // A repeating task needs a date to repeat from.
        if rule != nil, block.dueDate == nil {
            block.dueDate = Calendar.current.startOfDay(for: .now)
        }
        block.recurrence = rule?.anchored(to: block.dueDate)
        block.touch()
        save()
    }

    /// Moves a reminder by the same amount the due date moved.
    ///
    /// A reminder is meaningful relative to its occurrence ("15 minutes
    /// before"), so rescheduling the task has to carry it along.
    private func shiftReminder(on block: Block, fromDue previousDue: Date?) {
        guard
            let reminder = block.reminderAt,
            let previousDue,
            let newDue = block.dueDate
        else { return }
        block.reminderAt = newDue.addingTimeInterval(reminder.timeIntervalSince(previousDue))
    }

    /// Kept as a mutation callsite marker. OS state only follows committed
    /// data; a synchronous save below this call publishes the final snapshot.
    func scheduleReminderIfNeeded(for block: Block) {
        guard !context.hasChanges else { return }
        refreshAllReminders()
    }

    /// A fresh reader avoids exposing retained unsaved live model values to the
    /// OS. This also covers direct title/list edits, Undo, copies, and imports.
    func refreshAllReminders() {
        do {
            let reader = ModelContext(context.container)
            reader.autosaveEnabled = false
            let lists = try reader.fetch(FetchDescriptor<TaskList>())
            let tasks = try reader.fetch(FetchDescriptor<Block>(predicate: #Predicate { $0.kindRaw == "task" }))
            let intents = tasks.compactMap { task -> ReminderIntent? in
                guard let date = task.reminderAt ?? (task.includesTime ? task.dueDate : nil) else { return nil }
                var id = task.listID
                var visited = Set<UUID>()
                var owningList: TaskList?
                while let next = id, visited.insert(next).inserted,
                      let list = lists.first(where: { $0.id == next }) {
                    if list.mergedIntoID == nil { owningList = list; break }
                    id = list.mergedIntoID
                }
                let reason: String? = task.isTrashed || owningList?.isEffectivelyTrashed == true ? "in Trash"
                    : task.isCompleted ? "task completed"
                    : owningList == nil ? "list unavailable"
                    : owningList?.isEffectivelyArchived == true ? "list archived" : nil
                return ReminderIntent(id: task.id, occurrenceID: task.occurrenceID,
                    title: task.displayTitle, listName: owningList?.displayTitle ?? "",
                    date: date, inactiveReason: reason)
            }
            NotificationService.shared.reconcileReminders(intents)
        } catch {
            NotificationService.shared.reminderReadFailed("Saved reminders could not be read. \(error.localizedDescription)")
        }
    }

    // MARK: - Flags

    func toggleStar(_ block: Block) {
        block.isStarred.toggle()
        block.touch()
        if block.isStarred {
            log(.starred, title: block.displayTitle, block: block)
        }
        save()
    }

    func setPriority(_ priority: TaskPriority, for block: Block) {
        block.priority = priority
        block.touch()
        save()
    }

    // MARK: - Labels

    /// Finds an existing label by name or creates one with a derived colour.
    @discardableResult
    func findOrCreateLabel(named rawName: String) -> TaskLabel? {
        let name = TaskLabel.normalize(rawName)
        guard !name.isEmpty else { return nil }

        if let existing = matchingLabels(named: name).first {
            return existing
        }
        let label = TaskLabel(
            name: name,
            accent: TaskLabel.suggestedAccent(for: name),
            sortIndex: (allLabels().map(\.sortIndex).max() ?? 0) + BlockTree.indexStep
        )
        context.insert(label)
        return label
    }

    func addLabel(_ label: TaskLabel, to block: Block) {
        guard !block.labelIDs.contains(label.id) else { return }
        block.labelIDs.append(label.id)
        block.touch()
        log(.labeled, title: block.displayTitle, detail: label.name, block: block)
        save()
    }

    func removeLabel(_ label: TaskLabel, from block: Block) {
        block.labelIDs.removeAll { $0 == label.id }
        block.touch()
        save()
    }

    func toggleLabel(_ label: TaskLabel, on block: Block) {
        if block.labelIDs.contains(label.id) {
            removeLabel(label, from: block)
        } else {
            addLabel(label, to: block)
        }
    }

    func toggleLabel(id: UUID, on block: Block) {
        guard let label = label(id: id) else { return }
        toggleLabel(label, on: block)
    }

    func clearLabels(on block: Block) {
        guard !block.labelIDs.isEmpty else { return }
        block.labelIDs.removeAll()
        block.touch()
        save()
    }

    func renameLabel(_ label: TaskLabel, to newName: String) throws {
        try renameLabel(id: label.id, to: newName)
    }

    /// Deletes a label and takes it off every task outside Trash. Returns what
    /// ``restoreDeletedLabel(_:)`` needs to put it back, or nil if it failed.
    @discardableResult
    func deleteLabel(_ label: TaskLabel) -> DeletedLabel? {
        do {
            let labelID = label.id
            let state = LabelMergePlan.LabelState(label)
            let all = try context.fetch(FetchDescriptor<Block>())
            try preserveTrashLabel(label, referencedBy: all)
            var positions: [UUID: Int] = [:]
            for block in all where !block.isTrashed {
                guard let position = block.labelIDs.firstIndex(of: labelID) else { continue }
                positions[block.id] = position
                block.labelIDs.removeAll { $0 == labelID }
            }
            context.delete(label)
            try persistChanges()
            labelRevision += 1
            return DeletedLabel(label: state, positions: positions, deletedAt: .now)
        } catch {
            persistenceError = "The label could not be deleted. \(error.localizedDescription)"
            return nil
        }
    }

    /// Undo of ``deleteLabel(_:)``: the label comes back as it was, where it
    /// sat among the labels of each task that had it and is still outside
    /// Trash. A label of the same name made since the deletion stands in for
    /// it rather than a second one. Returns the id those tasks carry, or nil
    /// if it failed.
    @discardableResult
    func restoreDeletedLabel(_ deleted: DeletedLabel) -> UUID? {
        do {
            let labels = try context.fetch(FetchDescriptor<TaskLabel>()).filter { !$0.isDeleted }
            let labelID: UUID
            if labels.contains(where: { $0.id == deleted.label.id }) {
                labelID = deleted.label.id
            } else if let same = labels.first(where: {
                $0.createdAt >= deleted.deletedAt && TaskLabel.namesMatch($0.name, deleted.label.name)
            }) {
                labelID = same.id
            } else {
                context.insert(deleted.label.restore())
                labelID = deleted.label.id
            }
            let ids = Array(deleted.positions.keys)
            for block in try context.fetch(FetchDescriptor<Block>(predicate: #Predicate { ids.contains($0.id) }))
            where !block.isTrashed && !block.labelIDs.contains(labelID) {
                let position = min(deleted.positions[block.id] ?? block.labelIDs.count, block.labelIDs.count)
                block.labelIDs.insert(labelID, at: position)
            }
            try persistChanges()
            labelRevision += 1
            return labelID
        } catch {
            persistenceError = "The label could not be restored. \(error.localizedDescription)"
            return nil
        }
    }

    func blockCount(for label: TaskLabel) -> Int {
        let labelID = label.id
        let descriptor = FetchDescriptor<Block>(predicate: #Predicate { !$0.isCompleted })
        let all = (try? context.fetch(descriptor)) ?? []
        return all.filter { !$0.isTrashed && $0.labelIDs.contains(labelID) }.count
    }

    // MARK: - Moving between lists

    /// Moves a task (and its subtree) to the root of another list.
    func moveToList(_ block: Block, list destination: TaskList) {
        let previousList = list(id: block.listID)
        guard previousList?.id != destination.id || block.parentID != nil else { return }

        _ = move(block, toParent: nil, above: nil, in: destination.id)
        log(
            .moved,
            title: block.displayTitle,
            detail: "to \(destination.displayTitle)",
            block: block,
            list: destination
        )
        save()
    }

    // MARK: - Text formatting

    /// "today", "Tue" or "12 Mar", for due chips, repeat summaries and history.
    static func relativeDateText(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "today" }
        if calendar.isDateInTomorrow(date) { return "tomorrow" }
        if calendar.isDateInYesterday(date) { return "yesterday" }

        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: .now),
            to: calendar.startOfDay(for: date)
        ).day ?? 0

        // Within a week either way, the weekday name is the clearest label.
        if abs(days) < 7 {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
        if calendar.component(.year, from: date) == calendar.component(.year, from: .now) {
            return date.formatted(.dateTime.day().month(.abbreviated))
        }
        return date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    /// Unambiguous "12 Mar 2026, 6:00 PM" form used by pickers and export.
    static func absoluteDateText(_ date: Date, includesTime: Bool) -> String {
        includesTime
            ? date.formatted(date: .abbreviated, time: .shortened)
            : date.formatted(date: .abbreviated, time: .omitted)
    }
}

extension String {
    var capitalizedFirstLetter: String {
        guard let first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}
