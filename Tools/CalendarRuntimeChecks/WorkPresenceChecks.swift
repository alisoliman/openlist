import Foundation
import SwiftData

/// The iPhone's presence policy: its app is suspended while its user works,
/// so a clock gap keeps work recording and a relaunch can carry the open
/// session on. The Mac's default, pausing where the app last saw the work, is
/// covered by the gap and restart checks in main.swift.
func checkWorkPresencePolicy() throws {
    let lifetime = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
    let fixture = Store(context: lifetime.mainContext)
    fixture.bootstrap()
    let preferences = UserDefaults(suiteName: "openlist.presence.checks.\(UUID().uuidString)")!
    let source = ExternalCalendarSource(defaults: preferences, fixtureBusyTimes: [])
    var asked: [UUID] = []
    let phone = WorkPresencePolicy(pausesAfterClockGap: false, adoptsOpenSession: { asked.append($0.id); return true })
    let planner = CalendarCoordinator(store: fixture, defaults: preferences, externalCalendars: source, presence: phone)
    let work = Block(kind: .task, text: "Draft Q3 OKRs", listID: fixture.inboxList()!.id)
    work.selectedForDay = date(); work.schedulingEstimateMinutes = 90
    fixture.context.insert(work); fixture.save()
    planner.bootstrap(now: date(), monitorsEnabled: false)
    check(asked.isEmpty, "with no open session, the policy is never asked")

    check(planner.start(task: work, now: date(14, 10)), "work starts under the iPhone's policy")
    planner.tick(now: date(14, 10, 40))
    check(planner.activeSession?.taskID == work.id, "a suspended app's clock gap keeps the iPhone's work recording")
    check(planner.trackedMinutes(for: work, now: date(14, 10, 40)) == 40, "the time the app was suspended counts as work")

    let session = planner.activeSession!
    let relaunched = CalendarCoordinator(store: fixture, defaults: preferences, externalCalendars: source, presence: phone)
    relaunched.bootstrap(now: date(14, 11), monitorsEnabled: false)
    check(asked == [session.id], "a relaunch asks the policy about this device's open session")
    check(relaunched.activeSession?.id == session.id && relaunched.resumeTaskID == nil && relaunched.notice == nil,
          "an adopted session keeps running instead of pausing at its last heartbeat")
    check(relaunched.trackedMinutes(for: work, now: date(14, 11)) == 60 && relaunched.workSelection == WorkTaskReference(work),
          "an adopted session counts from its start and is the Work panel's task")
    relaunched.pause(now: date(14, 11, 5))
    check(session.endedAt == date(14, 11, 5) && relaunched.resumeTaskID == work.id, "Pause after adoption records up to the tap")

    check(relaunched.start(task: work, now: date(14, 12)), "work starts again")
    relaunched.tick(now: date(14, 12, 2), checkClockGap: false)
    let declining = WorkPresencePolicy(pausesAfterClockGap: false, adoptsOpenSession: { _ in false })
    let declined = CalendarCoordinator(store: fixture, defaults: preferences, externalCalendars: source, presence: declining)
    declined.bootstrap(now: date(14, 13), monitorsEnabled: false)
    check(declined.activeSession == nil && declined.resumeTaskID == work.id, "a session the policy declines is offered to resume")
    check(fixture.workSessions(taskID: work.id).allSatisfy { $0.endedAt != nil }
          && fixture.workSessions(taskID: work.id).contains { $0.endedAt == date(14, 12, 2) },
          "a declined session closes at its last heartbeat, as on the Mac")

    fixture.toggleCompletion(work, now: date(14, 13, 1))
    let stale = WorkSession(task: work, deviceID: fixture.calendarDeviceID!, startedAt: date(14, 13, 2))
    fixture.context.insert(stale); fixture.save()
    asked = []
    let afterDone = CalendarCoordinator(store: fixture, defaults: preferences, externalCalendars: source, presence: phone)
    afterDone.bootstrap(now: date(14, 14), monitorsEnabled: false)
    check(asked.isEmpty && afterDone.activeSession == nil && stale.endedAt != nil,
          "an open session of a completed task is never adopted")
}
