import Foundation

/// The days the Calendar shows. The grid, Plan and "Not planned yet" share
/// them, so a planned block always lands where it can be seen.
enum CalendarWeek {
    /// Day and 3 days start today. Week is the week around today that starts
    /// on `calendar`'s first weekday, the "Week starts on" setting. Given
    /// another day, they show that day instead of today.
    static func days(count: Int, from now: Date, calendar: Calendar) -> [Date] {
        let today = calendar.startOfDay(for: now)
        let offset = count == 7 ? (calendar.component(.weekday, from: today) - calendar.firstWeekday + 7) % 7 : 0
        guard let first = calendar.date(byAdding: .day, value: -offset, to: today) else { return [] }
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
    }

    /// The Week view's span, from the start of its first day to the end of its last.
    static func span(from now: Date, calendar: Calendar) -> DateInterval {
        let days = days(count: 7, from: now, calendar: calendar)
        let start = days.first ?? calendar.startOfDay(for: now)
        let end = days.last.flatMap { calendar.date(byAdding: .day, value: 1, to: $0) } ?? start
        return DateInterval(start: start, end: max(start, end))
    }

    /// The day the Calendar shows its range from after stepping `step` ranges
    /// on (or back) from `days`: a day, three days or a week at a time. Nil
    /// once that range is the one around today again, which it then follows.
    static func anchor(stepping days: [Date], by step: Int, now: Date, calendar: Calendar) -> Date? {
        guard let first = days.first,
              let day = calendar.date(byAdding: .day, value: step * days.count, to: first) else { return nil }
        return anchor(showing: day, count: days.count, now: now, calendar: calendar)
    }

    /// The day the Calendar shows its range from so that `day` is in it: nil
    /// when the range around today has it.
    static func anchor(showing day: Date, count: Int, now: Date, calendar: Calendar) -> Date? {
        let current = days(count: count, from: now, calendar: calendar)
        return current.contains { calendar.isDate($0, inSameDayAs: day) } ? nil : calendar.startOfDay(for: day)
    }

    /// Where Plan puts a task of `duration`: the first free quarter hour in
    /// its list's hours, clear of `busy`, from now or its deferral. As the
    /// design's Plan, it looks no further than the week around today while
    /// that week still has hours long enough for the task; once none are
    /// left, it goes on into the next week. A deferral past this week gets a
    /// week of its own.
    static func slot(duration: TimeInterval, deferredUntil: Date?, category: AvailabilityCategory,
                     preferences: CalendarPreferences, busy: [DateInterval], now: Date, calendar: Calendar) -> PlanSlot {
        let quarter: TimeInterval = 15 * 60
        let from = max(now, deferredUntil ?? now)
        // On a quarter hour, not before a deferral, and only inside the list's hours:
        // the scheduler's windows already leave out breaks, overrides and days off,
        // and follow the wall clock across DST.
        let earliest = Date(timeIntervalSinceReferenceDate: (from.timeIntervalSinceReferenceDate / quarter).rounded(.up) * quarter)
        func hours(to end: Date) -> [DateInterval] {
            earliest < end ? AdaptiveScheduler.availabilityIntervals(for: category, preferences: preferences,
                                                                    from: earliest, to: end, calendar: calendar) : []
        }
        func first(in windows: [DateInterval]) -> DateInterval? {
            for window in windows {
                var start = window.start
                while start.addingTimeInterval(duration) <= window.end {
                    let slot = DateInterval(start: start, duration: duration)
                    if !busy.contains(where: { $0.start < slot.end && slot.start < $0.end }) { return slot }
                    start = start.addingTimeInterval(quarter)
                }
            }
            return nil
        }
        let week = span(from: now, calendar: calendar)
        if let deferredUntil, deferredUntil >= week.end {
            let end = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: earliest)) ?? earliest
            return first(in: hours(to: end)).map(PlanSlot.found) ?? .none(.weekFrom(from))
        }
        let thisWeek = hours(to: week.end)
        if let slot = first(in: thisWeek) { return .found(slot) }
        // Hours long enough are left this week, only taken: no further, as the design.
        if thisWeek.contains(where: { $0.duration >= duration }) { return .none(.thisWeek) }
        let nextWeekEnd = calendar.date(byAdding: .day, value: 7, to: week.end) ?? week.end
        return first(in: hours(to: nextWeekEnd)).map(PlanSlot.found) ?? .none(.nextWeek)
    }

    /// The tasks the calendar gives a block that isn't done: running work,
    /// paused work, or a placement that ends in the week around today or
    /// later. A missed slot earlier in the week still counts, drawn as
    /// carried forward; one from an earlier week no longer does, so the task
    /// can be planned again.
    static func placedTaskIDs(_ blocks: [PlannedBlock], now: Date, calendar: Calendar) -> Set<UUID> {
        let start = span(from: now, calendar: calendar).start
        return Set(blocks.filter { !$0.isCompleted && ($0.isActive || $0.end > start) }.map(\.taskID))
    }
}

/// Where Plan put a task, or how far it looked for a free slot.
enum PlanSlot: Equatable {
    case found(DateInterval)
    case none(Reach)

    enum Reach: Equatable {
        /// The week around today, which still has hours long enough, all taken.
        case thisWeek
        /// This week, out of hours long enough, and the next.
        case nextWeek
        /// The week from a deferral past this one.
        case weekFrom(Date)
    }
}
