import Foundation

/// The days the Calendar shows. The grid, Plan and "Not planned yet" share
/// them, so a planned block always lands where it can be seen.
enum CalendarWeek {
    /// Day and 3 days start today. Week is the week around today that starts
    /// on `calendar`'s first weekday, the "Week starts on" setting.
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

    /// The tasks the calendar gives a block that isn't done: running work,
    /// paused work, or a placement that ends in the Week view's week or later.
    /// A missed slot earlier in the week still counts, drawn as carried
    /// forward; one from before it can't be seen anywhere, so it no longer does.
    static func placedTaskIDs(_ blocks: [PlannedBlock], now: Date, calendar: Calendar) -> Set<UUID> {
        let start = span(from: now, calendar: calendar).start
        return Set(blocks.filter { !$0.isCompleted && ($0.isActive || $0.end > start) }.map(\.taskID))
    }
}
