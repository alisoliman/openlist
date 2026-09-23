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
    private(set) var visibleBlocks: [PlannedBlock] = []
    private(set) var startNudge: CalendarStartNudge? {
        didSet { if oldValue != startNudge { onNudgesChanged?() } }
    }
    private(set) var overrunNudge: CalendarOverrunNudge? {
        didSet { if oldValue != overrunNudge { onNudgesChanged?() } }
    }
    private(set) var rescheduleSummary: CalendarRescheduleSummary?
    /// Extra time the running work has been given, automatically or from
    /// "more time", and the flexible tasks its latest extension moved.
    private(set) var workExtension: CalendarWorkExtension?
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
    private(set) var pendingWorkStart: WorkTaskReference?
    private var switchingFrom: WorkTaskReference?
    private(set) var workCompletion: WorkCompletionSummary?
    private(set) var continuationProposal: WorkContinuationProposal?
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
    private var activeBoundary: Date?
    private var lastObservedAt: Date?
    private var lastCalendarRefresh: Date = .distantPast
    private var approvedWorkEnd: Date?
    private var estimatedWorkEnd: Date?
    private var usedAutomaticExtension = false
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
            refreshCompletedDisplay()
            return
        }
        tick(now: now, checkClockGap: false, materialChange: true)
    }

    func replan(now: Date = .now) {
        let previous = plan
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
        summarizeMoves(from: previous, message: "The plan was updated.", excluding: activeSession?.taskID)
    }

    @discardableResult
    func start(task: Block, now: Date = .now) -> Bool {
        guard task.isTask, !task.isCompleted, store.list(id: task.listID)?.isEffectivelyArchived == false else { return false }
        if activeSession?.taskID == task.id, activeSession?.occurrenceID == task.occurrenceID { return true }
        guard let boundary = nextBoundary(for: task, at: now), boundary > now else {
            notice = "This time is outside the list’s available hours or overlaps fixed busy time. Choose an available slot or update availability."
            return false
        }
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
        let baseline = baselineEnd(for: session, task: task, now: now)
        estimatedWorkEnd = baseline
        approvedWorkEnd = baseline
        usedAutomaticExtension = false
        workExtension = nil
        showedFinishHeadsUp = false
        overrunNudge = nil
        startNudge = nil
        activeBoundary = boundary
        lastObservedAt = now
        resumeTaskID = nil
        resumeOccurrenceID = nil
        persistResume()
        pendingWorkStart = nil
        workCompletion = nil
        continuationProposal = nil
        workSelection = WorkTaskReference(task)
        notice = nil
        replan(now: now)
        return true
    }

    func pause(reason: String = "Paused", now: Date = .now, replanning: Bool = true) {
        guard let session = activeSession else { return }
        let wasUpdating = isUpdating
        isUpdating = true
        // A button or lock notification may arrive before a delayed timer. The
        // last known hard boundary still limits recorded work in that case.
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
            persistResume()
        }
        activeSessionID = nil
        activeBoundary = nil
        lastObservedAt = nil
        approvedWorkEnd = nil
        estimatedWorkEnd = nil
        workExtension = nil
        overrunNudge = nil
        isUpdating = wasUpdating
        if replanning { replan(now: now) }
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
        pendingWorkStart = nil
        tick(now: now, checkClockGap: false, materialChange: true)
    }

    func deferTask(task: Block, to day: Date) {
        if activeSession?.taskID == task.id { pause(reason: "Deferred") }
        store.deferTask(task, to: day)
        if resumeTaskID == task.id { resumeTaskID = nil }
        replan()
    }

    func resume() {
        guard let task = resumableTask else { dismissResume(); return }
        requestWork(WorkTaskReference(task))
    }

    func dismissResume() {
        resumeTaskID = nil
        resumeOccurrenceID = nil
        persistResume()
        workSelection = nil
        notice = nil
    }

    /// Offers paused work again after a caller dismissed it, as long as the
    /// occurrence can still be worked and nothing else has taken its place.
    func restoreResume(_ reference: WorkTaskReference) {
        guard activeSession == nil, resumeTaskID == nil, validWorkTask(reference) != nil else { return }
        resumeTaskID = reference.taskID
        resumeOccurrenceID = reference.occurrenceID
        persistResume()
        workSelection = reference
    }

    func move(block: PlannedBlock, to start: Date, isPinned: Bool = false, now: Date = .now) {
        guard let task = store.block(id: block.taskID), task.occurrenceID == block.occurrenceID, !block.isActive else { return }
        let duration = min(block.end.timeIntervalSince(block.start), remainingMinutes(for: task, now: now) * 60)
        let end = start.addingTimeInterval(duration)
        guard let placement = store.setPlacement(for: task, start: start, end: end,
                                                 isPinned: isPinned, placementID: block.placementID),
              store.persistenceError == nil else {
            notice = store.persistenceError ?? "The requested time could not be saved. Try again."
            return
        }
        missedPlacementIDs.remove(placement.id)
        replan(now: now)
        let represented = plan.blocks.filter { $0.placementID == placement.id }
        let honored = represented.contains {
            abs($0.start.timeIntervalSince(start)) < 1 && $0.end >= end.addingTimeInterval(-1)
        }
        if isPinned {
            let conflicts = Array(Set(represented.flatMap(\.conflicts))).sorted()
            if !conflicts.isEmpty {
                notice = "Pinned time saved. " + conflicts.joined(separator: " ")
            } else if !honored {
                notice = "Pinned time saved, but " + moveConstraint(for: task, placement: placement, now: now) + ". Review its planning status."
            } else {
                notice = nil
            }
        } else if honored {
            notice = nil
        } else {
            notice = "Preferred time saved, but " + moveConstraint(for: task, placement: placement, now: now)
                + ". Choose another time or use Pin time to keep it fixed and review conflicts."
        }
    }

    /// Explain an unfulfilled preference using the same availability and fixed
    /// intervals as planning, without changing the saved choice into a hard pin.
    private func moveConstraint(for task: Block, placement: SchedulePlacement, now: Date) -> String {
        let start = placement.start
        let end = placement.end
        if start < now { return "that time has already passed" }
        if start >= plan.end || end > plan.end { return "that time is outside the rolling four-week planning horizon" }
        if let earliest = task.deferredUntil, start < earliest {
            return "the task is deferred until " + earliest.formatted(date: .abbreviated, time: .omitted)
        }
        if let due = task.dueDate {
            let cutoff = task.includesTime ? due : calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: due))!
            if end > cutoff { return "it would finish after the task’s deadline" }
        }
        let category = AvailabilityCategory(rawValue: store.list(id: task.listID)?.availabilityCategoryRaw ?? "work") ?? .work
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end))!
        let hours = AdaptiveScheduler.availabilityIntervals(for: category, preferences: preferences,
                                                            from: calendar.startOfDay(for: start), to: dayEnd, calendar: calendar)
        if !hours.contains(where: { $0.start <= start && $0.end >= end }) {
            return "it falls outside \(category.title.lowercased()) hours or overlaps a break"
        }
        if let meeting = externalCalendars.busyTimes.first(where: { $0.start < end && $0.end > start }) {
            return "it overlaps \(meeting.title.isEmpty ? "fixed busy time" : meeting.title)"
        }
        if plan.blocks.contains(where: { ($0.isPinned || $0.isActive) && $0.placementID != placement.id && $0.start < end && $0.end > start }) {
            return "it overlaps active work or another pinned time"
        }
        return "other scheduled work or session-length rules prevent that placement"
    }

    func pin(block: PlannedBlock) {
        guard let task = store.block(id: block.taskID), task.occurrenceID == block.occurrenceID, !block.isActive else { return }
        store.setPlacement(for: task, start: block.start, end: block.end, isPinned: true, placementID: block.placementID)
        replan()
    }

    func unpin(block: PlannedBlock) {
        guard let id = block.placementID, let placement = store.placements().first(where: { $0.id == id }) else { return }
        placement.isPinned = false
        store.save()
        replan()
    }

    func handleMacUnavailable(reason: String, now: Date = .now) {
        guard let session = activeSession, let task = store.block(id: session.taskID), !task.tracksAwayFromMac else { return }
        resumeTaskID = task.id
        pause(reason: reason, now: now)
        if activeSession == nil { notice = "Work paused because \(reason.lowercased()). Resume when ready." }
    }

    func handleMacReturn(now: Date = .now) {
        tick(now: now, checkClockGap: true)
        refreshCalendars(now: now)
        onMacReturn?()
    }

    /// Timer ticks retain the last promised placements. Only a real task/calendar
    /// change, an approved overrun, or one missed task changes the schedule.
    func tick(now: Date = .now, checkClockGap: Bool = true, materialChange: Bool = false) {
        guard hasStarted, !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }
        validateWorkReferences()
        if now.timeIntervalSince(lastCalendarRefresh) >= 300 { refreshCalendars(now: now) }
        let materialChange = materialChange || pendingCalendarChange
        pendingCalendarChange = false
        var needsPlan = materialChange || plan.start != calendar.startOfDay(for: now)
        if materialChange { refreshActiveEstimate(now: now) }
        if activeSessionID != nil, activeSession == nil {
            clearActiveState()
            needsPlan = true
        }
        if let session = activeSession {
            if session.endedAt != nil || store.block(id: session.taskID)?.occurrenceID != session.occurrenceID || store.block(id: session.taskID)?.isCompleted != false {
                clearActiveState()
                needsPlan = true
            } else if let task = store.block(id: session.taskID) {
                if store.list(id: task.listID)?.isEffectivelyArchived != false {
                    pause(reason: "List unavailable", now: now)
                } else if checkClockGap, !task.tracksAwayFromMac, let last = lastObservedAt, now.timeIntervalSince(last) > 75 {
                    resumeTaskID = task.id
                    pause(reason: "Mac was unavailable", now: min(last, activeBoundary ?? last, approvedWorkEnd ?? last))
                    if activeSession == nil { notice = "Work paused at the last observed activity. Resume when ready." }
                } else {
                    // Check the previously known boundary first, even when a late
                    // callback arrives after the meeting or break has finished.
                    // A real edit may remove a boundary that is still ahead;
                    // ordinary clock updates never erase a crossed boundary.
                    if materialChange, let known = activeBoundary, known > now {
                        activeBoundary = nextBoundary(for: task, at: now)
                    }
                    let boundary = min(activeBoundary ?? .distantFuture, nextBoundary(for: task, at: now) ?? now)
                    advanceActiveWork(session: session, task: task, through: now, boundary: boundary)
                    if activeSession != nil {
                        if now >= boundary {
                            resumeTaskID = task.id
                            pause(reason: "Meeting or end of available hours", now: boundary)
                            if activeSession == nil { notice = "Work paused at fixed busy time or the end of available hours. Remaining work has been rescheduled." }
                        } else {
                            activeBoundary = boundary
                            lastObservedAt = now
                            if now.timeIntervalSince(session.lastHeartbeatAt) >= 60 { store.heartbeatWorkSession(session, now: now) }
                            updateFinishNudge(task: task, now: now, boundary: boundary)
                        }
                    }
                }
            }
        }
        if needsPlan { replan(now: now) }
        else { updateStartNudge(now: now) }
        moveMissedWork(now: now)
    }

    /// Continue is explicit approval to move flexible work for another 15 minutes.
    /// A paused confirmation starts a fresh record at the actual click time.
    func acceptMoreTime(now: Date = .now) {
        guard let nudge = overrunNudge, let task = store.block(id: nudge.taskID),
              task.occurrenceID == nudge.occurrenceID, !task.isCompleted else {
            overrunNudge = nil
            return
        }
        let previous = plan
        if activeSession == nil {
            guard start(task: task, now: now) else { return }
            approvedWorkEnd = now.addingTimeInterval(15 * 60)
        } else {
            approvedWorkEnd = max(now, approvedWorkEnd ?? now).addingTimeInterval(15 * 60)
        }
        usedAutomaticExtension = true
        showedFinishHeadsUp = true
        overrunNudge = nil
        replan(now: now)
        let moved = summarizeMoves(from: previous, message: "Made room for continued work.", excluding: task.id)
        extendWork(task, by: 15, moved: moved)
    }

    func dismissRescheduleSummary() { rescheduleSummary = nil }

    private func advanceActiveWork(session: WorkSession, task: Block, through now: Date, boundary: Date) {
        var moved = Set<UUID>()
        while let end = approvedWorkEnd, end <= now, end < boundary {
            let proposed = min(end.addingTimeInterval(15 * 60), boundary)
            let affected = displacedTaskIDs(from: end, to: proposed, excluding: task.occurrenceID)
            if !affected.isEmpty {
                let nudge = CalendarOverrunNudge(taskID: task.id, occurrenceID: task.occurrenceID,
                    kind: .needsConfirmation, estimatedEnd: end,
                    proposedEnd: proposed, movedTaskCount: affected.count)
                pause(reason: "More time needs confirmation", now: end, replanning: false)
                guard activeSession == nil else { return }
                // Preserve everyone else's promised times while the user decides.
                rescheduleOnly(task: task, now: now)
                overrunNudge = nudge
                startNudge = nil
                return
            }
            let previous = plan
            approvedWorkEnd = proposed
            usedAutomaticExtension = true
            showedFinishHeadsUp = true
            overrunNudge = nil
            // Replan at the approved boundary, not a late callback: another block
            // may need to stay anchored there for the next extension decision.
            replan(now: end)
            moved.formUnion(summarizeMoves(from: previous, message: "Made room for continued work.", excluding: task.id))
            extendWork(task, by: Int((proposed.timeIntervalSince(end) / 60).rounded()),
                       moved: moved.sorted { $0.uuidString < $1.uuidString })
        }
    }

    /// Records more time given to the running work, for the window to report.
    private func extendWork(_ task: Block, by minutes: Int, moved: [UUID]) {
        guard let end = approvedWorkEnd else { return }
        let earlier = workExtension.flatMap { $0.occurrenceID == task.occurrenceID ? $0.minutes : nil } ?? 0
        workExtension = CalendarWorkExtension(taskID: task.id, occurrenceID: task.occurrenceID, end: end,
                                              minutes: earlier + minutes, movedTaskIDs: moved)
    }

    private func updateFinishNudge(task: Block, now: Date, boundary: Date) {
        guard !showedFinishHeadsUp, !usedAutomaticExtension, let end = estimatedWorkEnd,
              end < boundary, now >= end.addingTimeInterval(-2 * 60) else { return }
        showedFinishHeadsUp = true
        let proposed = min(end.addingTimeInterval(15 * 60), boundary)
        overrunNudge = CalendarOverrunNudge(taskID: task.id, occurrenceID: task.occurrenceID,
            kind: .headsUp, estimatedEnd: end, proposedEnd: proposed,
            movedTaskCount: displacedTaskIDs(from: end, to: proposed, excluding: task.occurrenceID).count)
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

    private func refreshActiveEstimate(now: Date) {
        guard let session = activeSession, let task = store.block(id: session.taskID),
              session.endedAt == nil, task.occurrenceID == session.occurrenceID else { return }
        let baseline = baselineEnd(for: session, task: task, now: now)
        guard baseline != estimatedWorkEnd else { return }
        estimatedWorkEnd = baseline
        approvedWorkEnd = max(now, baseline)
        // Editing the estimate changes the desired end, not the number of times
        // Openlist has already moved another task without asking.
        showedFinishHeadsUp = usedAutomaticExtension
        overrunNudge = nil
        // The new estimate replaces any time given past the old one.
        workExtension = nil
    }

    private func clearActiveState() {
        activeSessionID = nil
        activeBoundary = nil
        lastObservedAt = nil
        approvedWorkEnd = nil
        estimatedWorkEnd = nil
        workExtension = nil
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
            let conflict = "Pinned time was missed; remaining work has been replanned."
            if !next.assessments[index].conflicts.contains(conflict) { next.assessments[index].conflicts.append(conflict) }
        }
        plan = next
        store.calendarPlannedBlocks = next.blocks
        storeSchedulingSignature = schedulingSignature()
        refreshCompletedDisplay()
        if let nudge = overrunNudge, store.block(id: nudge.taskID)?.occurrenceID != nudge.occurrenceID || store.block(id: nudge.taskID)?.isCompleted != false {
            overrunNudge = nil
        }
        updateStartNudge(now: now)
    }

    private func refreshCompletedDisplay() {
        completedBlocks = store.completedCalendarBlocks()
        visibleBlocks = (plan.blocks + completedBlocks).sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
    }

    /// The timer, Pause, checkbox completion and displayed elapsed time share
    /// this read-only cap. A delayed callback is never permission to record work
    /// through another task's unapproved displacement or a fixed meeting.
    private func recordingEndpoint(for session: WorkSession, at now: Date) -> Date {
        guard session.id == activeSessionID, session.deviceID == deviceID,
              var end = approvedWorkEnd else { return min(now, session.lastHeartbeatAt) }
        let boundary = activeBoundary ?? now
        while end < now && end < boundary {
            let proposed = min(end.addingTimeInterval(15 * 60), boundary)
            let affected = displacedTaskIDs(from: end, to: proposed, excluding: session.occurrenceID)
            if !affected.isEmpty { return min(now, end, boundary) }
            end = proposed
        }
        return min(now, end, boundary)
    }

    private func updateStartNudge(now: Date) {
        guard activeSession == nil, overrunNudge?.needsConfirmation != true else { startNudge = nil; return }
        let next = plan.blocks.first { block in
            !block.isActive && block.start <= now && block.end > block.start &&
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
        let missed = plan.blocks.filter {
            !$0.isActive && $0.occurrenceID != activeSession?.occurrenceID &&
                $0.start.addingTimeInterval(5 * 60) <= now &&
                $0.occurrenceID != overrunNudge?.occurrenceID
        }
        var handled = Set<UUID>()
        for block in missed where handled.insert(block.occurrenceID).inserted {
            guard let task = store.block(id: block.taskID), task.occurrenceID == block.occurrenceID, !task.isCompleted else { continue }
            if block.isPinned, let placementID = block.placementID { missedPlacementIDs.insert(placementID) }
            let previous = plan
            rescheduleOnly(task: task, now: now)
            summarizeMoves(from: previous, message: "Moved an unstarted task to the next free time.")
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
                replacement.assessments[index].conflicts.append("Pinned time was missed; remaining work has been replanned.")
                replacement.assessments[index].reason += " Pinned time was missed; review the new placement."
            }
        }
        let blocks = (anchors + replacement.blocks).sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
        let assessments = plan.assessments.filter { $0.occurrenceID != task.occurrenceID } + replacement.assessments
        publish(CalendarPlan(start: plan.start, end: plan.end, blocks: blocks, assessments: assessments), now: now)
    }

    private func displacedTaskIDs(from start: Date, to end: Date, excluding occurrence: UUID) -> [UUID] {
        Set(plan.blocks.filter { !$0.isPinned && !$0.isActive && $0.occurrenceID != occurrence && $0.start < end && $0.end > start }.map(\.taskID))
            .sorted { $0.uuidString < $1.uuidString }
    }

    /// Reports the flexible tasks that moved since `previous`, and returns them.
    @discardableResult
    private func summarizeMoves(from previous: CalendarPlan, message: String, excluding taskID: UUID? = nil) -> [UUID] {
        let moved = Set(previous.blocks.filter { block in
            guard !block.isActive, !block.isPinned, block.taskID != taskID,
                  let task = store.block(id: block.taskID), !task.isCompleted,
                  task.occurrenceID == block.occurrenceID, store.list(id: task.listID)?.isEffectivelyArchived == false else { return false }
            return !plan.blocks.contains { $0.occurrenceID == block.occurrenceID && $0.start == block.start && $0.end == block.end }
        }.map(\.taskID)).sorted { $0.uuidString < $1.uuidString }
        guard !moved.isEmpty else { return [] }
        rescheduleSummary = CalendarRescheduleSummary(message: "\(moved.count) \(moved.count == 1 ? "task" : "tasks") rescheduled.",
            movedTaskCount: moved.count, taskIDs: moved, reason: message)
        return moved
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
        if overrunNudge?.needsConfirmation == true { continuationProposal = previewContinuation(now: now) }
        isWorkPanelPresented = true
    }

    func selectWork(_ reference: WorkTaskReference) {
        guard validWorkTask(reference) != nil else { return }
        workSelection = reference
        workCompletion = nil
        pendingWorkStart = nil
        notice = nil
    }

    @discardableResult
    func requestWork(_ reference: WorkTaskReference, now: Date = .now) -> Bool {
        guard let task = validWorkTask(reference) else {
            notice = "This task occurrence is no longer available. Choose another task."
            isWorkPanelPresented = true
            return false
        }
        selectWork(reference)
        isWorkPanelPresented = true
        if overrunNudge?.needsConfirmation == true, overrunNudge?.occurrenceID == reference.occurrenceID {
            refreshContinuation(now: now)
            return false
        }
        if let session = activeSession, session.occurrenceID != reference.occurrenceID {
            pendingWorkStart = reference
            switchingFrom = store.block(id: session.taskID).map(WorkTaskReference.init)
            return false
        }
        return start(task: task, now: now)
    }

    func cancelWorkSwitch() { pendingWorkStart = nil; switchingFrom = nil; showWork() }

    @discardableResult
    func confirmWorkSwitch(now: Date = .now) -> Bool {
        guard let reference = pendingWorkStart, let task = validWorkTask(reference) else {
            pendingWorkStart = nil; notice = "That task is no longer available."; return false
        }
        let current = activeSession.flatMap { store.block(id: $0.taskID) }.map(WorkTaskReference.init)
        guard current == switchingFrom else {
            switchingFrom = current
            notice = "The current session changed. Review the switch again."
            return false
        }
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

    func canStartWork(_ reference: WorkTaskReference, now: Date = .now) -> Bool {
        guard let task = validWorkTask(reference), let end = nextBoundary(for: task, at: now) else { return false }
        return end > now
    }

    func plannedWork(_ reference: WorkTaskReference, now: Date = .now) -> PlannedBlock? {
        plan.blocks.first { $0.occurrenceID == reference.occurrenceID && !$0.isActive && $0.end > now }
    }

    func workPlanSource(_ task: Block) -> String {
        if let block = plannedWork(WorkTaskReference(task)), block.isPinned { return "You pinned this time." }
        if store.placements(taskID: task.id).contains(where: { $0.occurrenceID == task.occurrenceID }) { return "Planned from your preferred time." }
        if task.selectedForDay != nil { return "Planned from your Today selection." }
        return "Automatically planned in your \(store.list(id: task.listID)?.availabilityCategoryRaw == "personal" ? "Personal" : "Work") hours."
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

    func keepWorkPaused() { overrunNudge = nil; continuationProposal = nil }

    func previewContinuation(now: Date = .now) -> WorkContinuationProposal? {
        guard let nudge = overrunNudge, nudge.needsConfirmation,
              let task = store.block(id: nudge.taskID), task.occurrenceID == nudge.occurrenceID,
              validWorkTask(WorkTaskReference(task)) != nil,
              let boundary = nextBoundary(for: task, at: now), boundary > now else { return nil }
        let end = min(now.addingTimeInterval(15 * 60), boundary)
        let active = ActiveScheduleInput(taskID: task.id, occurrenceID: task.occurrenceID, start: now, end: end)
        let preview = workPreview(active: active, now: now)
        return WorkContinuationProposal(task: WorkTaskReference(task), pausedAt: nudge.estimatedEnd,
            proposedEnd: end, boundary: boundary, changes: workPlanChanges(in: preview, excluding: task.id))
    }

    func refreshContinuation(now: Date = .now) { continuationProposal = previewContinuation(now: now) }

    @discardableResult
    func confirmContinuation(_ reviewed: WorkContinuationProposal, now: Date = .now) -> Bool {
        guard let current = previewContinuation(now: now) else {
            continuationProposal = nil
            notice = "Work cannot continue in this time. Review the next available slot."
            return false
        }
        // Compare what the person can actually review (minute-level placements).
        func signature(_ proposal: WorkContinuationProposal) -> [String] {
            proposal.changes.map { "\($0.occurrenceID)|\(Int($0.previousStart.timeIntervalSince1970 / 60))|\($0.proposedStart.map { Int($0.timeIntervalSince1970 / 60) } ?? -1)" }
        }
        guard current.task == reviewed.task, current.boundary == reviewed.boundary,
              signature(current) == signature(reviewed) else {
            continuationProposal = current
            notice = "The plan changed. Review the updated times before continuing."
            return false
        }
        acceptMoreTime(now: now)
        return activeSession?.occurrenceID == reviewed.task.occurrenceID
    }

    func previewMove(_ block: PlannedBlock, to start: Date, now: Date = .now) -> [WorkPlanChange] {
        guard let task = store.block(id: block.taskID), validWorkTask(WorkTaskReference(task)) != nil,
              task.occurrenceID == block.occurrenceID else { return [] }
        let duration = min(block.end.timeIntervalSince(block.start), remainingMinutes(for: task, now: now) * 60)
        var placements = store.placements().filter { $0.id != block.placementID }.map {
            PlacementInput(id: $0.id, taskID: $0.taskID, occurrenceID: $0.occurrenceID, start: $0.start, end: $0.end, isPinned: $0.isPinned)
        }
        placements.append(PlacementInput(id: block.placementID ?? UUID(), taskID: task.id, occurrenceID: task.occurrenceID,
            start: start, end: start.addingTimeInterval(duration), isPinned: false))
        let active = activeSession.flatMap { session -> ActiveScheduleInput? in
            guard let task = store.block(id: session.taskID) else { return nil }
            return ActiveScheduleInput(taskID: task.id, occurrenceID: task.occurrenceID, start: session.startedAt,
                end: min(targetEnd(for: session, task: task, now: now), activeBoundary ?? .distantFuture))
        }
        return workPlanChanges(in: workPreview(active: active, placements: placements, now: now), excluding: task.id)
    }

    private func workPreview(active: ActiveScheduleInput?, placements: [PlacementInput]? = nil, now: Date) -> CalendarPlan {
        let tasks = ((try? store.context.fetch(FetchDescriptor<Block>(predicate: #Predicate { $0.trashID == nil && $0.kindRaw == "task" && !$0.isCompleted }))) ?? [])
            .filter { validWorkTask(WorkTaskReference($0)) != nil }
        let placements = placements ?? store.placements().filter { !missedPlacementIDs.contains($0.id) }.map {
            PlacementInput(id: $0.id, taskID: $0.taskID, occurrenceID: $0.occurrenceID, start: $0.start, end: $0.end, isPinned: $0.isPinned)
        }
        return AdaptiveScheduler.plan(tasks: tasks.map { scheduleInput(for: $0, now: now) }, preferences: preferences,
            busyTimes: externalCalendars.busyTimes, placements: placements, active: active, now: now, calendar: calendar)
    }

    private func workPlanChanges(in preview: CalendarPlan, excluding taskID: UUID) -> [WorkPlanChange] {
        var seen: Set<UUID> = []
        return plan.blocks.compactMap { old -> WorkPlanChange? in
            guard old.taskID != taskID, !old.isActive, !old.isPinned, !seen.contains(old.occurrenceID),
                  let task = store.block(id: old.taskID), validWorkTask(WorkTaskReference(task)) != nil,
                  !preview.blocks.contains(where: { $0.occurrenceID == old.occurrenceID && $0.start == old.start && $0.end == old.end }) else { return nil }
            seen.insert(old.occurrenceID)
            let next = preview.blocks.first { $0.occurrenceID == old.occurrenceID }
            return WorkPlanChange(taskID: old.taskID, occurrenceID: old.occurrenceID, title: task.displayTitle,
                previousStart: old.start, proposedStart: next?.start)
        }
    }

    private func validateWorkReferences() {
        if resumeTaskID != nil && resumableTask == nil { resumeTaskID = nil; resumeOccurrenceID = nil; persistResume() }
        if let reference = workSelection, validWorkTask(reference) == nil {
            workSelection = nil
            if isWorkPanelPresented && workCompletion == nil { notice = "This task occurrence is no longer available. Choose another task." }
        }
        if let reference = pendingWorkStart, validWorkTask(reference) == nil { pendingWorkStart = nil; switchingFrom = nil }
    }

    private func persistResume() {
        defaults.set(resumeTaskID?.uuidString, forKey: "work.resumeTaskID")
        defaults.set(resumeOccurrenceID?.uuidString, forKey: "work.resumeOccurrenceID")
    }

    private func nextBoundary(for task: Block, at now: Date) -> Date? {
        let category = AvailabilityCategory(rawValue: store.list(id: task.listID)?.availabilityCategoryRaw ?? "work") ?? .work
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let intervals = AdaptiveScheduler.availabilityIntervals(for: category, preferences: preferences, from: calendar.startOfDay(for: now), to: end, calendar: calendar)
        guard let interval = intervals.first(where: { $0.start <= now && $0.end > now }) else { return nil }
        let pins = store.placements().filter { placement in
            guard placement.isPinned, placement.occurrenceID != task.occurrenceID,
                  let owner = store.block(id: placement.taskID), owner.isTask, !owner.isCompleted,
                  owner.occurrenceID == placement.occurrenceID,
                  store.list(id: owner.listID)?.isEffectivelyArchived == false else { return false }
            return placement.end > placement.start
        }
        let fixed = externalCalendars.busyTimes.map { DateInterval(start: $0.start, end: $0.end) } + pins.map { DateInterval(start: $0.start, end: $0.end) }
        guard !fixed.contains(where: { $0.start <= now && $0.end > now }) else { return nil }
        return min(interval.end, fixed.filter { $0.start > now }.map(\.start).min() ?? interval.end)
    }
}

/// More time given to the running work, and the flexible tasks moved for it.
struct CalendarWorkExtension: Equatable, Sendable {
    var taskID: UUID
    var occurrenceID: UUID
    /// Where the work may now run until.
    var end: Date
    /// The extra minutes this session has been given in all.
    var minutes: Int
    /// The tasks the latest extension moved, if any.
    var movedTaskIDs: [UUID]
}
