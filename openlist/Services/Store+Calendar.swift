import Foundation
import SwiftData

struct DurationSuggestion {
    var minutes: Int
    var sampleCount: Int
    var description: String
}

private struct SessionCloseState {
    var session: WorkSession
    var endedAt: Date?
    var lastHeartbeatAt: Date
    var pauseReason: String?

    init(_ session: WorkSession) {
        self.session = session
        endedAt = session.endedAt
        lastHeartbeatAt = session.lastHeartbeatAt
        pauseReason = session.pauseReason
    }

    func restore() {
        session.endedAt = endedAt
        session.lastHeartbeatAt = lastHeartbeatAt
        session.pauseReason = pauseReason
    }
}

extension Store {
    func selectForToday(_ block: Block, now: Date = .now) {
        guard block.isTask, !block.isCompleted else { return }
        block.selectedForDay = Calendar.current.startOfDay(for: now)
        block.deferredUntil = nil
        block.touch()
        save()
    }

    func deselectForToday(_ block: Block) {
        block.selectedForDay = nil
        block.deferredUntil = nil
        block.touch()
        save()
    }

    func deferTask(_ block: Block, to day: Date) {
        guard block.isTask, !block.isCompleted else { return }
        let day = Calendar.current.startOfDay(for: day)
        pauseWorkSessions(for: block, reason: "Deferred")
        block.deferredUntil = day
        block.selectedForDay = day
        for placement in placements(taskID: block.id) where placement.occurrenceID == block.occurrenceID {
            context.delete(placement)
        }
        block.touch()
        save()
    }

    /// Ends a deferral: the task no longer waits for its day. The day it was
    /// selected for goes with it while still ahead; once that day has come
    /// the task stays selected, as it's planned for today by then.
    func clearDeferral(_ block: Block, now: Date = .now) {
        guard block.isTask, block.deferredUntil != nil else { return }
        let calendar = Calendar.current
        if let day = block.selectedForDay, calendar.startOfDay(for: day) > calendar.startOfDay(for: now) {
            block.selectedForDay = nil
        }
        block.deferredUntil = nil
        block.touch()
        save()
    }

    func setTaskEstimate(_ minutes: Int, for block: Block) {
        block.schedulingEstimateMinutes = max(0, min(60 * 24 * 28, minutes))
        block.touch()
        save()
    }

    func setKeepTogether(_ value: Bool, for block: Block) {
        block.keepsSessionsTogether = value
        block.touch()
        save()
    }

    func setTracksAway(_ value: Bool, for block: Block) {
        block.tracksAwayFromMac = value
        block.touch()
        save()
    }

    func setAvailabilityCategory(_ category: String, for list: TaskList) {
        guard category == "work" || category == "personal" else { return }
        list.availabilityCategoryRaw = category
        list.touch()
        save()
    }

    func workSessions(taskID: UUID? = nil) -> [WorkSession] {
        var descriptor = FetchDescriptor<WorkSession>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        if let taskID { descriptor.predicate = #Predicate { $0.taskID == taskID } }
        return ((try? context.fetch(descriptor)) ?? []).filter { !$0.isDeleted }
    }

    func completionRecords(taskID: UUID? = nil) -> [CompletionRecord] {
        var descriptor = FetchDescriptor<CompletionRecord>(sortBy: [SortDescriptor(\.completedAt, order: .reverse)])
        if let taskID { descriptor.predicate = #Predicate { $0.taskID == taskID } }
        return ((try? context.fetch(descriptor)) ?? []).filter { !$0.isDeleted }
    }

    func placements(taskID: UUID? = nil) -> [SchedulePlacement] {
        var descriptor = FetchDescriptor<SchedulePlacement>(sortBy: [SortDescriptor(\.start)])
        if let taskID { descriptor.predicate = #Predicate { $0.taskID == taskID } }
        return ((try? context.fetch(descriptor)) ?? []).filter { !$0.isDeleted }
    }

    @discardableResult
    func setPlacement(for block: Block, start: Date, end: Date, isPinned: Bool = false, placementID: UUID? = nil) -> SchedulePlacement? {
        guard block.isTask, !block.isCompleted, end > start else { return nil }
        let existing = placementID.flatMap { id in
            placements(taskID: block.id).first { $0.id == id && $0.occurrenceID == block.occurrenceID }
        }
        let placement = existing ?? SchedulePlacement(task: block, start: start, end: end, isPinned: isPinned)
        if existing == nil { context.insert(placement) }
        placement.start = start
        placement.end = end
        placement.isPinned = isPinned
        // A slot doesn't pick the task for its day, as the design's Plan
        // doesn't; the slot itself keeps the task in the plan.
        block.touch()
        save()
        return placement
    }

    func removePlacement(_ placement: SchedulePlacement) {
        context.delete(placement)
        save()
    }

    @discardableResult
    func startWorkSession(for block: Block, deviceID: String, now: Date = .now) -> WorkSession? {
        guard block.isTask, !block.isCompleted, let list = list(id: block.listID), !list.isEffectivelyArchived else { return nil }
        let openSessions = workSessions().filter { $0.endedAt == nil }
        if let existing = openSessions.first(where: {
            $0.taskID == block.id && $0.occurrenceID == block.occurrenceID && $0.deviceID == deviceID
        }) {
            do { try persistChanges(); return existing }
            catch { persistenceError = "Work could not be started. \(error.localizedDescription)"; return nil }
        }
        let closing = openSessions.filter {
            $0.deviceID == deviceID || ($0.taskID == block.id && $0.occurrenceID == block.occurrenceID)
        }
        let previousSessions = closing.map(SessionCloseState.init)
        let previousSelection = block.selectedForDay
        let previousDeferral = block.deferredUntil
        for session in closing {
            let isLocal = session.deviceID == deviceID
            closeSession(session, reason: isLocal ? "Started another task" : "Continued on another Mac",
                         now: isLocal ? now : min(now, session.lastHeartbeatAt))
        }
        let session = WorkSession(task: block, deviceID: deviceID, startedAt: now)
        session.plannedIntervals = calendarPlannedBlocks.filter {
            $0.taskID == block.id && $0.occurrenceID == block.occurrenceID && !$0.isCompleted
        }.map { CompletionCalendarInterval(start: $0.start, end: $0.end) }
        context.insert(session)
        block.selectedForDay = Calendar.current.startOfDay(for: now)
        block.deferredUntil = nil
        do {
            try persistChanges()
            return session
        } catch {
            // Restore only this operation. Rolling back the whole context would
            // discard unrelated editor drafts that are still waiting to save.
            context.delete(session)
            for previous in previousSessions { previous.restore() }
            block.selectedForDay = previousSelection
            block.deferredUntil = previousDeferral
            context.processPendingChanges()
            persistenceError = "Work could not be started. \(error.localizedDescription)"
            return nil
        }
    }

    @discardableResult
    func pauseWorkSession(_ session: WorkSession, reason: String, now: Date = .now) -> Bool {
        guard session.endedAt == nil else { return true }
        let previous = SessionCloseState(session)
        closeSession(session, reason: reason, now: now)
        do {
            try persistChanges()
            return true
        } catch {
            previous.restore()
            persistenceError = "Work could not be paused. \(error.localizedDescription)"
            return false
        }
    }

    /// Records that work is still under way. The heartbeat alone changes
    /// nothing the widgets show or the plan reads (the running session signs
    /// as "active"), so it saves without announcing and a running session
    /// does not rebuild the widget snapshot every minute. Other edits waiting
    /// to save go out with it and are announced as usual.
    func heartbeatWorkSession(_ session: WorkSession, now: Date = .now) {
        guard session.endedAt == nil else { return }
        let onlyHeartbeat = !context.hasChanges && pendingActivity.isEmpty
        session.lastHeartbeatAt = max(session.startedAt, now)
        guard !isSavingSuspended else { return }
        do {
            try persistChanges(announcing: !onlyHeartbeat)
        } catch {
            persistenceError = "Your latest changes could not be saved. \(error.localizedDescription)"
        }
    }

    /// Only closed sessions accept corrections; elapsed time remains visible
    /// while working. A nil correction restores the original observed time.
    func correctSession(_ session: WorkSession, minutes: Double?) {
        guard session.endedAt != nil else { return }
        if let minutes, !minutes.isFinite || minutes < 0 { return }
        session.correctedMinutes = minutes
        save()
    }

    func pauseWorkSessions(for block: Block, reason: String, now: Date = .now) {
        for session in workSessions(taskID: block.id)
        where session.occurrenceID == block.occurrenceID && session.endedAt == nil {
            let isForeign = calendarDeviceID.map { $0 != session.deviceID } ?? false
            let endpoint = isForeign ? min(now, session.lastHeartbeatAt)
                : min(now, calendarRecordingEndpoint?(session, now) ?? now)
            closeSession(session, reason: reason, now: endpoint)
        }
    }

    private func closeSession(_ session: WorkSession, reason: String, now: Date) {
        session.endedAt = max(session.startedAt, now)
        session.lastHeartbeatAt = session.endedAt!
        session.pauseReason = reason
    }

    /// Called before changing an occurrence's identity or deleting a task.
    /// History remains independent; only future placements are discarded.
    func discardTaskSchedule(for block: Block, reason: String, now: Date = .now) {
        pauseWorkSessions(for: block, reason: reason, now: now)
        for placement in placements(taskID: block.id) where placement.occurrenceID == block.occurrenceID {
            context.delete(placement)
        }
        block.selectedForDay = nil
        block.deferredUntil = nil
    }

    /// Capture before any parent/reset changes its occurrence. The override
    /// preserves a completing parent's cycle even after its last rule ends.
    func recurringCompletionCycle(for block: Block, completingAncestor: (id: UUID, cycleID: UUID)? = nil) -> UUID? {
        if block.recurrence != nil { return unadvancedCompletionCycle(for: block) }
        var parentID = block.parentID
        var visited: Set<UUID> = [block.id]
        while let id = parentID, visited.insert(id).inserted, let parent = self.block(id: id) {
            if id == completingAncestor?.id { return completingAncestor?.cycleID }
            if parent.recurrence != nil { return unadvancedCompletionCycle(for: parent) }
            parentID = parent.parentID
        }
        return nil
    }

    private func unadvancedCompletionCycle(for block: Block) -> UUID {
        if let cycle = pendingReopenedCycleIDs[block.occurrenceID] { return cycle }
        // Parent checkbox cascades can finish a self-recurring child without
        // advancing its rule. Both that task and its descendants inherit the
        // preserved cycle after reopening changes its calendar UUID.
        let id = block.id
        let descriptor = FetchDescriptor<ActivityEvent>(predicate: #Predicate { $0.blockID == id && $0.kindRaw == "reopened" })
        if let cycle = (try? context.fetch(descriptor))?.compactMap({ event -> UUID? in
            guard event.change?.after?.occurrenceID == block.occurrenceID else { return nil }
            return event.change?.completionCycleID
        }).first { return cycle }
        return block.occurrenceID
    }

    func recordCalendarCompletion(for block: Block, now: Date, recurringCycleID: UUID? = nil) {
        // A cloud-delivered completion must not produce duplicate local history.
        if !completionRecords(taskID: block.id).contains(where: { $0.occurrenceID == block.occurrenceID }) {
            let record = CompletionRecord(
                task: block,
                completedAt: now,
                estimateMinutes: block.schedulingEstimateMinutes > 0
                    ? block.schedulingEstimateMinutes : calendarDefaultEstimateMinutes
            )
            // A subtask belongs to its ancestor's recurring cycle even when
            // it has no recurrence rule of its own. Capture that fact now;
            // later moves, parent deletion or rule edits cannot recover it.
            let cycleID = recurringCycleID ?? recurringCompletionCycle(for: block)
            record.wasRecurring = cycleID != nil
            pendingCompletionCycleIDs[record.id] = cycleID
            let originalPlan = workSessions(taskID: block.id)
                .filter { $0.occurrenceID == block.occurrenceID && $0.plannedIntervalsData != nil }
                .min { $0.startedAt < $1.startedAt }
            if let originalPlan {
                record.plannedIntervals = originalPlan.plannedIntervals
            } else {
                record.plannedIntervals = calendarPlannedBlocks.filter {
                    $0.taskID == block.id && $0.occurrenceID == block.occurrenceID && !$0.isCompleted
                }.map { CompletionCalendarInterval(start: $0.start, end: $0.end) }
            }
            context.insert(record)
        }
        discardTaskSchedule(for: block, reason: "Completed", now: now)
    }

    /// Completion history is display-only. It must never be passed back to the
    /// scheduler as availability, estimates, or fixed placements.
    func completedCalendarBlocks() -> [PlannedBlock] {
        let sessions = Dictionary(grouping: workSessions().filter { $0.endedAt != nil }, by: \.occurrenceID)
        return completionRecords().flatMap { record -> [PlannedBlock] in
            let actual = (sessions[record.occurrenceID] ?? []).filter { $0.taskID == record.taskID }.sorted { $0.startedAt < $1.startedAt }
            let tracked = !actual.isEmpty
            let intervals: [(span: CompletionCalendarInterval, keepsSlot: Bool)]
            if tracked {
                var spans = actual.map { session in
                    let seconds = session.durationMinutes() * 60
                    let maximum = max(0, Date.distantFuture.timeIntervalSince(session.startedAt))
                    let duration = seconds.isFinite ? min(maximum, max(0, seconds)) : maximum
                    return CompletionCalendarInterval(start: session.startedAt, end: session.startedAt.addingTimeInterval(duration))
                }
                // Work done in a planned slot keeps the slot, as its running block
                // did, stretched to any work past either end. Work elsewhere shows
                // where it happened, and a slot nobody worked in shows nothing.
                for slot in record.plannedIntervals {
                    let inside = spans.filter { $0.start < slot.end && $0.end > slot.start }
                    guard let start = inside.map(\.start).min(), let end = inside.map(\.end).max() else { continue }
                    spans.removeAll { $0.start < slot.end && $0.end > slot.start }
                    spans.append(CompletionCalendarInterval(start: min(slot.start, start), end: max(slot.end, end)))
                }
                // Only what was merged into a slot still meets one.
                intervals = spans.sorted { $0.start < $1.start }.map { span in
                    (span, record.plannedIntervals.contains { $0.start < span.end && $0.end > span.start })
                }
            } else if !record.plannedIntervals.isEmpty {
                intervals = record.plannedIntervals.map { ($0, true) }
            } else {
                intervals = [(CompletionCalendarInterval(start: record.completedAt, end: record.completedAt), false)]
            }
            return intervals.enumerated().map { index, interval in
                PlannedBlock(id: "completed-\(record.id.uuidString)-\(index)", taskID: record.taskID,
                             occurrenceID: record.occurrenceID, start: interval.span.start, end: interval.span.end,
                             isPinned: false, placementID: nil, conflicts: [],
                             completionID: record.id, titleSnapshot: record.title, isTimeTracked: tracked,
                             keepsSlot: interval.keepsSlot)
            }
        }.sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
    }

    /// Similar means the same recurring task or substantial overlap in title
    /// words. Only completed occurrences with actual recorded work contribute;
    /// planned estimates and incomplete sessions never train the suggestion.
    func suggestedDuration(for block: Block) -> DurationSuggestion? {
        let stopWords: Set<String> = ["the", "a", "an", "to", "of", "for", "and", "in", "on", "with"]
        func words(_ title: String) -> Set<String> {
            Set(title.lowercased().components(separatedBy: .alphanumerics.inverted)
                .filter { $0.count > 1 && !stopWords.contains($0) })
        }
        let target = words(block.displayTitle)
        let history = completionRecords().filter { record in
            if record.taskID == block.id { return true }
            let candidate = words(record.title)
            let shared = target.intersection(candidate).count
            return shared >= 2 && Double(shared) / Double(max(1, target.union(candidate).count)) >= 0.5
        }
        let sessions = workSessions().filter { $0.endedAt != nil }
        var samples: [Double] = []
        for record in history.prefix(20) {
            let minutes = sessions.filter { $0.taskID == record.taskID && $0.occurrenceID == record.occurrenceID }
                .reduce(0) { $0 + $1.durationMinutes() }
            if minutes.isFinite && minutes > 0 { samples.append(minutes) }
        }
        guard !samples.isEmpty else { return nil }
        samples.sort()
        let midpoint = samples.count / 2
        let median = samples.count.isMultiple(of: 2) ? (samples[midpoint - 1] + samples[midpoint]) / 2 : samples[midpoint]
        let minutes = max(5, Int((min(60 * 24 * 28, median) / 5).rounded()) * 5)
        return DurationSuggestion(
            minutes: minutes, sampleCount: samples.count,
            description: "Based on recorded work from \(samples.count) similar completed \(samples.count == 1 ? "task" : "tasks")."
        )
    }
}
