import Foundation
import SwiftData

var checks = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    guard value() else { fatalError("FAIL: \(message)") }
}
let calendar = Calendar.current
func date(_ day: Int = 14, _ hour: Int = 9, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
}
let schema = Schema([TaskList.self, Block.self, SidebarSection.self, TaskLabel.self, Attachment.self, ActivityEvent.self,
                     WorkSession.self, CompletionRecord.self, SchedulePlacement.self])
let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
let container = try ModelContainer(for: schema, configurations: [config])
let store = Store(context: container.mainContext)
store.bootstrap()
let list = store.inboxList()!
let defaults = ReviewSession.defaults
let suite = "openlist.calendar.runtime." + CommandLine.arguments[1]
defer { defaults.removePersistentDomain(forName: suite) }
let events = [FixedBusyTime(id: "meeting", title: "Fixture meeting", start: date(14, 10), end: date(14, 11))]
let external = ExternalCalendarSource(defaults: defaults, fixtureBusyTimes: events)
let coordinator = CalendarCoordinator(store: store, defaults: defaults, externalCalendars: external)
coordinator.bootstrap(now: date(), monitorsEnabled: false)
func task(_ title: String, minutes: Int = 30, due: Date? = nil, selected: Bool = true) -> Block {
    let task = Block(kind: .task, text: title, listID: list.id)
    task.schedulingEstimateMinutes = minutes
    task.dueDate = due
    task.includesTime = due != nil
    if selected { task.selectedForDay = date() }
    store.context.insert(task)
    store.save()
    return task
}
let a = task("Write brief")
let b = task("Review brief")
coordinator.replan(now: date())
check(coordinator.activeSession == nil && store.workSessions().isEmpty, "a scheduled block does not start tracking")
coordinator.tick(now: date(14, 9, 20))
check(coordinator.activeSession == nil && store.workSessions().isEmpty, "passing planned start never implies active work")
check(coordinator.start(task: a, now: date()), "explicit Start opens an available session")
check(coordinator.activeSession?.taskID == a.id, "exactly the started task is active")
coordinator.tick(now: date(14, 9, 30), checkClockGap: false)
check(coordinator.activeSession?.taskID == a.id, "reaching the estimate keeps recording")
check(coordinator.workExtension?.end == date(14, 9, 45) && coordinator.workExtension?.minutes == 15, "the block grows to the next quarter hour plus 15 minutes")
check(coordinator.workExtension?.movedTaskIDs == [b.id], "the extension names the flexible task it moved")
coordinator.tick(now: date(14, 9, 31), checkClockGap: false)
let activeForecast = coordinator.plan.blocks.first { $0.isActive }
check(activeForecast?.end == date(14, 9, 45), "31-minute overrun extends the original estimate to 45 minutes")
check(coordinator.plan.blocks.filter { $0.taskID == b.id }.allSatisfy { $0.start >= date(14, 9, 45) }, "active overrun displaces flexible work")
coordinator.tick(now: date(14, 9, 46), checkClockGap: false)
check(coordinator.plan.blocks.first { $0.isActive }?.end == date(14, 10), "second overrun grows only as far as the next meeting")
coordinator.tick(now: date(14, 10, 7), checkClockGap: false)
check(coordinator.activeSession?.taskID == a.id, "running into a meeting keeps recording")
check(coordinator.workConflict?.kind == .event && coordinator.workConflict?.title == "Fixture meeting"
      && coordinator.workConflict?.start == date(14, 10), "the conflict names the meeting and when it starts")
check(coordinator.plan.blocks.first { $0.isActive }?.end == date(14, 10), "the working block never grows into the meeting")
check(coordinator.trackedMinutes(for: a, now: date(14, 10, 7)) == 67, "recording carries on through the meeting")
coordinator.pause(now: date(14, 10, 10))
check(store.workSessions(taskID: a.id).first?.endedAt == date(14, 10, 10), "pausing in the meeting records up to the click")
check(coordinator.workConflict == nil && coordinator.workExtension == nil, "pausing clears the conflict and the extension")
check(coordinator.plan.blocks.filter { $0.taskID == a.id }.allSatisfy { $0.start >= date(14, 11) }, "remaining work uses next slot after meeting")
check(coordinator.start(task: a, now: date(14, 10, 20)), "Start records during fixed busy time too")
check(!coordinator.plan.blocks.contains { $0.isActive }, "work started in a meeting has no block to grow")
coordinator.pause(now: date(14, 10, 30))
check(coordinator.start(task: a, now: date(14, 11)), "work can explicitly resume after meeting")
coordinator.handleMacUnavailable(reason: "Mac locked", now: date(14, 11, 5))
check(coordinator.activeSession == nil && coordinator.resumeTaskID == a.id, "lock pauses work and offers resume")
check(store.workSessions(taskID: a.id).first?.durationMinutes() == 5, "lock pause does not count absent time")
coordinator.handleMacReturn(now: date(14, 11, 15))
check(coordinator.activeSession == nil && coordinator.resumeTaskID == a.id, "return requires approval rather than auto-resuming")
store.setTracksAway(true, for: a)
store.setTaskEstimate(180, for: a) // Keep the estimate beyond lunch to isolate the hard-boundary rule.
check(coordinator.start(task: a, now: date(14, 11, 15)), "away-tracking task can start")
coordinator.handleMacUnavailable(reason: "Mac slept", now: date(14, 11, 20))
check(coordinator.activeSession?.taskID == a.id, "per-task away opt-in keeps session active")
coordinator.handleMacReturn(now: date(14, 12, 10))
check(coordinator.activeSession?.taskID == a.id, "away-tracked work keeps recording into a break")
check(coordinator.workConflict?.kind == .breakTime && coordinator.workConflict?.start == date(14, 12), "running into a break marks the conflict at the break")
let short = task("Two-minute reply", minutes: 2)
check(coordinator.remainingMinutes(for: short, now: date()) == 2, "short tasks retain short estimates")
check(coordinator.start(task: short, now: date(14, 13)), "short task explicitly starts")
coordinator.replan(now: date(14, 13))
check(coordinator.plan.blocks.first { $0.isActive }?.durationMinutes == 2, "active short task is not padded to 15 minutes")
coordinator.pause(now: date(14, 13, 1))
check(coordinator.remainingMinutes(for: short, now: date(14, 13, 1)) == 1, "pause preserves a short remaining duration")
let session = store.workSessions(taskID: short.id).first!
store.correctSession(session, minutes: 0.5)
check(coordinator.remainingMinutes(for: short, now: date(14, 13, 1)) == 1.5, "time correction changes remaining plan")
let deferred = task("Future choice", selected: false)
store.deferTask(deferred, to: date(15))
coordinator.replan(now: date())
check(coordinator.plan.blocks.contains { $0.taskID == deferred.id && $0.start >= calendar.startOfDay(for: date(15)) }, "explicitly deferred undated work is scheduled on its future day")
let backlog = task("Unselected backlog", selected: false)
coordinator.replan(now: date())
check(!coordinator.plan.assessments.contains { $0.taskID == backlog.id }, "unselected undated backlog stays outside scheduling")
let beyond = task("Later deadline", due: date(30).addingTimeInterval(30 * 86400), selected: false)
coordinator.replan(now: date())
check(coordinator.plan.assessments.first { $0.taskID == beyond.id }?.status == .outsidePlanningHorizon, "far deadlines have explicit horizon status")
store.setTracksAway(false, for: a)
check(coordinator.start(task: a, now: date(14, 14)), "session starts for gap test")
coordinator.tick(now: date(14, 14, 5))
check(coordinator.activeSession == nil, "unobserved clock gap conservatively pauses work")
check(store.workSessions(taskID: a.id).first?.endedAt == date(14, 14), "clock gap never fabricates active work")
let restartTask = task("Recover session")
check(coordinator.start(task: restartTask, now: date(14, 14, 10)), "restart fixture starts")
coordinator.tick(now: date(14, 14, 11), checkClockGap: false)
let recovered = CalendarCoordinator(store: store, defaults: defaults, externalCalendars: external)
recovered.bootstrap(now: date(14, 16), monitorsEnabled: false)
check(recovered.activeSession == nil && recovered.resumeTaskID == restartTask.id, "relaunch offers resume instead of counting application absence")
check(store.workSessions(taskID: restartTask.id).first?.endedAt == date(14, 14, 11), "restart closes at last persisted heartbeat")
let autoComplete = task("Checkbox completed")
check(recovered.start(task: autoComplete, now: date(14, 16)), "session starts before checkbox completion")
store.toggleCompletion(autoComplete)
recovered.tick(now: date(14, 16, 1), checkClockGap: false)
check(recovered.activeSession == nil && store.completionRecords(taskID: autoComplete.id).count == 1, "ordinary checkbox completion records history and stops active coordinator")
let remoteTask = task("Remote heartbeat", minutes: 60)
let remote = WorkSession(task: remoteTask, deviceID: "another-Mac", startedAt: date(15, 13))
remote.lastHeartbeatAt = date(15, 13, 5)
store.context.insert(remote)
store.save()
check(recovered.trackedMinutes(for: remoteTask, now: date(15, 15)) == 5, "foreign open work counts only through its last observed heartbeat")
check(recovered.remainingMinutes(for: remoteTask, now: date(15, 15)) == 55, "foreign crash cannot consume unobserved estimate")
check(recovered.start(task: remoteTask, now: date(15, 15)), "explicit Start takes over work on this Mac")
check(remote.endedAt == date(15, 13, 5), "takeover closes foreign session at confirmed heartbeat")
check(store.workSessions(taskID: remoteTask.id).filter { $0.endedAt == nil }.count == 1, "takeover leaves one known open occurrence session")
recovered.pause(now: date(15, 15, 1))
let archivedList = store.createList(title: "Archived pin owner")
let archivedTask = Block(kind: .task, text: "Archived pinned task", listID: archivedList.id)
store.context.insert(archivedTask)
store.setPlacement(for: archivedTask, start: date(16, 13), end: date(16, 14), isPinned: true)
archivedList.isArchived = true
store.save()
let freeTask = task("Free despite archived pin")
check(recovered.isWithinAvailability(WorkTaskReference(freeTask), now: date(16, 13)), "archived task's retained pin cannot turn a visually free slot into busy time")
check(recovered.start(task: freeTask, now: date(16, 13)), "archived pin fixture starts")
recovered.pause(now: date(16, 13, 1))
let gapTask = task("Missed notification across lunch")
check(recovered.start(task: gapTask, now: date(16, 11)), "gap across break fixture starts")
recovered.tick(now: date(16, 11, 1), checkClockGap: false)
recovered.tick(now: date(16, 13, 5))
check(store.workSessions(taskID: gapTask.id).first?.durationMinutes() == 1, "clock gap is capped at last observation even when a meeting or break was crossed")
check(recovered.activeSession == nil, "missed notification leaves work paused")
let resetTask = task("Reset active history")
check(recovered.start(task: resetTask, now: date(16, 14)), "reset fixture starts")
store.clearCalendarHistory()
recovered.tick(now: date(16, 14, 1), checkClockGap: false)
check(recovered.activeSession == nil, "deleting history cannot leave a ghost active model")
check(store.workSessions().isEmpty, "history reset removes all saved sessions")

// Exercise recovery against an actual read-only persistent store, rather than
// mocking the save result. Later reopen the same SQLite file writable so the
// recovery path proves that app absence never becomes recorded work.
func checkReadOnlyRecovery() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("OpenlistCalendarRecovery-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("Recovery.store")
    let taskID = UUID()
    let sessionID = UUID()
    let deviceID = defaults.string(forKey: "calendar.deviceID")!
    do {
        let writable = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        let fixture = Store(context: writable.mainContext)
        fixture.context.autosaveEnabled = false
        fixture.bootstrap()
        let task = Block(kind: .task, text: "Recover unsaved pause", listID: fixture.inboxList()!.id)
        task.id = taskID
        task.schedulingEstimateMinutes = 60
        fixture.context.insert(task)
        let session = WorkSession(task: task, deviceID: deviceID, startedAt: date(14, 9))
        session.id = sessionID
        session.lastHeartbeatAt = date(14, 9, 5)
        fixture.context.insert(session)
        try fixture.persistChanges()
    }
    do {
        let readonly = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, allowsSave: false, cloudKitDatabase: .none)])
        let failing = Store(context: readonly.mainContext)
        failing.context.autosaveEnabled = false
        let task = failing.block(id: taskID)!
        let source = ExternalCalendarSource(defaults: defaults, fixtureBusyTimes: [])
        let recovery = CalendarCoordinator(store: failing, defaults: defaults, externalCalendars: source)
        recovery.bootstrap(now: date(14, 13), monitorsEnabled: false)
        check(failing.persistenceError != nil && recovery.notice == failing.persistenceError, "failed recovery surfaces the real storage error instead of claiming work was paused")
        check(recovery.activeSession == nil && failing.workSessions().first?.endedAt == nil, "failed recovery does not adopt the stale open session as active")
        check(recovery.trackedMinutes(for: task, now: date(14, 15)) == 5 && recovery.remainingMinutes(for: task, now: date(14, 15)) == 55, "failed recovery counts only the five confirmed minutes while storage remains unavailable")
        check(!recovery.start(task: task, now: date(14, 13)), "Start fails while the orphan session cannot be durably recovered")
        check(recovery.activeSession == nil && failing.workSessions().count == 1 && failing.workSessions().first?.id == sessionID, "failed recovery retry creates no additional or phantom active session")
        check(failing.workSessions().first?.lastHeartbeatAt == date(14, 9, 5) && failing.workSessions().first?.endedAt == nil && recovery.notice == failing.persistenceError, "failed retry preserves the original heartbeat and actionable error")
    }
    do {
        let writable = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        let fixture = Store(context: writable.mainContext)
        fixture.context.autosaveEnabled = false
        let task = fixture.block(id: taskID)!
        let source = ExternalCalendarSource(defaults: defaults, fixtureBusyTimes: [])
        let recovery = CalendarCoordinator(store: fixture, defaults: defaults, externalCalendars: source)
        recovery.bootstrap(now: date(14, 13), monitorsEnabled: false)
        check(fixture.persistenceError == nil && fixture.workSessions().first?.endedAt == date(14, 9, 5), "writable reopening durably recovers the original session at its last heartbeat")
        check(recovery.activeSession == nil && recovery.resumeTaskID == taskID, "successful retry still requires explicit resume")
        check(recovery.start(task: task, now: date(14, 13)), "explicit Start succeeds after storage recovers")
        check(recovery.activeSession?.id != sessionID && recovery.activeSession?.startedAt == date(14, 13), "successful resume starts a fresh session at the actual resume time")
        check(recovery.trackedMinutes(for: task, now: date(14, 13, 1)) == 6, "resumed time adds one new minute without counting four hours of app absence")
        recovery.pause(now: date(14, 13, 2))
    }
    do {
        let reopened = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        let fixture = Store(context: reopened.mainContext)
        let sessions = fixture.workSessions(taskID: taskID)
        check(sessions.count == 2 && sessions.allSatisfy { $0.endedAt != nil } && sessions.reduce(0, { $0 + $1.durationMinutes() }) == 7, "recovered five-minute and resumed two-minute sessions survive another disk reopen")
    }
}
store.deferTask(backlog, to: date(15))
store.deselectForToday(backlog)
recovered.replan(now: date())
check(backlog.deferredUntil == nil && !recovered.plan.assessments.contains { $0.taskID == backlog.id }, "clearing an undated deferral returns work to unscheduled backlog")
// Manual preferences remain flexible, but an infeasible drop must explain why
// the visible block moved elsewhere. Explicit pinning retains the requested time.
func checkManualMoveFeedback() throws {
    let moveContainer = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
    let moveStore = Store(context: moveContainer.mainContext)
    moveStore.bootstrap()
    let movedTask = Block(kind: .task, text: "Move feedback fixture", listID: moveStore.inboxList()!.id)
    movedTask.schedulingEstimateMinutes = 30
    movedTask.selectedForDay = date()
    moveStore.context.insert(movedTask)
    moveStore.save()
    let source = ExternalCalendarSource(defaults: defaults, fixtureBusyTimes: events)
    let planner = CalendarCoordinator(store: moveStore, defaults: defaults, externalCalendars: source)
    planner.bootstrap(now: date(), monitorsEnabled: false)
    func currentBlock() -> PlannedBlock { planner.plan.blocks.first { $0.taskID == movedTask.id }! }

    planner.move(block: currentBlock(), to: date(14, 18), now: date())
    check(planner.notice?.contains("outside work hours") == true, "unavailable preferred move explains why it was not honored")
    check(moveStore.placements(taskID: movedTask.id).contains { $0.start == date(14, 18) && !$0.isPinned }, "unavailable move still saves a preference without silently pinning")
    check(currentBlock().start != date(14, 18), "unavailable preferred time does not contaminate the feasible schedule")

    planner.move(block: currentBlock(), to: date(14, 13), now: date())
    check(currentBlock().start == date(14, 13) && currentBlock().placementID != nil, "feasible move is actually represented by its saved placement")
    check(planner.notice == nil, "honored move clears a previous rejection notice")

    planner.move(block: currentBlock(), to: date(14, 10), now: date())
    check(planner.notice?.contains("Fixture meeting") == true, "busy-time rejection names the conflicting external event")
    check(currentBlock().start != date(14, 10), "preferred move cannot overlap fixed busy time")

    planner.move(block: currentBlock(), to: date(14, 10), isPinned: true, now: date())
    let pinned = currentBlock()
    check(pinned.isPinned && pinned.start == date(14, 10), "explicit Pin time preserves an otherwise infeasible requested time")
    check(pinned.conflicts.contains { $0.contains("Fixture meeting") }, "explicit pinned conflict remains visible on the scheduled block")
    check(planner.notice?.contains("Pinned time saved.") == true && planner.notice?.contains("Fixture meeting") == true, "pinning confirms the saved time and explains its conflict")
    movedTask.dueDate = date(14, 16)
    movedTask.includesTime = true
    moveStore.save()
    planner.replan(now: date())
    let coverage = planner.plan.assessments.first { $0.taskID == movedTask.id }!
    check(coverage.status == .cannotFitBeforeDeadline && coverage.beforeDeadlineMinutes == 0, "a meeting-conflicting pin never counts as safe deadline coverage")

    planner.move(block: currentBlock(), to: date(14, 13), isPinned: true, now: date())
    check(currentBlock().isPinned && currentBlock().conflicts.isEmpty && planner.notice == nil, "moving the pin into free hours clears its previous conflict notice")
    planner.move(block: currentBlock(), to: date(14, 16, 30), now: date())
    check(planner.notice?.contains("after the task’s deadline") == true, "after-deadline preferred move has a specific explanation")

    let distant = calendar.date(byAdding: .day, value: 40, to: date())!
    planner.move(block: currentBlock(), to: distant, now: date())
    check(planner.notice?.contains("four-week planning horizon") == true, "outside-horizon preferred move explains its planning boundary")

    let tomorrowTask = Block(kind: .task, text: "Selected today, preferred tomorrow", listID: moveStore.inboxList()!.id)
    tomorrowTask.selectedForDay = date()
    tomorrowTask.schedulingEstimateMinutes = 30
    moveStore.context.insert(tomorrowTask)
    moveStore.save()
    planner.replan(now: date())
    let tomorrowBlock = planner.plan.blocks.first { $0.taskID == tomorrowTask.id }!
    planner.move(block: tomorrowBlock, to: date(15, 13), now: date())
    check(planner.plan.blocks.contains { $0.taskID == tomorrowTask.id && $0.start == date(15, 13) && $0.placementID != nil }, "a feasible next-day preference is honored for a task selected today")
    check(planner.notice == nil, "honored next-day placement produces no false rejection notice")
}
// These clocks operate on the same production coordinator as the app; no timer
// sleeps or automatic task starts are involved.
func checkSchedulingNudges() throws {
    func fixture(events: [FixedBusyTime] = []) throws -> (Store, CalendarCoordinator, ModelContainer) {
        let fixtureContainer = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        let fixtureStore = Store(context: fixtureContainer.mainContext)
        fixtureStore.bootstrap()
        let source = ExternalCalendarSource(defaults: defaults, fixtureBusyTimes: events)
        let planner = CalendarCoordinator(store: fixtureStore, defaults: defaults, externalCalendars: source)
        return (fixtureStore, planner, fixtureContainer)
    }
    func add(_ title: String, to fixture: Store, minutes: Int = 30, priority: Int = 0, due: Date? = nil) -> Block {
        let result = Block(kind: .task, text: title, listID: fixture.inboxList()!.id)
        result.selectedForDay = date()
        result.schedulingEstimateMinutes = minutes
        result.priorityRaw = priority
        result.dueDate = due
        result.includesTime = due != nil
        fixture.context.insert(result)
        fixture.save()
        return result
    }
    do {
        let (fixtureStore, planner, lifetime) = try fixture()
        defer { withExtendedLifetime(lifetime) {} }
        let first = add("Missed deadline session", to: fixtureStore, priority: 3, due: date(14, 9, 30))
        let second = add("Keep the next commitment", to: fixtureStore, priority: 2)
        let third = add("Keep another commitment", to: fixtureStore, priority: 1)
        planner.bootstrap(now: date(14, 8, 59), monitorsEnabled: false)
        let original = planner.plan.blocks
        check(original.first?.taskID == first.id && original.first?.start == date(), "deadline task is promised the opening slot")
        let anchor = Dictionary(uniqueKeysWithValues: original.filter { $0.taskID != first.id }.map { ($0.taskID, $0.start) })
        var nudgeChanges = 0
        planner.onNudgesChanged = { nudgeChanges += 1 }
        planner.tick(now: date())
        check(planner.startNudge?.taskID == first.id && planner.startNudge?.scheduledStart == date(), "scheduled start offers an explicit Start nudge")
        check(planner.startNudge?.graceEndsAt == date(14, 9, 5), "nudge has a five-minute grace period")
        planner.tick(now: date(14, 9, 4).addingTimeInterval(59))
        check(planner.plan.blocks.map(\.start) == original.map(\.start), "timer ticks preserve every placement throughout the grace period")
        check(fixtureStore.workSessions().isEmpty, "a visible or ignored start nudge never records work")
        planner.tick(now: date(14, 9, 5))
        let moved = planner.plan.blocks.first { $0.taskID == first.id }!
        check(moved.start == date(14, 10, 30), "ignored task uses the next gap that fits its whole short session")
        check(planner.plan.blocks.filter { $0.taskID == second.id || $0.taskID == third.id }.allSatisfy { anchor[$0.taskID] == $0.start }, "missing a start never shifts the other promised tasks")
        let risk = planner.plan.assessments.first { $0.taskID == first.id }!
        check(risk.status == .cannotFitBeforeDeadline && risk.beforeDeadlineMinutes == 0, "lost deadline coverage is flagged after the missed start")
        check(planner.rescheduleSummary?.taskIDs == [first.id] && planner.rescheduleSummary?.movedTaskCount == 1, "reschedule feedback identifies only the task actually moved")
        check(planner.startNudge == nil && nudgeChanges == 2, "start nudge clears once moved and does not repeat on unchanged ticks")
        planner.tick(now: date(14, 9, 6))
        check(planner.plan.blocks.first { $0.taskID == first.id }?.start == date(14, 10, 30), "subsequent timer ticks retain the replacement gap")
        check(fixtureStore.calendarPlannedBlocks.map(\.id) == planner.plan.blocks.map(\.id), "Store receives the current plan for later completion snapshots")
        second.text += " renamed"
        fixtureStore.save()
        planner.storeDidChange(now: date(14, 9, 10))
        check(planner.plan.blocks.first { $0.taskID == second.id }?.start == anchor[second.id], "an unrelated title save cannot drift the established schedule")
        check(planner.rescheduleSummary?.message == "1 task rescheduled.", "reschedule feedback leads with the number of affected tasks")
    }
    do {
        let (fixtureStore, planner, lifetime) = try fixture()
        defer { withExtendedLifetime(lifetime) {} }
        let first = add("One free extension", to: fixtureStore, priority: 3)
        let next = add("Work that needs protection", to: fixtureStore, priority: 2)
        planner.bootstrap(now: date(), monitorsEnabled: false)
        check(planner.start(task: first, now: date()), "nudge fixture requires an explicit start")
        planner.tick(now: date(14, 9, 28), checkClockGap: false)
        check(planner.overrunNudge?.estimatedEnd == date(14, 9, 30) && planner.overrunNudge?.proposedEnd == date(14, 9, 45), "estimated finish gives one quiet heads-up")
        check(planner.startNudge == nil, "an active task suppresses unstarted work nudges")
        planner.tick(now: date(14, 9, 29), checkClockGap: false)
        check(planner.activeSession != nil && planner.plan.blocks.first { $0.isActive }?.end == date(14, 9, 45), "a minute before the estimate the block grows to the next quarter hour plus 15 minutes")
        let nextAnchor = planner.plan.blocks.first { $0.taskID == next.id }!
        check(nextAnchor.start == date(14, 9, 45), "the extension moves the following flexible task")
        check(planner.workExtension?.movedTaskIDs == [next.id] && planner.rescheduleSummary?.taskIDs == [next.id], "extension summary names displaced work")
        check(planner.overrunNudge == nil, "heads-up clears after the extension")
        planner.tick(now: date(14, 9, 40), checkClockGap: false)
        check(planner.overrunNudge == nil && planner.workExtension?.minutes == 15 && planner.plan.blocks.first { $0.taskID == next.id }?.start == nextAnchor.start, "routine ticks do not extend again or drift the next task")
        planner.tick(now: date(14, 9, 44), checkClockGap: false)
        check(planner.activeSession != nil && planner.plan.blocks.first { $0.isActive }?.end == date(14, 10) && planner.workExtension?.minutes == 30, "a further extension keeps recording and adds another step")
        check(planner.plan.blocks.first { $0.taskID == next.id }?.start == date(14, 10), "a further extension keeps moving later flexible work")
        let grant = planner.workExtension!
        check(planner.undoExtension(grant, now: date(14, 9, 45)), "Undo takes the latest extension back")
        check(planner.plan.blocks.first { $0.isActive }?.end == date(14, 9, 45) && planner.plan.blocks.first { $0.taskID == next.id }?.start == date(14, 9, 45), "Undo puts back the blocks from before the extension")
        check(planner.activeSession != nil && planner.workExtension?.minutes == 15, "Undo keeps recording and the earlier extension")
        planner.tick(now: date(14, 9, 48), checkClockGap: false)
        check(planner.plan.blocks.first { $0.isActive }?.end == date(14, 9, 45) && planner.workExtension?.minutes == 15, "an undone extension is not granted again by itself")
        check(planner.redoExtension(grant, now: date(14, 9, 48)), "Redo gives the extension back")
        check(planner.plan.blocks.first { $0.isActive }?.end == date(14, 10) && planner.plan.blocks.first { $0.taskID == next.id }?.start == date(14, 10), "Redo restores the extended blocks")
        check(!planner.redoExtension(grant, now: date(14, 9, 48)), "an extension is given back only once")
        planner.complete(task: first, now: date(14, 9, 55))
        check(planner.overrunNudge == nil && planner.workExtension == nil && planner.plan.blocks.allSatisfy { $0.taskID != first.id }, "Done clears the extension and flexible work")
        check(planner.completedBlocks.filter { $0.taskID == first.id }.count == 1, "completed calendar retains the actual work segment")
        check(planner.visibleBlocks.filter { $0.taskID == first.id }.allSatisfy { $0.isCompleted && $0.isTimeTracked }, "completion display distinguishes tracked history from upcoming work")
        check(planner.completedBlocks.filter { $0.taskID == first.id }.reduce(0, { $0 + $1.durationMinutes }) == 55, "completed history keeps the time recorded past the estimate")
    }
    do {
        let (fixtureStore, planner, lifetime) = try fixture()
        defer { withExtendedLifetime(lifetime) {} }
        let first = add("Update a running estimate", to: fixtureStore, priority: 3)
        let second = add("Protect after an estimate edit", to: fixtureStore, priority: 2)
        planner.bootstrap(now: date(), monitorsEnabled: false)
        check(planner.start(task: first, now: date()), "editable active estimate fixture starts")
        planner.tick(now: date(14, 9, 30), checkClockGap: false)
        check(planner.workExtension?.end == date(14, 9, 45), "estimate edit fixture is extended once")
        first.schedulingEstimateMinutes = 60
        fixtureStore.save()
        planner.storeDidChange(now: date(14, 9, 31))
        check(planner.plan.blocks.first { $0.isActive }?.end == date(14, 10), "a material estimate edit updates active runway to the revised estimate")
        check(planner.plan.blocks.first { $0.taskID == second.id }?.start == date(14, 10), "a changed active estimate reflows the following task")
        check(planner.rescheduleSummary?.taskIDs == [second.id], "material replan feedback identifies the other task that moved")
        check(planner.workExtension == nil, "the revised estimate replaces the time given past the old one")
        planner.tick(now: date(14, 10), checkClockGap: false)
        check(planner.activeSession != nil && planner.workExtension?.end == date(14, 10, 15) && planner.workExtension?.minutes == 15, "the revised estimate is extended like the original one")
        check(planner.plan.blocks.first { $0.taskID == second.id }?.start == date(14, 10, 15), "extending the revised estimate moves the following task")
    }
    do {
        let (fixtureStore, planner, lifetime) = try fixture()
        defer { withExtendedLifetime(lifetime) {} }
        let first = add("Finish early", to: fixtureStore, priority: 3)
        let second = add("Move into released time", to: fixtureStore, priority: 2)
        planner.bootstrap(now: date(), monitorsEnabled: false)
        planner.complete(task: first, now: date(14, 9, 10))
        check(planner.plan.blocks.first { $0.taskID == second.id }?.start == date(14, 9, 10), "early completion releases time through a material replan")
        check(planner.rescheduleSummary?.taskIDs == [second.id], "completion summary excludes the completed task itself")
        check(planner.completedBlocks.first { $0.taskID == first.id }?.isTimeTracked == false, "untracked completion uses planned history without fabricating a work session")
    }
    do {
        let (fixtureStore, planner, lifetime) = try fixture(events: [FixedBusyTime(id: "boundary", title: "Fixed meeting", start: date(14, 10), end: date(14, 11))])
        defer { withExtendedLifetime(lifetime) {} }
        let solo = add("Uninterrupted free time", to: fixtureStore)
        planner.bootstrap(now: date(), monitorsEnabled: false)
        check(planner.start(task: solo, now: date()), "solo work starts in availability")
        planner.tick(now: date(14, 9, 30), checkClockGap: false)
        planner.tick(now: date(14, 9, 46), checkClockGap: false)
        check(planner.activeSession != nil && planner.overrunNudge == nil && planner.plan.blocks.first { $0.isActive }?.end == date(14, 10), "empty free gaps allow further extensions without gratuitous confirmation")
        planner.tick(now: date(14, 10, 5), checkClockGap: false)
        check(planner.activeSession != nil && planner.workConflict?.title == "Fixed meeting" && planner.workConflict?.start == date(14, 10), "a meeting stops the block growing, not the recording")
        check(planner.plan.blocks.first { $0.isActive }?.end == date(14, 10), "even free extensions never grow into a meeting")
        planner.tick(now: date(14, 10, 20), checkClockGap: false)
        check(planner.workConflict?.start == date(14, 10) && planner.trackedMinutes(for: solo, now: date(14, 10, 20)) == 80, "work keeps recording through the meeting it ran into")
        planner.pause(now: date(14, 10, 30))
        check(planner.workConflict == nil && fixtureStore.workSessions(taskID: solo.id).first?.endedAt == date(14, 10, 30), "pausing records up to the click and clears the conflict")
    }
    do {
        let (fixtureStore, planner, lifetime) = try fixture(events: [FixedBusyTime(id: "late-boundary", title: "Fixed meeting", start: date(14, 10), end: date(14, 11))])
        defer { withExtendedLifetime(lifetime) {} }
        let first = add("Late overrun callback", to: fixtureStore, priority: 3)
        let deadline = add("Ten-minute deadline", to: fixtureStore, minutes: 10, priority: 2, due: date(14, 9, 45))
        planner.bootstrap(now: date(), monitorsEnabled: false)
        check(planner.start(task: first, now: date()), "late callback fixture starts explicitly")
        planner.tick(now: date(14, 9, 58), checkClockGap: false)
        check(planner.activeSession != nil && planner.workExtension?.end == date(14, 10) && planner.workExtension?.minutes == 30, "a late callback extends once, to where the work has got to, capped at the meeting")
        check(planner.trackedMinutes(for: first, now: date(14, 9, 58)) == 58, "a late callback never drops recorded time")
        check(planner.plan.assessments.first { $0.taskID == deadline.id }?.status == .cannotFitBeforeDeadline, "moved deadline work remains visibly at risk")
    }
    do {
        let (fixtureStore, planner, lifetime) = try fixture(events: [FixedBusyTime(id: "short-extension", title: "Soon meeting", start: date(14, 9, 35), end: date(14, 10))])
        defer { withExtendedLifetime(lifetime) {} }
        let first = add("Only five minutes fit", to: fixtureStore)
        planner.bootstrap(now: date(), monitorsEnabled: false)
        check(planner.start(task: first, now: date()), "clipped extension fixture starts")
        planner.tick(now: date(14, 9, 28), checkClockGap: false)
        check(planner.overrunNudge?.proposedEnd == date(14, 9, 35), "finish nudge exposes the actual meeting-clipped extension end")
        planner.tick(now: date(14, 9, 30), checkClockGap: false)
        check(planner.plan.blocks.first { $0.isActive }?.end == date(14, 9, 35), "automatic extension is shortened to avoid a fixed meeting")
        check(planner.workExtension?.minutes == 5, "the shortened extension reports the minutes it actually gave")
        planner.tick(now: date(14, 9, 34), checkClockGap: false)
        check(planner.workConflict?.title == "Soon meeting" && planner.workConflict?.start == date(14, 9, 35), "a meeting straight after the extension is the conflict")
        planner.pause(now: date(14, 9, 40))
        check(fixtureStore.workSessions(taskID: first.id).first?.endedAt == date(14, 9, 40), "a late Pause records through the meeting up to the click")
    }
    do {
        let (fixtureStore, planner, lifetime) = try fixture()
        defer { withExtendedLifetime(lifetime) {} }
        let first = add("Run into a pinned task", to: fixtureStore, priority: 3)
        let pinned = add("Pinned review", to: fixtureStore, priority: 2)
        fixtureStore.setPlacement(for: pinned, start: date(14, 9, 40), end: date(14, 10, 10), isPinned: true)
        planner.bootstrap(now: date(), monitorsEnabled: false)
        check(planner.start(task: first, now: date()), "pinned conflict fixture starts")
        planner.tick(now: date(14, 9, 29), checkClockGap: false)
        check(planner.workExtension?.end == date(14, 9, 40), "an extension stops at another task's pinned time")
        planner.tick(now: date(14, 9, 39), checkClockGap: false)
        check(planner.activeSession != nil && planner.workConflict?.kind == .task && planner.workConflict?.title == "Pinned review"
              && planner.workConflict?.start == date(14, 9, 40), "another task's pinned time is named as what the work runs into")
        check(planner.plan.blocks.first { $0.taskID == pinned.id }?.start == date(14, 9, 40), "running work never moves a pinned task")
    }
    do {
        let (fixtureStore, planner, lifetime) = try fixture()
        defer { withExtendedLifetime(lifetime) {} }
        let first = add("Extend available hours", to: fixtureStore, minutes: 120)
        planner.bootstrap(now: date(), monitorsEnabled: false)
        let originalPreferences = planner.preferences
        var extended = originalPreferences
        extended.work.overrides = [AvailabilityOverride(date: date(), windows: [AvailabilityWindow(startMinute: 9 * 60, endMinute: 9 * 60 + 45)])]
        planner.updatePreferences(extended, now: date())
        check(planner.start(task: first, now: date()), "changing future availability fixture starts")
        extended.work.overrides = [AvailabilityOverride(date: date(), windows: [AvailabilityWindow(startMinute: 9 * 60, endMinute: 10 * 60 + 15)])]
        planner.updatePreferences(extended, now: date(14, 9, 15))
        planner.tick(now: date(14, 9, 46), checkClockGap: false)
        check(planner.activeSession != nil && planner.plan.blocks.first { $0.isActive }?.end == date(14, 10, 15), "a material availability extension removes the old still-future pause boundary")
        planner.tick(now: date(14, 10, 20), checkClockGap: false)
        check(planner.activeSession != nil && planner.workConflict?.kind == .endOfHours && planner.workConflict?.title == "Work"
              && planner.workConflict?.start == date(14, 10, 15), "the end of the newly established hours stops the block, not the recording")
        planner.updatePreferences(originalPreferences, now: date(14, 10, 20))
    }
    for completes in [false, true] {
        let (fixtureStore, planner, lifetime) = try fixture()
        defer { withExtendedLifetime(lifetime) {} }
        let first = add("Direct delayed action", to: fixtureStore, priority: 3)
        _ = add("Protected next block", to: fixtureStore, priority: 2)
        planner.bootstrap(now: date(), monitorsEnabled: false)
        check(planner.start(task: first, now: date()), "delayed direct action fixture starts")
        planner.tick(now: date(14, 9, 31), checkClockGap: false)
        check(planner.workExtension?.end == date(14, 10), "a tick past the estimate extends from the quarter hour it falls in")
        check(planner.trackedMinutes(for: first, now: date(14, 9, 46)) == 46, "elapsed display keeps counting between timer ticks")
        if completes {
            fixtureStore.toggleCompletion(first, now: date(14, 9, 46))
            planner.storeDidChange(now: date(14, 9, 46))
        } else {
            planner.pause(now: date(14, 9, 46))
        }
        check(fixtureStore.workSessions(taskID: first.id).first?.endedAt == date(14, 9, 46), "direct Stop and ordinary checkbox completion record up to the moment they happen")
    }
    do {
        let (fixtureStore, planner, lifetime) = try fixture()
        defer { withExtendedLifetime(lifetime) {} }
        let first = add("Done before a late first-extension callback", to: fixtureStore, priority: 3)
        _ = add("Following flexible work", to: fixtureStore, priority: 2)
        planner.bootstrap(now: date(), monitorsEnabled: false)
        check(planner.start(task: first, now: date()), "direct first-extension fixture starts")
        fixtureStore.toggleCompletion(first, now: date(14, 9, 31))
        planner.storeDidChange(now: date(14, 9, 31))
        check(fixtureStore.workSessions(taskID: first.id).first?.durationMinutes() == 31, "a completion before any extension still records the time past the estimate")
    }
    do {
        let (fixtureStore, planner, lifetime) = try fixture()
        defer { withExtendedLifetime(lifetime) {} }
        let history = add("Correct yesterday's work", to: fixtureStore)
        let historicalSession = WorkSession(task: history, deviceID: fixtureStore.calendarDeviceID!, startedAt: date(13, 18))
        historicalSession.endedAt = date(13, 18, 10)
        historicalSession.lastHeartbeatAt = date(13, 18, 10)
        fixtureStore.context.insert(historicalSession)
        fixtureStore.toggleCompletion(history, now: date(13, 18, 10))
        _ = add("Keep today's first anchor", to: fixtureStore, priority: 3)
        _ = add("Keep today's second anchor", to: fixtureStore, priority: 2)
        planner.bootstrap(now: date(), monitorsEnabled: false)
        let anchors = planner.plan.blocks.map(\.start)
        fixtureStore.correctSession(historicalSession, minutes: 5)
        planner.storeDidChange(now: date(14, 9, 1))
        check(planner.plan.blocks.map(\.start) == anchors, "correcting completed history cannot shift unrelated live task anchors")
        check(planner.completedBlocks.first { $0.taskID == history.id }?.durationMinutes == 5, "history-only save still refreshes corrected completed calendar time")
    }
    do {
        let (fixtureStore, planner, lifetime) = try fixture()
        defer { withExtendedLifetime(lifetime) {} }
        let pinned = add("Missed pinned time", to: fixtureStore, priority: 3)
        let other = add("Keep unstarted neighbor", to: fixtureStore, priority: 2)
        fixtureStore.setPlacement(for: pinned, start: date(), end: date(14, 9, 30), isPinned: true)
        planner.bootstrap(now: date(), monitorsEnabled: false)
        let neighbor = planner.plan.blocks.first { $0.taskID == other.id }!
        planner.tick(now: date(14, 9, 5), checkClockGap: false)
        check(planner.plan.assessments.first { $0.taskID == pinned.id }?.conflicts.contains { $0.contains("Pinned time was missed") } == true, "ignoring a pinned start preserves an explicit missed-pin conflict")
        check(planner.plan.blocks.first { $0.taskID == other.id }?.start == neighbor.start && fixtureStore.workSessions().isEmpty, "missed pins move their remaining work without moving neighbors or inventing activity")
        planner.replan(now: date(14, 9, 6))
        check(planner.plan.blocks.filter { $0.taskID == pinned.id }.allSatisfy { !$0.isPinned }, "a later material replan never resurrects a known missed pin's partial slot")
        check(planner.plan.assessments.first { $0.taskID == pinned.id }?.conflicts.contains { $0.contains("Pinned time was missed") } == true, "missed-pin feedback survives subsequent material changes")
    }
}
try checkSchedulingNudges()
try checkWorkCompanion()
try checkManualMoveFeedback()
try checkReadOnlyRecovery()
print("Passed \(checks) calendar runtime checks")
