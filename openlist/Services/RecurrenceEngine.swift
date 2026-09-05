//
//  RecurrenceEngine.swift
//  openlist
//

import Foundation

/// Computes when a repeating task is next due.
enum RecurrenceEngine {
    /// The next due date for `rule`, or `nil` when the rule has run out.
    ///
    /// - Parameters:
    ///   - dueDate: the occurrence being completed. When a repeating task has
    ///     never had a date, the caller passes the completion date.
    ///   - completedAt: when the user actually ticked it off, used by rules
    ///     anchored to completion rather than the schedule.
    static func nextDate(
        rule: Recurrence,
        dueDate: Date?,
        completedAt: Date = .now,
        calendar: Calendar = .current
    ) -> Date? {
        guard !rule.isFinished else { return nil }

        let anchor: Date
        switch rule.anchor {
        case .dueDate:
            anchor = dueDate ?? completedAt
        case .completionDate:
            // Keep the original time of day but move to the completion day.
            if let dueDate {
                anchor = transplantTime(of: dueDate, onto: completedAt, calendar: calendar)
            } else {
                anchor = completedAt
            }
        }

        guard var candidate = advance(anchor, by: rule, calendar: calendar) else { return nil }

        // A schedule-anchored rule that has fallen behind catches up to the
        // future rather than emitting a string of past-due occurrences.
        if rule.anchor == .dueDate {
            var guardCount = 0
            while candidate <= completedAt, guardCount < 1_000 {
                guard let next = advance(candidate, by: rule, calendar: calendar) else { return nil }
                candidate = next
                guardCount += 1
            }
        }

        if let endDate = rule.endDate, candidate > endDate { return nil }
        return candidate
    }

    /// One step forward from `date` under `rule`.
    private static func advance(_ date: Date, by rule: Recurrence, calendar: Calendar) -> Date? {
        let interval = max(1, rule.interval)

        switch rule.frequency {
        case .daily:
            return calendar.date(byAdding: .day, value: interval, to: date)

        case .weekly:
            guard !rule.weekdays.isEmpty else {
                return calendar.date(byAdding: .weekOfYear, value: interval, to: date)
            }
            return nextWeekdayOccurrence(after: date, rule: rule, interval: interval, calendar: calendar)

        case .monthly:
            guard var next = calendar.date(byAdding: .month, value: interval, to: date) else { return nil }
            // `dayOfMonth` is what stops a series that started on the 31st from
            // sticking on the 28th: each step clamps from the intended day
            // rather than from the previous (already clamped) result. `Store`
            // pins it when the rule is created.
            if let dayOfMonth = rule.dayOfMonth {
                next = clampDay(dayOfMonth, in: next, calendar: calendar) ?? next
            }
            return next

        case .yearly:
            return calendar.date(byAdding: .year, value: interval, to: date)
        }
    }

    /// Walks forward day by day to the next weekday named by the rule,
    /// honouring an every-N-weeks interval.
    private static func nextWeekdayOccurrence(
        after date: Date,
        rule: Recurrence,
        interval: Int,
        calendar: Calendar
    ) -> Date? {
        let anchorWeek = startOfWeek(containing: date, calendar: calendar)

        for offset in 1...(7 * interval + 7) {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: date) else { continue }
            let weekday = calendar.component(.weekday, from: candidate)
            guard rule.weekdays.contains(weekday) else { continue }

            guard interval > 1 else { return candidate }

            // Count whole weeks between the two containing weeks. Deriving this
            // from week-of-year numbers assumes 52 weeks per year and drifts a
            // week every time the series crosses a 53-week year.
            let weeksApart = calendar.dateComponents(
                [.weekOfYear],
                from: anchorWeek,
                to: startOfWeek(containing: candidate, calendar: calendar)
            ).weekOfYear ?? 0
            if weeksApart % interval == 0 { return candidate }
        }
        return nil
    }

    private static func startOfWeek(containing date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    private static func clampDay(_ day: Int, in date: Date, calendar: Calendar) -> Date? {
        guard let range = calendar.range(of: .day, in: .month, for: date) else { return nil }
        var components = calendar.dateComponents([.year, .month, .hour, .minute, .second], from: date)
        components.day = min(day, range.upperBound - 1)
        return calendar.date(from: components)
    }

    private static func transplantTime(of source: Date, onto target: Date, calendar: Calendar) -> Date {
        let time = calendar.dateComponents([.hour, .minute, .second], from: source)
        var components = calendar.dateComponents([.year, .month, .day], from: target)
        components.hour = time.hour
        components.minute = time.minute
        components.second = time.second
        return calendar.date(from: components) ?? target
    }

    /// Preview of the next few occurrences, shown in the repeat picker.
    static func upcoming(rule: Recurrence, from dueDate: Date?, count: Int = 3) -> [Date] {
        var results: [Date] = []
        var cursor = dueDate
        var workingRule = rule

        for _ in 0..<count {
            guard let next = nextDate(rule: workingRule, dueDate: cursor, completedAt: cursor ?? .now) else { break }
            results.append(next)
            cursor = next
            workingRule.completedOccurrences += 1
            if workingRule.isFinished { break }
        }
        return results
    }
}
