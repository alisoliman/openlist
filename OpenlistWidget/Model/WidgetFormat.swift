//
//  WidgetFormat.swift
//  OpenlistWidget
//

import Foundation

/// The wording widgets use for dates, times and durations.
///
/// Clock times are always 24-hour "HH:mm", like the rest of the Next
/// interface. Day and month names come from the calendar's locale, so tests
/// can pin them with a fixed calendar.
nonisolated enum WidgetFormat {
    // MARK: - Due dates

    /// "3d late", "10:00", "Repeats", "Today", "Tomorrow", "Sat 26", "3 Oct",
    /// or "Done". Empty when the task has no date.
    static func dueText(for item: WidgetSnapshot.Item, now: Date, calendar: Calendar = .current) -> String {
        if item.isCompleted { return "Done" }
        guard let due = item.dueDate else { return "" }
        let offset = dayOffset(from: now, to: due, calendar: calendar)
        if offset < 0 { return "\(-offset)d late" }
        switch offset {
        case 0:
            if item.includesTime { return clock(due, calendar: calendar) }
            return item.hasRepeat ? "Repeats" : "Today"
        case 1:
            return "Tomorrow"
        case 2...6:
            return dayLabel(due, calendar: calendar)
        default:
            let month = calendar.shortMonthSymbols[calendar.component(.month, from: due) - 1]
            return "\(calendar.component(.day, from: due)) \(month)"
        }
    }

    /// Whole calendar days from `now` to `date`; negative in the past.
    static func dayOffset(from now: Date, to date: Date, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: start, to: day).day ?? 0
    }

    // MARK: - Days

    /// "Sat 26".
    static func dayLabel(_ date: Date, calendar: Calendar = .current) -> String {
        let weekday = calendar.shortWeekdaySymbols[calendar.component(.weekday, from: date) - 1]
        return "\(weekday) \(calendar.component(.day, from: date))"
    }

    /// "Wednesday".
    static func weekdayName(_ date: Date, calendar: Calendar = .current) -> String {
        calendar.weekdaySymbols[calendar.component(.weekday, from: date) - 1]
    }

    /// "September".
    static func monthName(_ date: Date, calendar: Calendar = .current) -> String {
        calendar.standaloneMonthSymbols[calendar.component(.month, from: date) - 1]
    }

    /// "21 – 27 September", or "28 September – 4 October" across a month end.
    static func weekRange(from start: Date, calendar: Calendar = .current) -> String {
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        let startDay = calendar.component(.day, from: start)
        let endDay = calendar.component(.day, from: end)
        if calendar.isDate(start, equalTo: end, toGranularity: .month) {
            return "\(startDay) – \(endDay) \(monthName(end, calendar: calendar))"
        }
        return "\(startDay) \(monthName(start, calendar: calendar)) – \(endDay) \(monthName(end, calendar: calendar))"
    }

    // MARK: - Times

    /// "09:30".
    static func clock(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// "10:00–11:30".
    static func range(_ start: Date, _ end: Date, calendar: Calendar = .current) -> String {
        "\(clock(start, calendar: calendar))–\(clock(end, calendar: calendar))"
    }

    /// "50 min left". Never says zero while the block is still running.
    static func minutesLeft(until end: Date, now: Date) -> String {
        "\(max(1, minutes(from: now, to: end))) min left"
    }

    /// "in 50 min".
    static func minutesUntil(_ start: Date, now: Date) -> String {
        "in \(max(1, minutes(from: now, to: start))) min"
    }

    /// How long ago an Inbox capture arrived: "now", "15m", "2h", "1d".
    ///
    /// Minutes count in fives. A widget only redraws at its timeline's
    /// entries, and `ageChange(of:after:)` gives one for every change of this
    /// label, so a finer label would either be wrong between entries or cost
    /// an entry a minute.
    static func age(of date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<300: return "now"
        case ..<3600: return "\(Int(seconds / 300) * 5)m"
        case ..<86_400: return "\(Int(seconds / 3600))h"
        default: return "\(Int(seconds / 86_400))d"
        }
    }

    /// The next moment after `now` when `age(of:now:)` reads differently:
    /// every five minutes through the first hour, then on each whole hour
    /// and each whole day since the capture.
    static func ageChange(of date: Date, after now: Date) -> Date {
        let seconds = max(0, now.timeIntervalSince(date))
        let step: TimeInterval = seconds < 3600 ? 300 : seconds < 86_400 ? 3600 : 86_400
        return date.addingTimeInterval(((seconds / step).rounded(.down) + 1) * step)
    }

    // MARK: - Labels

    /// "🗻 Weekend in Kyoto". Vibrant rendering drops the emoji, which would
    /// otherwise turn into a grey smudge.
    static func listLine(icon: String, name: String, includesIcon: Bool = true) -> String {
        guard includesIcon, !icon.isEmpty else { return name }
        return name.isEmpty ? icon : "\(icon) \(name)"
    }

    /// "1 meeting", "4 meetings".
    static func count(_ value: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(value) \(value == 1 ? singular : plural ?? singular + "s")"
    }

    /// Rounded to the nearest minute, as the design's "50 min left" is.
    private static func minutes(from start: Date, to end: Date) -> Int {
        Int((end.timeIntervalSince(start) / 60).rounded())
    }
}
