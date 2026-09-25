import Foundation

/// Counts retained actions, not today's checked state. No coverage ledger
/// exists, so an empty day is unknown and never an asserted zero.
nonisolated struct ActivityHeatmap: Equatable, Sendable {
    var days: [ActivityHeatmapDay]
    var calendar: Calendar
    var invalidDateCount: Int
    /// Consecutive days with a counted completion, ending today or, while
    /// today has none yet, yesterday. Read from the whole retained history
    /// rather than the displayed weeks, so every surface agrees on it.
    var streak: Int
    /// The earliest completion dated after `now`, which is left out until
    /// then (another Mac's clock can run ahead). A kept heatmap is stale
    /// from that moment even if no history changes.
    var nextCompletionAt: Date?

    var start: Date { days[0].id }
    var end: Date { days[days.count - 1].id }
    var total: Int { days.reduce(0) { $0 + $1.count } }
    var unclassifiedCount: Int { days.reduce(invalidDateCount) { $0 + $1.unclassifiedCount } }

    /// Covers `weeks` weeks aligned to `calendar.firstWeekday`: the current
    /// week through today, and the full weeks before it.
    init(completions: [ActivityCompletion], now: Date = .now, calendar: Calendar = .current, weeks: Int = 12) {
        self.calendar = calendar
        let today = calendar.startOfDay(for: now)
        let weekdayOffset = (calendar.component(.weekday, from: today) - calendar.firstWeekday + 7) % 7
        let weekStart = calendar.date(byAdding: .day, value: -weekdayOffset, to: today)!
        let firstDay = calendar.date(byAdding: .day, value: -7 * (max(1, weeks) - 1), to: weekStart)!
        var dates: [Date] = []
        var next = firstDay
        while next <= today {
            dates.append(next)
            next = calendar.date(byAdding: .day, value: 1, to: next)!
        }

        var known: [Date: [ActivityCompletion]] = [:]
        var unknown: [Date: Int] = [:]
        invalidDateCount = completions.filter { !$0.date.timeIntervalSinceReferenceDate.isFinite }.count
        let valid = completions.filter { $0.date.timeIntervalSinceReferenceDate.isFinite && $0.date <= now }
        nextCompletionAt = completions.lazy.map(\.date).filter { $0.timeIntervalSinceReferenceDate.isFinite && $0 > now }.min()
        let byEvent: [ActivityCompletion] = Dictionary(grouping: valid, by: \.id).values.map {
            ActivityCompletion.mergingDuplicates($0)
        }
        let byRecord: [String: [ActivityCompletion]] = Dictionary(grouping: byEvent) { entry in
            entry.completionID.map { "record:\($0)" } ?? "event:\(entry.id)"
        }
        let merged: [ActivityCompletion] = byRecord.values.map { ActivityCompletion.mergingDuplicates($0) }
        let sorted = merged.sorted { left, right in
            if left.date != right.date { return left.date < right.date }
            return left.id.uuidString < right.id.uuidString
        }
        var seenKeys: Set<String> = []
        var countedDays: Set<Date> = []
        for entry in sorted {
            let day = calendar.startOfDay(for: entry.date)
            guard !entry.hasConflictingDetails, let taskID = entry.taskID, let recurring = entry.wasRecurring,
                  !recurring || entry.cycleID != nil || entry.occurrenceID != nil else {
                if day >= firstDay { unknown[day, default: 0] += 1 }
                continue
            }
            let key = recurring ? "\(taskID):\(entry.cycleID ?? entry.occurrenceID!)" : "\(taskID):task"
            // Deduplicate before clipping the range: completing an old ordinary
            // task again this week cannot turn into an extra completion.
            guard seenKeys.insert(key).inserted else { continue }
            countedDays.insert(day)
            if day >= firstDay { known[day, default: []].append(entry) }
        }
        days = dates.map { ActivityHeatmapDay(id: $0, completions: known[$0] ?? [], unclassifiedCount: unknown[$0] ?? 0) }

        // A day that has not been worked yet does not break the streak.
        func dayBefore(_ day: Date) -> Date { calendar.startOfDay(for: calendar.date(byAdding: .day, value: -1, to: day)!) }
        var cursor = countedDays.contains(today) ? today : dayBefore(today)
        var run = 0
        while countedDays.contains(cursor) {
            run += 1
            cursor = dayBefore(cursor)
        }
        streak = run
    }
}
