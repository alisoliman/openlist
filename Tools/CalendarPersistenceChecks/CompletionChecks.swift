import Foundation
import SwiftData

private final class UndoProbe { var value = 1 }

extension CalendarPersistenceChecks {
    static func runCompletionChecks(store: Store, list: TaskList, day: Date, storeURL: URL) {
        store.calendarDeviceID = "completion-check"
        func slot(_ task: Block, _ start: Date, _ minutes: Double) -> PlannedBlock {
            PlannedBlock(id: UUID().uuidString, taskID: task.id, occurrenceID: task.occurrenceID,
                         start: start, end: start.addingTimeInterval(minutes * 60),
                         isPinned: false, placementID: nil, conflicts: [])
        }
        let nine = day.addingTimeInterval(9 * 3_600)
        let completedAt = nine.addingTimeInterval(3_600)
        let untracked = store.appendBlock(kind: .task, text: "Untracked calendar snapshot", to: .init(listID: list.id))
        let originalOccurrence = untracked.occurrenceID
        let planned = [slot(untracked, nine, 25), slot(untracked, nine.addingTimeInterval(7_200), 15)]
        store.calendarPlannedBlocks = planned
        store.toggleCompletion(untracked, now: completedAt)
        let untrackedRecord = store.completionRecords(taskID: untracked.id).first!
        let savedIntervals = planned.map { CompletionCalendarInterval(start: $0.start, end: $0.end) }
        check(untrackedRecord.plannedIntervals == savedIntervals, "Completion durably snapshots every displayed split slot before replanning")
        check(store.workSessions(taskID: untracked.id).isEmpty, "Completing an unstarted planned task invents no recorded work")
        let untrackedBlocks = store.completedCalendarBlocks().filter { $0.completionID == untrackedRecord.id }
        check(untrackedBlocks.map { CompletionCalendarInterval(start: $0.start, end: $0.end) } == savedIntervals && untrackedBlocks.allSatisfy { $0.isCompleted && !$0.isTimeTracked }, "Untracked completed blocks retain planned times with explicit untracked metadata")
        untracked.text = "Renamed after completion"
        store.save()
        check(store.completedCalendarBlocks().filter { $0.completionID == untrackedRecord.id }.allSatisfy { $0.titleSnapshot == "Untracked calendar snapshot" }, "Renaming a task never renames its completed occurrence")
        store.toggleCompletion(untracked, now: completedAt)
        check(untracked.occurrenceID != originalOccurrence && store.completionRecords(taskID: untracked.id).count == 1, "Normal reopening preserves completed calendar history")
        store.toggleCompletion(untracked, now: completedAt.addingTimeInterval(60))
        let secondRecord = store.completionRecords(taskID: untracked.id).first!
        let marker = store.completedCalendarBlocks().first { $0.completionID == secondRecord.id }!
        check(secondRecord.plannedIntervals.isEmpty && marker.start == secondRecord.completedAt && marker.start == marker.end && !marker.isTimeTracked, "Stale previous-occurrence plan never leaks into a newly completed occurrence")
        let secondUndo = store.completionUndo!
        check(store.undoCompletion(secondUndo.id) && store.completionRecords(taskID: untracked.id).count == 1 && !untracked.isCompleted, "Undo removes only the new completion while normal prior history remains")

        let tracked = store.appendBlock(kind: .task, text: "Tracked calendar snapshot", to: .init(listID: list.id))
        store.calendarPlannedBlocks = [slot(tracked, nine.addingTimeInterval(10_800), 45)]
        let originalTrackedPlan = store.calendarPlannedBlocks.map { CompletionCalendarInterval(start: $0.start, end: $0.end) }
        let first = store.startWorkSession(for: tracked, deviceID: "completion-check", now: nine)!
        store.calendarPlannedBlocks = [slot(tracked, nine, 60)]
        store.pauseWorkSession(first, reason: "Break", now: nine.addingTimeInterval(600))
        store.correctSession(first, minutes: 15)
        let second = store.startWorkSession(for: tracked, deviceID: "completion-check", now: nine.addingTimeInterval(2_400))!
        store.toggleCompletion(tracked, now: completedAt)
        let trackedRecord = store.completionRecords(taskID: tracked.id).first!
        var actual = store.completedCalendarBlocks().filter { $0.completionID == trackedRecord.id }
        check(actual.count == 2 && actual.allSatisfy(\.isTimeTracked) && actual.map(\.durationMinutes) == [15, 20], "Tracked completions show actual sessions with corrected durations, not their planned estimate")
        check(second.endedAt == completedAt && trackedRecord.plannedIntervals.count == 1, "Completion closes active work and separately retains its original planning snapshot")
        check(first.plannedIntervals == originalTrackedPlan && trackedRecord.plannedIntervals == originalTrackedPlan, "Early Start and active overruns cannot replace the original pre-start planned interval")
        store.correctSession(first, minutes: 12)
        actual = store.completedCalendarBlocks().filter { $0.completionID == trackedRecord.id }
        check(actual.first?.end == nine.addingTimeInterval(720) && actual.last?.end == completedAt, "Later time corrections update actual completed calendar intervals")
        check(trackedRecord.plannedIntervals == originalTrackedPlan, "Correcting recorded time never changes original planned-slot history")
        tracked.text = "Changed live title"
        store.deleteBlocks([tracked])
        check(store.completedCalendarBlocks().filter { $0.completionID == trackedRecord.id }.allSatisfy { $0.titleSnapshot == "Tracked calendar snapshot" && $0.isTimeTracked }, "Deleting or renaming the task preserves immutable completed titles and actual work")

        let inSlot = store.appendBlock(kind: .task, text: "Worked inside its slot", to: .init(listID: list.id))
        store.calendarPlannedBlocks = [slot(inSlot, nine, 30), slot(inSlot, nine.addingTimeInterval(7_200), 30)]
        let inside = store.startWorkSession(for: inSlot, deviceID: "completion-check", now: nine.addingTimeInterval(300))!
        store.pauseWorkSession(inside, reason: "Break", now: nine.addingTimeInterval(900))
        let overrun = store.startWorkSession(for: inSlot, deviceID: "completion-check", now: nine.addingTimeInterval(1_200))!
        let elsewhere = nine.addingTimeInterval(3_600)
        store.pauseWorkSession(overrun, reason: "Break", now: nine.addingTimeInterval(2_100))
        let away = store.startWorkSession(for: inSlot, deviceID: "completion-check", now: elsewhere)!
        store.toggleCompletion(inSlot, now: elsewhere.addingTimeInterval(600))
        let inSlotRecord = store.completionRecords(taskID: inSlot.id).first!
        let settled = store.completedCalendarBlocks().filter { $0.completionID == inSlotRecord.id }
        check(away.endedAt == elsewhere.addingTimeInterval(600) && settled.allSatisfy(\.isTimeTracked)
                && settled.map { CompletionCalendarInterval(start: $0.start, end: $0.end) }
                == [CompletionCalendarInterval(start: nine, end: nine.addingTimeInterval(2_100)),
                    CompletionCalendarInterval(start: elsewhere, end: elsewhere.addingTimeInterval(600))],
              "Work done in a planned slot settles at the slot, stretched past its end, while work elsewhere and an unworked slot keep to what happened")
        store.calendarPlannedBlocks = []

        let legacyTask = store.appendBlock(kind: .task, text: "Legacy completion marker", to: .init(listID: list.id))
        let legacy = CompletionRecord(task: legacyTask, completedAt: completedAt)
        legacy.plannedIntervalsData = Data("not json".utf8)
        store.context.insert(legacy)
        store.save()
        let legacyBlock = store.completedCalendarBlocks().first { $0.completionID == legacy.id }!
        check(legacyBlock.start == completedAt && legacyBlock.end == completedAt && !legacyBlock.isTimeTracked, "Legacy or unreadable snapshots show a completion marker without inventing estimated work")

        let parent = store.appendBlock(kind: .task, text: "Undo recurring parent", to: .init(listID: list.id))
        parent.dueDate = day
        parent.recurrence = .weekly
        parent.reminderAt = nine
        let child = store.insertChild(text: "Undo unfinished child", of: parent)
        let doneChild = store.insertChild(text: "Undo previously done child", of: parent)
        store.toggleCompletion(doneChild, now: completedAt)
        let previousChildRecords = Set(store.completionRecords(taskID: doneChild.id).map(\.id))
        let parentBefore = CompletionTaskState(parent)
        let childOccurrence = child.occurrenceID
        let doneChildOccurrence = doneChild.occurrenceID
        store.selectForToday(parent, now: day)
        store.selectForToday(child, now: day)
        let pinned = store.setPlacement(for: parent, start: nine, end: completedAt, isPinned: true)!
        let pinnedID = pinned.id
        store.calendarPlannedBlocks = [slot(parent, nine, 60), slot(child, completedAt, 25)]
        let work = store.startWorkSession(for: parent, deviceID: "completion-check", now: nine)!
        let manager = UndoManager()
        manager.groupsByEvent = false
        var notifications = 0
        store.onCompletionUndoAvailable = { action in
            notifications += 1
            store.registerCompletionUndo(action, with: manager)
        }
        manager.beginUndoGrouping()
        store.toggleCompletion(parent, now: completedAt)
        manager.endUndoGrouping()
        let action = store.completionUndo!
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: day)!
        check(notifications == 1, "A parent completion publishes one saved Undo action")
        check(parent.deferredUntil == tomorrow && child.deferredUntil == tomorrow && parent.selectedForDay == nil, "Future recurring occurrences and their undated subtasks wait until tomorrow automatically")
        check(work.endedAt == completedAt && store.workSessions(taskID: parent.id).allSatisfy { $0.endedAt != nil }, "Completion pauses work before an Undo can restore task state")
        let changedDue = tomorrow.addingTimeInterval(5 * 86_400)
        parent.text = "Keep this later title edit"
        parent.note = "Keep this later note edit"
        store.setDueDate(changedDue, for: parent)
        manager.undo()
        check(parent.occurrenceID == parentBefore.occurrenceID && parent.recurrenceData == parentBefore.recurrenceData && !parent.isCompleted, "Native completion Undo restores the recurring occurrence and repeat rule")
        check(parent.dueDate == changedDue && parent.text == "Keep this later title edit" && parent.note == "Keep this later note edit", "Completion Undo preserves later due-date, title and note edits")
        check(parent.selectedForDay == day && parent.deferredUntil == nil && store.placements(taskID: parent.id).contains { $0.id == pinnedID && $0.isPinned }, "Undo restores selection and the exact original pinned placement")
        check(child.occurrenceID == childOccurrence && !child.isCompleted && doneChild.occurrenceID == doneChildOccurrence && doneChild.isCompleted, "Undo restores both unfinished and previously completed descendant states")
        check(store.completionRecords(taskID: parent.id).isEmpty && store.completionRecords(taskID: child.id).isEmpty && Set(store.completionRecords(taskID: doneChild.id).map(\.id)) == previousChildRecords, "Undo removes only completion records created by that parent action")
        check(work.durationMinutes() == 60 && work.endedAt == completedAt, "Undo preserves actual recorded work and never restarts tracking")
        manager.redo()
        check(parent.occurrenceID != parentBefore.occurrenceID && store.completionRecords(taskID: parent.id).count == 1 && store.placements(taskID: parent.id).isEmpty, "Native Redo restores the same completion snapshots and removes restored placements")
        check(work.durationMinutes() == 60 && store.workSessions(taskID: parent.id).count == 1, "Redo also preserves recorded work without creating a session")
        let probe = UndoProbe()
        manager.beginUndoGrouping()
        manager.registerUndo(withTarget: probe) { $0.value = 0 }
        manager.setActionName("Later unrelated edit")
        manager.endUndoGrouping()
        check(store.undoCompletion(action.id), "Snackbar Undo remains targeted even after another editable action")
        manager.undo()
        check(probe.value == 0 && !manager.canUndo, "Snackbar consumes only its own native Undo entry and does not swallow unrelated Undo")
        store.onCompletionUndoAvailable = nil
        store.selectForToday(parent, now: day)
        check(parent.deferredUntil == nil, "Explicit Today selection makes a future repeat eligible immediately")

        store.toggleCompletion(parent, now: completedAt)
        let oldAction = store.completionUndo!
        store.toggleCompletion(parent, now: completedAt.addingTimeInterval(60))
        let latestOccurrence = parent.occurrenceID
        check(!store.undoCompletion(oldAction.id) && parent.occurrenceID == latestOccurrence && store.completionRecords(taskID: parent.id).count == 2, "Undo rejects stale recurring actions after a later occurrence was completed")
        let deletedAction = store.completionUndo!
        store.deleteBlocks([parent])
        check(!store.undoCompletion(deletedAction.id) && store.block(id: parent.id) == nil, "Completion Undo never resurrects a deleted task")
        let failureTask = store.appendBlock(kind: .task, text: "Undo save failure", to: .init(listID: list.id))
        store.setPlacement(for: failureTask, start: nine, end: completedAt, isPinned: true)
        store.toggleCompletion(failureTask, now: completedAt)
        let failureAction = store.completionUndo!
        do {
            let readonly = try ModelContainer(for: AppPersistence.schema, configurations: [ModelConfiguration(schema: AppPersistence.schema, url: storeURL, allowsSave: false, cloudKitDatabase: .none)])
            let failing = Store(context: readonly.mainContext)
            failing.context.autosaveEnabled = false
            failing.completionUndoChanges[failureAction.id] = store.completionUndoChanges[failureAction.id]
            let task = failing.block(id: failureTask.id)!
            task.note = "Unrelated unsaved note"
            check(!failing.undoCompletion(failureAction.id) && failing.persistenceError != nil, "A real read-only save failure never acknowledges completion Undo")
            check(task.isCompleted && task.note == "Unrelated unsaved note" && failing.completionRecords(taskID: task.id).count == 1 && failing.placements(taskID: task.id).isEmpty, "Failed completion Undo restores only its own task, placement and history changes")
        } catch {
            check(false, "Read-only Undo failure fixture opens: \(error)")
        }
        store.editorNotice = nil
        store.calendarPlannedBlocks = []
        store.save()
    }

    static func runCompletionReopenChecks(store: Store) {
        let untracked = store.completionRecords().first { $0.title == "Untracked calendar snapshot" }!
        let blocks = store.completedCalendarBlocks().filter { $0.completionID == untracked.id }
        check(untracked.plannedIntervals.count == 2 && blocks.map(\.durationMinutes) == [25, 15] && blocks.allSatisfy { !$0.isTimeTracked }, "Split untracked completion slots survive a separate-process disk reopening")
        let tracked = store.completionRecords().first { $0.title == "Tracked calendar snapshot" }!
        let actual = store.completedCalendarBlocks().filter { $0.completionID == tracked.id }
        check(actual.map(\.durationMinutes) == [12, 20] && actual.allSatisfy(\.isTimeTracked), "Deleted-task actual completion intervals and corrections survive disk reopening")
        check(tracked.plannedIntervals.first?.start == Calendar.current.startOfDay(for: tracked.completedAt).addingTimeInterval(12 * 3_600) && tracked.plannedIntervals.first?.end.timeIntervalSince(tracked.plannedIntervals.first!.start) == 45 * 60, "Original pre-start plan survives completion and separate-process reopening")
        check(store.completionUndo == nil && store.completionUndoChanges.isEmpty, "Restart retains completion history without reviving transient Undo or tracking state")
    }
}
