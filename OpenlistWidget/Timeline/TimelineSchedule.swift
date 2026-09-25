//
//  TimelineSchedule.swift
//  OpenlistWidget
//

import Foundation

/// When each kind of widget needs a fresh entry.
///
/// Widgets cannot run code on their own, so anything that changes with the
/// clock (a task turning late, the Up Next countdown, the agenda's now line)
/// has to be an entry prepared in advance. The app reloads the timelines a
/// change affects: every widget for tasks, counts and lists; only Up Next and
/// Agenda when just the plan moved, at most every quarter hour while the app
/// is in the background. These dates cover the time in between.
nonisolated enum TimelineSchedule {
    /// Entries far enough apart to stay inside WidgetKit's budget.
    static let maximumEntries = 120

    /// Now, the moment each timed task still due today turns late, each
    /// moment an Inbox capture's age label changes ("now", "15m", "2h"), and
    /// each moment a pending tap stops being drawn.
    static func snapshotDates(for snapshot: WidgetSnapshot, pending: [WidgetCommand] = [], now: Date, calendar: Calendar = .current) -> [Date] {
        // Every task behind the due-today count, not just the rows shown, so
        // the counters move on time as well as the rows.
        let turns = snapshot.dueToday.compactMap { due -> Date? in
            guard due.includesTime, due.date > now, calendar.isDate(due.date, inSameDayAs: now) else { return nil }
            return due.date
        }
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let ages = snapshot.inboxItems.flatMap { ageChanges(of: $0.createdAt, after: now, until: midnight) }
        return tidy([now] + turns + ages + expiries(of: pending, after: now, calendar: calendar), now: now)
    }

    /// Up Next: a minute at a time for the next 90 minutes while a block
    /// counts down or work is recording, plus every start and end today and
    /// each moment a pending tap stops being drawn.
    static func upNextDates(for snapshot: WidgetSnapshot, pending: [WidgetCommand] = [], now: Date, calendar: Calendar = .current) -> [Date] {
        let boundaries = boundaries(of: snapshot, after: now, calendar: calendar) + expiries(of: pending, after: now, calendar: calendar)
        let hasBlocksLeft = snapshot.agenda.contains {
            $0.kind == .task && !$0.isCompleted && $0.end > now && calendar.isDate($0.start, inSameDayAs: now)
        }
        // Recording work fills its bar and, without work, a block under way or
        // ahead counts down. Paused work holds still, and so does a clear day:
        // only the boundaries change what the widget shows.
        let movesEachMinute = snapshot.work.map { $0.state == .working } ?? hasBlocksLeft
        guard movesEachMinute else { return tidy([now] + boundaries, now: now) }
        let horizon = now.addingTimeInterval(90 * 60)
        let minutes = steps(from: now, every: 60, until: horizon, calendar: calendar)
        return tidy([now] + minutes + boundaries.filter { $0 <= horizon }, now: now)
    }

    /// When Up Next's timeline runs out: its last entry, or tomorrow when the
    /// day's plan is over.
    static func upNextReload(after dates: [Date], now: Date, calendar: Calendar = .current) -> Date {
        let last = dates.last ?? now
        return last > now ? last : nextDay(after: now, calendar: calendar)
    }

    /// Agenda: every quarter hour until midnight, so the now line moves, plus
    /// every start and end today and each moment a pending tap stops being drawn.
    static func agendaDates(for snapshot: WidgetSnapshot, pending: [WidgetCommand] = [], now: Date, calendar: Calendar = .current) -> [Date] {
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let quarters = steps(from: now, every: 15 * 60, until: midnight, calendar: calendar)
        return tidy([now] + quarters + boundaries(of: snapshot, after: now, calendar: calendar)
            + expiries(of: pending, after: now, calendar: calendar), now: now)
    }

    /// When a timeline that covers the rest of the day runs out: a minute
    /// past midnight, or its last entry when the entry cap cut the day short.
    static func reload(after dates: [Date], now: Date, calendar: Calendar = .current) -> Date {
        let tomorrow = nextDay(after: now, calendar: calendar)
        guard dates.count >= maximumEntries, let last = dates.last, last > now else { return tomorrow }
        return min(last, tomorrow)
    }

    /// A minute past the coming midnight, when "today" itself changes.
    static func nextDay(after now: Date, calendar: Calendar = .current) -> Date {
        calendar.nextDate(after: now, matching: DateComponents(hour: 0, minute: 1), matchingPolicy: .nextTime)
            ?? now.addingTimeInterval(3600)
    }

    // MARK: - Building blocks

    /// Starts and ends of today's meetings and blocks still ahead.
    private static func boundaries(of snapshot: WidgetSnapshot, after now: Date, calendar: Calendar) -> [Date] {
        snapshot.agenda
            .filter { calendar.isDate($0.start, inSameDayAs: now) }
            .flatMap { [$0.start, $0.end] }
            .filter { $0 > now && calendar.isDate($0, inSameDayAs: now) }
    }

    /// When each tap still waiting for the app expires today. The app drops
    /// it then, so the widget stops drawing it at that entry rather than
    /// showing it until the next reload.
    private static func expiries(of pending: [WidgetCommand], after now: Date, calendar: Calendar) -> [Date] {
        pending.map(\.expiry).filter { $0 > now && calendar.isDate($0, inSameDayAs: now) }
    }

    /// Each moment after `now`, up to `end`, when a capture's age label changes.
    private static func ageChanges(of created: Date, after now: Date, until end: Date) -> [Date] {
        var result: [Date] = []
        var next = WidgetFormat.ageChange(of: created, after: now)
        while next <= end, result.count < maximumEntries {
            result.append(next)
            next = WidgetFormat.ageChange(of: created, after: next)
        }
        return result
    }

    /// Clock-aligned steps after `now`: 10:41, 10:42… or 10:45, 11:00…
    private static func steps(from now: Date, every interval: TimeInterval, until end: Date, calendar: Calendar) -> [Date] {
        let dayStart = calendar.startOfDay(for: now)
        let elapsed = now.timeIntervalSince(dayStart)
        var next = dayStart.addingTimeInterval((elapsed / interval).rounded(.down) * interval + interval)
        var result: [Date] = []
        while next <= end, result.count < maximumEntries {
            result.append(next)
            next = next.addingTimeInterval(interval)
        }
        return result
    }

    /// Sorted, without duplicates or past dates, and capped.
    private static func tidy(_ dates: [Date], now: Date) -> [Date] {
        Array(Set(dates.filter { $0 >= now })).sorted().prefix(maximumEntries).map { $0 }
    }
}
