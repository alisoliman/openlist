import Foundation

/// Pure, deterministic planning. It never starts a task and never writes an external event.
enum AdaptiveScheduler {
    private struct Span {
        var start: Date
        var end: Date
        var minutes: Double { max(0, end.timeIntervalSince(start) / 60) }
    }
    private static let tolerance = 0.001

    static func plan(
        tasks: [ScheduleTask], preferences: CalendarPreferences,
        busyTimes: [FixedBusyTime] = [], placements: [PlacementInput] = [],
        active: ActiveScheduleInput? = nil, now: Date = Date(), calendar: Calendar = .current
    ) -> CalendarPlan {
        let dayStart = calendar.startOfDay(for: now)
        let horizon = calendar.date(byAdding: .day, value: max(1, min(28, preferences.horizonDays)), to: dayStart)!
        // Flexible blocks begin on a minute boundary; explicitly active work retains its real time.
        let flexibleStart = Date(timeIntervalSinceReferenceDate: ceil(now.timeIntervalSinceReferenceDate / 60) * 60)
        let minimum = Double(max(1, preferences.minimumSessionMinutes))
        let byOccurrence = Dictionary(tasks.map { ($0.occurrenceID, $0) }, uniquingKeysWith: { first, _ in first })
        let uniqueTasks = byOccurrence.values.sorted { $0.occurrenceID.uuidString < $1.occurrenceID.uuidString }
        let busy = busyTimes.filter { $0.end > $0.start && $0.end > now && $0.start < horizon }
        var occupied = merge(busy.map { Span(start: max(now, $0.start), end: min(horizon, $0.end)) })
        let availability: [AvailabilityCategory: [Span]] = [
            .work: availableSpans(profile: preferences.work, from: dayStart, to: horizon, calendar: calendar),
            .personal: availableSpans(profile: preferences.personal, from: dayStart, to: horizon, calendar: calendar)
        ]
        var blocks: [PlannedBlock] = []
        var represented: [UUID: Double] = [:]
        var outsidePinnedMinutes: [UUID: Double] = [:]
        var outsidePinConflicts: [UUID: [String]] = [:]

        // The caller alone decides whether a task is active. An ordinary past block never becomes active.
        if let active, let task = byOccurrence[active.occurrenceID], active.taskID == task.taskID,
           active.start <= now, active.end > now,
           let hours = availability[task.category]?.first(where: { $0.start <= now && $0.end > now }) {
            var end = min(active.end, hours.end, horizon)
            if let meeting = busy.filter({ $0.end > now && $0.start < end }).min(by: { $0.start < $1.start }) {
                end = max(now, meeting.start)
            }
            let desired = requiredMinutes(task)
            // The runtime passes a forecast extension when an estimate has been exhausted.
            end = min(end, now.addingTimeInterval(desired * 60))
            if end > now {
                let span = Span(start: now, end: end)
                blocks.append(block(task: task, span: span, suffix: "active", isActive: true))
                occupied = merge(occupied + [span])
                represented[task.occurrenceID] = span.minutes
            }
        }

        let pins = placements.filter {
            $0.isPinned && $0.end > $0.start && $0.end > now && $0.start < horizon &&
                byOccurrence[$0.occurrenceID]?.taskID == $0.taskID
        }.sorted(by: placementOrder)
        for pin in pins {
            guard let task = byOccurrence[pin.occurrenceID] else { continue }
            let left = max(0, requiredMinutes(task) - represented[task.occurrenceID, default: 0])
            guard left > tolerance else { continue }
            let start = max(now, pin.start)
            let end = min(horizon, pin.end, start.addingTimeInterval(left * 60))
            guard end > start else { continue }
            let span = Span(start: start, end: end)
            var conflicts = busy.filter { intersects(span, Span(start: $0.start, end: $0.end)) }
                .map { "Overlaps \($0.title.isEmpty ? "an external event" : $0.title)." }
            if !contains(span, in: availability[task.category, default: []]) {
                conflicts.append("Outside \(task.category.title.lowercased()) availability or inside a break.")
            }
            if let earliest = task.earliestStart, start < earliest {
                conflicts.append("Pinned before this task is available to start.")
            }
            if let due = task.dueDate, end > due {
                conflicts.append("Pinned time extends past the deadline.")
            }
            if blocks.contains(where: { $0.isActive && intersects(span, Span(start: $0.start, end: $0.end)) }) {
                conflicts.append("Overlaps active work.")
            }
            if task.keepTogether && (span.minutes + tolerance < requiredMinutes(task) || represented[task.occurrenceID, default: 0] > tolerance) {
                conflicts.append("Pinned placement splits a task marked Keep together.")
            }
            blocks.append(block(task: task, span: span, suffix: pin.id.uuidString, isPinned: true,
                                placementID: pin.id, conflicts: Array(Set(conflicts)).sorted()))
            represented[task.occurrenceID, default: 0] += span.minutes
            occupied = merge(occupied + [span])
        }

        // Compare the actual represented pins, after clipping reduced estimates and active work.
        // Stale saved extents must not manufacture a conflict with an otherwise safe pin.
        for index in blocks.indices where blocks[index].isPinned {
            let span = Span(start: blocks[index].start, end: blocks[index].end)
            if blocks.indices.contains(where: { other in
                other != index && blocks[other].isPinned && intersects(span, Span(start: blocks[other].start, end: blocks[other].end))
            }) {
                blocks[index].conflicts.append("Overlaps another pinned block.")
                blocks[index].conflicts.sort()
            }
        }

        // A fixed commitment does not become flexible merely because it extends beyond
        // the visible horizon. Reserve its outside portion without claiming safe coverage.
        for pin in placements.filter({ $0.isPinned && $0.end > horizon && $0.end > $0.start }).sorted(by: placementOrder) {
            guard let task = byOccurrence[pin.occurrenceID], pin.taskID == task.taskID else { continue }
            let left = max(0, requiredMinutes(task) - represented[task.occurrenceID, default: 0])
            let outsideStart = max(horizon, pin.start)
            let minutes = min(left, max(0, pin.end.timeIntervalSince(outsideStart) / 60))
            guard minutes > tolerance else { continue }
            represented[task.occurrenceID, default: 0] += minutes
            outsidePinnedMinutes[task.occurrenceID, default: 0] += minutes
            if let due = task.dueDate, outsideStart.addingTimeInterval(minutes * 60) > due {
                outsidePinConflicts[task.occurrenceID, default: []].append("Pinned time beyond the planning horizon extends past the deadline.")
            }
        }

        let placedIDs = Set(placements.filter { $0.end > now || $0.isPinned }.map(\.occurrenceID))
        let candidates = uniqueTasks.filter { task in
            task.selectedForToday || task.earliestStart != nil || placedIDs.contains(task.occurrenceID) || active?.occurrenceID == task.occurrenceID ||
                (task.dueDate.map { $0 <= horizon } ?? false)
        }
        let todayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        let selectedDemand = candidates.filter(\.selectedForToday).reduce(0) {
            $0 + max(0, requiredMinutes($1) - represented[$1.occurrenceID, default: 0])
        }
        var risk: [UUID: Bool] = [:]
        for task in candidates {
            guard let due = task.dueDate else { continue }
            let capacity = freeSpans(for: task, availability: availability, occupied: occupied,
                                     after: flexibleStart, before: min(horizon, due)).reduce(0) { $0 + $1.minutes }
            let dueDemand = candidates.filter {
                $0.category == task.category && ($0.dueDate.map { $0 <= due } ?? false)
            }.reduce(0) { $0 + max(0, requiredMinutes($1) - represented[$1.occurrenceID, default: 0]) }
            // Same-day cutoffs are urgent. For later cutoffs, include competing today work so a
            // nominally feasible deadline cannot silently be starved by selected tasks.
            risk[task.occurrenceID] = due <= todayEnd || capacity + tolerance < dueDemand + selectedDemand
        }
        let ordered = candidates.sorted { lhs, rhs in
            let lhsRank = risk[lhs.occurrenceID] == true ? 0 : (lhs.selectedForToday ? 1 : 2)
            let rhsRank = risk[rhs.occurrenceID] == true ? 0 : (rhs.selectedForToday ? 1 : 2)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            if lhsRank != 1 && lhs.dueDate != rhs.dueDate { return (lhs.dueDate ?? .distantFuture) < (rhs.dueDate ?? .distantFuture) }
            if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            return lhs.occurrenceID.uuidString < rhs.occurrenceID.uuidString
        }

        func allocate(_ task: ScheduleTask, before cutoff: Date, preferredBefore preferredCutoff: Date? = nil) {
            var remaining = max(0, requiredMinutes(task) - represented[task.occurrenceID, default: 0])
            guard remaining > tolerance else { return }
            var sequence = blocks.filter { $0.occurrenceID == task.occurrenceID && !$0.isPinned && !$0.isActive }.count
            func append(_ span: Span, placementID: UUID? = nil) {
                blocks.append(block(task: task, span: span, suffix: "flex-\(sequence)", placementID: placementID))
                sequence += 1
                remaining = max(0, remaining - span.minutes)
                represented[task.occurrenceID, default: 0] += span.minutes
                occupied = merge(occupied + [span])
            }
            // Preferred placements yield to fixed time, urgent work, availability and deadlines.
            for placement in placements.filter({ !$0.isPinned && $0.occurrenceID == task.occurrenceID && $0.taskID == task.taskID }).sorted(by: placementOrder) {
                guard remaining > tolerance, placement.start >= flexibleStart, placement.end > placement.start else { continue }
                let slots = freeSpans(for: task, availability: availability, occupied: occupied,
                                      after: flexibleStart, before: preferredCutoff ?? cutoff)
                guard let slot = slots.first(where: { $0.start <= placement.start && $0.end > placement.start }) else { continue }
                let available = Span(start: placement.start, end: min(slot.end, placement.end)).minutes
                let duration = chunk(remaining: remaining, available: available, minimum: minimum, keepTogether: task.keepTogether)
                guard duration > tolerance else { continue }
                let span = Span(start: placement.start, end: placement.start.addingTimeInterval(duration * 60))
                append(span, placementID: placement.id)
            }
            // Fill earliest safe space. Splitting never creates a tiny tail from a longer task.
            let slots = freeSpans(for: task, availability: availability, occupied: occupied, after: flexibleStart, before: cutoff)
            for slot in slots where remaining > tolerance {
                let duration = chunk(remaining: remaining, available: slot.minutes, minimum: minimum, keepTogether: task.keepTogether)
                guard duration > tolerance else { continue }
                append(Span(start: slot.start, end: slot.start.addingTimeInterval(duration * 60)))
            }
        }

        // First protect actual cutoffs. Today work gets today's free time in priority order;
        // overflowing tasks cannot consume another task's feasible pre-deadline slots.
        for task in ordered {
            let cutoff = min(horizon, task.dueDate ?? (task.selectedForToday ? todayEnd : horizon))
            // Selecting today controls automatic placement, but a later deliberate move is
            // still a valid preference. Try it before today's fallback, within the deadline.
            allocate(task, before: cutoff, preferredBefore: min(horizon, task.dueDate ?? horizon))
        }
        // After the feasible deadline work, keep the remaining workload visible on future days.
        for task in ordered { allocate(task, before: horizon) }

        var assessments: [TaskScheduleAssessment] = []
        for task in uniqueTasks {
            let isCandidate = candidates.contains { $0.occurrenceID == task.occurrenceID }
            guard isCandidate || task.dueDate != nil else { continue } // Undated backlog is deliberately untouched.
            let taskBlocks = blocks.filter { $0.occurrenceID == task.occurrenceID }
            let safeBlocks = taskBlocks.filter { $0.conflicts.isEmpty }
            let scheduled = safeBlocks.reduce(0) { $0 + $1.durationMinutes }
            let beforeDeadline = safeBlocks.reduce(0.0) { result, block in
                result + max(0, min(block.end, task.dueDate ?? horizon).timeIntervalSince(block.start) / 60)
            }
            let required = requiredMinutes(task)
            let status: TaskScheduleStatus
            var reason: String
            if !isCandidate {
                status = .outsidePlanningHorizon
                reason = "Deadline is beyond the rolling four-week plan. Select for today to schedule sooner."
            } else if let due = task.dueDate, due <= horizon, beforeDeadline + tolerance < required {
                status = .cannotFitBeforeDeadline
                let missing = Int(ceil(required - beforeDeadline))
                reason = "\(missing) min cannot fit before the deadline.\(taskBlocks.contains(where: { !$0.conflicts.isEmpty }) ? " Review pinned conflicts." : "")"
            } else if scheduled + tolerance < required {
                status = .outsidePlanningHorizon
                if outsidePinnedMinutes[task.occurrenceID, default: 0] > tolerance {
                    reason = "\(Int(ceil(outsidePinnedMinutes[task.occurrenceID, default: 0]))) min are pinned beyond the four-week plan."
                } else {
                    reason = taskBlocks.contains(where: { !$0.conflicts.isEmpty })
                        ? "Pinned conflicts leave insufficient safe time within the four-week plan."
                        : "\(Int(ceil(required - scheduled))) min remain beyond available time in the four-week plan."
                }
            } else {
                status = .scheduled
                reason = task.dueDate == nil ? "All remaining work has scheduled time." : "Enough time is scheduled before the deadline."
            }
            let missedPins = placements.filter {
                $0.isPinned && $0.taskID == task.taskID && $0.occurrenceID == task.occurrenceID && $0.end <= now && $0.end > $0.start
            }
            let conflicts = Array(Set(taskBlocks.flatMap(\.conflicts) + outsidePinConflicts[task.occurrenceID, default: []] + (missedPins.isEmpty ? [] : ["Pinned time was missed; remaining work has been replanned."]))).sorted()
            if !missedPins.isEmpty { reason += " Pinned time was missed; review the new placement." }
            assessments.append(TaskScheduleAssessment(taskID: task.taskID, occurrenceID: task.occurrenceID,
                status: status, requiredMinutes: required, scheduledMinutes: scheduled,
                beforeDeadlineMinutes: beforeDeadline, reason: reason, conflicts: conflicts))
        }
        blocks.sort { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
        return CalendarPlan(start: dayStart, end: horizon, blocks: blocks, assessments: assessments)
    }

    static func availabilityIntervals(for category: AvailabilityCategory, preferences: CalendarPreferences,
                                      from: Date, to: Date, calendar: Calendar = .current) -> [DateInterval] {
        availableSpans(profile: preferences.profile(for: category), from: from, to: to, calendar: calendar)
            .map { DateInterval(start: $0.start, end: $0.end) }
    }

    /// Returns the current availability's end, clipped at the next external meeting. Runtime uses
    /// this same boundary to pause explicit active work rather than infer activity from a block.
    static func activeBoundary(category: AvailabilityCategory, preferences: CalendarPreferences,
                               busyTimes: [FixedBusyTime], now: Date, calendar: Calendar = .current) -> Date? {
        let day = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: day)!
        guard let window = availableSpans(profile: preferences.profile(for: category), from: day, to: tomorrow, calendar: calendar)
            .first(where: { $0.start <= now && $0.end > now }) else { return nil }
        if busyTimes.contains(where: { $0.start <= now && $0.end > now }) { return nil }
        return busyTimes.filter { $0.start > now && $0.start < window.end && $0.end > $0.start }.map(\.start).min() ?? window.end
    }

    private static func requiredMinutes(_ task: ScheduleTask) -> Double {
        task.remainingMinutes.isFinite ? max(0, task.remainingMinutes) : 0
    }

    private static func block(task: ScheduleTask, span: Span, suffix: String, isPinned: Bool = false,
                              placementID: UUID? = nil, conflicts: [String] = [], isActive: Bool = false) -> PlannedBlock {
        PlannedBlock(id: "\(task.occurrenceID.uuidString)-\(suffix)", taskID: task.taskID,
                     occurrenceID: task.occurrenceID, start: span.start, end: span.end,
                     isPinned: isPinned, placementID: placementID, conflicts: conflicts, isActive: isActive)
    }

    private static func placementOrder(_ lhs: PlacementInput, _ rhs: PlacementInput) -> Bool {
        lhs.start == rhs.start ? lhs.id.uuidString < rhs.id.uuidString : lhs.start < rhs.start
    }

    private static func chunk(remaining: Double, available: Double, minimum: Double, keepTogether: Bool) -> Double {
        if available + tolerance >= remaining { return remaining }
        if keepTogether || available + tolerance < minimum { return 0 }
        let tail = remaining - available
        if tail + tolerance < minimum {
            let adjusted = remaining - minimum
            return adjusted + tolerance >= minimum ? adjusted : 0
        }
        return available
    }

    private static func freeSpans(for task: ScheduleTask, availability: [AvailabilityCategory: [Span]], occupied: [Span], after: Date, before: Date) -> [Span] {
        let start = max(after, task.earliestStart ?? after)
        guard before > start else { return [] }
        let windows = availability[task.category, default: []].compactMap { span -> Span? in
            let clipped = Span(start: max(start, span.start), end: min(before, span.end))
            return clipped.end > clipped.start ? clipped : nil
        }
        return subtract(occupied, from: windows)
    }

    private static func availableSpans(profile: AvailabilityProfile, from start: Date, to end: Date, calendar: Calendar) -> [Span] {
        var result: [Span] = []
        var day = calendar.startOfDay(for: start)
        while day < end {
            let next = calendar.date(byAdding: .day, value: 1, to: day)!
            let weekday = calendar.component(.weekday, from: day)
            let override = profile.overrides.last { calendar.isDate($0.date, inSameDayAs: day) }
            let windows = override?.windows ?? profile.weekly[weekday, default: []]
            let breaks = override?.breaks ?? profile.breaks[weekday, default: []]
            func spans(_ windows: [AvailabilityWindow]) -> [Span] {
                windows.compactMap { window in
                    guard window.startMinute >= 0, window.endMinute <= 1440,
                          window.startMinute < window.endMinute else { return nil }
                    func time(_ minute: Int) -> Date {
                        if minute == 1440 { return next }
                        // Wall-clock matching handles spring-forward gaps and fall-back repeats.
                        return calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0,
                                             of: day, matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward) ?? next
                    }
                    let span = Span(start: max(start, time(window.startMinute)), end: min(end, time(window.endMinute)))
                    return span.end > span.start ? span : nil
                }
            }
            result += subtract(merge(spans(breaks)), from: merge(spans(windows)))
            day = next
        }
        return merge(result)
    }

    private static func intersects(_ lhs: Span, _ rhs: Span) -> Bool { lhs.start < rhs.end && rhs.start < lhs.end }

    private static func contains(_ span: Span, in windows: [Span]) -> Bool {
        windows.contains { $0.start <= span.start && $0.end >= span.end }
    }

    private static func merge(_ spans: [Span]) -> [Span] {
        var result: [Span] = []
        for span in spans.filter({ $0.end > $0.start }).sorted(by: { $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start }) {
            if let last = result.last, span.start <= last.end {
                result[result.count - 1].end = max(last.end, span.end)
            } else { result.append(span) }
        }
        return result
    }

    private static func subtract(_ busy: [Span], from windows: [Span]) -> [Span] {
        var result: [Span] = []
        for window in windows {
            var cursor = window.start
            for obstacle in busy where obstacle.end > cursor && obstacle.start < window.end {
                if obstacle.start > cursor { result.append(Span(start: cursor, end: min(window.end, obstacle.start))) }
                cursor = max(cursor, obstacle.end)
                if cursor >= window.end { break }
            }
            if cursor < window.end { result.append(Span(start: cursor, end: window.end)) }
        }
        return result
    }
}
