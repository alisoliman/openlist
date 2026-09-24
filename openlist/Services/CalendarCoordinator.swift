import AppKit
import Foundation
import SwiftData

/// Owns the live clock on this Mac. Plans are derived, never synced as generated
/// events; task choices, explicit placements and work records use the main Store.
@Observable @MainActor
final class CalendarCoordinator {
    let store: Store
    let externalCalendars: ExternalCalendarSource
    private(set) var preferences: CalendarPreferences
    private(set) var plan: CalendarPlan = .empty
    private(set) var completedBlocks: [PlannedBlock] = []
    /// What the calendar draws. Only explicit planning puts a task there: its
    /// placements at their saved times, past ones included, the running work,
    /// paused work where it was, and completed occurrences that had a slot or
    /// recorded work. The plan's flexible blocks only drive the Work panel's
    /// suggestion; Start nudges and what gets reported as moved are drawn blocks.
    private(set) var visibleBlocks: [PlannedBlock] = []
    /// The block in `visibleBlocks` that paused work keeps, drawn as the work
    /// while it can resume.
    private(set) var pausedBlockID: String?
    private(set) var startNudge: CalendarStartNudge? {
        didSet { if oldValue != startNudge { onNudgesChanged?() } }
    }
    private(set) var overrunNudge: CalendarOverrunNudge? {
        didSet { if oldValue != overrunNudge { onNudgesChanged?() } }
    }
    private(set) var rescheduleSummary: CalendarRescheduleSummary?
    /// Extra time the running work has been given past its slot or estimate,
    /// and the placed tasks its latest extension moved.
    private(set) var workExtension: CalendarWorkExtension?
    /// The meeting or break the running work ran into once its block could
    /// grow no further. Recording carries on through it.
    private(set) var workConflict: CalendarWorkConflict?
    @ObservationIgnored var onNudgesChanged: (() -> Void)?
    /// Runs each time the Mac reports you back: waking, the screen, unlocking.
    @ObservationIgnored var onMacReturn: (() -> Void)?
    private var activeSessionID: UUID?
    var activeSession: WorkSession? {
        guard let activeSessionID else { return nil }
        return store.workSessions().first { $0.id == activeSessionID }
    }
    private(set) var resumeTaskID: UUID?
    private(set) var resumeOccurrenceID: UUID?
    var isWorkPanelPresented = false
    private(set) var workSelection: WorkTaskReference?
    private(set) var workCompletion: WorkCompletionSummary?
    private(set) var quietUntil: [String: Double] = [:]
    var workNotificationsEnabled: Bool {
        didSet {
            defaults.set(workNotificationsEnabled, forKey: "work.notificationsEnabled")
            onNudgesChanged?()
        }
    }
    var notice: String?
    private let defaults: UserDefaults
    private let deviceID: String
    private let monitor = MacWorkMonitor()
    private var timer: Timer?
    private var isUpdating = false
    private var hasStarted = false
    /// Where the running work's block has to stop growing: the next meeting or
    /// the end of the hours it started in. Nil for work started outside them,
    /// which records like any other but has no block to grow.
    private var activeBoundary: Date?
    /// While the Mac is away and the running work tracks away: where that time
    /// stops counting, the next fixed event, another task's pinned time or the
    /// end of the list's hours. At the Mac, work records through them.
    private var awayLimit: Date?
    private var lastObservedAt: Date?
    private var lastCalendarRefresh: Date = .distantPast
    /// Where the running work's block ends, the end of the slot it works
    /// through (or its estimate) plus any extensions, before `activeBoundary`
    /// caps it.
    private var approvedWorkEnd: Date?
    /// Where the running work's estimate runs out, to notice it changing.
    private var estimatedWorkEnd: Date?
    /// Where the running work's block was when it paused, and how it read,
    /// kept while it can resume.
    private var pausedWork: PausedWork?
    /// The running work's extensions, newest last, and those Undo took back.
    private var extensionSteps: [WorkExtensionStep] = []
    private var undoneExtensionSteps: [WorkExtensionStep] = []
    /// Extensions of work that has since stopped, and those Undo took back:
    /// Undo and Redo still move the placements they moved, as the design's
    /// Undo puts them back however the work stands.
    private var settledExtensionSteps: [WorkExtensionStep] = []
    private var undoneSettledSteps: [WorkExtensionStep] = []
    /// Set once Undo takes an extension back, so the block isn't grown again
    /// straight away. Work keeps recording past it.
    private var extensionsHeld = false
    private var showedFinishHeadsUp = false
    private var busySignature: [String] = []
    private var isRefreshingCalendars = false
    private var pendingCalendarChange = false
    private var storeSchedulingSignature: [String] = []
    private var missedPlacementIDs: Set<UUID> = []
    private var calendar: Calendar { .current }

    init(store: Store, defaults: UserDefaults = ReviewSession.defaults, externalCalendars: ExternalCalendarSource? = nil) {
        self.store = store
        self.defaults = defaults
        workNotificationsEnabled = defaults.bool(forKey: "work.notificationsEnabled")
        quietUntil = defaults.dictionary(forKey: "work.quietUntil") as? [String: Double] ?? [:]
        resumeTaskID = defaults.string(forKey: "work.resumeTaskID").flatMap(UUID.init(uuidString:))
        resumeOccurrenceID = defaults.string(forKey: "work.resumeOccurrenceID").flatMap(UUID.init(uuidString:))
        self.externalCalendars = externalCalendars ?? ExternalCalendarSource(defaults: defaults)
        if let data = defaults.data(forKey: "calendar.preferences"),
           let decoded = try? JSONDecoder().decode(CalendarPreferences.self, from: data) {
            preferences = decoded
        } else {
            preferences = CalendarPreferences()
        }
        deviceID = defaults.string(forKey: "calendar.deviceID") ?? UUID().uuidString
        defaults.set(deviceID, forKey: "calendar.deviceID")
        store.calendarDeviceID = deviceID
        store.calendarDefaultEstimateMinutes = Int(preferences.defaultEstimateMinutes)
        store.calendarRecordingEndpoint = { [weak self] session, now in
            self?.recordingEndpoint(for: session, at: now) ?? min(now, session.lastHeartbeatAt)
        }
        self.externalCalendars.onChange = { [weak self] in
            guard let self, !self.isRefreshingCalendars, self.busyTimesChanged() else { return }
            self.tick(checkClockGap: false, materialChange: true)
        }
        monitor.onUnavailable = { [weak self] reason in self?.handleMacUnavailable(reason: reason) }
        monitor.onReturn = { [weak self] in self?.handleMacReturn() }
        monitor.onTerminate = { [weak self] in self?.pause(reason: "Openlist closed") }
    }

    func bootstrap(now: Date = .now, monitorsEnabled: Bool = true) {
        guard !hasStarted else { return }
        hasStarted = true
        // A saved open record is not evidence that work continued while the app
        // was absent. Recover only this Mac's session, at its last heartbeat.
        var recoveryFailed = false
        for session in store.workSessions() where session.deviceID == deviceID && session.endedAt == nil {
            if !store.pauseWorkSession(session, reason: "Openlist restarted", now: min(now, session.lastHeartbeatAt)) {
                recoveryFailed = true
            }
            resumeTaskID = session.taskID
            resumeOccurrenceID = session.occurrenceID
        }
        validateWorkReferences()
        if recoveryFailed { notice = store.persistenceError ?? "Previous work could not be recovered. Try again after saving is available." }
        else if resumeTaskID != nil { notice = "Previous work was paused at its last recorded time. Resume when ready." }
        refreshCalendars(now: now)
        replan(now: now)
        if monitorsEnabled {
            monitor.start()
            timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            if let timer { RunLoop.main.add(timer, forMode: .common) }
        }
    }

    func estimatedMinutes(for task: Block) -> Double {
        task.schedulingEstimateMinutes > 0 ? Double(task.schedulingEstimateMinutes) : preferences.defaultEstimateMinutes
    }

    func trackedMinutes(for task: Block, now: Date = .now) -> Double {
        store.workSessions(taskID: task.id).filter { $0.occurrenceID == task.occurrenceID }
            .reduce(0) { $0 + recordedMinutes(for: $1, now: now) }
    }

    func recordedMinutes(for session: WorkSession, now: Date = .now) -> Double {
        let endpoint = session.endedAt != nil ? now : recordingEndpoint(for: session, at: now)
        return session.durationMinutes(at: endpoint)
    }

    func remainingMinutes(for task: Block, now: Date = .now) -> Double {
        if let activeSession, activeSession.taskID == task.id, activeSession.occurrenceID == task.occurrenceID {
            return max(0, targetEnd(for: activeSession, task: task, now: now).timeIntervalSince(now) / 60)
        }
        // Finishing the estimate does not finish the task. Keep a small runway
        // until the user explicitly completes it or corrects the estimate.
        let remaining = estimatedMinutes(for: task) - trackedMinutes(for: task, now: now)
        return remaining > 0 ? remaining : 15
    }

    func updatePreferences(_ value: CalendarPreferences, now: Date = .now) {
        var value = value
        value.defaultEstimateMinutes = min(24 * 60, max(1, value.defaultEstimateMinutes.isFinite ? value.defaultEstimateMinutes : 30))
        value.minimumSessionMinutes = min(240, max(1, value.minimumSessionMinutes))
        value.horizonDays = 28
        guard let data = try? JSONEncoder().encode(value) else { return }
        preferences = value
        defaults.set(data, forKey: "calendar.preferences")
        store.calendarDefaultEstimateMinutes = Int(value.defaultEstimateMinutes.rounded())
        tick(now: now, checkClockGap: false, materialChange: true)
    }

    func refreshCalendars(now: Date = .now) {
        lastCalendarRefresh = now
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 28, to: start)!
        isRefreshingCalendars = true
        externalCalendars.refresh(start: start, end: end)
        isRefreshingCalendars = false
        if busyTimesChanged() {
            if isUpdating { pendingCalendarChange = true }
            else { tick(now: now, checkClockGap: false, materialChange: true) }
        }
    }

    func storeDidChange(now: Date = .now) {
        guard hasStarted, !isUpdating else { return }
        guard schedulingSignature() != storeSchedulingSignature else {
            refreshVisibleBlocks(now: now)
            return
        }
        tick(now: now, checkClockGap: false, materialChange: true)
    }

    func replan(now: Date = .now) {
        refreshActiveEstimate(now: now)
        missedPlacementIDs.subtract(store.placements().filter { $0.start > now }.map(\.id))
        let lists = store.allLists()
        let categories = Dictionary(uniqueKeysWithValues: lists.map { ($0.id, AvailabilityCategory(rawValue: $0.availabilityCategoryRaw) ?? .work) })
        let tasks = ((try? store.context.fetch(FetchDescriptor<Block>(predicate: #Predicate { $0.trashID == nil && $0.kindRaw == "task" && !$0.isCompleted }))) ?? [])
            .filter { task in task.listID.flatMap { categories[store.resolvedListID($0) ?? $0] } != nil }
        let inputs = tasks.map { scheduleInput(for: $0, now: now) }
        let placements = store.placements().filter { !missedPlacementIDs.contains($0.id) }.map { PlacementInput(id: $0.id, taskID: $0.taskID, occurrenceID: $0.occurrenceID,
                                                                 start: $0.start, end: $0.end, isPinned: $0.isPinned) }
        var active: ActiveScheduleInput?
        if let session = activeSession, session.endedAt == nil, let task = store.block(id: session.taskID), !task.isCompleted,
           session.occurrenceID == task.occurrenceID {
            active = ActiveScheduleInput(taskID: task.id, occurrenceID: task.occurrenceID, start: session.startedAt,
                                         end: min(targetEnd(for: session, task: task, now: now), activeBoundary ?? .distantFuture))
        }
        publish(AdaptiveScheduler.plan(tasks: inputs, preferences: preferences, busyTimes: externalCalendars.busyTimes,
                                       placements: placements, active: active, now: now, calendar: calendar), now: now)
    }

    /// Starts recording `task` now, whatever the plan says: outside the list's
    /// hours or during busy time too. Other running work is paused first, so
    /// switching needs no separate confirmation.
    @discardableResult
    func start(task: Block, now: Date = .now) -> Bool {
        guard task.isTask, !task.isCompleted, store.list(id: task.listID)?.isEffectivelyArchived == false else { return false }
        if activeSession?.taskID == task.id, activeSession?.occurrenceID == task.occurrenceID { return true }
        isUpdating = true
        defer { isUpdating = false }
        if activeSession != nil {
            pause(reason: "Switched task", now: now)
            guard activeSession == nil else { return false }
        }
        // Retry interrupted recovery before adopting any old same-device record.
        // An old open row must never turn app absence into elapsed working time.
        for orphan in store.workSessions() where orphan.deviceID == deviceID && orphan.endedAt == nil && orphan.id != activeSessionID {
            guard store.pauseWorkSession(orphan, reason: "Recovered before starting", now: min(now, orphan.lastHeartbeatAt)) else {
                notice = store.persistenceError ?? "Previous work could not be recovered. Try again."
                return false
            }
        }
        guard let session = store.startWorkSession(for: task, deviceID: deviceID, now: now), store.persistenceError == nil else {
            notice = store.persistenceError ?? "Work could not be started."
            return false
        }
        activeSessionID = session.id
        let boundary = nextBoundary(for: task, at: now)
        let baseline = baselineEnd(for: session, task: task, now: now)
        estimatedWorkEnd = baseline
        approvedWorkEnd = plannedWorkEnd(for: session, task: task, estimate: baseline)
        resetExtensions()
        showedFinishHeadsUp = false
        overrunNudge = nil
        startNudge = nil
        activeBoundary = boundary
        awayLimit = nil
        lastObservedAt = now
        resumeTaskID = nil
        resumeOccurrenceID = nil
        pausedWork = nil
        persistResume()
        workCompletion = nil
        workSelection = WorkTaskReference(task)
        notice = nil
        replan(now: now)
        return true
    }

    func pause(reason: String = "Paused", now: Date = .now) {
        guard let session = activeSession else { return }
        let wasUpdating = isUpdating
        isUpdating = true
        // Where its block is now, kept in place once it's paused.
        let drawn = workingBlock(placed: store.calendarPlannedBlocks, now: now)
        // Records up to `now`: the click for Pause, or the last observed time
        // after a clock gap. Only time away from the Mac past where it stops
        // counting ends earlier.
        let endpoint = recordingEndpoint(for: session, at: now)
        guard store.pauseWorkSession(session, reason: reason, now: endpoint) else {
            notice = store.persistenceError ?? "Work could not be paused. Try again."
            isUpdating = wasUpdating
            return
        }
        if let task = store.block(id: session.taskID), task.occurrenceID == session.occurrenceID, !task.isCompleted {
            resumeTaskID = task.id
            resumeOccurrenceID = task.occurrenceID
            workSelection = WorkTaskReference(task)
            pausedWork = drawn.map { block in
                PausedWork(occurrenceID: block.occurrenceID, start: block.start, end: block.end,
                           grant: workExtension?.occurrenceID == block.occurrenceID ? workExtension : nil,
                           conflict: workConflict?.occurrenceID == block.occurrenceID ? workConflict : nil)
            }
            persistResume()
        }
        activeSessionID = nil
        activeBoundary = nil
        awayLimit = nil
        lastObservedAt = nil
        approvedWorkEnd = nil
        estimatedWorkEnd = nil
        resetExtensions()
        overrunNudge = nil
        isUpdating = wasUpdating
        replan(now: now)
    }

    func complete(task: Block, now: Date = .now) {
        guard validWorkTask(WorkTaskReference(task)) != nil else { return }
        let reference = WorkTaskReference(task)
        let title = task.displayTitle
        let minutes = trackedMinutes(for: task, now: now)
        store.toggleCompletion(task, now: now)
        guard store.persistenceError == nil else { notice = store.persistenceError; return }
        workCompletion = WorkCompletionSummary(task: reference, title: title, recordedMinutes: minutes,
            nextDate: task.occurrenceID != reference.occurrenceID ? task.dueDate : nil, undoID: store.completionUndo?.id)
        // Saving can synchronously replan and invalidate the old occurrence.
        // This intentional completion has its own confirmation, not a stale-target warning.
        workSelection = nil
        notice = nil
        resumeTaskID = nil
        resumeOccurrenceID = nil
        persistResume()
        tick(now: now, checkClockGap: false, materialChange: true)
    }

    /// Defers the task, stopping its work if it runs, and takes that work off
    /// the notch. Returns the work taken off, whose paused state is kept, so
    /// `restoreResume` offers it again as it was.
    @discardableResult
    func deferTask(task: Block, to day: Date) -> WorkTaskReference? {
        if activeSession?.taskID == task.id { pause(reason: "Deferred") }
        let resume = resumableTask.flatMap { $0.id == task.id ? WorkTaskReference($0) : nil }
        store.deferTask(task, to: day)
        if resumeTaskID == task.id {
            resumeTaskID = nil
            resumeOccurrenceID = nil
            persistResume()
        }
        replan()
        return resume
    }

    func dismissResume() {
        resumeTaskID = nil
        resumeOccurrenceID = nil
        pausedWork = nil
        persistResume()
        workSelection = nil
        notice = nil
        refreshVisibleBlocks(now: .now)
    }

    /// Offers paused work again after a caller dismissed it, as long as the
    /// occurrence can still be worked and nothing else has taken its place.
    func restoreResume(_ reference: WorkTaskReference) {
        guard activeSession == nil, resumeTaskID == nil, validWorkTask(reference) != nil else { return }
        resumeTaskID = reference.taskID
        resumeOccurrenceID = reference.occurrenceID
        persistResume()
        workSelection = reference
        refreshVisibleBlocks(now: .now)
    }

    func handleMacUnavailable(reason: String, now: Date = .now) {
        guard let session = activeSession, let task = store.block(id: session.taskID) else { return }
        // Work that tracks away keeps recording while you're gone, up to the
        // next fixed event, another task's pinned time or the end of the
        // list's hours. Away outside them, it pauses like any other.
        if task.tracksAwayFromMac, let limit = awayLimit ?? nextBoundary(for: task, at: now, stopsAtPins: true) {
            awayLimit = limit
            return
        }
        resumeTaskID = task.id
        pause(reason: reason, now: now)
        if activeSession == nil { notice = "Work paused because \(reason.lowercased()). Resume when ready." }
    }

    func handleMacReturn(now: Date = .now) {
        tick(now: now, checkClockGap: true)
        // Back at the Mac, work records through fixed events again.
        awayLimit = nil
        refreshCalendars(now: now)
        onMacReturn?()
    }

    /// Timer ticks retain the last promised placements. Only a real task/calendar
    /// change, an extension of running work, or one missed task changes the schedule.
    func tick(now: Date = .now, checkClockGap: Bool = true, materialChange: Bool = false) {
        guard hasStarted, !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }
        validateWorkReferences()
        if now.timeIntervalSince(lastCalendarRefresh) >= 300 { refreshCalendars(now: now) }
        let materialChange = materialChange || pendingCalendarChange
        pendingCalendarChange = false
        var needsPlan = materialChange || plan.start != calendar.startOfDay(for: now)
        if materialChange {
            refreshActiveEstimate(now: now)
            // The blocks saved around each extension no longer match the plan;
            // Undo and Redo plan afresh instead.
            for index in extensionSteps.indices { extensionSteps[index].saved = nil }
            for index in undoneExtensionSteps.indices { undoneExtensionSteps[index].saved = nil }
        }
        if activeSessionID != nil, activeSession == nil {
            clearActiveState()
            needsPlan = true
        }
        if let session = activeSession {
            if session.endedAt != nil || store.block(id: session.taskID)?.occurrenceID != session.occurrenceID || store.block(id: session.taskID)?.isCompleted != false {
                clearActiveState()
                needsPlan = true
            } else if let task = store.block(id: session.taskID) {
                let gap = checkClockGap ? lastObservedAt.flatMap { now.timeIntervalSince($0) > 75 ? $0 : nil } : nil
                // A gap in the timer is time away too, for work that tracks away.
                let awayEnd = awayLimit ?? (task.tracksAwayFromMac ? gap.flatMap { nextBoundary(for: task, at: $0, stopsAtPins: true) } : nil)
                if store.list(id: task.listID)?.isEffectivelyArchived != false {
                    pause(reason: "List unavailable", now: now)
                } else if let last = gap, awayEnd == nil {
                    resumeTaskID = task.id
                    pause(reason: "Mac was unavailable", now: last)
                    if activeSession == nil { notice = "Work paused at the last observed activity. Resume when ready." }
                } else if let awayEnd, now > awayEnd {
                    // Away from the Mac, work stops at the next fixed event or
                    // the end of the list's hours, and records up to there.
                    awayLimit = awayEnd
                    resumeTaskID = task.id
                    pause(reason: "Mac was unavailable", now: now)
                    if activeSession == nil { notice = "Work paused at fixed busy time or the end of available hours while you were away. Resume when ready." }
                } else {
                    // A real edit may remove a boundary that is still ahead;
                    // ordinary clock updates never move one.
                    if materialChange, let known = activeBoundary, known > now {
                        activeBoundary = nextBoundary(for: task, at: now)
                    }
                    lastObservedAt = now
                    if now.timeIntervalSince(session.lastHeartbeatAt) >= 60 { store.heartbeatWorkSession(session, now: now) }
                    updateFinishNudge(task: task, now: now)
                    extendActiveWork(task: task, now: now)
                }
            }
        }
        if needsPlan { replan(now: now) }
        else { updateStartNudge(now: now) }
        moveMissedWork(now: now)
    }

    func dismissRescheduleSummary() { rescheduleSummary = nil }

    /// Keeps recording past the slot, as the design's overrun does. A minute
    /// before the block ends it grows to the next quarter hour plus 15 minutes,
    /// never past the next meeting or break: the slot it works through grows
    /// with it, and the tasks placed after it today move out of its way. When
    /// the meeting or break leaves no room, work carries on and the conflict is
    /// marked. The end of the list's hours only stops the block growing.
    /// Nothing grows while the Mac is away.
    private func extendActiveWork(task: Block, now: Date) {
        guard !extensionsHeld, awayLimit == nil, workConflict?.occurrenceID != task.occurrenceID,
              let session = activeSession, let boundary = activeBoundary, let approved = approvedWorkEnd else { return }
        let end = min(approved, boundary)
        guard now >= end.addingTimeInterval(-60) else { return }
        let quarter = TimeInterval(15 * 60)
        let stop = nextStop(for: task, at: end)
        var proposed = Date(timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate / quarter).rounded(.up) * quarter + quarter)
        if let stop, proposed > stop.start { proposed = stop.start }
        guard proposed > end else {
            if let stop, let kind = stop.kind {
                workConflict = CalendarWorkConflict(taskID: task.id, occurrenceID: task.occurrenceID,
                                                    kind: kind, title: stop.title, start: stop.start)
            }
            return
        }
        let previousPlan = plan
        let previousGrant = workExtension
        let previousSummary = rescheduleSummary
        let slot = workingSlot(for: session, until: end)
        let moved = reflow(from: min(slot?.start ?? session.startedAt, session.startedAt), to: proposed,
                           working: session.occurrenceID, now: now)
        let grown = slot.flatMap { slot in
            slot.end < proposed ? PlacementMove(id: slot.id, taskID: task.id, from: DateInterval(start: slot.start, end: slot.end),
                                                to: DateInterval(start: slot.start, end: proposed)) : nil
        }
        let moves = (grown.map { [$0] } ?? []) + moved
        move(moves)
        approvedWorkEnd = proposed
        overrunNudge = nil
        replan(now: now)
        // Only the placements it moved, which the calendar draws, as the design reports.
        var placed: [UUID] = []
        for move in moved where !placed.contains(move.taskID) { placed.append(move.taskID) }
        report(placed, message: "Made room for continued work.")
        let earlier = previousGrant.flatMap { $0.occurrenceID == task.occurrenceID ? $0.minutes : nil } ?? 0
        let grant = CalendarWorkExtension(taskID: task.id, occurrenceID: task.occurrenceID, end: proposed,
                                          minutes: earlier + Int((proposed.timeIntervalSince(end) / 60).rounded(.up)),
                                          movedTaskIDs: placed)
        workExtension = grant
        let saved = WorkExtensionStep.SavedPlans(previous: previousPlan, next: plan,
                                                 previousSummary: previousSummary, summary: rescheduleSummary)
        extensionSteps.append(WorkExtensionStep(sessionID: session.id, grant: grant, previousGrant: previousGrant,
                                                previousEnd: approved, moves: moves, saved: saved))
        undoneExtensionSteps = []
    }

    /// Where the running work growing to `end` moves the placements after its
    /// start today, as the design reflows the day: in time order, each one the
    /// work or a task moved before it now runs over goes to the next free
    /// quarter hour in its list's hours, clear of meetings and the other
    /// blocks. One with no room left today stays where it is.
    private func reflow(from start: Date, to end: Date, working occurrenceID: UUID, now: Date) -> [PlacementMove] {
        let day = calendar.startOfDay(for: now)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: day) else { return [] }
        let today = livePlacements().filter { $0.start >= day && $0.start < dayEnd }
        let pending = today.filter { $0.occurrenceID != occurrenceID && $0.start >= start }
        var spans = Dictionary(today.map { ($0.id, DateInterval(start: $0.start, end: $0.end)) }, uniquingKeysWith: { first, _ in first })
        let fixed = externalCalendars.busyTimes.filter { $0.end > day && $0.start < dayEnd }.map { DateInterval(start: $0.start, end: $0.end) }
            + visibleBlocks.filter { $0.isCompleted && $0.end > day && $0.start < dayEnd }.map { DateInterval(start: $0.start, end: $0.end) }
            + [DateInterval(start: start, end: end)]
        let quarter = TimeInterval(15 * 60)
        var moves: [PlacementMove] = []
        var cursor = end
        for (index, placement) in pending.enumerated() {
            guard let span = spans[placement.id] else { continue }
            if span.start >= cursor {
                cursor = max(cursor, span.end)
                continue
            }
            guard let owner = store.block(id: placement.taskID) else { continue }
            // Around the tasks already settled, not the ones still to come.
            let later = Set(pending[(index + 1)...].map(\.id))
            let busy = fixed + spans.filter { $0.key != placement.id && !later.contains($0.key) }.map(\.value)
            let hours = availability(for: owner, on: now)
            var candidate = Date(timeIntervalSinceReferenceDate: (cursor.timeIntervalSinceReferenceDate / quarter).rounded(.up) * quarter)
            while candidate.addingTimeInterval(span.duration) <= dayEnd {
                let target = DateInterval(start: candidate, duration: span.duration)
                if hours.contains(where: { $0.start <= target.start && $0.end >= target.end }),
                   !busy.contains(where: { $0.start < target.end && target.start < $0.end }) {
                    moves.append(PlacementMove(id: placement.id, taskID: placement.taskID, from: span, to: target))
                    spans[placement.id] = target
                    cursor = target.end
                    break
                }
                candidate = candidate.addingTimeInterval(quarter)
            }
        }
        return moves
    }

    /// Puts placements where `moves` take them, or with `back` where they came
    /// from, in one save. One changed since is left alone. False when any was.
    @discardableResult
    private func move(_ moves: [PlacementMove], back: Bool = false) -> Bool {
        guard !moves.isEmpty else { return true }
        let placements = Dictionary(store.placements().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var complete = true
        let wasUpdating = isUpdating
        // The save isn't another change for the plan to follow; the caller plans.
        isUpdating = true
        for move in moves {
            let (from, to) = back ? (move.to, move.from) : (move.from, move.to)
            guard let placement = placements[move.id], placement.start == from.start, placement.end == from.end else {
                complete = false
                continue
            }
            placement.start = to.start
            placement.end = to.end
        }
        store.save()
        isUpdating = wasUpdating
        return complete
    }

    /// Whether Undo can still take `grant` back: the work it was given to is
    /// still running and nothing has since replaced it, or, once that work
    /// has stopped, a placement it moved is still where it left it.
    func canUndoExtension(_ grant: CalendarWorkExtension) -> Bool {
        extensionSteps.contains { $0.grant == grant && $0.sessionID == activeSessionID }
            || settledExtensionSteps.contains { $0.grant == grant && canMove($0.moves, back: true) }
    }

    /// Whether Redo can still give back `grant`, which Undo took.
    func canRedoExtension(_ grant: CalendarWorkExtension) -> Bool {
        undoneExtensionSteps.contains { $0.grant == grant && $0.sessionID == activeSessionID }
            || undoneSettledSteps.contains { $0.grant == grant && canMove($0.moves, back: false) }
    }

    /// Takes back the running work's latest extension: its block ends where it
    /// did and the tasks moved for it return to their slots, or, once another
    /// change has replaced those, are planned afresh around it. Work keeps
    /// recording, but the block isn't grown again until Redo or the next start.
    /// Once the work has stopped, only the slot and the tasks go back.
    @discardableResult
    func undoExtension(_ grant: CalendarWorkExtension, now: Date = .now) -> Bool {
        guard let step = extensionSteps.last, step.grant == grant, workExtension == grant,
              activeSession?.id == step.sessionID else { return undoSettledExtension(grant, now: now) }
        extensionSteps.removeLast()
        undoneExtensionSteps.append(step)
        approvedWorkEnd = step.previousEnd
        workExtension = step.previousGrant
        workConflict = nil
        extensionsHeld = true
        // A placement moved again since stays where it is now.
        let restored = move(step.moves, back: true)
        if restored, let saved = step.saved, showsBlocks(of: saved.next) {
            rescheduleSummary = saved.previousSummary
            publish(saved.previous, now: now)
        } else {
            undoneExtensionSteps[undoneExtensionSteps.count - 1].saved = nil
            replan(now: now)
        }
        return true
    }

    /// Gives back an extension Undo took, with the same blocks while nothing
    /// else has changed them.
    @discardableResult
    func redoExtension(_ grant: CalendarWorkExtension, now: Date = .now) -> Bool {
        guard let step = undoneExtensionSteps.last, step.grant == grant, workExtension == step.previousGrant,
              activeSession?.id == step.sessionID else { return redoSettledExtension(grant, now: now) }
        undoneExtensionSteps.removeLast()
        extensionSteps.append(step)
        approvedWorkEnd = grant.end
        workExtension = grant
        extensionsHeld = false
        let applied = move(step.moves)
        if applied, let saved = step.saved, showsBlocks(of: saved.previous) {
            rescheduleSummary = saved.summary
            publish(saved.next, now: now)
        } else {
            extensionSteps[extensionSteps.count - 1].saved = nil
            replan(now: now)
        }
        return true
    }

    /// Whether the plan still has exactly the blocks of `saved`: no move, pin
    /// or missed start has changed them since.
    private func showsBlocks(of saved: CalendarPlan) -> Bool {
        plan.blocks.count == saved.blocks.count && zip(plan.blocks, saved.blocks).allSatisfy {
            $0.id == $1.id && $0.start == $1.start && $0.end == $1.end
        }
    }

    /// Undo of an extension whose work has stopped: the slot it grew and the
    /// tasks it moved go back where they were, each one that hasn't changed
    /// since. Work on the task running again ends where its slot now does,
    /// and isn't grown again until Redo or the next start.
    private func undoSettledExtension(_ grant: CalendarWorkExtension, now: Date) -> Bool {
        guard let index = settledExtensionSteps.lastIndex(where: { $0.grant == grant }),
              canMove(settledExtensionSteps[index].moves, back: true) else { return false }
        let step = settledExtensionSteps.remove(at: index)
        undoneSettledSteps.append(step)
        move(step.moves, back: true)
        followSettledMove(of: step, undo: true)
        replan(now: now)
        return true
    }

    /// Redo of an extension whose work has stopped: its moves again.
    private func redoSettledExtension(_ grant: CalendarWorkExtension, now: Date) -> Bool {
        guard let index = undoneSettledSteps.lastIndex(where: { $0.grant == grant }),
              canMove(undoneSettledSteps[index].moves, back: false) else { return false }
        let step = undoneSettledSteps.remove(at: index)
        settledExtensionSteps.append(step)
        move(step.moves)
        followSettledMove(of: step, undo: false)
        replan(now: now)
        return true
    }

    /// Once Undo or Redo has moved the stopped work's slot: paused, its block
    /// and the notch read extended, by the latest extension left in place,
    /// only while there is one, and with Undo no longer run into anything,
    /// as the design's snapshot has it; running again, it ends where its
    /// slot now ends.
    private func followSettledMove(of step: WorkExtensionStep, undo: Bool) {
        let occurrenceID = step.grant.occurrenceID
        if pausedWork?.occurrenceID == occurrenceID {
            pausedWork?.grant = settledExtensionSteps.last { $0.grant.occurrenceID == occurrenceID }?.grant
            if undo { pausedWork?.conflict = nil }
        }
        guard let session = activeSession, session.occurrenceID == occurrenceID,
              let task = store.block(id: session.taskID), let estimate = estimatedWorkEnd else { return }
        approvedWorkEnd = plannedWorkEnd(for: session, task: task, estimate: estimate)
        overrunNudge = nil
        // Redo lets it grow again, unless the running work has an Undo of its own to redo.
        extensionsHeld = undo || undoneExtensionSteps.contains { $0.sessionID == activeSessionID }
    }

    /// Whether any placement `moves` took is still where they left it (or,
    /// for Redo, where they took it from), for Undo or Redo to move.
    private func canMove(_ moves: [PlacementMove], back: Bool) -> Bool {
        guard !moves.isEmpty else { return false }
        let placements = Dictionary(store.placements().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return moves.contains { move in
            let at = back ? move.to : move.from
            return placements[move.id].map { $0.start == at.start && $0.end == at.end } == true
        }
    }

    /// Clears what the running work's extensions and conflict left behind.
    /// Their moves stay undoable once the work stops.
    private func resetExtensions() {
        workExtension = nil
        workConflict = nil
        // Only the placements are left to put back, not the plan around them.
        func settled(_ steps: [WorkExtensionStep]) -> [WorkExtensionStep] {
            steps.filter { !$0.moves.isEmpty }.map { step in
                var step = step
                step.saved = nil
                return step
            }
        }
        settledExtensionSteps += settled(extensionSteps)
        undoneSettledSteps += settled(undoneExtensionSteps)
        extensionSteps = []
        undoneExtensionSteps = []
        extensionsHeld = false
    }

    /// A quiet heads-up two minutes before the block runs out, for the
    /// background notification. The block then grows by itself.
    private func updateFinishNudge(task: Block, now: Date) {
        guard !showedFinishHeadsUp, workExtension == nil, let session = activeSession, let end = approvedWorkEnd,
              let boundary = activeBoundary, end < boundary, now >= end.addingTimeInterval(-2 * 60) else { return }
        showedFinishHeadsUp = true
        let proposed = min(end.addingTimeInterval(15 * 60), boundary)
        let start = min(workingSlot(for: session, until: end)?.start ?? session.startedAt, session.startedAt)
        let moved = Set(reflow(from: start, to: proposed, working: task.occurrenceID, now: now).map(\.taskID))
        overrunNudge = CalendarOverrunNudge(taskID: task.id, occurrenceID: task.occurrenceID,
            estimatedEnd: end, proposedEnd: proposed, movedTaskCount: moved.count)
    }

    private func targetEnd(for session: WorkSession, task: Block, now: Date) -> Date {
        approvedWorkEnd ?? baselineEnd(for: session, task: task, now: now)
    }

    private func baselineEnd(for session: WorkSession, task: Block, now: Date) -> Date {
        let prior = store.workSessions(taskID: task.id).filter { $0.id != session.id && $0.occurrenceID == task.occurrenceID }
            .reduce(0) { $0 + recordedMinutes(for: $1, now: now) }
        let remaining = estimatedMinutes(for: task) - prior
        return session.startedAt.addingTimeInterval((remaining > 0 ? remaining : 15) * 60)
    }

    /// Where the running work's block ends until it overruns: the end of the
    /// slot it works through, which keeps its planned time as in the design,
    /// or else where its estimate runs out, short of the next task placed
    /// after it starts.
    private func plannedWorkEnd(for session: WorkSession, task: Block, estimate: Date) -> Date {
        if let slot = workingSlot(for: session, until: estimate) { return slot.end }
        let next = otherPlacements(than: task).map(\.start).filter { $0 > session.startedAt }.min()
        return min(estimate, next ?? estimate)
    }

    /// The occurrence's placement the running work takes on the calendar: the
    /// first one it's in or reaches before `end`.
    private func workingSlot(for session: WorkSession, until end: Date) -> SchedulePlacement? {
        store.placements(taskID: session.taskID).first {
            $0.occurrenceID == session.occurrenceID && $0.end > $0.start && $0.start < end && $0.end > session.startedAt
        }
    }

    private func refreshActiveEstimate(now: Date) {
        guard let session = activeSession, let task = store.block(id: session.taskID),
              session.endedAt == nil, task.occurrenceID == session.occurrenceID else { return }
        let baseline = baselineEnd(for: session, task: task, now: now)
        guard baseline != estimatedWorkEnd else { return }
        estimatedWorkEnd = baseline
        // Working through a slot, the slot sets where the block ends, not the estimate.
        guard workingSlot(for: session, until: max(baseline, approvedWorkEnd ?? baseline)) == nil else { return }
        approvedWorkEnd = max(now, plannedWorkEnd(for: session, task: task, estimate: baseline))
        showedFinishHeadsUp = false
        overrunNudge = nil
        // The new estimate replaces any time given past the old one.
        resetExtensions()
    }

    private func clearActiveState() {
        activeSessionID = nil
        activeBoundary = nil
        awayLimit = nil
        lastObservedAt = nil
        approvedWorkEnd = nil
        estimatedWorkEnd = nil
        resetExtensions()
        overrunNudge = nil
    }

    private func scheduleInput(for task: Block, now: Date) -> ScheduleTask {
        let due = task.dueDate.map { due in task.includesTime ? due : calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: due))! }
        let selected = task.selectedForDay.map { calendar.startOfDay(for: $0) <= calendar.startOfDay(for: now) } ?? false
        let category = AvailabilityCategory(rawValue: store.list(id: task.listID)?.availabilityCategoryRaw ?? "work") ?? .work
        return ScheduleTask(taskID: task.id, occurrenceID: task.occurrenceID, title: task.displayTitle,
            category: category, remainingMinutes: remainingMinutes(for: task, now: now), dueDate: due,
            selectedForToday: selected, earliestStart: task.deferredUntil,
            priority: task.priorityRaw, keepTogether: task.keepsSessionsTogether)
    }

    private func publish(_ next: CalendarPlan, now: Date) {
        var next = next
        let missed = Set(store.placements().filter { missedPlacementIDs.contains($0.id) }.map(\.occurrenceID))
        for index in next.assessments.indices where missed.contains(next.assessments[index].occurrenceID) {
            let conflict = AdaptiveScheduler.missedPlacementConflict
            if !next.assessments[index].conflicts.contains(conflict) { next.assessments[index].conflicts.append(conflict) }
        }
        plan = next
        storeSchedulingSignature = schedulingSignature()
        refreshVisibleBlocks(now: now)
        if let nudge = overrunNudge, store.block(id: nudge.taskID)?.occurrenceID != nudge.occurrenceID || store.block(id: nudge.taskID)?.isCompleted != false {
            overrunNudge = nil
        }
        updateStartNudge(now: now)
    }

    private func refreshVisibleBlocks(now: Date) {
        completedBlocks = store.completedCalendarBlocks()
        var blocks = store.placements().compactMap { placement -> PlannedBlock? in
            guard placement.end > placement.start, let task = store.block(id: placement.taskID),
                  task.occurrenceID == placement.occurrenceID, validWorkTask(WorkTaskReference(task)) != nil else { return nil }
            return PlannedBlock(id: "\(placement.occurrenceID.uuidString)-\(placement.id.uuidString)", taskID: task.id,
                                occurrenceID: task.occurrenceID, start: placement.start, end: placement.end,
                                isPinned: placement.isPinned, placementID: placement.id,
                                conflicts: plan.blocks.first { $0.placementID == placement.id }?.conflicts ?? [])
        }
        // A completion keeps the slots it was shown in, not the plan's flexible ones.
        store.calendarPlannedBlocks = blocks
        if let working = workingBlock(placed: blocks, now: now) {
            blocks.removeAll { $0.id == working.id }
            blocks.append(working)
        }
        // Paused work keeps its block where it was, drawn as the work while it
        // can resume: its slot, or where it ran when it had none.
        var paused: String?
        if activeSession == nil, let task = resumableTask, let span = pausedSpan(of: task) {
            if let slot = blocks.first(where: { $0.occurrenceID == task.occurrenceID && $0.start < span.end && $0.end > span.start }) {
                paused = slot.id
            } else if span.end > span.start {
                let block = PlannedBlock(id: "\(task.occurrenceID.uuidString)-active", taskID: task.id, occurrenceID: task.occurrenceID,
                                         start: span.start, end: span.end, isPinned: false, placementID: nil, conflicts: [])
                blocks.append(block)
                paused = block.id
            }
        }
        pausedBlockID = paused
        let recurring = Set(store.completionRecords().filter(\.wasRecurring).map(\.id))
        blocks += completedBlocks.filter { block in
            // A tick with neither a slot nor recorded work leaves nothing to draw.
            guard block.isTimeTracked || block.end > block.start,
                  let task = store.block(id: block.taskID), task.trashID == nil else { return false }
            // Reopening a task takes its done block away; a repeat rolling on doesn't.
            return block.completionID.map(recurring.contains) == true
                || (task.isCompleted && task.occurrenceID == block.occurrenceID)
        }
        visibleBlocks = blocks.sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
    }

    /// The running work, from the start of the slot it's working through (or
    /// from when it started, if that's earlier or it has none) to where the
    /// plan lets it run. It takes that slot's place on the calendar. Past what
    /// it has been given, the block holds its end, as the design's does at a
    /// meeting it runs into; only work outside its hours, with none to give,
    /// is drawn up to now.
    private func workingBlock(placed: [PlannedBlock], now: Date) -> PlannedBlock? {
        guard let session = activeSession, session.endedAt == nil, let task = store.block(id: session.taskID),
              task.occurrenceID == session.occurrenceID, !task.isCompleted else { return nil }
        let target = targetEnd(for: session, task: task, now: now)
        let end = plan.blocks.first { $0.isActive && $0.occurrenceID == session.occurrenceID }?.end
            ?? activeBoundary.map { min(target, $0) } ?? max(now, target)
        let slot = placed.first { $0.occurrenceID == session.occurrenceID && $0.start < end && $0.end > session.startedAt }
        let start = min(slot?.start ?? session.startedAt, session.startedAt)
        guard end > start else { return nil }
        return PlannedBlock(id: slot?.id ?? "\(session.occurrenceID.uuidString)-active", taskID: task.id,
                            occurrenceID: session.occurrenceID, start: start, end: end, isPinned: slot?.isPinned ?? false,
                            placementID: slot?.placementID, conflicts: [], isActive: true)
    }

    /// How paused work's block reads while it can resume, as it did when the
    /// work paused: what it had run into, or whether it had been extended.
    var pausedWorkNote: (extended: Bool, conflict: CalendarWorkConflict?)? {
        guard pausedBlockID != nil, let pausedWork, pausedWork.occurrenceID == resumeOccurrenceID else { return nil }
        return (pausedWork.grant != nil, pausedWork.conflict)
    }

    /// What the work in hand ran into, for the notch: running, or paused, as
    /// it was when it paused, as its block reads.
    var displayedWorkConflict: CalendarWorkConflict? {
        activeSession != nil ? workConflict : pausedWorkNote?.conflict
    }

    /// The extra time the work in hand has been given, for the notch: running,
    /// or paused, as it was when it paused.
    var displayedWorkExtension: CalendarWorkExtension? {
        guard activeSession == nil else { return workExtension }
        return pausedWorkNote == nil ? nil : pausedWork?.grant
    }

    /// Where paused work's block was: as it paused, or after a relaunch,
    /// where its last session ran.
    private func pausedSpan(of task: Block) -> (start: Date, end: Date)? {
        if let pausedWork, pausedWork.occurrenceID == task.occurrenceID { return (pausedWork.start, pausedWork.end) }
        guard let session = store.workSessions(taskID: task.id).first(where: { $0.occurrenceID == task.occurrenceID && $0.endedAt != nil }),
              let end = session.endedAt else { return nil }
        return (session.startedAt, end)
    }

    /// The timer, Pause, checkbox completion and displayed elapsed time share
    /// this read-only endpoint. Work running on this Mac records up to now, past
    /// its estimate and through fixed events alike, and while the Mac is away up
    /// to `awayLimit`; any other open record only up to its last heartbeat.
    private func recordingEndpoint(for session: WorkSession, at now: Date) -> Date {
        guard session.id == activeSessionID, session.deviceID == deviceID else { return min(now, session.lastHeartbeatAt) }
        return min(now, awayLimit ?? now)
    }

    /// Offers Start for a slot the calendar draws while it runs, never for the
    /// plan's flexible blocks, which have none. None comes while there's work
    /// in hand, running or paused, as the design's "Planned now" hides then.
    private func updateStartNudge(now: Date) {
        guard activeSession == nil, resumableTask == nil else { startNudge = nil; return }
        let next = visibleBlocks.first { block in
            block.placementID != nil && !block.isActive && !block.isCompleted &&
                block.start <= now && now < block.end &&
                (quietUntil[block.occurrenceID.uuidString] ?? 0) <= now.timeIntervalSince1970 &&
                store.block(id: block.taskID)?.occurrenceID == block.occurrenceID &&
                store.block(id: block.taskID)?.isCompleted == false
        }
        startNudge = next.map {
            CalendarStartNudge(taskID: $0.taskID, occurrenceID: $0.occurrenceID,
                scheduledStart: $0.start, graceEndsAt: $0.start.addingTimeInterval(5 * 60))
        }
    }

    private func moveMissedWork(now: Date) {
        // Read the established plan before moving anything. A fresh plan starting
        // at `now` would hide missed starts forever and make the whole day drift.
        let slotEnds = Dictionary(store.placements().map { ($0.id, $0.end) }, uniquingKeysWith: max)
        // Blocks that running work has run over stay put until it stops.
        let workingSince = activeSession?.startedAt ?? .distantFuture
        let missed = plan.blocks.filter { block in
            !block.isActive && block.occurrenceID != activeSession?.occurrenceID &&
                block.start.addingTimeInterval(5 * 60) <= now && block.start < workingSince &&
                // A placement keeps its whole saved slot, even when less work is
                // left than it holds; it's missed only once that slot is over.
                (block.placementID.map { (slotEnds[$0] ?? block.end) <= now } ?? true) &&
                block.occurrenceID != overrunNudge?.occurrenceID
        }
        var handled = Set<UUID>()
        for block in missed where handled.insert(block.occurrenceID).inserted {
            guard let task = store.block(id: block.taskID), task.occurrenceID == block.occurrenceID, !task.isCompleted else { continue }
            if block.isPinned, let placementID = block.placementID { missedPlacementIDs.insert(placementID) }
            rescheduleOnly(task: task, now: now)
        }
        updateStartNudge(now: now)
    }

    private func rescheduleOnly(task: Block, now: Date) {
        let anchors = plan.blocks.filter { $0.occurrenceID != task.occurrenceID }
        let busy = externalCalendars.busyTimes + anchors.filter { $0.end > now }.map {
            FixedBusyTime(id: "planned-" + $0.id, title: "other scheduled work", start: $0.start, end: $0.end)
        }
        // A missed preference is no longer a useful suggestion. Future pins stay
        // fixed; a missed pin is retained as an assessment conflict, not tracking.
        let placements = store.placements(taskID: task.id).filter { $0.occurrenceID == task.occurrenceID && $0.isPinned && $0.start > now }.map {
            PlacementInput(id: $0.id, taskID: $0.taskID, occurrenceID: $0.occurrenceID, start: $0.start, end: $0.end, isPinned: true)
        }
        let input = scheduleInput(for: task, now: now)
        var replacement = AdaptiveScheduler.plan(tasks: [input], preferences: preferences, busyTimes: busy,
            placements: placements, now: now, calendar: calendar)
        if store.placements(taskID: task.id).contains(where: { $0.occurrenceID == task.occurrenceID && $0.isPinned && $0.start <= now }) {
            for index in replacement.assessments.indices {
                replacement.assessments[index].conflicts.append(AdaptiveScheduler.missedPlacementConflict)
                replacement.assessments[index].reason += AdaptiveScheduler.missedPlacementReason
            }
        }
        let blocks = (anchors + replacement.blocks).sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
        let assessments = plan.assessments.filter { $0.occurrenceID != task.occurrenceID } + replacement.assessments
        publish(CalendarPlan(start: plan.start, end: plan.end, blocks: blocks, assessments: assessments), now: now)
    }

    /// Tells the Work panel which tasks just moved, and why.
    private func report(_ moved: [UUID], message: String) {
        guard !moved.isEmpty else { return }
        rescheduleSummary = CalendarRescheduleSummary(message: "\(moved.count) \(moved.count == 1 ? "task" : "tasks") rescheduled.",
            movedTaskCount: moved.count, taskIDs: moved, reason: message)
    }

    /// Store saves also happen for notes, titles and editor selections. Those
    /// changes must not move an otherwise unchanged schedule toward the clock.
    private func schedulingSignature() -> [String] {
        func timestamp(_ date: Date?) -> String { date.map { String($0.timeIntervalSinceReferenceDate) } ?? "-" }
        let tasks = (try? store.context.fetch(FetchDescriptor<Block>(predicate: #Predicate { $0.trashID == nil && $0.kindRaw == "task" }))) ?? []
        var parts = tasks.map {
            [$0.id.uuidString, $0.occurrenceID.uuidString, $0.listID?.uuidString ?? "-", String($0.isCompleted),
             String($0.schedulingEstimateMinutes), timestamp($0.dueDate), String($0.includesTime), timestamp($0.selectedForDay),
             timestamp($0.deferredUntil), String($0.priorityRaw), String($0.keepsSessionsTogether), String($0.tracksAwayFromMac)].joined(separator: "|")
        }
        parts += store.allLists(includeArchived: true).map {
            "list|\($0.id)|\($0.availabilityCategoryRaw)|\($0.isEffectivelyArchived)|\($0.parentListID?.uuidString ?? "-")|\($0.mergedIntoID?.uuidString ?? "-")"
        }
        parts += store.placements().map { "placement|\($0.id)|\($0.taskID)|\($0.occurrenceID)|\(timestamp($0.start))|\(timestamp($0.end))|\($0.isPinned)" }
        let liveOccurrences = Set(tasks.filter { !$0.isCompleted }.map(\.occurrenceID))
        parts += store.workSessions().filter { liveOccurrences.contains($0.occurrenceID) }.map {
            "session|\($0.id)|\($0.taskID)|\($0.occurrenceID)|\(timestamp($0.startedAt))|\(timestamp($0.endedAt))|\($0.correctedMinutes.map(String.init(describing:)) ?? "-")|\($0.id == activeSessionID ? "active" : timestamp($0.lastHeartbeatAt))"
        }
        return parts.sorted()
    }

    private func busyTimesChanged() -> Bool {
        let signature = externalCalendars.busyTimes.map { "\($0.id)|\($0.start.timeIntervalSinceReferenceDate)|\($0.end.timeIntervalSinceReferenceDate)" }.sorted()
        guard signature != busySignature else { return false }
        busySignature = signature
        return true
    }

    // MARK: - Work companion

    func validWorkTask(_ reference: WorkTaskReference) -> Block? {
        guard let task = store.block(id: reference.taskID), task.isTask, task.trashID == nil,
              !task.isCompleted, task.occurrenceID == reference.occurrenceID,
              store.list(id: task.listID)?.isEffectivelyArchived == false else { return nil }
        return task
    }

    var resumableTask: Block? {
        guard let id = resumeTaskID, let task = store.block(id: id), task.occurrenceID == resumeOccurrenceID else { return nil }
        return validWorkTask(WorkTaskReference(task))
    }

    var selectedWorkTask: Block? { workSelection.flatMap(validWorkTask) }

    func suggestedWork(now: Date = .now) -> Block? {
        for block in plan.blocks where !block.isActive && block.end > now {
            guard (quietUntil[block.occurrenceID.uuidString] ?? 0) <= now.timeIntervalSince1970,
                  let task = store.block(id: block.taskID), task.occurrenceID == block.occurrenceID,
                  validWorkTask(WorkTaskReference(task)) != nil else { continue }
            return task
        }
        return nil
    }

    func showWork(for task: Block? = nil, now: Date = .now) {
        if let task { workSelection = WorkTaskReference(task); workCompletion = nil }
        else if let session = activeSession, let task = store.block(id: session.taskID) { workSelection = WorkTaskReference(task) }
        else if let task = resumableTask { workSelection = WorkTaskReference(task) }
        else if workCompletion == nil { workSelection = suggestedWork(now: now).map(WorkTaskReference.init) }
        isWorkPanelPresented = true
    }

    func selectWork(_ reference: WorkTaskReference) {
        guard validWorkTask(reference) != nil else { return }
        workSelection = reference
        workCompletion = nil
        notice = nil
    }

    /// Starts `reference` from the Work panel, a menu or a notification. Like
    /// Start working anywhere, it replaces other running work straight away.
    @discardableResult
    func requestWork(_ reference: WorkTaskReference, now: Date = .now) -> Bool {
        guard let task = validWorkTask(reference) else {
            notice = "This task occurrence is no longer available. Choose another task."
            isWorkPanelPresented = true
            return false
        }
        selectWork(reference)
        isWorkPanelPresented = true
        return start(task: task, now: now)
    }

    func stopWorking(now: Date = .now) {
        pause(reason: "Stopped working", now: now)
        if activeSession == nil { notice = nil }
    }

    func quietWork(_ reference: WorkTaskReference, now: Date = .now) {
        guard validWorkTask(reference) != nil else { return }
        quietUntil[reference.occurrenceID.uuidString] = now.addingTimeInterval(15 * 60).timeIntervalSince1970
        defaults.set(quietUntil, forKey: "work.quietUntil")
        updateStartNudge(now: now)
        onNudgesChanged?()
    }

    func undoQuietWork(_ reference: WorkTaskReference, now: Date = .now) {
        quietUntil.removeValue(forKey: reference.occurrenceID.uuidString)
        defaults.set(quietUntil, forKey: "work.quietUntil")
        updateStartNudge(now: now)
        onNudgesChanged?()
    }

    /// Whether `now` falls in the list's hours and clear of fixed busy time.
    /// Work starts either way; outside them it only has no block to grow.
    func isWithinAvailability(_ reference: WorkTaskReference, now: Date = .now) -> Bool {
        guard let task = validWorkTask(reference), let end = nextBoundary(for: task, at: now) else { return false }
        return end > now
    }

    /// The occurrence's next slot as the calendar draws it. Flexible work isn't
    /// planned until it's placed, so it has none.
    func plannedWork(_ reference: WorkTaskReference, now: Date = .now) -> PlannedBlock? {
        visibleBlocks.first {
            $0.occurrenceID == reference.occurrenceID && $0.placementID != nil && !$0.isActive && !$0.isCompleted && $0.end > now
        }
    }

    func dismissWorkCompletion() { workCompletion = nil; workSelection = nil }

    func undoWorkCompletion(now: Date = .now) {
        guard let summary = workCompletion, let id = summary.undoID else { return }
        guard store.undoCompletion(id) else {
            notice = store.persistenceError ?? "This completion changed elsewhere and can no longer be undone here."
            return
        }
        workCompletion = nil
        notice = nil
        workSelection = summary.task
        if validWorkTask(summary.task) != nil {
            resumeTaskID = summary.task.taskID
            resumeOccurrenceID = summary.task.occurrenceID
            persistResume()
        }
        tick(now: now, checkClockGap: false, materialChange: true)
    }

    /// What `block` moved to `start` would overlap on the calendar: meetings
    /// and the other blocks drawn there, in time order. Nothing else moves
    /// for it; the move is a placement like Plan's.
    func moveOverlaps(_ block: PlannedBlock, to start: Date) -> [WorkMoveOverlap] {
        let end = start.addingTimeInterval(max(0, block.end.timeIntervalSince(block.start)))
        let meetings = externalCalendars.busyTimes.filter { $0.start < end && start < $0.end }.map {
            WorkMoveOverlap(id: "busy-" + $0.id, title: $0.title.isEmpty ? "Busy" : $0.title, start: $0.start, end: $0.end)
        }
        let blocks = visibleBlocks.filter { $0.id != block.id && $0.end > $0.start && $0.start < end && start < $0.end }.map {
            WorkMoveOverlap(id: $0.id, title: store.block(id: $0.taskID)?.displayTitle ?? $0.titleSnapshot ?? "Task", start: $0.start, end: $0.end)
        }
        return (meetings + blocks).sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
    }

    private func validateWorkReferences() {
        if resumeTaskID != nil && resumableTask == nil { resumeTaskID = nil; resumeOccurrenceID = nil; persistResume() }
        if let reference = workSelection, validWorkTask(reference) == nil {
            workSelection = nil
            if isWorkPanelPresented && workCompletion == nil { notice = "This task occurrence is no longer available. Choose another task." }
        }
    }

    private func persistResume() {
        defaults.set(resumeTaskID?.uuidString, forKey: "work.resumeTaskID")
        defaults.set(resumeOccurrenceID?.uuidString, forKey: "work.resumeOccurrenceID")
    }

    /// Where work on `task` running at `now` has to stop: the next meeting or
    /// the end of the hours it's in, and with `stopsAtPins`, the next time
    /// another task is pinned. Nil outside those hours or during one of them.
    private func nextBoundary(for task: Block, at now: Date, stopsAtPins: Bool = false) -> Date? {
        let intervals = availability(for: task, on: now)
        guard let interval = intervals.first(where: { $0.start <= now && $0.end > now }) else { return nil }
        let fixed = externalCalendars.busyTimes.map { DateInterval(start: $0.start, end: $0.end) }
            + (stopsAtPins ? otherPlacements(than: task).filter(\.isPinned).map { DateInterval(start: $0.start, end: $0.end) } : [])
        guard !fixed.contains(where: { $0.start <= now && $0.end > now }) else { return nil }
        return min(interval.end, fixed.filter { $0.start > now }.map(\.start).min() ?? interval.end)
    }

    /// The first fixed thing at or after `date` that running work on `task`
    /// has to stop at: a meeting, a break or, with no kind as it is no
    /// conflict, the end of the list's hours. Tasks placed later move out of
    /// its way instead. Nil once `date` is outside the list's hours.
    private func nextStop(for task: Block, at date: Date) -> (start: Date, kind: CalendarWorkConflict.Kind?, title: String)? {
        let intervals = availability(for: task, on: date)
        guard let window = intervals.first(where: { $0.start <= date && date <= $0.end }) else { return nil }
        // The hours go on after a break, which the design names Lunch at
        // midday: one that takes in any of 12:00–13:00, as the default does.
        let resumes = intervals.map(\.start).filter { $0 >= window.end }.min()
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: window.end) ?? window.end
        let isLunch = resumes.map { window.end < noon.addingTimeInterval(3600) && $0 > noon } ?? false
        var stops: [(start: Date, kind: CalendarWorkConflict.Kind?, title: String)] = [
            (window.end, resumes == nil ? nil : .breakTime, isLunch ? "Lunch" : "")
        ]
        stops += externalCalendars.busyTimes.filter { $0.end > date && $0.end > $0.start }
            .map { (max($0.start, date), .event, $0.title) }
        // A meeting that starts with a break or the end of the hours is the one named.
        func rank(_ kind: CalendarWorkConflict.Kind?) -> Int { kind?.rawValue ?? .max }
        return stops.min { $0.start == $1.start ? rank($0.kind) < rank($1.kind) : $0.start < $1.start }
    }

    private func availability(for task: Block, on date: Date) -> [DateInterval] {
        let category = AvailabilityCategory(rawValue: store.list(id: task.listID)?.availabilityCategoryRaw ?? "work") ?? .work
        let day = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: day)!
        return AdaptiveScheduler.availabilityIntervals(for: category, preferences: preferences, from: day, to: end, calendar: calendar)
    }

    /// Placements the calendar draws: open tasks', at their current occurrence.
    private func livePlacements() -> [SchedulePlacement] {
        store.placements().filter { placement in
            guard placement.end > placement.start, let owner = store.block(id: placement.taskID),
                  owner.occurrenceID == placement.occurrenceID else { return false }
            return validWorkTask(WorkTaskReference(owner)) != nil
        }
    }

    /// Other open tasks' placements.
    private func otherPlacements(than task: Block) -> [SchedulePlacement] {
        livePlacements().filter { $0.occurrenceID != task.occurrenceID }
    }
}

/// More time given to the running work past its slot or estimate, and the
/// placed tasks moved for it.
struct CalendarWorkExtension: Equatable, Sendable {
    var taskID: UUID
    var occurrenceID: UUID
    /// Where the work's block now ends.
    var end: Date
    /// The extra minutes this session has been given in all.
    var minutes: Int
    /// The tasks whose placements the latest extension moved, in time order.
    var movedTaskIDs: [UUID]
}

/// What the running work ran into once its block could grow no further.
/// Recording carries on through it. The end of the list's hours only stops
/// the block growing, so it is never one.
struct CalendarWorkConflict: Equatable, Sendable {
    /// In the order a tie is named: a meeting before a break.
    enum Kind: Int, Equatable, Sendable {
        case event, breakTime
    }
    var taskID: UUID
    var occurrenceID: UUID
    var kind: Kind
    /// The meeting's title; for a break, "Lunch" at midday, else empty.
    var title: String
    var start: Date
}

/// Where paused work's block was and how it read when the work paused:
/// the extra time it had been given and what it had run into.
private struct PausedWork {
    var occurrenceID: UUID
    var start: Date
    var end: Date
    var grant: CalendarWorkExtension?
    var conflict: CalendarWorkConflict?
}

/// A placement an extension moved, or the slot it grew.
private struct PlacementMove {
    var id: UUID
    var taskID: UUID
    var from: DateInterval
    var to: DateInterval
}

/// One extension of the running work, kept so Undo and Redo can take it back
/// and give it again while that session runs, and move its placements once
/// the work has stopped.
private struct WorkExtensionStep {
    var sessionID: UUID
    var grant: CalendarWorkExtension
    var previousGrant: CalendarWorkExtension?
    var previousEnd: Date
    /// The slot it grew and the placements it moved.
    var moves: [PlacementMove]
    /// The plan on either side of the extension, so Undo and Redo put exactly
    /// those blocks back. Nil once another change has replaced them.
    var saved: SavedPlans?

    struct SavedPlans {
        var previous: CalendarPlan
        var next: CalendarPlan
        var previousSummary: CalendarRescheduleSummary?
        var summary: CalendarRescheduleSummary?
    }
}
