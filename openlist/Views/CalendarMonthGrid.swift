import Foundation

/// Calendar arithmetic shared by the full-width date grid and its checks.
/// Add calendar days, never fixed seconds, so DST cannot duplicate or skip cells.
nonisolated enum CalendarMonthGrid {
    static func days(in month: Date, calendar: Calendar) -> [Date] {
        guard let start = calendar.dateInterval(of: .month, for: month)?.start else { return [] }
        let offset = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        guard let first = calendar.date(byAdding: .day, value: -offset, to: start) else { return [] }
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
    }

    /// Whether `day` comes before the day of `earliest`, so it can't be picked.
    static func isBefore(_ day: Date, earliest: Date?, calendar: Calendar) -> Bool {
        guard let earliest else { return false }
        return calendar.startOfDay(for: day) < calendar.startOfDay(for: earliest)
    }

    /// The wall-clock time of `date`, in minutes after midnight.
    static func minute(of date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// `day` at `minute` after midnight on the wall clock, and never before
    /// `earliest`. A time a clock change skips becomes the next one there is.
    static func date(_ day: Date, atMinute minute: Int, notBefore earliest: Date? = nil, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: day)
        let minute = min(max(minute, 0), 1439)
        let date = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: start) ?? start
        return earliest.map { max($0, date) } ?? date
    }
}
