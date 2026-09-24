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
check(coordinator.workExtension?.movedTaskIDs.isEmpty == true && coordinator.rescheduleSummary == nil,
      "the extension moves the flexible task in the plan, and reports only placed tasks as moved")
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
check(coordinator.activeSession == nil && coordinator.resumeTaskID == a.id, "away opt-in still respects end of availability / lunch break")
check(store.workSessions(taskID: a.id).first?.endedAt == date(14, 12), "away work clips at lunch while asleep")
check(coordinator.workConflict == nil && coordinator.notice?.contains("while you were away") == true, "the clip is reported as time away, not as work running into the break")
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
// A move from the Work panel is a placement like Plan's, drawn where it's
// put: its preview names what it would overlap on the calendar, and a pinned
// placement keeps the requested time, its conflicts shown.
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

    // Plan's path: a pinned placement for the occurrence, then a replan.
    func pin(at start: Date) {
        let block = currentBlock()
        _ = moveStore.setPlacement(for: movedTask, start: start, end: start.addingTimeInterval(block.end.timeIntervalSince(block.start)),
                                   isPinned: true, placementID: block.placementID)
        planner.replan(now: date())
    }
    pin(at: date(14, 10))
    let pinned = currentBlock()
    check(pinned.isPinned && pinned.start == date(14, 10), "a pinned placement preserves an otherwise infeasible requested time")
    check(pinned.conflicts.contains { $0.contains("Fixture meeting") }, "a pinned conflict remains visible on the scheduled block")
    movedTask.dueDate = date(14, 16)
    movedTask.includesTime = true
    moveStore.save()
    planner.replan(now: date())
    let coverage = planner.plan.assessments.first { $0.taskID == movedTask.id }!
    check(coverage.status == .cannotFitBeforeDeadline && coverage.beforeDeadlineMinutes == 0, "a meeting-conflicting pin never counts as safe deadline coverage")

    pin(at: date(14, 13))
    check(currentBlock().isPinned && currentBlock().start == date(14, 13) && currentBlock().conflicts.isEmpty,
          "a pin moved into free hours clears its previous conflict")

    let neighbour = Block(kind: .task, text: "Drawn neighbour", listID: moveStore.inboxList()!.id)
    neighbour.schedulingEstimateMinutes = 30
    moveStore.context.insert(neighbour)
    moveStore.setPlacement(for: neighbour, start: date(14, 13, 30), end: date(14, 14), isPinned: true)
    let flexible = Block(kind: .task, text: "Flexible neighbour", listID: moveStore.inboxList()!.id)
    flexible.schedulingEstimateMinutes = 30
    flexible.selectedForDay = date()
    moveStore.context.insert(flexible)
    moveStore.save()
    planner.replan(now: date())
    let drawn = planner.visibleBlocks.first { $0.taskID == movedTask.id }!
    check(drawn.start == date(14, 13) && drawn.placementID != nil, "the pinned placement is what the calendar draws")
    check(planner.moveOverlaps(drawn, to: date(14, 10, 15)).map(\.title) == ["Fixture meeting"], "a move into a meeting names the meeting it would overlap")
    check(planner.moveOverlaps(drawn, to: date(14, 13, 15)).map(\.title) == ["Drawn neighbour"], "and the other blocks the calendar draws there")
    check(planner.moveOverlaps(drawn, to: date(14, 15)).isEmpty, "a free time overlaps nothing, and never the block itself")
    let flexibleSlot = planner.plan.blocks.first { $0.taskID == flexible.id }!
    check(!flexibleSlot.isPinned && planner.moveOverlaps(drawn, to: flexibleSlot.start).allSatisfy { $0.title != "Flexible neighbour" },
          "work the calendar doesn't draw is never named as overlapped")
    check(moveStore.placements(taskID: movedTask.id).count == 1 && planner.visibleBlocks.first { $0.taskID == movedTask.id }?.start == date(14, 13),
          "a preview saves nothing")
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
        check(planner.startNudge == nil, "flexible work, which the calendar doesn't draw, offers no Start nudge")
        planner.tick(now: date(14, 9, 4).addingTimeInterval(59))
        check(planner.plan.blocks.map(\.start) == original.map(\.start), "timer ticks preserve every placement throughout the grace period")
        check(fixtureStore.workSessions().isEmpty, "a visible or ignored start nudge never records work")
        planner.tick(now: date(14, 9, 5))
        let moved = planner.plan.blocks.first { $0.taskID == first.id }!
        check(moved.start == date(14, 10, 30), "ignored task uses the next gap that fits its whole short session")
        check(planner.plan.blocks.filter { $0.taskID == second.id || $0.taskID == third.id }.allSatisfy { anchor[$0.taskID] == $0.start }, "missing a start never shifts the other promised tasks")
        let risk = planner.plan.assessments.first { $0.taskID == first.id }!
        check(risk.status == .cannotFitBeforeDeadline && risk.beforeDeadlineMinutes == 0, "lost deadline coverage is flagged after the missed start")
        check(planner.rescheduleSummary == nil, "a missed flexible start moves nothing the calendar draws, so nothing is reported as rescheduled")
        check(planner.startNudge == nil && nudgeChanges == 0, "no Start nudge comes or goes for flexible work")
        planner.tick(now: date(14, 9, 6))
        check(planner.plan.blocks.first { $0.taskID == first.id }?.start == date(14, 10, 30), "subsequent timer ticks retain the replacement gap")
        check(planner.visibleBlocks.isEmpty && fixtureStore.calendarPlannedBlocks.isEmpty, "automatically planned work stays off the calendar, and out of completion snapshots, until it is placed")
        second.text += " renamed"
        fixtureStore.save()
        planner.storeDidChange(now: date(14, 9, 10))
        check(planner.plan.blocks.first { $0.taskID == second.id }?.start == anchor[second.id], "an unrelated title save cannot drift the established schedule")
        check(planner.rescheduleSummary == nil, "an unrelated save reports nothing as rescheduled")
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
        check(planner.workExtension?.movedTaskIDs.isEmpty == true && planner.rescheduleSummary == nil,
              "moving only flexible work, the extension reports nothing as rescheduled")
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
        check(planner.rescheduleSummary == nil, "a replan that moves only flexible work reports nothing as rescheduled")
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
        check(planner.rescheduleSummary == nil, "a completion that frees time for flexible work reports nothing as rescheduled")
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
        let first = add("Run past a pinned task", to: fixtureStore, priority: 3)
        let pinned = add("Pinned review", to: fixtureStore, priority: 2)
        let pin = fixtureStore.setPlacement(for: pinned, start: date(14, 9, 40), end: date(14, 10, 10), isPinned: true)!
        planner.bootstrap(now: date(), monitorsEnabled: false)
        check(planner.start(task: first, now: date(14, 9, 15)), "pinned task fixture starts")
        check(planner.visibleBlocks.first { $0.isActive }?.end == date(14, 9, 40), "work without a slot stops short of the next task placed after it")
        planner.tick(now: date(14, 9, 39), checkClockGap: false)
        check(planner.workExtension?.end == date(14, 10) && planner.workConflict == nil, "an extension grows past another task's pinned time")
        check(pin.start == date(14, 10) && pin.end == date(14, 10, 30) && planner.workExtension?.movedTaskIDs == [pinned.id]
                && planner.rescheduleSummary?.taskIDs == [pinned.id], "the pinned task moves out of the running work's way, and is named as moved")
        check(planner.plan.blocks.first { $0.taskID == pinned.id }?.start == date(14, 10)
                && planner.visibleBlocks.first { $0.taskID == pinned.id }?.start == date(14, 10), "the plan and the calendar follow the moved pin")
    }
    do {
        // The design's overrun: q1 in its 10:00–11:30 slot runs past it, with
        // p1 placed at 11:30, lunch at 12 and p3 at 13:00.
        let (fixtureStore, planner, lifetime) = try fixture(events: [
            FixedBusyTime(id: "standup", title: "Standup", start: date(14, 9, 30), end: date(14, 10)),
            FixedBusyTime(id: "board", title: "Board prep", start: date(14, 14), end: date(14, 15))
        ])
        defer { withExtendedLifetime(lifetime) {} }
        let okrs = add("Draft Q3 OKRs", to: fixtureStore, minutes: 90, priority: 3)
        let feedback = add("Write interview feedback for Priya", to: fixtureStore, minutes: 20, priority: 2)
        let scorecard = add("Update the design role scorecard", to: fixtureStore, minutes: 30, priority: 1)
        let slot = fixtureStore.setPlacement(for: okrs, start: date(14, 10), end: date(14, 11, 30), isPinned: true)!
        let next = fixtureStore.setPlacement(for: feedback, start: date(14, 11, 30), end: date(14, 11, 50), isPinned: true)!
        let later = fixtureStore.setPlacement(for: scorecard, start: date(14, 13), end: date(14, 13, 30), isPinned: true)!
        planner.bootstrap(now: date(14, 10, 20), monitorsEnabled: false)
        func drawn(_ task: Block) -> PlannedBlock? { planner.visibleBlocks.first { $0.taskID == task.id } }
        check(planner.start(task: okrs, now: date(14, 10, 20)), "design overrun fixture starts late in its slot")
        check(drawn(okrs)?.isActive == true && drawn(okrs)?.start == date(14, 10) && drawn(okrs)?.end == date(14, 11, 30),
              "a late start keeps the slot's end until the work overruns it")
        planner.tick(now: date(14, 11, 28), checkClockGap: false)
        check(planner.workExtension == nil && planner.overrunNudge?.movedTaskCount == 2, "the heads-up counts the placed tasks the extension will move")
        planner.tick(now: date(14, 11, 29), checkClockGap: false)
        check(planner.workExtension?.end == date(14, 11, 45) && planner.workConflict == nil,
              "a minute before the slot ends it grows to the next quarter plus 15 minutes, past the next task's time")
        check(slot.end == date(14, 11, 45) && drawn(okrs)?.end == date(14, 11, 45), "the slot it works through grows with it")
        check(next.start == date(14, 13) && next.end == date(14, 13, 20), "the next task moves past lunch to the first free quarter")
        check(later.start == date(14, 13, 30) && later.end == date(14, 14), "the task after it moves on in turn, clear of the meeting")
        check(planner.workExtension?.movedTaskIDs == [feedback.id, scorecard.id], "the extension names the tasks it moved, in time order")
        check(planner.rescheduleSummary?.taskIDs == [feedback.id, scorecard.id] && planner.rescheduleSummary?.message == "2 tasks rescheduled.",
              "the Work panel reports the placements moved, leading with how many")
        check(drawn(feedback)?.start == date(14, 13) && drawn(scorecard)?.start == date(14, 13, 30), "the calendar draws the moved tasks at their new times")
        let grant = planner.workExtension!
        check(planner.undoExtension(grant, now: date(14, 11, 31)), "Undo takes the design's extension back")
        check(slot.end == date(14, 11, 30) && next.start == date(14, 11, 30) && later.start == date(14, 13)
                && drawn(feedback)?.start == date(14, 11, 30), "Undo puts the slot and the moved tasks back")
        check(planner.redoExtension(grant, now: date(14, 11, 32)), "Redo gives the design's extension back")
        check(slot.end == date(14, 11, 45) && next.start == date(14, 13) && later.start == date(14, 13, 30), "Redo moves them again")
        planner.tick(now: date(14, 11, 44), checkClockGap: false)
        check(planner.workExtension?.end == date(14, 12) && slot.end == date(14, 12) && planner.workExtension?.movedTaskIDs.isEmpty == true,
              "the next extension stops at lunch and moves nothing that is already clear")
        planner.tick(now: date(14, 11, 59), checkClockGap: false)
        check(planner.activeSession != nil && planner.workConflict?.kind == .breakTime && planner.workConflict?.start == date(14, 12),
              "at lunch the work runs into the break and keeps recording")
        check(planner.workConflict?.title == "Lunch", "the midday break is named Lunch, as the design's")
        planner.tick(now: date(14, 12, 3), checkClockGap: false)
        check(drawn(okrs)?.isActive == true && drawn(okrs)?.end == date(14, 12), "the working block holds at the break it runs into")
        planner.pause(now: date(14, 12, 5))
        check(planner.pausedBlockID != nil && planner.pausedBlockID == drawn(okrs)?.id && drawn(okrs)?.start == date(14, 10)
                && drawn(okrs)?.end == date(14, 12) && drawn(okrs)?.isActive == false, "paused work keeps its grown slot, drawn as the work")
        check(planner.pausedWorkNote?.conflict?.kind == .breakTime && planner.pausedWorkNote?.extended == true,
              "paused work still runs into the break it ran into, and was extended, as the design's reads")
        check(planner.workConflict == nil && planner.workExtension == nil && planner.displayedWorkConflict?.title == "Lunch"
                && planner.displayedWorkExtension?.minutes == 30, "paused, the notch keeps what the work ran into and its extra time, as its block does")
        planner.dismissResume()
        check(planner.pausedBlockID == nil && planner.pausedWorkNote == nil && drawn(okrs)?.end == date(14, 12), "stopped work leaves an ordinary slot where it ran")
        check(planner.displayedWorkConflict == nil && planner.displayedWorkExtension == nil, "stopped work leaves the notch nothing to show")
    }
    do {
        // Once the work pauses, Undo still puts back what its extension moved,
        // as the design's Undo restores the placements however the work stands.
        let (fixtureStore, planner, lifetime) = try fixture()
        defer { withExtendedLifetime(lifetime) {} }
        let okrs = add("Draft Q3 OKRs", to: fixtureStore, minutes: 90, priority: 3)
        let feedback = add("Write interview feedback for Priya", to: fixtureStore, minutes: 20, priority: 2)
        let slot = fixtureStore.setPlacement(for: okrs, start: date(14, 10), end: date(14, 11, 30), isPinned: true)!
        let next = fixtureStore.setPlacement(for: feedback, start: date(14, 11, 30), end: date(14, 11, 50), isPinned: true)!
        planner.bootstrap(now: date(14, 10), monitorsEnabled: false)
        func drawn(_ task: Block) -> PlannedBlock? { planner.visibleBlocks.first { $0.taskID == task.id } }
        check(planner.start(task: okrs, now: date(14, 10)), "undo after a pause fixture starts")
        planner.tick(now: date(14, 11, 29), checkClockGap: false)
        let grant = planner.workExtension!
        check(slot.end == date(14, 11, 45) && next.start == date(14, 13) && grant.movedTaskIDs == [feedback.id], "the extension grows the slot and moves the next task")
        planner.pause(now: date(14, 11, 35))
        check(planner.workExtension == nil && planner.pausedWorkNote?.extended == true && planner.pausedWorkNote?.conflict == nil,
              "paused work reads extended, as it did while it ran")
        check(planner.displayedWorkExtension?.minutes == 15 && planner.displayedWorkConflict == nil, "the paused notch keeps its +15m")
        check(planner.canUndoExtension(grant) && !planner.canRedoExtension(grant), "after a pause, Undo still offers the extension's moves")
        check(planner.undoExtension(grant, now: date(14, 11, 36)), "Undo after a pause takes the extension's moves back")
        check(slot.end == date(14, 11, 30) && next.start == date(14, 11, 30) && next.end == date(14, 11, 50)
                && drawn(feedback)?.start == date(14, 11, 30), "Undo after a pause puts the slot and the moved task back")
        check(planner.pausedBlockID == drawn(okrs)?.id && planner.pausedWorkNote?.extended == false && planner.displayedWorkExtension == nil,
              "with its extension undone, paused work keeps its block and reads working again, and the notch drops its +15m")
        check(!planner.canUndoExtension(grant) && planner.canRedoExtension(grant), "an undone extension's moves can be redone")
        check(planner.redoExtension(grant, now: date(14, 11, 37)) && slot.end == date(14, 11, 45) && next.start == date(14, 13)
                && planner.pausedWorkNote?.extended == true && planner.displayedWorkExtension?.minutes == 15, "Redo after a pause moves them again")
        // Another move since keeps the task where it now is.
        next.start = date(14, 15)
        next.end = date(14, 15, 20)
        fixtureStore.save()
        check(planner.undoExtension(grant, now: date(14, 11, 38)) && slot.end == date(14, 11, 30) && next.start == date(14, 15),
              "Undo leaves a task moved since where it is")
        check(planner.redoExtension(grant, now: date(14, 11, 39)) && slot.end == date(14, 11, 45), "Redo gives the slot back")
        // Working again, the resumed block ends where its slot does once Undo shrinks it.
        check(planner.start(task: okrs, now: date(14, 11, 40)), "undo after a pause fixture resumes")
        check(drawn(okrs)?.isActive == true && drawn(okrs)?.end == date(14, 11, 45), "resumed work ends with its grown slot")
        check(planner.undoExtension(grant, now: date(14, 11, 41)) && slot.end == date(14, 11, 30), "Undo of the paused extension works while the task runs again")
        check(drawn(okrs)?.end == date(14, 11, 30), "the running block follows its slot back")
        planner.tick(now: date(14, 11, 42), checkClockGap: false)
        check(planner.workExtension == nil && slot.end == date(14, 11, 30), "and isn't grown again by itself straight away")
        planner.stopWorking(now: date(14, 11, 43))
        planner.dismissResume()
        check(planner.canRedoExtension(grant) && planner.redoExtension(grant, now: date(14, 11, 44)) && slot.end == date(14, 11, 45),
              "stopped work's extension can still be redone")
        check(planner.undoExtension(grant, now: date(14, 11, 45)) && slot.end == date(14, 11, 30), "and undone again")
    }
    do {
        // Done settles the extension too: Undo still moves its tasks back.
        let (fixtureStore, planner, lifetime) = try fixture()
        defer { withExtendedLifetime(lifetime) {} }
        let okrs = add("Finish while extended", to: fixtureStore, minutes: 90, priority: 3)
        let feedback = add("Moved before Done", to: fixtureStore, minutes: 20, priority: 2)
        fixtureStore.setPlacement(for: okrs, start: date(14, 10), end: date(14, 11, 30), isPinned: true)
        let next = fixtureStore.setPlacement(for: feedback, start: date(14, 11, 30), end: date(14, 11, 50), isPinned: true)!
        planner.bootstrap(now: date(14, 10), monitorsEnabled: false)
        check(planner.start(task: okrs, now: date(14, 10)), "done after an extension fixture starts")
        planner.tick(now: date(14, 11, 29), checkClockGap: false)
        let grant = planner.workExtension!
        check(next.start == date(14, 13), "the extension moves the next task before Done")
        planner.complete(task: okrs, now: date(14, 11, 35))
        check(planner.activeSession == nil && planner.canUndoExtension(grant), "after Done, Undo still offers the extension's moves")
        check(planner.undoExtension(grant, now: date(14, 11, 36)) && next.start == date(14, 11, 30), "Undo after Done puts the moved task back")
    }
    do {
        // A task with no room left in its hours today stays where it is.
        let (fixtureStore, planner, lifetime) = try fixture()
        defer { withExtendedLifetime(lifetime) {} }
        let first = add("Run to the end of the day", to: fixtureStore)
        let last = add("Last thing today", to: fixtureStore, minutes: 20)
        let pin = fixtureStore.setPlacement(for: last, start: date(14, 16, 40), end: date(14, 17), isPinned: true)!
        planner.bootstrap(now: date(14, 16), monitorsEnabled: false)
        check(planner.start(task: first, now: date(14, 16)), "end of day fixture starts")
        planner.tick(now: date(14, 16, 29), checkClockGap: false)
        check(planner.workExtension?.end == date(14, 16, 45) && pin.start == date(14, 16, 40) && planner.workExtension?.movedTaskIDs.isEmpty == true,
              "a task with no room left in its hours today stays where it is")
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
        check(planner.activeSession != nil && planner.workConflict == nil && planner.workExtension == nil,
              "the end of the newly established hours only stops the block growing: no conflict, and recording carries on")
        planner.updatePreferences(originalPreferences, now: date(14, 10, 20))
    }
    do {
        // Only the midday break is Lunch; any other reads as a break.
        let (fixtureStore, planner, lifetime) = try fixture()
        defer { withExtendedLifetime(lifetime) {} }
        let late = add("Run into the afternoon break", to: fixtureStore, minutes: 15)
        planner.bootstrap(now: date(14, 14, 30), monitorsEnabled: false)
        let original = planner.preferences
        var hours = original
        hours.work.breaks = Dictionary(uniqueKeysWithValues: (2...6).map {
            ($0, [AvailabilityWindow(startMinute: 12 * 60, endMinute: 13 * 60), AvailabilityWindow(startMinute: 15 * 60, endMinute: 15 * 60 + 15)])
        })
        planner.updatePreferences(hours, now: date(14, 14, 30))
        check(planner.start(task: late, now: date(14, 14, 30)), "afternoon break fixture starts")
        planner.tick(now: date(14, 14, 44), checkClockGap: false)
        planner.tick(now: date(14, 14, 59), checkClockGap: false)
        check(planner.workConflict?.kind == .breakTime && planner.workConflict?.start == date(14, 15) && planner.workConflict?.title == "",
              "an afternoon break is no lunch")
        planner.updatePreferences(original, now: date(14, 15))
    }
    do {
        // Undo only offers what it can still take back.
        let (fixtureStore, planner, lifetime) = try fixture()
        defer { withExtendedLifetime(lifetime) {} }
        let first = add("Undo an extension later", to: fixtureStore, priority: 3)
        let next = add("Moved by the extension", to: fixtureStore, priority: 2)
        planner.bootstrap(now: date(), monitorsEnabled: false)
        check(planner.start(task: first, now: date()), "late undo fixture starts")
        planner.tick(now: date(14, 9, 29), checkClockGap: false)
        let grant = planner.workExtension!
        check(planner.canUndoExtension(grant) && !planner.canRedoExtension(grant), "a fresh extension can be undone")
        next.priorityRaw = 1
        fixtureStore.save()
        planner.storeDidChange(now: date(14, 9, 31))
        check(planner.canUndoExtension(grant) && planner.undoExtension(grant, now: date(14, 9, 32)), "Undo after a material edit still takes the extension back")
        check(planner.activeSession != nil && planner.workExtension == nil, "undoing after a material edit keeps recording without the extension")
        check(planner.plan.blocks.first { $0.taskID == next.id }.map { $0.start < date(14, 9, 45) } == true, "without the saved blocks, the moved task is planned afresh without the extension")
        planner.tick(now: date(14, 9, 36), checkClockGap: false)
        check(planner.workExtension == nil && planner.canRedoExtension(grant), "an extension undone after a material edit is not granted again by itself")
        check(planner.redoExtension(grant, now: date(14, 9, 37)), "Redo after a replan gives the extension back")
        check(planner.workExtension == grant && planner.plan.blocks.first { $0.isActive }?.end == date(14, 9, 45), "the redone extension plans the block to its end again")
        planner.pause(now: date(14, 9, 40))
        check(!planner.canUndoExtension(grant) && !planner.undoExtension(grant, now: date(14, 9, 41)), "after a pause there is no extension left to undo")
        check(planner.start(task: first, now: date(14, 9, 42)), "late undo fixture resumes")
        check(!planner.canUndoExtension(grant) && !planner.undoExtension(grant, now: date(14, 9, 43)), "a new session never takes back the previous one's extension")
    }
    do {
        let (fixtureStore, planner, lifetime) = try fixture()
        defer { withExtendedLifetime(lifetime) {} }
        let first = add("Keep working after Undo", to: fixtureStore, priority: 3)
        let next = add("Wait for the running work", to: fixtureStore, priority: 2)
        planner.bootstrap(now: date(), monitorsEnabled: false)
        check(planner.start(task: first, now: date()), "overrun fixture starts")
        planner.tick(now: date(14, 9, 29), checkClockGap: false)
        check(planner.undoExtension(planner.workExtension!, now: date(14, 9, 31)), "overrun fixture undoes its extension")
        check(planner.plan.blocks.first { $0.taskID == next.id }?.start == date(14, 9, 30), "Undo puts the next task back at its old time")
        for minute in stride(from: 32, through: 50, by: 2) { planner.tick(now: date(14, 9, minute), checkClockGap: false) }
        check(planner.plan.blocks.first { $0.taskID == next.id }?.start == date(14, 9, 30), "a block the running work runs over stays put instead of hopping every five minutes")
        planner.pause(now: date(14, 9, 50))
        check(planner.plan.blocks.filter { $0.taskID == next.id }.allSatisfy { $0.start >= date(14, 9, 50) }, "once the work stops, the task it ran over is planned from then")
    }
    do {
        // Away from the Mac, time stops counting at the next fixed event or
        // the end of the list's hours; at the Mac, work records through them.
        let (fixtureStore, planner, lifetime) = try fixture(events: [FixedBusyTime(id: "away-meeting", title: "Away meeting", start: date(14, 10), end: date(14, 11))])
        defer { withExtendedLifetime(lifetime) {} }
        let away = add("Read on paper", to: fixtureStore)
        fixtureStore.setTracksAway(true, for: away)
        planner.bootstrap(now: date(), monitorsEnabled: false)
        check(planner.start(task: away, now: date()), "away fixture starts")
        planner.handleMacUnavailable(reason: "Mac locked", now: date(14, 9, 10))
        planner.tick(now: date(14, 9, 29))
        check(planner.activeSession != nil && planner.workExtension == nil, "while the Mac is away, work keeps recording but its block does not grow")
        planner.handleMacReturn(now: date(14, 9, 40))
        check(planner.activeSession != nil && planner.trackedMinutes(for: away, now: date(14, 9, 40)) == 40, "back before the meeting, all the time away is recorded")
        planner.tick(now: date(14, 9, 41))
        check(planner.workExtension?.end == date(14, 10), "back at the Mac, the block grows again up to the meeting")
        planner.tick(now: date(14, 10, 5), checkClockGap: false)
        check(planner.activeSession != nil && planner.workConflict?.title == "Away meeting", "at the Mac, away-tracked work records into a meeting like any other")
        planner.handleMacUnavailable(reason: "Mac locked", now: date(14, 10, 20))
        check(planner.activeSession == nil && fixtureStore.workSessions(taskID: away.id).first?.endedAt == date(14, 10, 20), "leaving the Mac during fixed busy time pauses away-tracked work at once")
        check(planner.start(task: away, now: date(14, 11, 30)), "away fixture starts before lunch")
        planner.tick(now: date(14, 11, 44), checkClockGap: false)
        planner.tick(now: date(14, 11, 59), checkClockGap: false)
        check(planner.activeSession != nil && planner.workConflict?.kind == .breakTime && planner.workConflict?.start == date(14, 12), "at the Mac, running into a break marks the conflict at the break")
        planner.pause(now: date(14, 12, 5))
        check(planner.start(task: away, now: date(14, 16)), "away fixture starts late in the day")
        planner.handleMacUnavailable(reason: "Mac slept", now: date(14, 16, 5))
        planner.handleMacReturn(now: date(15, 9))
        check(planner.activeSession == nil && fixtureStore.workSessions(taskID: away.id).first?.endedAt == date(14, 17), "a night away ends the work at the end of the day's hours")
        check(planner.workExtension == nil && planner.notice?.contains("while you were away") == true, "the morning reports the pause, not an extension")
        check(planner.start(task: away, now: date(15, 13)), "away fixture starts after lunch")
        planner.tick(now: date(15, 18))
        check(planner.activeSession == nil && fixtureStore.workSessions(taskID: away.id).first?.endedAt == date(15, 17), "an unannounced gap is time away too, clipped at the end of the hours")
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
        let placement = fixtureStore.setPlacement(for: pinned, start: date(), end: date(14, 9, 30), isPinned: true)!
        planner.bootstrap(now: date(), monitorsEnabled: false)
        let neighbor = planner.plan.blocks.first { $0.taskID == other.id }!
        check(planner.visibleBlocks.map(\.taskID) == [pinned.id] && fixtureStore.calendarPlannedBlocks.map(\.placementID) == [placement.id], "only the explicit placement is drawn and snapshotted, not the flexible neighbor")
        check(planner.plannedWork(WorkTaskReference(pinned), now: date())?.placementID == placement.id
                && planner.plannedWork(WorkTaskReference(other), now: date()) == nil,
              "the Work panel's planned time is the drawn slot, and flexible work has none")
        planner.tick(now: date(14, 9, 20), checkClockGap: false)
        check(planner.plan.blocks.contains { $0.placementID == placement.id } && planner.startNudge?.taskID == pinned.id, "an unstarted pinned block keeps its slot and its Start nudge while the slot runs")
        check(planner.startNudge?.scheduledStart == date() && planner.startNudge?.graceEndsAt == date(14, 9, 5), "the nudge names the slot's start and has a five-minute grace period")
        planner.tick(now: date(14, 9, 31), checkClockGap: false)
        check(planner.plan.assessments.first { $0.taskID == pinned.id }?.conflicts.contains { $0.contains("Pinned time was missed") } == true, "ignoring a pinned slot preserves an explicit missed-pin conflict")
        check(planner.plan.blocks.first { $0.taskID == other.id }?.start == neighbor.start && fixtureStore.workSessions().isEmpty, "missed pins move their remaining work without moving neighbors or inventing activity")
        planner.replan(now: date(14, 9, 32))
        let missed = planner.visibleBlocks.filter { $0.taskID == pinned.id }
        check(missed.count == 1 && missed[0].start == date() && missed[0].end == date(14, 9, 30) && !missed[0].isActive, "a missed placement stays drawn at its planned time, to read as carried forward")
        check(planner.plan.blocks.filter { $0.taskID == pinned.id }.allSatisfy { !$0.isPinned }, "a later material replan never resurrects a known missed pin")
        check(planner.plan.assessments.first { $0.taskID == pinned.id }?.conflicts.contains { $0.contains("Pinned time was missed") } == true, "missed-pin feedback survives subsequent material changes")
    }
    do {
        let (fixtureStore, planner, lifetime) = try fixture()
        defer { withExtendedLifetime(lifetime) {} }
        let placed = add("Work through a planned slot", to: fixtureStore, priority: 3)
        let unplaced = add("Work without a slot", to: fixtureStore, priority: 1)
        let placement = fixtureStore.setPlacement(for: placed, start: date(), end: date(14, 9, 30), isPinned: true)!
        planner.bootstrap(now: date(), monitorsEnabled: false)
        check(planner.start(task: placed, now: date(14, 9, 5)), "a late start on a planned slot starts")
        func working() -> [PlannedBlock] { planner.visibleBlocks.filter { $0.taskID == placed.id } }
        check(working().count == 1 && working()[0].isActive && working()[0].placementID == placement.id && working()[0].start == date(), "running work takes its slot's place, from the slot's start")
        placed.schedulingEstimateMinutes = 60
        fixtureStore.save()
        planner.storeDidChange(now: date(14, 9, 10))
        check(working().first?.start == date() && working().first?.end == date(14, 9, 30),
              "a replan while working keeps the time already worked on the calendar, and the slot's end over the new estimate")
        planner.pause(now: date(14, 9, 20))
        check(working().count == 1 && !working()[0].isActive && working()[0].start == date() && working()[0].end == date(14, 9, 30), "paused work leaves its slot where it was planned")
        check(planner.pausedBlockID == working()[0].id, "the paused slot is drawn as the work while it can resume")
        check(planner.start(task: unplaced, now: date(14, 9, 40)), "work without a slot starts")
        check(planner.pausedBlockID == nil, "other work taking over ends the paused block")
        planner.replan(now: date(14, 9, 45))
        check(planner.visibleBlocks.first { $0.taskID == unplaced.id && $0.isActive }?.start == date(14, 9, 40), "work without a slot is drawn from when it started")
        planner.pause(now: date(14, 9, 50))
        let kept = planner.visibleBlocks.filter { $0.taskID == unplaced.id }
        check(kept.count == 1 && !kept[0].isActive && kept[0].id == planner.pausedBlockID && kept[0].start == date(14, 9, 40)
                && kept[0].end == date(14, 10, 10) && planner.plannedWork(WorkTaskReference(unplaced), now: date(14, 9, 50)) == nil,
              "paused work without a slot keeps its block where it was, which is no planned slot")
        planner.dismissResume()
        check(!planner.visibleBlocks.contains { $0.taskID == unplaced.id } && planner.pausedBlockID == nil, "stopping it takes that block away")
    }
    do {
        let (fixtureStore, planner, lifetime) = try fixture()
        defer { withExtendedLifetime(lifetime) {} }
        let placed = add("Planned, then ticked", to: fixtureStore, priority: 3)
        let unplaced = add("Ticked without a slot", to: fixtureStore, priority: 2)
        let repeating = add("Repeat with a slot", to: fixtureStore, priority: 1, due: date(14, 17))
        repeating.recurrence = .weekly
        let trashed = add("Ticked, then trashed", to: fixtureStore)
        fixtureStore.setPlacement(for: placed, start: date(14, 13), end: date(14, 13, 30), isPinned: true)
        fixtureStore.setPlacement(for: repeating, start: date(14, 14), end: date(14, 14, 30), isPinned: true)
        fixtureStore.setPlacement(for: trashed, start: date(14, 15), end: date(14, 15, 30), isPinned: true)
        planner.bootstrap(now: date(), monitorsEnabled: false)
        for task in [placed, unplaced, repeating, trashed] { fixtureStore.toggleCompletion(task, now: date(14, 9, 10)) }
        planner.storeDidChange(now: date(14, 9, 10))
        func done(_ task: Block) -> [PlannedBlock] { planner.visibleBlocks.filter { $0.taskID == task.id && $0.isCompleted } }
        check(done(placed).count == 1 && done(placed)[0].start == date(14, 13) && done(placed)[0].end == date(14, 13, 30), "a completed placement is drawn done at its slot")
        check(done(unplaced).isEmpty && planner.completedBlocks.contains { $0.taskID == unplaced.id }, "a tick with no slot or recorded work stays in history but off the calendar")
        check(done(repeating).first?.start == date(14, 14) && !repeating.isCompleted, "a repeat that rolled on keeps its done block")
        fixtureStore.toggleCompletion(placed, now: date(14, 9, 11))
        _ = fixtureStore.trashBlocks([trashed])
        planner.storeDidChange(now: date(14, 9, 11))
        check(done(placed).isEmpty && fixtureStore.completionRecords(taskID: placed.id).count == 1, "reopening takes the done block off the calendar and keeps the history")
        check(done(trashed).isEmpty && !planner.visibleBlocks.contains { $0.taskID == trashed.id }, "a trashed task leaves nothing on the calendar")
    }
    do {
        let (fixtureStore, planner, lifetime) = try fixture()
        defer { withExtendedLifetime(lifetime) {} }
        let placed = add("Reopened from its done block", to: fixtureStore)
        fixtureStore.setPlacement(for: placed, start: date(14, 13), end: date(14, 13, 30), isPinned: true)
        planner.bootstrap(now: date(), monitorsEnabled: false)
        fixtureStore.toggleCompletion(placed, now: date(14, 9, 10))
        planner.storeDidChange(now: date(14, 9, 10))
        let done = planner.visibleBlocks.filter { $0.taskID == placed.id && $0.isCompleted }
        // What the done block's check does: reopen, then put the new occurrence in the block's slot.
        fixtureStore.toggleCompletion(placed, now: date(14, 9, 11))
        for block in done { fixtureStore.setPlacement(for: placed, start: block.start, end: block.end, isPinned: true) }
        planner.storeDidChange(now: date(14, 9, 11))
        let drawn = planner.visibleBlocks.filter { $0.taskID == placed.id }
        check(done.count == 1 && drawn.count == 1 && !drawn[0].isCompleted && drawn[0].occurrenceID == placed.occurrenceID
                && drawn[0].start == date(14, 13) && drawn[0].end == date(14, 13, 30),
              "a task reopened from its done block is drawn open at the same slot")
    }
    do {
        let (fixtureStore, planner, lifetime) = try fixture()
        defer { withExtendedLifetime(lifetime) {} }
        let pinned = add("A long slot for short work", to: fixtureStore)
        let placement = fixtureStore.setPlacement(for: pinned, start: date(), end: date(14, 10), isPinned: true)!
        planner.bootstrap(now: date(), monitorsEnabled: false)
        func missed() -> Bool {
            planner.plan.assessments.first { $0.taskID == pinned.id }?.conflicts.contains { $0.contains("Pinned time was missed") } == true
        }
        planner.tick(now: date(14, 9, 31), checkClockGap: false)
        check(!missed() && planner.plan.blocks.contains { $0.placementID == placement.id } && planner.startNudge?.taskID == pinned.id,
              "a slot longer than the work left in it isn't missed once the work would have ended")
        planner.tick(now: date(14, 10, 1), checkClockGap: false)
        check(missed(), "the slot is missed once the slot itself is over")
    }
}
try checkSchedulingNudges()
try checkWorkCompanion()
try checkManualMoveFeedback()
try checkReadOnlyRecovery()
print("Passed \(checks) calendar runtime checks")
