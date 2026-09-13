import Foundation

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
let formatter = ISO8601DateFormatter()
var count = 0
@MainActor
func date(_ value: String) -> Date { formatter.date(from: value)! }
@MainActor
func check(_ value: @autoclosure () -> Bool, _ message: String) {
    count += 1
    guard value() else { fatalError("Scheduling check failed: \(message)") }
}
@MainActor
func near(_ lhs: Double, _ rhs: Double) -> Bool { abs(lhs - rhs) < 0.001 }
@MainActor
func task(_ number: Int, minutes: Double = 30, due: Date? = nil, today: Bool = true,
          category: AvailabilityCategory = .work, earliest: Date? = nil, priority: Int = 0,
          together: Bool = false) -> ScheduleTask {
    let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!
    return ScheduleTask(taskID: id, occurrenceID: id, title: "Task \(number)", category: category,
                        remainingMinutes: minutes, dueDate: due, selectedForToday: today,
                        earliestStart: earliest, priority: priority, keepTogether: together)
}
let now = date("2026-09-14T09:00:00+02:00") // Monday
let ten = date("2026-09-14T10:00:00+02:00")
let eleven = date("2026-09-14T11:00:00+02:00")
let noon = date("2026-09-14T12:00:00+02:00")
let tomorrow = date("2026-09-15T00:00:00+02:00")
@MainActor
func preferences(windows: [AvailabilityWindow] = [.init(startMinute: 540, endMinute: 1020)], breaks: [AvailabilityWindow] = []) -> CalendarPreferences {
    CalendarPreferences(work: AvailabilityProfile(weekly: Dictionary(uniqueKeysWithValues: (1...7).map { ($0, windows) }),
        breaks: Dictionary(uniqueKeysWithValues: (1...7).map { ($0, breaks) })), personal: .personalDefault)
}
@MainActor
func plan(_ tasks: [ScheduleTask], preferences: CalendarPreferences = .init(), busy: [FixedBusyTime] = [],
          placements: [PlacementInput] = [], active: ActiveScheduleInput? = nil, at: Date = now) -> CalendarPlan {
    AdaptiveScheduler.plan(tasks: tasks, preferences: preferences, busyTimes: busy, placements: placements,
                           active: active, now: at, calendar: calendar)
}
@MainActor
func verifyConservation(_ result: CalendarPlan, tasks: [ScheduleTask]) {
    for task in tasks {
        let duration = result.blocks.filter { $0.occurrenceID == task.occurrenceID }.reduce(0) { $0 + $1.durationMinutes }
        check(duration <= task.remainingMinutes + 0.001, "Planner never duplicates required work")
    }
    for (index, block) in result.blocks.enumerated() {
        check(block.end > block.start, "Every block has positive duration")
        check(block.start >= now && block.end <= result.end, "Blocks remain in future planning horizon")
        for other in result.blocks.dropFirst(index + 1) where !block.isPinned && !other.isPinned {
            check(block.end <= other.start || other.end <= block.start, "Flexible work never overlaps")
        }
    }
}

let first = plan([task(1)])
check(first.blocks.count == 1 && first.blocks[0].start == now, "Selected task schedules at next availability")
check(near(first.blocks[0].durationMinutes, 30), "Default estimate is 30 minutes")
check(first.assessments[0].status == .scheduled, "Feasible selected task is scheduled")
check(plan([task(1, today: false)]).blocks.isEmpty, "Undated backlog is not scheduled")
check(plan([task(1, today: false)]).assessments.isEmpty, "Undated backlog is not reported as overflow")
let dueOnly = plan([task(1, due: tomorrow, today: false)])
check(!dueOnly.blocks.isEmpty, "Upcoming due task schedules without today selection")
let distant = task(1, due: date("2026-11-14T00:00:00+01:00"), today: false)
check(plan([distant]).assessments[0].status == .outsidePlanningHorizon, "Distant due task distinguished from infeasible deadline")
check(plan([distant]).blocks.isEmpty, "Distant unselected deadline remains outside plan")
var selectedDistant = distant
selectedDistant.selectedForToday = true
check(plan([selectedDistant]).assessments[0].status == .scheduled, "Today selection brings distant deadline into plan")

let meeting = FixedBusyTime(id: "meeting", title: "Team meeting", start: ten, end: eleven)
let aroundMeeting = plan([task(1, minutes: 180)], busy: [meeting])
check(aroundMeeting.blocks.count == 3, "Task splits around meeting and lunch")
check(aroundMeeting.blocks[0].end == ten && aroundMeeting.blocks[1].start == eleven, "External busy interval is fixed")
// The second hour after meeting ends at lunch; remaining hour follows lunch.
check(near(aroundMeeting.blocks.reduce(0) { $0 + $1.durationMinutes }, 180), "All split time conserved")
let afternoon = plan([task(1, minutes: 60)], at: date("2026-09-14T11:40:00+02:00"))
check(afternoon.blocks[0].start == date("2026-09-14T13:00:00+02:00"), "20-minute pre-break gap skipped for longer task")
let short = plan([task(1, minutes: 15)], at: date("2026-09-14T11:40:00+02:00"))
check(near(short.blocks[0].durationMinutes, 15), "Entire short tasks may use shorter slots")
let tinyTail = plan([task(1, minutes: 70)], preferences: preferences(windows: [.init(startMinute: 540, endMinute: 600), .init(startMinute: 660, endMinute: 720)]))
check(tinyTail.blocks.map { Int($0.durationMinutes) } == [45, 25], "Split adjusts first chunk to avoid a tiny tail")
let unsplittable = plan([task(1, minutes: 40)], preferences: preferences(windows: [.init(startMinute: 540, endMinute: 570)]))
check(unsplittable.blocks.isEmpty, "40-minute task cannot split into fragments below minimum")
check(unsplittable.assessments[0].status == .outsidePlanningHorizon, "Undated overload has horizon status")
let together = plan([task(1, minutes: 90, together: true)], busy: [meeting])
check(together.blocks.count == 1 && together.blocks[0].start == date("2026-09-14T13:00:00+02:00"), "Keep together waits for one contiguous slot")
let impossibleTogether = plan([task(1, minutes: 90, due: tomorrow, together: true)], preferences: preferences(windows: [.init(startMinute: 540, endMinute: 600)]))
check(impossibleTogether.assessments[0].status == .cannotFitBeforeDeadline, "Keep together reports impossible cutoff")

let oneHour = preferences(windows: [.init(startMinute: 540, endMinute: 600)])
let pressured = plan([task(1, minutes: 60, priority: 4), task(2, minutes: 60, due: ten, today: false)], preferences: oneHour)
check(pressured.blocks[0].taskID == task(2).taskID, "Deadline risk outranks higher-priority today task")
check(pressured.blocks[1].start == date("2026-09-15T09:00:00+02:00"), "Overflow moves to future availability")
let todayFirst = plan([task(1, minutes: 60, due: date("2026-09-25T17:00:00+02:00"), today: false), task(2, minutes: 60)], preferences: preferences())
check(todayFirst.blocks[0].taskID == task(2).taskID, "Today outranks a comfortable future deadline")
let priority = plan([task(1, priority: 1), task(2, priority: 3)])
check(priority.blocks[0].taskID == task(2).taskID, "Priority breaks today ties")
let dueTie = plan([task(1, due: ten, priority: 1), task(2, due: ten, priority: 3)])
check(dueTie.blocks[0].taskID == task(2).taskID, "Priority breaks equal deadline ties")
let dueOrder = plan([task(1, minutes: 60, due: eleven, priority: 4), task(2, minutes: 60, due: ten, priority: 0)])
check(dueOrder.blocks[0].taskID == task(2).taskID, "Earlier urgent cutoff comes first")
let overloaded = plan([task(1, minutes: 90, due: ten)], preferences: oneHour)
check(overloaded.assessments[0].status == .cannotFitBeforeDeadline, "Overloaded deadline is explicit")
check(near(overloaded.assessments[0].beforeDeadlineMinutes, 60), "Deadline coverage counts only pre-cutoff time")
check(near(overloaded.assessments[0].scheduledMinutes, 90), "Late overflow remains planned")
let cumulative = plan([task(1, minutes: 90, due: date("2026-09-15T10:00:00+02:00"), today: false),
                       task(2, minutes: 60, due: date("2026-09-15T10:00:00+02:00"), today: false),
                       task(3, minutes: 60, priority: 4)], preferences: oneHour)
check(cumulative.blocks[0].taskID == task(1).taskID, "Cumulative due pressure outranks today work")
check(cumulative.assessments.contains { $0.status == .cannotFitBeforeDeadline }, "Competing deadline shortfall remains visible")

let overdueHuge = plan([task(1, minutes: 300, due: ten, today: false), task(2, minutes: 60, due: noon, today: false)], preferences: preferences())
check(overdueHuge.assessments.first { $0.taskID == task(2).taskID }?.status == .scheduled, "Late overflow cannot steal a later task's feasible deadline")
check(overdueHuge.blocks.first { $0.taskID == task(2).taskID }?.start == ten, "Later deadline gets next pre-deadline hour before overdue overflow")
let undatedDeferred = plan([task(1, today: false, earliest: tomorrow)])
check(undatedDeferred.blocks.first?.start == date("2026-09-15T09:00:00+02:00"), "Explicit deferral schedules undated work on its chosen future day")
let distantDeferred = plan([task(1, today: false, earliest: date("2026-11-01T00:00:00+01:00"))])
check(distantDeferred.assessments.first?.status == .outsidePlanningHorizon && distantDeferred.blocks.isEmpty, "Deferral outside horizon remains explicit")
let outsidePin = PlacementInput(id: UUID(), taskID: task(1).taskID, occurrenceID: task(1).occurrenceID,
    start: date("2026-10-13T09:00:00+02:00"), end: date("2026-10-13T09:30:00+02:00"), isPinned: true)
let outsidePinnedPlan = plan([task(1, today: false)], placements: [outsidePin])
check(outsidePinnedPlan.blocks.isEmpty, "A pin beyond the horizon cannot silently move into today's plan")
check(outsidePinnedPlan.assessments[0].status == .outsidePlanningHorizon && outsidePinnedPlan.assessments[0].reason.contains("pinned"), "Outside-horizon pin has an explicit assessment")
let deadlineOutsidePin = plan([task(1, due: tomorrow)], placements: [outsidePin])
check(deadlineOutsidePin.blocks.isEmpty && deadlineOutsidePin.assessments[0].status == .cannotFitBeforeDeadline, "Outside-horizon pin cannot falsely satisfy a nearer deadline")
check(deadlineOutsidePin.assessments[0].conflicts.contains { $0.contains("deadline") }, "Outside-horizon pin after cutoff is a visible fixed-time conflict")
let crossingPin = PlacementInput(id: UUID(), taskID: task(1).taskID, occurrenceID: task(1).occurrenceID,
    start: date("2026-10-11T23:00:00+02:00"), end: date("2026-10-12T01:00:00+02:00"), isPinned: true)
let crossingPinnedPlan = plan([task(1, minutes: 120)], preferences: preferences(windows: [.init(startMinute: 0, endMinute: 1440)]), placements: [crossingPin])
check(crossingPinnedPlan.blocks.count == 1 && near(crossingPinnedPlan.blocks[0].durationMinutes, 60), "Pin crossing the horizon is clipped for display without moving its outside remainder")
check(near(crossingPinnedPlan.assessments[0].scheduledMinutes, 60) && crossingPinnedPlan.assessments[0].status == .outsidePlanningHorizon, "Cross-horizon pin counts only its visible safe coverage")

let separate = plan([task(1, category: .personal), task(2, category: .work)])
check(separate.blocks.first(where: { $0.taskID == task(1).taskID })?.start == date("2026-09-14T18:00:00+02:00"), "Personal task uses personal hours")
var overlapPreferences = preferences()
overlapPreferences.personal = overlapPreferences.work
let overlapCategories = plan([task(1, category: .personal), task(2, category: .work)], preferences: overlapPreferences)
check(overlapCategories.blocks[0].end == overlapCategories.blocks[1].start, "Separate profiles share one human calendar")
var overridePreferences = preferences()
overridePreferences.work.overrides = [AvailabilityOverride(date: now, windows: [])]
check(plan([task(1)], preferences: overridePreferences).blocks[0].start == date("2026-09-15T09:00:00+02:00"), "Empty date override removes that day's availability")
overridePreferences.work.overrides = [AvailabilityOverride(date: now, windows: [.init(startMinute: 600, endMinute: 720)], breaks: [.init(startMinute: 630, endMinute: 660)])]
let overridden = plan([task(1, minutes: 60)], preferences: overridePreferences)
check(overridden.blocks.map(\.start) == [ten, eleven], "Date override replaces weekly hours and breaks")
let deferred = plan([task(1, earliest: tomorrow)])
check(deferred.blocks[0].start == date("2026-09-15T09:00:00+02:00"), "Deferred task cannot return earlier than chosen day")

let placementID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
let preferred = PlacementInput(id: placementID, taskID: task(1).taskID, occurrenceID: task(1).occurrenceID, start: eleven, end: noon, isPinned: false)
check(plan([task(1, minutes: 60)], placements: [preferred]).blocks[0].start == eleven, "Valid manual preference is retained")
let preferenceMeeting = FixedBusyTime(id: "busy", title: "Call", start: eleven, end: noon)
let movedPreference = plan([task(1, minutes: 60)], busy: [preferenceMeeting], placements: [preferred])
check(movedPreference.blocks[0].start == now && !movedPreference.blocks[0].isPinned, "Preferred block moves around fixed meeting")
var tomorrowPreference = preferred
tomorrowPreference.start = date("2026-09-15T10:00:00+02:00")
tomorrowPreference.end = date("2026-09-15T11:00:00+02:00")
let preferredTomorrow = plan([task(1, minutes: 60)], placements: [tomorrowPreference])
check(preferredTomorrow.blocks[0].start == tomorrowPreference.start, "Manual future preference is retained for an undated task selected today")
check(preferredTomorrow.blocks[0].placementID == tomorrowPreference.id && !preferredTomorrow.blocks[0].isPinned, "Future preference retains its editable placement identity without becoming pinned")
let futureMeeting = FixedBusyTime(id: "future-meeting", title: "Tomorrow's meeting", start: tomorrowPreference.start, end: tomorrowPreference.end)
check(plan([task(1, minutes: 60)], busy: [futureMeeting], placements: [tomorrowPreference]).blocks[0].start == now, "Future preference still yields to external busy time")
let nearDeadlinePreference = plan([task(1, minutes: 60, due: tomorrow)], placements: [tomorrowPreference])
check(nearDeadlinePreference.blocks[0].start == now && nearDeadlinePreference.assessments[0].status == .scheduled, "Preference after cutoff yields to feasible time before deadline")
let feasibleDuePreference = plan([task(1, minutes: 60, due: tomorrowPreference.end, today: false)], placements: [tomorrowPreference])
check(feasibleDuePreference.blocks[0].start == tomorrowPreference.start && feasibleDuePreference.assessments[0].status == .scheduled, "Valid future preference ending at deadline is honored")
let urgentAtPreferredTime = plan([
    task(1, minutes: 60),
    task(2, minutes: 60, due: tomorrowPreference.end, today: false, earliest: tomorrowPreference.start)
], placements: [tomorrowPreference])
check(urgentAtPreferredTime.blocks.first { $0.taskID == task(2).taskID }?.start == tomorrowPreference.start, "An at-risk deadline outranks another task's advisory preference")
check(urgentAtPreferredTime.blocks.first { $0.taskID == task(1).taskID }?.start == now, "Conflicting future preference replans to available time")
var pinned = preferred
pinned.isPinned = true
let pinConflict = plan([task(1, minutes: 60, due: tomorrow)], busy: [preferenceMeeting], placements: [pinned])
check(pinConflict.blocks[0].start == eleven && pinConflict.blocks[0].isPinned, "Pinned conflict retains fixed placement")
check(!pinConflict.blocks[0].conflicts.isEmpty, "Pinned meeting conflict is flagged")
check(pinConflict.assessments[0].scheduledMinutes == 0, "Conflicting pin is not counted as safe coverage")
check(pinConflict.assessments[0].status == .cannotFitBeforeDeadline, "Unsafe pinned work cannot falsely satisfy a deadline")
let flexibleAroundPin = plan([task(1, minutes: 60), task(2, minutes: 180)], placements: [pinned])
check(flexibleAroundPin.blocks.filter { !$0.isPinned }.allSatisfy { $0.end <= eleven || $0.start >= noon }, "Flexible blocks cannot overlap pins")
var secondPin = pinned
secondPin.id = UUID()
secondPin.taskID = task(2).taskID
secondPin.occurrenceID = task(2).occurrenceID
let pinsConflict = plan([task(1, minutes: 60), task(2, minutes: 60)], placements: [pinned, secondPin])
check(pinsConflict.blocks.allSatisfy { !$0.conflicts.isEmpty }, "Both mutually conflicting pins are flagged")
check(pinsConflict.assessments.allSatisfy { $0.scheduledMinutes == 0 }, "Overlapping pins never double count safe work")

let missedPin = PlacementInput(id: UUID(), taskID: task(1).taskID, occurrenceID: task(1).occurrenceID,
    start: now.addingTimeInterval(-3600), end: now.addingTimeInterval(-1800), isPinned: true)
let missedPlan = plan([task(1, today: false)], placements: [missedPin])
check(!missedPlan.assessments[0].conflicts.isEmpty, "Missed pinned commitment remains flagged")
check(missedPlan.blocks[0].start == now && !missedPlan.blocks[0].isActive, "Missed pin replans without pretending the task started")
let wrongPin = PlacementInput(id: UUID(), taskID: task(99).taskID, occurrenceID: task(1).occurrenceID, start: eleven, end: noon, isPinned: true)
check(plan([task(1)], placements: [wrongPin]).blocks.allSatisfy { !$0.isPinned }, "Mismatched task and occurrence cannot capture another task's pin")
let shortPinned = plan([task(1, minutes: 15)], placements: [pinned])
check(near(shortPinned.blocks.reduce(0) { $0 + $1.durationMinutes }, 15), "Long saved placement never overcounts a reduced estimate")
let unavailablePin = PlacementInput(id: UUID(), taskID: task(1).taskID, occurrenceID: task(1).occurrenceID,
    start: noon, end: noon.addingTimeInterval(1800), isPinned: true)
check(plan([task(1)], placements: [unavailablePin]).blocks[0].conflicts.contains { $0.contains("break") }, "Pinned break conflict is visible")

let active = ActiveScheduleInput(taskID: task(1).taskID, occurrenceID: task(1).occurrenceID, start: now.addingTimeInterval(-1800), end: now.addingTimeInterval(45 * 60))
let explicitActive = plan([task(1, minutes: 45), task(2, minutes: 30, priority: 4)], active: active)
check(explicitActive.blocks[0].isActive && explicitActive.blocks[0].taskID == task(1).taskID, "Explicit active work is protected from priorities")
check(explicitActive.blocks[1].start == now.addingTimeInterval(45 * 60), "Active 15-minute overrun moves subsequent flexible task")
let unstarted = plan([task(1), task(2)], placements: [PlacementInput(id: UUID(), taskID: task(1).taskID, occurrenceID: task(1).occurrenceID, start: now.addingTimeInterval(-1800), end: now, isPinned: false)])
check(unstarted.blocks.allSatisfy { !$0.isActive }, "An unstarted block never becomes ongoing work")
let boundaryActive = ActiveScheduleInput(taskID: task(1).taskID, occurrenceID: task(1).occurrenceID, start: now, end: eleven)
let activeMeeting = plan([task(1, minutes: 120)], busy: [meeting], active: boundaryActive)
check(activeMeeting.blocks[0].end == ten && activeMeeting.blocks[1].start == eleven, "Active forecast pauses at meeting and resumes remaining in next slot")
check(AdaptiveScheduler.activeBoundary(category: .work, preferences: .init(), busyTimes: [meeting], now: now, calendar: calendar) == ten, "Runtime meeting boundary uses planner availability")
check(AdaptiveScheduler.activeBoundary(category: .work, preferences: .init(), busyTimes: [meeting], now: ten, calendar: calendar) == nil, "Runtime cannot start inside meeting")
check(AdaptiveScheduler.activeBoundary(category: .work, preferences: .init(), busyTimes: [], now: noon, calendar: calendar) == nil, "Runtime cannot start during break")
check(AdaptiveScheduler.activeBoundary(category: .work, preferences: .init(), busyTimes: [], now: date("2026-09-14T16:50:00+02:00"), calendar: calendar) == date("2026-09-14T17:00:00+02:00"), "Runtime pauses at end of available hours")

let ownPinActive = plan([task(1, minutes: 45)], placements: [pinned], active: active)
check(ownPinActive.blocks.count == 1 && ownPinActive.blocks[0].isActive, "Active forecast does not double-count own pinned work")
let ignoredOwnPin = plan([task(1, minutes: 45), task(2, minutes: 60)], placements: [pinned, secondPin], active: active)
check(ignoredOwnPin.blocks.first { $0.taskID == task(2).taskID }?.conflicts.isEmpty == true, "Own pin replaced by active forecast cannot cause a phantom pin conflict")
var trimmedPin = pinned
trimmedPin.start = now
trimmedPin.end = eleven
var adjacentPin = secondPin
adjacentPin.start = ten
adjacentPin.end = eleven
let trimConflict = plan([task(1, minutes: 30), task(2, minutes: 60)], placements: [trimmedPin, adjacentPin])
check(trimConflict.blocks.allSatisfy { $0.conflicts.isEmpty }, "Unused pin extent after reduced estimate does not block another pin")
let duringMeetingActive = plan([task(1, minutes: 60)], busy: [FixedBusyTime(id: "current", title: "Meeting", start: now.addingTimeInterval(-60), end: ten)], active: active)
check(duringMeetingActive.blocks.allSatisfy { !$0.isActive } && duringMeetingActive.blocks[0].start == ten, "Active forecast cannot occupy a meeting already underway")
check(plan([task(1, minutes: 0)]).blocks.isEmpty, "Zero remaining work creates no duration")
check(plan([task(1, minutes: -.infinity)]).blocks.isEmpty, "Invalid negative duration cannot poison plan")
let secondsPlan = plan([task(1)], at: now.addingTimeInterval(11))
check(secondsPlan.blocks[0].start == now.addingTimeInterval(60), "Flexible start rounds forward without scheduling in the past")
let allDay = FixedBusyTime(id: "all-day", title: "Away", start: now, end: tomorrow)
check(plan([task(1)], busy: [allDay]).blocks[0].start == date("2026-09-15T09:00:00+02:00"), "All-day busy time removes all of today's capacity")
var badHours = preferences(windows: [.init(startMinute: -60, endMinute: 600), .init(startMinute: 720, endMinute: 540)])
badHours.horizonDays = 500
let bounded = plan([task(1)], preferences: badHours)
check(bounded.end == date("2026-10-12T00:00:00+02:00") && bounded.blocks.isEmpty, "Invalid windows are ignored and horizon remains four weeks")

let spring = date("2026-03-28T00:00:00+01:00")
let springPlan = plan([task(1)], preferences: preferences(), at: spring)
check(springPlan.end == date("2026-04-25T00:00:00+02:00"), "Four-week horizon counts local dates through DST")
let fall = date("2026-10-24T00:00:00+02:00")
let fallPlan = plan([task(1)], preferences: preferences(), at: fall)
check(fallPlan.end == date("2026-11-21T00:00:00+01:00"), "Four-week horizon handles fall-back day")
let transitionPrefs = preferences(windows: [.init(startMinute: 120, endMinute: 240)])
let dst = AdaptiveScheduler.availabilityIntervals(for: .work, preferences: transitionPrefs, from: date("2026-03-29T00:00:00+01:00"), to: date("2026-03-30T00:00:00+02:00"), calendar: calendar)
check(dst.count == 1 && near(dst[0].duration / 60, 60), "Spring-forward availability uses existing wall-clock minutes")
let encoded = try JSONEncoder().encode(overridePreferences)
let decoded = try JSONDecoder().decode(CalendarPreferences.self, from: encoded)
check(decoded == overridePreferences, "Availability and overrides round-trip through local persistence")

// A mixed four-week schedule exercises conservation, minimum sessions and deterministic input order.
let mixedTasks = (1...36).map { index in
    task(index, minutes: Double(25 + (index % 5) * 30), due: index % 3 == 0 ? calendar.date(byAdding: .day, value: index % 8, to: tomorrow)! : nil,
         today: index % 4 != 0, category: index % 6 == 0 ? .personal : .work, priority: index % 4, together: index % 7 == 0)
}
let mixed = plan(mixedTasks, busy: [meeting])
verifyConservation(mixed, tasks: mixedTasks)
let reversed = plan(mixedTasks.reversed(), busy: [meeting])
check(mixed.blocks.map(\.id) == reversed.blocks.map(\.id) && mixed.blocks.map(\.start) == reversed.blocks.map(\.start), "Planning is deterministic under input reordering")
print("Scheduling checks passed: \(count)")
