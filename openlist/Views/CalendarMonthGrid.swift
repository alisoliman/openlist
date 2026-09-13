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
}
