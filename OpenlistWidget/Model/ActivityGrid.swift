//
//  ActivityGrid.swift
//  OpenlistWidget
//

import Foundation

/// One day of the heatmap.
nonisolated struct ActivityCell: Equatable, Identifiable, Sendable {
    /// Start of the day.
    var date: Date
    /// Completions that day; `nil` for days still to come this week.
    var count: Int?
    var isToday: Bool

    var id: Date { date }
    var isFuture: Bool { count == nil }
    /// 0...4, the same bands as the Activity screen.
    var band: Int { ActivityGrid.band(count ?? 0) }
}

/// The heatmap's columns, built from the days the app publishes.
nonisolated enum ActivityGrid {
    /// `weeks` columns of seven days, oldest first, ending with the current
    /// week. Days before the published history count as zero.
    static func weeks(_ weeks: Int, activity: WidgetSnapshot.Activity, now: Date, calendar: Calendar = .current) -> [[ActivityCell]] {
        let counts = ActivityDays(activity, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        guard weeks > 0, let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start else { return [] }
        return (0..<weeks).map { column in
            let weekOffset = column - (weeks - 1)
            return (0..<7).compactMap { weekday -> ActivityCell? in
                guard let day = calendar.date(byAdding: .day, value: weekOffset * 7 + weekday, to: thisWeek) else { return nil }
                return ActivityCell(date: day, count: day > today ? nil : counts[day], isToday: day == today)
            }
        }
    }

    /// 0 for none, then 1, 2–3, 4–6 and 7 or more: the Activity screen's
    /// legend, defined once in `Shared/ActivityBand.swift`.
    static func band(_ count: Int) -> Int { ActivityBand.level(count) }
}

/// The figures under the heatmap: "2 today · 2 this week · 49 in September",
/// and the streak.
nonisolated struct ActivityStats: Equatable, Sendable {
    var today: Int
    var week: Int
    var month: Int
    /// Consecutive days with a completion, ending today. Today does not break
    /// it while it is still empty.
    var streak: Int
    /// "September".
    var monthName: String

    /// Derived from the days rather than the published totals, so they stay
    /// right when a widget renders after midnight without the app running.
    init(activity: WidgetSnapshot.Activity, now: Date, calendar: Calendar = .current) {
        monthName = WidgetFormat.monthName(now, calendar: calendar)
        guard let first = activity.days.first.map({ calendar.startOfDay(for: $0.date) }) else {
            today = activity.today
            week = activity.week
            month = activity.month
            streak = activity.streak
            return
        }
        let counts = ActivityDays(activity, calendar: calendar)
        let day = calendar.startOfDay(for: now)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: day)?.start ?? day
        today = counts[day]
        week = counts.sum { $0 >= weekStart && $0 <= day }
        month = counts.sum { $0 <= day && calendar.isDate($0, equalTo: day, toGranularity: .month) }

        var streak = 0
        var cursor = day
        var reachedStart = false
        while cursor >= first {
            if counts[cursor] > 0 {
                streak += 1
            } else if cursor != day {
                break
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
            reachedStart = cursor < first
        }
        // A streak running past the published history is longer than the
        // days can show; the app's own figure covers the rest.
        self.streak = reachedStart ? max(streak, activity.streak) : streak
    }
}

/// One bar of Summary's "This week".
nonisolated struct SummaryDay: Equatable, Identifiable, Sendable {
    /// Start of the day.
    var date: Date
    /// "M".
    var letter: String
    /// Completions; `nil` for days still to come.
    var count: Int?
    var isToday: Bool

    var id: Date { date }
}

nonisolated enum SummaryWeek {
    /// The current week from the app's first weekday.
    static func days(activity: WidgetSnapshot.Activity, now: Date, calendar: Calendar = .current) -> [SummaryDay] {
        let counts = ActivityDays(activity, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.dateInterval(of: .weekOfYear, for: today)?.start else { return [] }
        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let letter = calendar.veryShortStandaloneWeekdaySymbols[calendar.component(.weekday, from: day) - 1]
            return SummaryDay(date: day, letter: letter, count: day > today ? nil : counts[day], isToday: day == today)
        }
    }
}

/// Published day counts keyed by the start of each day.
private nonisolated struct ActivityDays {
    private var counts: [Date: Int] = [:]

    init(_ activity: WidgetSnapshot.Activity, calendar: Calendar) {
        for day in activity.days {
            counts[calendar.startOfDay(for: day.date), default: 0] += day.count
        }
    }

    subscript(day: Date) -> Int { counts[day] ?? 0 }

    func sum(where include: (Date) -> Bool) -> Int {
        counts.reduce(0) { include($1.key) ? $0 + $1.value : $0 }
    }
}
