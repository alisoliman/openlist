import Foundation
import SwiftData

func checkWorkCompanion() throws {
    let lifetime = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
    let fixture = Store(context: lifetime.mainContext)
    fixture.bootstrap()
    let preferences = UserDefaults(suiteName: "openlist.work.checks.\(UUID().uuidString)")!
    let source = ExternalCalendarSource(defaults: preferences, fixtureBusyTimes: [])
    let planner = CalendarCoordinator(store: fixture, defaults: preferences, externalCalendars: source)
    let first = Block(kind: .task, text: "Prepare the plan", listID: fixture.inboxList()!.id)
    first.selectedForDay = date(); first.schedulingEstimateMinutes = 30; first.priorityRaw = 3
    let second = Block(kind: .task, text: "Review the proposal", listID: first.listID)
    second.selectedForDay = date(); second.schedulingEstimateMinutes = 30; second.priorityRaw = 2
    fixture.context.insert(first); fixture.context.insert(second); fixture.save()
    planner.bootstrap(now: date(), monitorsEnabled: false)
    let reference = WorkTaskReference(first)
    check(!planner.workNotificationsEnabled, "background suggestions require opt-in")
    check(!planner.isWorkPanelPresented, "a ready suggestion never opens a popover automatically")
    planner.showWork(now: date())
    check(planner.workSelection == reference, "opening Work selects the currently planned occurrence")
    let anchors = planner.plan.blocks.map(\.start)
    let secondSlot = planner.plan.blocks.first { $0.taskID == second.id }!
    _ = planner.previewMove(secondSlot, to: date(), now: date())
    check(planner.plan.blocks.map(\.start) == anchors && fixture.placements().isEmpty, "move previews never mutate saved placements or the current plan")
    let firstSlot = planner.plan.blocks.first { $0.taskID == first.id }!
    check(planner.previewMove(firstSlot, to: date(14, 10), now: date()).contains {
        $0.taskID == second.id && $0.proposedStart == date()
    }, "preview reports a task moved earlier even when its new slot ends at its old start")
    planner.quietWork(reference, now: date())
    check(planner.startNudge == nil && planner.plan.blocks.map(\.start) == anchors, "Later quiets the suggestion without moving the plan")
    planner.tick(now: date(14, 9, 5), checkClockGap: false)
    check(planner.workSelection == reference, "replanning never swaps the open panel's action target")
    check(planner.startNudge?.taskID != first.id, "a missed-start replan cannot bypass occurrence-based quieting")
    let restored = CalendarCoordinator(store: fixture, defaults: preferences, externalCalendars: source)
    restored.bootstrap(now: date(14, 9, 6), monitorsEnabled: false)
    check(restored.quietUntil[reference.occurrenceID.uuidString] == date(14, 9, 15).timeIntervalSince1970, "quieting survives a coordinator restart")
    planner.undoQuietWork(reference, now: date())
    check(planner.quietUntil[reference.occurrenceID.uuidString] == nil, "Undo reminder restores eligibility")
    check(planner.requestWork(reference, now: date()), "explicit start records the selected occurrence")
    planner.stopWorking(now: date(14, 9, 5))
    check(planner.activeSession == nil && planner.resumableTask?.id == first.id && !first.isCompleted, "Stop saves time, keeps the task open, and offers Resume")
    check(fixture.workSessions(taskID: first.id).first?.durationMinutes() == 5, "manual Stop records the actual five minutes")
    let afterStop = CalendarCoordinator(store: fixture, defaults: preferences, externalCalendars: source)
    afterStop.bootstrap(now: date(14, 9, 10), monitorsEnabled: false)
    check(afterStop.resumableTask?.id == first.id && afterStop.activeSession == nil, "a stopped session survives reopening without counting the gap")
    check(planner.requestWork(reference, now: date(14, 9, 10)), "Resume starts another work segment")
    check(planner.requestWork(WorkTaskReference(second), now: date(14, 9, 12)), "starting a different task switches straight away")
    check(planner.activeSession?.taskID == second.id && planner.resumableTask == nil, "the switched-from task is not left waiting to resume")
    check(fixture.workSessions().filter { $0.endedAt == nil }.count == 1, "switch leaves exactly one open segment")
    check(fixture.workSessions(taskID: first.id).first?.durationMinutes() == 2, "switch saves the prior segment at the click time")
    planner.complete(task: second, now: date(14, 9, 14))
    check(second.isCompleted && planner.activeSession == nil && planner.workCompletion?.recordedMinutes == 2, "completion reports the saved occurrence and recorded time")
    planner.undoWorkCompletion(now: date(14, 9, 15))
    check(!second.isCompleted && planner.activeSession == nil, "Undo completion does not restart tracking")
    fixture.onDidSave = { planner.tick(now: date(14, 9, 15), checkClockGap: false, materialChange: true) }
    planner.complete(task: second, now: date(14, 9, 15))
    check(planner.notice == nil && planner.workCompletion != nil, "synchronous completion replan does not publish a stale occurrence warning")
    planner.undoWorkCompletion(now: date(14, 9, 15))
    fixture.onDidSave = nil
    let stale = WorkTaskReference(second)
    second.occurrenceID = UUID(); fixture.save()
    check(!planner.requestWork(stale, now: date(14, 9, 15)), "stale occurrence references cannot start a replacement repeat")
    check(planner.activeSession == nil, "a stale Start never creates a timer")

    // Start is never refused: outside the list's hours work records with no block to grow.
    first.schedulingEstimateMinutes = 30; first.selectedForDay = date(); first.priorityRaw = 3
    fixture.clearCalendarHistory()
    planner.replan(now: date(14, 20))
    check(!planner.isWithinAvailability(reference, now: date(14, 20)), "the evening is outside Work hours")
    check(planner.requestWork(reference, now: date(14, 20)), "Start working records outside the list's hours")
    check(planner.activeSession?.startedAt == date(14, 20) && !planner.plan.blocks.contains { $0.isActive }, "work outside the list's hours has no block in the plan")
    planner.tick(now: date(14, 20, 45), checkClockGap: false)
    check(planner.activeSession != nil && planner.workExtension == nil && planner.workConflict == nil, "past its estimate outside hours, work simply keeps recording")
    planner.stopWorking(now: date(14, 20, 50))
    check(planner.trackedMinutes(for: first, now: date(14, 21)) == 50, "work outside hours records every minute until Stop")
    first.isCompleted = true; fixture.save(); planner.tick(now: date(14, 20, 50), checkClockGap: false)
    check(planner.resumableTask == nil && planner.workSelection == nil, "external completion invalidates stale Resume and open-panel references")
    withExtendedLifetime(lifetime) {}
}
