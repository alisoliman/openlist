import Foundation

/// Counts the saved completions that still stand, as the design counts the
/// tasks done: one taken back since, by its Undo or by reopening the task,
/// with no completion after it, leaves the count. No coverage ledger exists,
/// so an empty day is unknown and never an asserted zero.
nonisolated struct ActivityHeatmap: Equatable, Sendable {
    var days: [ActivityHeatmapDay]
    var calendar: Calendar
    var invalidDateCount: Int

    var start: Date { days[0].id }
    var end: Date { days[days.count - 1].id }
    var total: Int { days.reduce(0) { $0 + $1.count } }
    var unclassifiedCount: Int { days.reduce(invalidDateCount) { $0 + $1.unclassifiedCount } }

    /// `weeks` whole weeks, the last one today's: the Activity screen shows 12,
    /// the medium Activity widget 21.
    init(completions: [ActivityCompletion], reversals: [ActivityReversal] = [], now: Date = .now,
         calendar: Calendar = .current, weeks: Int = 12) {
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
        let byEvent: [ActivityCompletion] = Dictionary(grouping: valid, by: \.id).values.map {
            ActivityCompletion.mergingDuplicates($0)
        }
        let byRecord: [String: [ActivityCompletion]] = Dictionary(grouping: byEvent) { entry in
            entry.completionID.map { "record:\($0)" } ?? "event:\(entry.id)"
        }
        // Each counted task or cycle's completions and the actions that took
        // one back, as they were saved; a record's every saved copy is its
        // merged entry, so its Redo stands for it again.
        var actions: [String: [ActivityHeatmapAction]] = [:]
        var keyByRecord: [UUID: String] = [:]
        for copies in byRecord.values {
            let entry = ActivityCompletion.mergingDuplicates(copies)
            guard !entry.hasConflictingDetails, let taskID = entry.taskID, let recurring = entry.wasRecurring,
                  !recurring || entry.cycleID != nil || entry.occurrenceID != nil else {
                let day = calendar.startOfDay(for: entry.date)
                if day >= firstDay { unknown[day, default: 0] += 1 }
                continue
            }
            let key = recurring ? "\(taskID):\(entry.cycleID ?? entry.occurrenceID!)" : "\(taskID):task"
            if let record = entry.completionID { keyByRecord[record] = key }
            for copy in copies { actions[key, default: []].append(ActivityHeatmapAction(at: copy.recordedAt, id: copy.id, entry: entry)) }
        }
        // An Undo takes back the record it removed. A reopen takes back an
        // ordinary task's count, or its own rule's unadvanced cycle; a subtask
        // of a repeat keeps its cycle's, since the repeat rolling on reopens it too.
        for reversal in reversals where reversal.date.timeIntervalSinceReferenceDate.isFinite {
            let key: String?
            if let record = reversal.completionID {
                key = keyByRecord[record]
            } else {
                key = reversal.taskID.map { task in reversal.cycleID.map { "\(task):\($0)" } ?? "\(task):task" }
            }
            guard let key, actions[key] != nil else { continue }
            actions[key]?.append(ActivityHeatmapAction(at: reversal.date, id: nil, entry: nil))
        }
        for timeline in actions.values {
            // Deduplicate before clipping the range: completing an old ordinary
            // task again this week cannot turn into an extra completion. The
            // first completion since the last one taken back supplies the day.
            var standing: ActivityCompletion?
            for action in timeline.sorted() {
                if let entry = action.entry { standing = standing ?? entry } else { standing = nil }
            }
            guard let standing else { continue }
            let day = calendar.startOfDay(for: standing.date)
            if day >= firstDay { known[day, default: []].append(standing) }
        }
        days = dates.map { date in
            let completions = (known[date] ?? []).sorted { left, right in
                if left.date != right.date { return left.date < right.date }
                return left.id.uuidString < right.id.uuidString
            }
            return ActivityHeatmapDay(id: date, completions: completions, unclassifiedCount: unknown[date] ?? 0)
        }
    }
}

/// A completion or a reversal in the order it was saved; a reversal saved at
/// the same moment as a completion comes after it.
private nonisolated struct ActivityHeatmapAction: Comparable {
    var at: Date
    var id: UUID?
    var entry: ActivityCompletion?

    static func < (left: Self, right: Self) -> Bool {
        if left.at != right.at { return left.at < right.at }
        if (left.entry == nil) != (right.entry == nil) { return right.entry == nil }
        return (left.id?.uuidString ?? "") < (right.id?.uuidString ?? "")
    }

    static func == (left: Self, right: Self) -> Bool {
        left.at == right.at && left.id == right.id && (left.entry == nil) == (right.entry == nil)
    }
}
