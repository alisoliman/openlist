import AppKit
import SwiftData

@main struct CalendarPersistenceChecks {
    static var checks = 0
    static var failures = 0
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !condition() { failures += 1; print("FAIL  \(message)") }
    }

    static func main() throws {
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let phase = CommandLine.arguments[3]
        let container = try ModelContainer(for: AppPersistence.schema, configurations: [AppPersistence.configuration(at: url, iCloudEnabled: false)])
        let store = Store(context: container.mainContext)
        store.context.autosaveEnabled = false
        let legacyID = UUID(uuidString: "C0000000-0000-0000-0000-000000000001")!
        if phase == "migrate" {
            let legacy = store.block(id: legacyID)!
            let list = store.list(id: legacy.listID)!
            check(legacy.text == "Legacy café 日本語 ✅" && legacy.note == "Preserve rich task payload", "Legacy task text and note survive migration")
            check(legacy.priority == .high && legacy.includesTime && legacy.recurrence == .weekly && legacy.richData != nil, "Existing recurrence, rich text and metadata survive migration")
            check(legacy.schedulingEstimateMinutes == 0 && legacy.selectedForDay == nil && legacy.deferredUntil == nil, "Migrated tasks inherit estimates and stay unselected")
            check(!legacy.keepsSessionsTogether && !legacy.tracksAwayFromMac && list.availabilityCategoryRaw == "work", "Safe migration defaults preserve explicit-start tracking")
            check(store.workSessions().isEmpty && store.completionRecords().isEmpty && store.placements().isEmpty, "Migration fabricates no sessions, completions or placements")
            check(Set(store.blocks(inList: list.id).map(\.occurrenceID)).count == 2, "Each migrated task receives an independent occurrence identity")

            let day = Calendar.current.startOfDay(for: .now)
            store.calendarDefaultEstimateMinutes = 45
            store.setAvailabilityCategory("personal", for: list)
            let parent = store.appendBlock(kind: .task, text: "Weekly design review", to: .init(listID: list.id))
            parent.dueDate = day
            parent.recurrence = .weekly
            let child = store.insertChild(text: "Write design notes", of: parent)
            let firstOccurrence = parent.occurrenceID
            let childOccurrence = child.occurrenceID
            store.selectForToday(parent)
            store.setKeepTogether(true, for: parent)
            store.setTracksAway(true, for: parent)
            let start = Date.now.addingTimeInterval(-3_600)
            let first = store.startWorkSession(for: parent, deviceID: "fixture-mac", now: start)!
            check(first.id == store.startWorkSession(for: parent, deviceID: "fixture-mac", now: start.addingTimeInterval(60))?.id, "Starting the same active task does not duplicate work")
            store.pauseWorkSession(first, reason: "Meeting", now: start.addingTimeInterval(1_200))
            check(first.durationMinutes() == 20 && first.pauseReason == "Meeting", "Pause records exact active elapsed minutes")
            store.correctSession(first, minutes: 25)
            check(first.durationMinutes() == 25 && first.endedAt == start.addingTimeInterval(1_200), "Correction preserves original timestamps")
            store.correctSession(first, minutes: -5)
            check(first.durationMinutes() == 25, "Negative time corrections are rejected")
            store.correctSession(first, minutes: .infinity)
            check(first.durationMinutes() == 25, "Non-finite time corrections are rejected")
            store.correctSession(first, minutes: nil)
            check(first.durationMinutes() == 20, "Removing a correction restores observed time")
            store.correctSession(first, minutes: 25)

            let second = store.startWorkSession(for: parent, deviceID: "fixture-mac", now: start.addingTimeInterval(1_800))!
            let childSession = store.startWorkSession(for: child, deviceID: "fixture-mac", now: start.addingTimeInterval(2_400))!
            check(second.endedAt == childSession.startedAt && store.workSessions().filter { $0.endedAt == nil }.count == 1, "Starting another task ends previous active work")
            let preferred = store.setPlacement(for: parent, start: day.addingTimeInterval(32_400), end: day.addingTimeInterval(34_200))!
            let pinned = store.setPlacement(for: parent, start: day.addingTimeInterval(36_000), end: day.addingTimeInterval(37_800), isPinned: true)!
            check(store.placements(taskID: parent.id).count == 2 && !preferred.isPinned && pinned.isPinned, "Multiple sessions retain separate preferred and pinned placements")
            let preferredID = preferred.id
            store.setPlacement(for: parent, start: day.addingTimeInterval(37_800), end: day.addingTimeInterval(39_600), placementID: preferredID)
            check(store.placements(taskID: parent.id).count == 2 && preferred.start == day.addingTimeInterval(37_800), "Moving one placement retains the other session")

            store.toggleCompletion(parent)
            let record = store.completionRecords(taskID: parent.id).first!
            check(record.occurrenceID == firstOccurrence && record.wasRecurring && record.estimateMinutes == 45 && record.dueDate == day, "Completion snapshots original recurring occurrence and effective estimate")
            check(!parent.isCompleted && parent.occurrenceID != firstOccurrence && parent.dueDate != day, "Recurrence advances with a fresh occurrence")
            check(parent.selectedForDay == nil && parent.deferredUntil == Calendar.current.date(byAdding: .day, value: 1, to: day) && store.placements(taskID: parent.id).isEmpty, "Recurring completion removes old selections and placements and defers the new occurrence until tomorrow")
            check(childSession.endedAt != nil && child.occurrenceID != childOccurrence && !child.isCompleted && store.completionRecords(taskID: child.id).count == 1, "Recurring parent records and closes descendant work before reset")
            let suggestion = store.suggestedDuration(for: parent)!
            check(suggestion.minutes == 35 && suggestion.sampleCount == 1 && parent.schedulingEstimateMinutes == 0, "Suggestions use corrected completed work and never apply automatically")
            store.correctSession(first, minutes: 1e100)
            check(store.suggestedDuration(for: parent)?.minutes == 40_320, "Extreme corrected time cannot overflow a duration suggestion")
            store.correctSession(first, minutes: 25)
            store.setTaskEstimate(suggestion.minutes, for: parent)
            check(parent.schedulingEstimateMinutes == 35, "Explicit approval applies suggested duration")
            store.toggleCompletion(parent)
            check(Set(store.completionRecords(taskID: parent.id).map(\.occurrenceID)).count == 2, "Successive recurring completions retain distinct occurrence records")

            let plain = store.appendBlock(kind: .task, text: "Standalone task", to: .init(listID: list.id))
            let plainChild = store.insertChild(text: "Standalone child", of: plain)
            _ = store.startWorkSession(for: plainChild, deviceID: "fixture-mac", now: start)
            store.toggleCompletion(plain)
            check(plainChild.isCompleted && store.completionRecords(taskID: plainChild.id).count == 1 && store.workSessions(taskID: plainChild.id).allSatisfy { $0.endedAt != nil }, "Ordinary parent completion records and closes descendant sessions")
            let completedOccurrence = plain.occurrenceID
            store.toggleCompletion(plain)
            check(plain.occurrenceID != completedOccurrence && store.completionRecords(taskID: plain.id).count == 1, "Reopening preserves historical completion and starts a new occurrence")
            store.selectForToday(plain, now: day.addingTimeInterval(-86_400))
            check(plain.selectedForDay! < day, "Selection retains its original day so overflow stays eligible")
            store.setPlacement(for: plain, start: day, end: day.addingTimeInterval(1_800), isPinned: true)
            let deferralSession = store.startWorkSession(for: plain, deviceID: "fixture-mac", now: start)!
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: day)!
            store.deferTask(plain, to: tomorrow)
            check(deferralSession.endedAt != nil && plain.deferredUntil == tomorrow && plain.selectedForDay == tomorrow && store.placements(taskID: plain.id).isEmpty, "Deferral pauses work and replaces old placements with requested day")
            let clone = store.duplicateBlock(parent)
            check(clone.occurrenceID != parent.occurrenceID && clone.schedulingEstimateMinutes == parent.schedulingEstimateMinutes && clone.keepsSessionsTogether && clone.tracksAwayFromMac, "Duplication copies planning options but gives independent occurrence identity")
            check(store.workSessions(taskID: clone.id).isEmpty && store.completionRecords(taskID: clone.id).isEmpty && clone.selectedForDay == nil, "Duplicates inherit no work history or selection")

            let undo = UndoManager()
            store.undoableEditorEdit(in: list.id, name: "Delete selected task", undoManager: undo) { store.deleteBlocks([plain]) }
            undo.undo()
            let restored = store.block(id: plain.id)!
            check(restored.deferredUntil == tomorrow && restored.selectedForDay == tomorrow && restored.occurrenceID == plain.occurrenceID, "Native structural undo restores planning metadata and occurrence")
            let deletedID = parent.id
            store.deleteBlocks([parent])
            check(store.block(id: deletedID) == nil && store.completionRecords(taskID: deletedID).count == 2 && !store.workSessions(taskID: deletedID).isEmpty, "Deleting a task preserves occurrence and session history")

            let priorTask = store.appendBlock(kind: .task, text: "Prior active task", to: .init(listID: list.id))
            let startCandidate = store.appendBlock(kind: .task, text: "Save failure candidate", to: .init(listID: list.id))
            store.deferTask(startCandidate, to: tomorrow)
            let priorSession = store.startWorkSession(for: priorTask, deviceID: "fixture-mac", now: start)!
            let foreign = WorkSession(task: startCandidate, deviceID: "another-mac", startedAt: start)
            foreign.lastHeartbeatAt = start.addingTimeInterval(300)
            store.context.insert(foreign)
            store.save()
            do {
                let readonly = try ModelContainer(for: AppPersistence.schema, configurations: [
                    ModelConfiguration(schema: AppPersistence.schema, url: url, allowsSave: false, cloudKitDatabase: .none)
                ])
                let failing = Store(context: readonly.mainContext)
                failing.context.autosaveEnabled = false
                let candidate = failing.block(id: startCandidate.id)!
                let previous = failing.workSessions(taskID: priorTask.id).first!
                let imported = failing.workSessions(taskID: startCandidate.id).first!
                let sessionCount = failing.workSessions().count
                candidate.text = "Unsaved unrelated title draft"
                let failedStart = failing.startWorkSession(for: candidate, deviceID: "fixture-mac", now: start.addingTimeInterval(600))
                check(failedStart == nil && failing.persistenceError != nil, "Real read-only save failure never acknowledges Start")
                check(failing.workSessions().count == sessionCount, "Failed Start removes inserted session (\(failing.workSessions().count) versus \(sessionCount))")
                check(previous.endedAt == nil && imported.endedAt == nil, "Failed Start restores local and foreign active records")
                check(candidate.selectedForDay == tomorrow && candidate.deferredUntil == tomorrow && candidate.text == "Unsaved unrelated title draft", "Failed Start restores selection and deferral while preserving unrelated draft")
                check(!failing.pauseWorkSession(previous, reason: "Cannot save", now: start.addingTimeInterval(600)) && previous.endedAt == nil && previous.lastHeartbeatAt == priorSession.lastHeartbeatAt, "Real failed Pause reports failure and restores session state")
                var completionNotifications = 0
                failing.onCompletionUndoAvailable = { _ in completionNotifications += 1 }
                failing.toggleCompletion(candidate)
                check(completionNotifications == 0 && failing.completionUndo == nil && failing.persistenceError != nil, "A real failed completion save publishes no Undo acknowledgement")
            }
            let takeover = store.startWorkSession(for: startCandidate, deviceID: "fixture-mac", now: start.addingTimeInterval(600))!
            check(foreign.endedAt == foreign.lastHeartbeatAt && foreign.durationMinutes() == 5 && takeover.deviceID == "fixture-mac", "Explicit Start takes over foreign open work only through its last heartbeat")
            check(store.workSessions(taskID: startCandidate.id).filter { $0.endedAt == nil }.count == 1 && startCandidate.deferredUntil == nil, "Takeover keeps one observed open session and clears deferral")
            store.pauseWorkSession(takeover, reason: "Fixture finished", now: start.addingTimeInterval(900))
            let foreignCompletionTask = store.appendBlock(kind: .task, text: "Foreign completion", to: .init(listID: list.id))
            let foreignCompletion = WorkSession(task: foreignCompletionTask, deviceID: "another-mac", startedAt: start)
            foreignCompletion.lastHeartbeatAt = start.addingTimeInterval(300)
            store.context.insert(foreignCompletion)
            store.calendarDeviceID = "fixture-mac"
            store.toggleCompletion(foreignCompletionTask)
            check(foreignCompletion.durationMinutes() == 5, "Completion does not turn a foreign stale session into invented work history")
            runCompletionChecks(store: store, list: list, day: day, storeURL: url)
            store.save()
            check(store.persistenceError == nil, "Calendar mutations persist to migrated disk store")
        } else if phase == "reopen" {
            let legacy = store.block(id: legacyID)!
            check(legacy.text == "Legacy café 日本語 ✅" && store.list(id: legacy.listID)?.availabilityCategoryRaw == "personal", "Original task and list availability survive process reopening")
            let histories = store.completionRecords().filter { $0.title == "Weekly design review" }
            check(histories.count == 2 && histories.allSatisfy { $0.wasRecurring }, "Deleted recurring task retains completion history after reopening")
            let work = store.workSessions().first { $0.correctedMinutes == 25 }
            check(work != nil && work?.durationMinutes() == 25, "Corrected time persists across process restart")
            let active = store.allLists().flatMap { store.blocks(inList: $0.id) }.first { $0.text == "Standalone task" }!
            check(active.deferredUntil != nil && active.selectedForDay == active.deferredUntil, "Deferred selection survives restart")
            runCompletionReopenChecks(store: store)
            store.clearCalendarHistory()
            check(store.workSessions().isEmpty && store.completionRecords().isEmpty && store.placements().isEmpty, "Explicit reset clears all calendar history and placements")
            check(store.block(id: legacyID) != nil && store.persistenceError == nil, "Calendar reset preserves live task data")
        } else if phase == "verify-reset" {
            check(store.workSessions().isEmpty && store.completionRecords().isEmpty && store.placements().isEmpty, "History reset remains durable after separate-process reopening")
            check(store.block(id: legacyID) != nil, "Calendar reset does not erase existing task content")
        } else if phase == "legacy-completion" {
            let record = store.completionRecords().first!
            check(record.title == "Pre-snapshot recurring completion" && record.wasRecurring && record.estimateMinutes == 45 && record.dueDate == Date(timeIntervalSince1970: 1_749_999_000), "Existing completion snapshots survive additive interval migration")
            check(record.plannedIntervalsData == nil && record.plannedIntervals.isEmpty, "Interval migration fabricates no planned time")
            let session = store.workSessions().first!
            check(session.title == "Pre-snapshot work session" && session.durationMinutes() == 20 && session.deviceID == "legacy-mac" && session.plannedIntervalsData == nil, "Existing recorded work and corrections survive additive original-plan migration")
            let marker = store.completedCalendarBlocks().first!
            check(marker.start == record.completedAt && marker.end == record.completedAt && marker.isCompleted && !marker.isTimeTracked, "Migrated completions without recorded intervals display a timestamp marker")
        }
        print(failures == 0 ? "✅ \(checks) calendar persistence checks passed (\(phase))" : "❌ \(failures)/\(checks) calendar persistence checks failed (\(phase))")
        exit(failures == 0 ? 0 : 1)
    }
}
