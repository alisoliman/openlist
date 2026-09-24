import Foundation
import SwiftData
import UserNotifications

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    guard condition() else { fatalError("FAIL: \(message)") }
}
func settleUntil(_ condition: @escaping () -> Bool) async {
    for _ in 0..<1000 {
        if condition() { return }
        await Task.yield()
    }
    fatalError("Async test boundary never arrived")
}
var clock = Date(timeIntervalSince1970: 1_900_000_000)
func intent(_ id: UUID = UUID(), date: Date? = nil, title: String = "Literal weekly task", inactive: String? = nil) -> ReminderIntent {
    ReminderIntent(id: id, occurrenceID: id, title: title, listName: "Personal", date: date ?? clock.addingTimeInterval(3600), inactiveReason: inactive)
}
let client = FakeReminderClient()
let recovery = ReminderRecovery(client: client, now: { clock })
let first = intent()
recovery.reconcile([first]); await recovery.waitUntilIdle()
check(recovery.statuses[first.id] == .accepted && client.requests.count == 1, "Accepted means matching OS pending request")
for _ in 0..<5 { recovery.retry(first.id) }
await recovery.waitUntilIdle()
check(client.adds.count == 1 && client.requests.count == 1, "Repeated retries keep one matching request without replacing it")
client.permission = .denied
recovery.refresh(); await recovery.waitUntilIdle()
check(recovery.statuses[first.id] == .denied && client.requests.isEmpty, "Permission loss is visible and old pending request is removed")
client.permissionFailure = true
_ = await recovery.requestPermission(); await recovery.waitUntilIdle()
check(recovery.authorizationError != nil && recovery.statuses[first.id] == .denied, "Authorization callback error is visible, never accepted")
client.permissionFailure = false
_ = await recovery.requestPermission(); await recovery.waitUntilIdle()
check(recovery.authorizationError == nil && recovery.statuses[first.id] == .accepted, "Permission recovery reschedules future intent")
let second = intent()
client.addFailures = 1
recovery.reconcile([first, second]); await recovery.waitUntilIdle()
if case .failed = recovery.statuses[second.id] { check(true, "Add rejection reported") } else { check(false, "Add rejection reported") }
let failedAttempts = client.adds.count
recovery.refresh(); await recovery.waitUntilIdle()
check(client.adds.count == failedAttempts, "Ordinary refresh does not loop rejected adds")
recovery.retry(second.id); await recovery.waitUntilIdle()
check(recovery.statuses[second.id] == .accepted && client.requests.count == 2, "Explicit future retry recovers without duplicate")
client.readFailure = true
recovery.refresh(); await recovery.waitUntilIdle()
check(recovery.recoveryError != nil, "Inventory read failure is observable")
client.readFailure = false
recovery.refresh(); await recovery.waitUntilIdle()
check(recovery.recoveryError == nil && recovery.statuses[first.id] == .accepted, "Successful inventory refresh clears stale recovery error")

// Delivered requests no longer appear in the pending API.
client.requests[first.id] = nil; client.delivered.insert(first.id)
recovery.reconcile([intent(first.id, inactive: "task completed"), second]); await recovery.waitUntilIdle()
check(!client.delivered.contains(first.id), "Completion removes already delivered request")
client.delivered.insert(second.id); client.requests[second.id] = nil
recovery.reconcile([]); await recovery.waitUntilIdle()
check(client.delivered.isEmpty, "Deletion removes delivered request without pending entry")
let deletedBeforeRestart = UUID()
client.delivered.insert(deletedBeforeRestart)
let restarted = ReminderRecovery(client: client, now: { clock })
restarted.reconcile([]); await restarted.waitUntilIdle()
check(client.delivered.isEmpty, "Restart removes delivered reminders for subjects missing from saved library")
let expired = intent(date: clock.addingTimeInterval(-1))
client.delivered.insert(expired.id)
restarted.reconcile([expired]); await restarted.waitUntilIdle()
check(restarted.statuses[expired.id] == .expired && client.requests.isEmpty, "Expired intent is shown and never replayed")
check(client.delivered.contains(expired.id), "A previously delivered expired alert may remain useful in Notification Center")
restarted.retry(expired.id); await restarted.waitUntilIdle()
check(client.requests.isEmpty, "Retry cannot replay expired alerts")

// Failure to read the saved library is distinct from querying the OS.
let unreadClient = FakeReminderClient()
let unseen = intent()
unreadClient.requests[unseen.id] = unseen; unreadClient.delivered.insert(unseen.id)
let unread = ReminderRecovery(client: unreadClient, now: { clock })
unread.recordReadFailure("Storage unavailable")
unread.refresh(); await unread.waitUntilIdle()
check(unreadClient.requests[unseen.id] != nil && unreadClient.delivered.contains(unseen.id), "No successful snapshot means refresh cannot cancel existing reminders")
check(unread.libraryReadError == "Storage unavailable", "Successful authorization cannot erase failed committed-library read")
unread.reconcile([unseen]); await unread.waitUntilIdle()
unread.recordReadFailure("Second read failed")
unread.refresh(); await unread.waitUntilIdle()
check(unread.libraryReadError == "Second read failed" && unread.statuses[unseen.id] == .accepted, "Old OS acceptance can coexist with visible library-read warning")
let unreadAttempts = unreadClient.adds.count
unreadClient.requests[unseen.id] = nil
unread.refresh(retryFailures: true); await unread.waitUntilIdle()
check(unreadClient.adds.count == unreadAttempts, "Unread newer library cannot recreate a missing request from old snapshot")
unread.reconcile([unseen])
check(unread.libraryReadError == nil, "Successful unchanged committed read clears only library-read error")
await unread.waitUntilIdle()
check(unreadClient.requests[unseen.id] != nil, "Recovered identical committed read retries missing prior request")
unread.recordReadFailure("Temporary failure")
unreadClient.permission = .denied
unread.refresh(); await unread.waitUntilIdle()
check(unread.statuses[unseen.id] == .denied, "Unread library does not hide known permission denial behind pending acceptance")
unreadClient.permission = .authorized
unread.reconcile([unseen]); await unread.waitUntilIdle()
unread.reconcile([]); await unread.waitUntilIdle()
check(unreadClient.requests.isEmpty && unreadClient.delivered.isEmpty, "Explicit valid empty library cancels prior pending and delivered requests")

// Stale authorization callback, delayed add, cancel and schedule replacement.
let raceClient = FakeReminderClient()
let race = ReminderRecovery(client: raceClient, now: { clock })
raceClient.holdAuthorization = true
let raceIntent = intent()
race.reconcile([raceIntent]); await settleUntil { raceClient.authorizationContinuation != nil }
raceClient.permission = .denied
race.refresh(); raceClient.releaseAuthorization(); await race.waitUntilIdle()
check(race.statuses[raceIntent.id] == .denied && raceClient.adds.isEmpty, "Old permission callback cannot accept newly denied state")
raceClient.permission = .authorized; raceClient.holdNextAdd = true
race.refresh(); await settleUntil { raceClient.addContinuation != nil }
race.reconcile([])
check(raceClient.removals.contains { $0.contains(raceIntent.id) }, "Committed cancellation removes request before delayed add callback")
raceClient.releaseAdd(); await race.waitUntilIdle()
check(raceClient.requests.isEmpty && race.statuses.isEmpty, "Late add after cancellation is removed again")
raceClient.holdNextAdd = true
race.reconcile([raceIntent]); await settleUntil { raceClient.addContinuation != nil }
let replacement = intent(raceIntent.id, date: clock.addingTimeInterval(7200), title: "Renamed")
race.reconcile([replacement]); raceClient.releaseAdd(); await race.waitUntilIdle()
check(raceClient.requests[raceIntent.id] == replacement && raceClient.requests.count == 1, "Changed schedule/title wins over old add completion")
raceClient.holdNextAdd = true
let soon = intent(date: clock.addingTimeInterval(2))
race.reconcile([soon]); await settleUntil { raceClient.addContinuation != nil }
clock = clock.addingTimeInterval(3); raceClient.releaseAdd(); await race.waitUntilIdle()
check(race.statuses[soon.id] == .expired && raceClient.requests.isEmpty, "Intent expiring while OS add is in flight is not accepted or retained")
raceClient.holdNextAdd = true
let oldLibrary = intent()
race.reconcile([oldLibrary]); await settleUntil { raceClient.addContinuation != nil }
race.resetForLibraryRestore(); let restored = intent(); race.reconcile([restored])
raceClient.releaseAdd(); await race.waitUntilIdle()
check(raceClient.requests.keys.sorted(by: { $0.uuidString < $1.uuidString }) == [restored.id], "Restore generation rejects late prior-library callback")

let sweepClient = FakeReminderClient()
let sweep = ReminderRecovery(client: sweepClient, now: { clock })
let a = intent(UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!, date: clock.addingTimeInterval(10))
let b = intent(UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!, date: clock.addingTimeInterval(3600))
sweep.reconcile([a]); await sweep.waitUntilIdle()
sweepClient.holdNextAdd = true
sweep.reconcile([a, b]); await settleUntil { sweepClient.addContinuation != nil }
clock = clock.addingTimeInterval(11)
sweepClient.requests[a.id] = nil
sweepClient.releaseAdd(); await sweep.waitUntilIdle()
check(sweep.statuses[a.id] == .expired && sweep.statuses[b.id] == .accepted, "Final pass expires earlier A while later B callback was held")
let aFuture = intent(a.id, date: clock.addingTimeInterval(7200))
sweep.reconcile([aFuture]); await sweep.waitUntilIdle()
sweepClient.holdNextAdd = true
sweep.reconcile([aFuture, b]); await settleUntil { sweepClient.addContinuation != nil }
sweepClient.requests[a.id] = nil
sweepClient.releaseAdd(); await sweep.waitUntilIdle()
check(sweep.statuses[a.id]?.needsRecovery == true && sweepClient.requests[a.id] == nil, "Final pass detects earlier accepted request evicted during later add")

let reviewClient = SystemReminderNotificationClient(center: nil, isEnabled: false)
let review = ReminderRecovery(client: reviewClient, now: { clock })
review.reconcile([intent()]); await review.waitUntilIdle()
check(review.authorization == .unavailable && review.statuses.values.allSatisfy { $0 == .unavailable }, "Review build never claims real OS acceptance")
check(NotificationService.isCalendarCategory(NotificationService.calendarStartCategory), "Calendar category namespace retained")

let simulationSuite = "openlist.reminder.simulation-check.\(UUID())"
let simulationDefaults = UserDefaults(suiteName: simulationSuite)!
defer { simulationDefaults.removePersistentDomain(forName: simulationSuite) }
let simulationClient = ReviewReminderClient(defaults: simulationDefaults)
let simulation = ReminderRecovery(client: simulationClient, isSimulated: true)
let simulatedIntent = intent(date: .now.addingTimeInterval(3600))
simulation.reconcile([simulatedIntent]); await simulation.waitUntilIdle()
check(simulation.statuses[simulatedIntent.id]?.needsRecovery == true, "Native review simulation first add exposes a recoverable failure")
simulation.retry(simulatedIntent.id); await simulation.waitUntilIdle()
check(simulation.title(for: simulation.statuses[simulatedIntent.id]!) == "Simulated pending reminder", "Successful fake retry cannot be labeled as real OS acceptance")
let restartedSimulation = ReminderRecovery(client: ReviewReminderClient(defaults: simulationDefaults), isSimulated: true)
restartedSimulation.reconcile([simulatedIntent]); await restartedSimulation.waitUntilIdle()
check(restartedSimulation.statuses[simulatedIntent.id] == .accepted, "Review simulation inventory is reconstructable after relaunch")

// Real elapsed time verifies status changes without leaving the open view.
let timerClient = FakeReminderClient()
let timerRecovery = ReminderRecovery(client: timerClient)
let timed = intent(date: Date.now.addingTimeInterval(0.15))
timerRecovery.reconcile([timed]); await timerRecovery.waitUntilIdle()
try await Task.sleep(for: .milliseconds(400))
await timerRecovery.waitUntilIdle()
check(timerRecovery.statuses[timed.id] == .expired, "Open recovery state updates when the deadline passes")
var draft = "Before quit"
var persisted = ""
var pendingWork = false
var waits = 0
var didFinish = false
try await TerminationDrain.run(commitDrafts: {}, persist: {
    if persisted != draft { persisted = draft; pendingWork = true }
}, wait: {
    waits += 1
    if waits == 1 { draft = "Edited while notification callback was pending" }
    pendingWork = false
    return true
}, hasPendingWork: { pendingWork }, finish: {
    check(persisted == draft && waits == 2, "Quit persists edits arriving during delayed OS work and drains their new request")
    didFinish = true
})
check(didFinish, "Quit completion runs only after stable final save")
var failureFinished = false
var saveAttempts = 0
do {
    try await TerminationDrain.run(commitDrafts: {}, persist: {
        saveAttempts += 1
        if saveAttempts == 2 { throw CocoaError(.fileWriteNoPermission) }
    }, wait: { true }, hasPendingWork: { false }, finish: { failureFinished = true })
} catch {}
check(!failureFinished && saveAttempts == 2, "Late final save failure never replies to quit successfully")
let hungClient = FakeReminderClient()
let hung = ReminderRecovery(client: hungClient)
hungClient.holdNextAdd = true
let hungIntent = intent(date: .now.addingTimeInterval(3600))
hung.reconcile([hungIntent]); await settleUntil { hungClient.addContinuation != nil }
var hungDraft = "Before wait"
var hungSaved = ""
var hungFinished = false
try await TerminationDrain.run(commitDrafts: {}, persist: { hungSaved = hungDraft }, wait: {
    hungDraft = "Edited during unresponsive OS callback"
    return await hung.drainForTermination(timeout: .milliseconds(50))
}, hasPendingWork: { hung.isRefreshing }, finish: { hungFinished = true })
check(hungFinished && hungSaved == hungDraft && hungClient.addContinuation != nil, "Quit timeout saves late edits without awaiting noncooperative child callback")
check(hung.statuses[hungIntent.id] == .checking, "Timed-out OS work is never reported as accepted")
hungClient.releaseAdd(); await hung.waitUntilIdle()

// Exercise actual trigger construction across DST boundaries without an OS center.
for timestamp in [1_806_198_300.0, 1_824_951_900.0] {
    let target = Date(timeIntervalSince1970: timestamp)
    let request = SystemReminderNotificationClient.request(for: intent(date: target))
    let trigger = request.trigger as! UNCalendarNotificationTrigger
    check(trigger.dateComponents.timeZone?.secondsFromGMT() == 0, "Trigger records explicit UTC rather than mutable local zone")
    check(abs(trigger.dateComponents.date!.timeIntervalSince(target)) < 1, "DST-boundary trigger preserves intended absolute instant")
    check(request.identifier == request.content.userInfo["blockID"] as? String, "Stable task UUID owns the only request identifier")
}
// The Reminder tab speaks plainly, not in the scheduler's terms, for each
// reason the Store gives a saved reminder that waits.
check(ReminderStatus.inactive("task completed").title == "Off while the task is done"
      && ReminderStatus.inactive("list archived").title == "Off while the list is archived"
      && ReminderStatus.inactive("list unavailable").title == "Off while its list can’t be found"
      && ReminderStatus.inactive("in Trash").title == "Off while it’s in Trash",
      "A reminder that waits says why in plain words")
let plainTitles: [ReminderStatus] = [.checking, .accepted, .permissionNeeded, .denied, .expired,
                                     .inactive("task completed"), .failed("x"), .unavailable]
check(plainTitles.allSatisfy { status in
          !["macOS", "Saved ·", "Not scheduled", "replayed", "scheduling"].contains { status.title.contains($0) }
      }, "No reminder status reads as the scheduler's state")
check(ReminderStatus.failed("x").title == "The reminder couldn’t be scheduled"
      && ReminderStatus.permissionNeeded.title == "Notifications aren’t allowed yet",
      "A status that needs the user reads whole beside a task's title in Settings")
// "1 day before" is a calendar day, at the due time's clock across a
// daylight-saving change, and minutes are elapsed; moving the due date
// carries a reminder at the same distance.
do {
    var amsterdam = Calendar(identifier: .gregorian)
    amsterdam.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
    func local(_ m: Int, _ d: Int, _ h: Int, _ minute: Int = 0) -> Date {
        amsterdam.date(from: DateComponents(year: 2026, month: m, day: d, hour: h, minute: minute))!
    }
    let springDue = local(3, 29, 9), fallDue = local(10, 25, 9)
    check(ReminderOffset(days: -1).date(from: springDue, calendar: amsterdam) == local(3, 28, 9)
          && ReminderOffset(days: -1).date(from: fallDue, calendar: amsterdam) == local(10, 24, 9),
          "A day before a daylight-saving day's due time keeps its clock time")
    check(ReminderOffset(minutes: -60).date(from: local(3, 29, 3, 30), calendar: amsterdam) == local(3, 29, 1, 30)
          && ReminderOffset(minutes: -10).date(from: springDue, calendar: amsterdam) == local(3, 29, 8, 50),
          "Minutes before are elapsed time, across the skipped hour too")
    let dayBefore = ReminderOffset(from: springDue, to: local(3, 28, 9), calendar: amsterdam)
    check(dayBefore == ReminderOffset(days: -1) && dayBefore.date(from: local(4, 5, 9), calendar: amsterdam) == local(4, 4, 9),
          "A reminder a day before stays a day before when the due date moves off a daylight-saving day")
    let early = ReminderOffset(from: local(3, 20, 9), to: local(3, 19, 8, 45), calendar: amsterdam)
    check(early.date(from: fallDue, calendar: amsterdam) == local(10, 24, 8, 45)
          && early.date(from: local(3, 20, 9), calendar: amsterdam) == local(3, 19, 8, 45),
          "A day and 15 minutes before moves as it reads, and back")
    // A day without a time reminds at a clock time (9:00 at the due time),
    // which it keeps wherever the due date moves.
    func moved(_ reminder: Date, _ from: Date, timed wasTimed: Bool, _ to: Date, timed isTimed: Bool) -> Date {
        ReminderOffset.reminder(reminder, movedFrom: from, timed: wasTimed, to: to, timed: isTimed, calendar: amsterdam)
    }
    check(moved(local(3, 27, 9), local(3, 27, 0), timed: false, local(3, 29, 0), timed: false) == local(3, 29, 9)
          && moved(local(3, 27, 9), local(3, 27, 0), timed: false, local(10, 25, 0), timed: false) == local(10, 25, 9)
          && moved(local(3, 28, 8, 50), local(3, 28, 0), timed: false, local(3, 29, 0), timed: false) == local(3, 29, 8, 50),
          "A due day without a time keeps its reminder's clock time onto a daylight-saving day")
    check(moved(local(3, 26, 18), local(3, 27, 0), timed: false, local(10, 25, 0), timed: false) == local(10, 24, 18),
          "A reminder the evening before a due day without a time stays the evening before")
    check(moved(local(3, 27, 9), local(3, 27, 0), timed: false, local(3, 29, 14), timed: true) == local(3, 29, 9)
          && moved(local(3, 27, 13, 50), local(3, 27, 14), timed: true, local(3, 29, 0), timed: false) == local(3, 29, 13, 50),
          "Adding or taking off a due time keeps the reminder's clock time, not a stretch from midnight")
    check(moved(local(3, 19, 9), local(3, 20, 9), timed: true, local(3, 29, 9), timed: true) == local(3, 28, 9)
          && moved(local(3, 29, 1, 30), local(3, 29, 3, 30), timed: true, local(3, 30, 3, 30), timed: true) == local(3, 30, 2, 30),
          "Between due times a reminder keeps its days and minutes")
}
print("\(checks) reminder recovery checks passed")
