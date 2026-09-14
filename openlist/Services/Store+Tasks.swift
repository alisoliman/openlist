//
//  Store+Tasks.swift
//  openlist
//

import Foundation
import SwiftData

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
            clearInboxForNextOccurrence(block)
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
        let oldOccurrenceID = block.occurrenceID
        block.occurrenceID = UUID()
        pendingReopenedCycleIDs[block.occurrenceID] = unadvancedCycle
        carryInboxSelection(block, from: oldOccurrenceID)
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
            clearInboxForNextOccurrence(descendant)
            descendant.isCompleted = false
            descendant.completedAt = nil
            if let nextEligible, descendant.dueDate == nil || descendant.dueDate! >= nextEligible {
                descendant.deferredUntil = nextEligible
            }
            descendant.touch()
        }
    }

    /// Fraction of a task's subtasks that are done, for the progress pill.
    ///
    /// Fetches the owning list, so this is for one-off use. Views that render
    /// many rows should build `BlockTree.subtaskCounts(in:)` once instead.
    func subtaskProgress(for block: Block) -> (done: Int, total: Int)? {
        guard let listID = block.listID else { return nil }
        let counts = BlockTree.subtaskCounts(in: blocks(inList: listID))
        guard let entry = counts[block.id], entry.total > 0 else { return nil }
        return entry
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

    func setDueTomorrow(_ block: Block) {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))
        setDueDate(tomorrow, includesTime: false, for: block)
    }

    func setDueNextWeek(_ block: Block) {
        let next = Calendar.current.date(byAdding: .day, value: 7, to: Calendar.current.startOfDay(for: .now))
        setDueDate(next, includesTime: false, for: block)
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
                let reason: String? = task.isTrashed || owningList?.isTrashed == true ? "in Trash"
                    : task.isCompleted ? "task completed"
                    : owningList == nil ? "list unavailable"
                    : owningList?.isArchived == true ? "list archived" : nil
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

    func deleteLabel(_ label: TaskLabel) {
        do {
            let labelID = label.id
            let all = try context.fetch(FetchDescriptor<Block>())
            try preserveTrashLabel(label, referencedBy: all)
            for block in all where !block.isTrashed && block.labelIDs.contains(labelID) {
                block.labelIDs.removeAll { $0 == labelID }
            }
            context.delete(label)
            try persistChanges()
        } catch {
            persistenceError = "The label could not be deleted. \(error.localizedDescription)"
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

    /// Physically moves a subtree to its unfiled ownership document. This is
    /// separate from Add/Remove from Inbox, which only changes membership.
    func moveToUnfiled(_ block: Block) {
        guard let inbox = inboxList() else { return }
        moveToList(block, list: inbox)
    }


    // MARK: - Text formatting

    /// How much detail a relative date string carries.
    enum DateStyle {
        /// "today", "Tue", "12 Mar" — for chips.
        case short
        /// "Today", "Tuesday", "Tue 12 March" — for section headings.
        case long
    }

    static func relativeDateText(_ date: Date, style: DateStyle = .short) -> String {
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
            return date.formatted(.dateTime.weekday(style == .long ? .wide : .abbreviated))
        }
        if calendar.component(.year, from: date) == calendar.component(.year, from: .now) {
            return style == .long
                ? date.formatted(.dateTime.weekday(.abbreviated).day().month(.wide))
                : date.formatted(.dateTime.day().month(.abbreviated))
        }
        return style == .long
            ? date.formatted(.dateTime.day().month(.wide).year())
            : date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    /// Short chip text such as "Today", "Tue", "12 Mar", with an optional time.
    static func dueChipText(for block: Block) -> String {
        guard let dueDate = block.dueDate else { return "" }
        var text = relativeDateText(dueDate).capitalizedFirstLetter
        if block.includesTime {
            text += " \(dueDate.formatted(date: .omitted, time: .shortened))"
        }
        return text
    }

    /// Unambiguous "12 Mar 2026, 6:00 PM" form used by pickers and export.
    static func absoluteDateText(_ date: Date, includesTime: Bool) -> String {
        includesTime
            ? date.formatted(date: .abbreviated, time: .shortened)
            : date.formatted(date: .abbreviated, time: .omitted)
    }

    /// "Today" / "Yesterday" / "Tue 12 March" headings for day-grouped lists.
    static func dayHeading(for date: Date) -> String {
        relativeDateText(date, style: .long).capitalizedFirstLetter
    }
}

extension String {
    var capitalizedFirstLetter: String {
        guard let first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}
