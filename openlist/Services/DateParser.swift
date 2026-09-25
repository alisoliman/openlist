//
//  DateParser.swift
//  openlist
//

import Foundation

/// The result of scanning free text for scheduling information.
struct ParsedSchedule: Equatable {
    var date: Date?
    var includesTime: Bool = false
    var recurrence: Recurrence?
    /// Ranges of the input that were consumed, so a caller can take exactly
    /// those spans out of the text it holds.
    var consumedRanges: [NSRange] = []
    /// What each of `consumedRanges` was read as, in the same order, so a
    /// caller can mark up the repeat rule, day and time it found.
    var consumedParts: [Part] = []

    enum Part: Equatable { case recurrence, day, time }

    var isEmpty: Bool { date == nil && recurrence == nil }
}

/// Recognises natural-language dates, times and repeat rules inside task text.
///
/// In "call mum tomorrow at 6pm" it finds a due date and time and reports
/// where the phrases are (`consumedRanges`, `consumedParts`); callers such as
/// `CaptureParse` mark them up and take them out of the title. Matching is
/// deliberately conservative: only unambiguous phrases are consumed so
/// ordinary prose such as "may" or "march" survives untouched.
enum DateParser {
    /// Scans `text` and returns everything it recognised.
    ///
    /// - Parameter reference: the "now" the phrases are relative to.
    static func parse(_ text: String, reference: Date = .now) -> ParsedSchedule {
        let ns = text as NSString
        var consumed: [NSRange] = []

        let recurrence = matchRecurrence(in: ns, consumed: &consumed)
        // Ranges consumed by the repeat rule must not be mistaken for a day
        // phrase when deciding whether a bare past time rolls to tomorrow.
        let consumedByRecurrence = consumed.count
        var day = matchDay(in: ns, reference: reference, consumed: &consumed)
        let consumedByDay = consumed.count
        let time = matchTime(in: ns, consumed: &consumed)

        // "at 6pm" on its own means today, or tomorrow if that time has passed.
        if day == nil, time != nil {
            day = Calendar.current.startOfDay(for: reference)
        }
        // A repeat rule with no explicit day starts today — except a rule that
        // names weekdays, which should start on the first day it actually
        // matches. "every monday" typed on a Saturday means next Monday.
        if day == nil, let recurrence {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: reference)
            if recurrence.frequency == .weekly, !recurrence.weekdays.isEmpty {
                day = firstMatchingDay(from: today, weekdays: recurrence.weekdays, calendar: calendar)
            } else {
                day = today
            }
        }

        var resolved: Date?
        var includesTime = false
        if let day {
            if let time {
                // A day phrase was matched only if something beyond the repeat
                // rule and the time itself was consumed.
                let hadExplicitDay = consumed.count > consumedByRecurrence + 1
                resolved = combine(day: day, time: time, reference: reference, hadExplicitDay: hadExplicitDay)
                includesTime = true
            } else {
                resolved = Calendar.current.startOfDay(for: day)
            }
        }

        var recurrenceResult = recurrence
        // Weekly rules typed as "every tuesday" carry their weekday from the
        // day phrase when the rule itself did not name one.
        if var rule = recurrenceResult, rule.frequency == .weekly, rule.weekdays.isEmpty, let resolved {
            rule.weekdays = [Calendar.current.component(.weekday, from: resolved)]
            recurrenceResult = rule
        }

        return ParsedSchedule(
            date: resolved,
            includesTime: includesTime,
            recurrence: recurrenceResult,
            consumedRanges: consumed,
            consumedParts: consumed.indices.map {
                $0 < consumedByRecurrence ? .recurrence : $0 < consumedByDay ? .day : .time
            }
        )
    }

    // MARK: - Day phrases

    private struct TimeOfDay: Equatable {
        var hour: Int
        var minute: Int
    }

    private static func matchDay(in ns: NSString, reference: Date, consumed: inout [NSRange]) -> Date? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: reference)

        // Relative keywords, longest first so "the day after tomorrow" wins.
        let keywords: [(String, (Date) -> Date?)] = [
            ("the day after tomorrow", { calendar.date(byAdding: .day, value: 2, to: $0) }),
            ("day after tomorrow", { calendar.date(byAdding: .day, value: 2, to: $0) }),
            ("next weekend", { nextWeekend(after: $0, calendar: calendar) }),
            ("this weekend", { upcomingWeekend(from: $0, calendar: calendar) }),
            // Next Monday, the start of next week, as the design's capture reads it.
            ("next week", { nextOccurrence(of: 2, from: $0, calendar: calendar, skipToday: true) }),
            ("next month", { calendar.date(byAdding: .month, value: 1, to: $0) }),
            ("next year", { calendar.date(byAdding: .year, value: 1, to: $0) }),
            ("end of week", { endOfWeek(from: $0, calendar: calendar) }),
            ("end of month", { endOfMonth(from: $0, calendar: calendar) }),
            ("tomorrow", { calendar.date(byAdding: .day, value: 1, to: $0) }),
            ("tmrw", { calendar.date(byAdding: .day, value: 1, to: $0) }),
            ("tmr", { calendar.date(byAdding: .day, value: 1, to: $0) }),
            ("yesterday", { calendar.date(byAdding: .day, value: -1, to: $0) }),
            ("today", { $0 }),
            // A day with no time of its own: due today, like the design's capture.
            ("tonight", { $0 }),
        ]

        for (phrase, transform) in keywords {
            if let range = firstMatch(pattern: "\\b\(NSRegularExpression.escapedPattern(for: phrase))\\b", in: ns, avoiding: consumed) {
                consumed.append(range)
                return transform(today)
            }
        }

        // "in 3 days", "in two weeks"
        if let (range, value, unit) = matchRelativeOffset(in: ns, avoiding: consumed) {
            consumed.append(range)
            return calendar.date(byAdding: unit, value: value, to: unit == .hour || unit == .minute ? reference : today)
        }

        // "next monday", "on friday", "monday"
        if let (range, weekday, forceNext) = matchWeekday(in: ns, avoiding: consumed) {
            consumed.append(range)
            return nextOccurrence(of: weekday, from: today, calendar: calendar, skipToday: forceNext)
        }

        // Numeric and month-name dates.
        if let result = matchExplicitDate(in: ns, reference: reference, consumed: &consumed) {
            return result
        }

        return nil
    }

    private static func matchRelativeOffset(
        in ns: NSString,
        avoiding consumed: [NSRange]
    ) -> (NSRange, Int, Calendar.Component)? {
        let pattern = "\\bin\\s+(\\d+|a|an|one|two|three|four|five|six|seven|eight|nine|ten)\\s+(minute|min|hour|hr|day|week|month|year)s?\\b"
        guard let match = firstMatchResult(pattern: pattern, in: ns, avoiding: consumed) else { return nil }

        let amountText = ns.substring(with: match.range(at: 1)).lowercased()
        let unitText = ns.substring(with: match.range(at: 2)).lowercased()
        guard let amount = numberValue(amountText) else { return nil }

        let component: Calendar.Component
        switch unitText {
        case "minute", "min": component = .minute
        case "hour", "hr": component = .hour
        case "day": component = .day
        case "week": component = .weekOfYear
        case "month": component = .month
        default: component = .year
        }
        return (match.range, amount, component)
    }

    private static func matchWeekday(
        in ns: NSString,
        avoiding consumed: [NSRange]
    ) -> (NSRange, Int, Bool)? {
        let names = "sunday|sun|monday|mon|tuesday|tue|tues|wednesday|wed|thursday|thu|thur|thurs|friday|fri|saturday|sat"
        let pattern = "\\b(next|this|on|coming)?\\s*(\(names))\\b"
        guard let match = firstMatchResult(pattern: pattern, in: ns, avoiding: consumed) else { return nil }

        let qualifier = match.range(at: 1).location == NSNotFound
            ? ""
            : ns.substring(with: match.range(at: 1)).lowercased()
        let name = ns.substring(with: match.range(at: 2)).lowercased()
        guard let weekday = weekdayValue(name) else { return nil }
        return (match.range, weekday, qualifier == "next" || qualifier == "coming")
    }

    private static func matchExplicitDate(
        in ns: NSString,
        reference: Date,
        consumed: inout [NSRange]
    ) -> Date? {
        let calendar = Calendar.current
        let months = "january|jan|february|feb|march|mar|april|apr|may|june|jun|july|jul|august|aug|september|sept|sep|october|oct|november|nov|december|dec"

        // ISO style: 2026-12-25
        if let match = firstMatchResult(pattern: "\\b(\\d{4})-(\\d{1,2})-(\\d{1,2})\\b", in: ns, avoiding: consumed) {
            var components = DateComponents()
            components.year = Int(ns.substring(with: match.range(at: 1)))
            components.month = Int(ns.substring(with: match.range(at: 2)))
            components.day = Int(ns.substring(with: match.range(at: 3)))
            if let date = calendar.date(from: components) {
                consumed.append(match.range)
                return date
            }
        }

        // "25 Dec", "25 December 2026"
        if let match = firstMatchResult(pattern: "\\b(\\d{1,2})(?:st|nd|rd|th)?\\s+(\(months))\\.?\\s*(\\d{4})?\\b", in: ns, avoiding: consumed) {
            let day = Int(ns.substring(with: match.range(at: 1)))
            let month = monthValue(ns.substring(with: match.range(at: 2)).lowercased())
            let year = match.range(at: 3).location == NSNotFound ? nil : Int(ns.substring(with: match.range(at: 3)))
            if let date = resolveDate(day: day, month: month, year: year, reference: reference, calendar: calendar) {
                consumed.append(match.range)
                return date
            }
        }

        // "Dec 25", "December 25th 2026"
        if let match = firstMatchResult(pattern: "\\b(\(months))\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?(?:,?\\s*(\\d{4}))?\\b", in: ns, avoiding: consumed) {
            let month = monthValue(ns.substring(with: match.range(at: 1)).lowercased())
            let day = Int(ns.substring(with: match.range(at: 2)))
            let year = match.range(at: 3).location == NSNotFound ? nil : Int(ns.substring(with: match.range(at: 3)))
            if let date = resolveDate(day: day, month: month, year: year, reference: reference, calendar: calendar) {
                consumed.append(match.range)
                return date
            }
        }

        // Numeric: 25/12 or 12/25/2026, interpreted using the user's locale order.
        // Only "/" is treated as a separator — a dot is far more often a
        // decimal point ("upgrade to swift 6.2", "buy 2.5 kg flour").
        if let match = firstMatchResult(pattern: "\\b(\\d{1,2})/(\\d{1,2})(?:/(\\d{2,4}))?\\b", in: ns, avoiding: consumed) {
            let first = Int(ns.substring(with: match.range(at: 1)))
            let second = Int(ns.substring(with: match.range(at: 2)))
            var year: Int?
            if match.range(at: 3).location != NSNotFound {
                let raw = Int(ns.substring(with: match.range(at: 3))) ?? 0
                year = raw < 100 ? 2_000 + raw : raw
            }

            let monthFirst = localePrefersMonthFirst()
            var day = monthFirst ? second : first
            var month = monthFirst ? first : second
            // Fall back to the other reading when the preferred one is impossible.
            if (month ?? 0) > 12, (day ?? 0) <= 12 { swap(&day, &month) }

            if let date = resolveDate(day: day, month: month, year: year, reference: reference, calendar: calendar) {
                consumed.append(match.range)
                return date
            }
        }

        return nil
    }

    // MARK: - Time phrases

    private static func matchTime(in ns: NSString, consumed: inout [NSRange]) -> TimeOfDay? {
        // Named times.
        let named: [(String, TimeOfDay)] = [
            ("midnight", TimeOfDay(hour: 0, minute: 0)),
            ("noon", TimeOfDay(hour: 12, minute: 0)),
            ("midday", TimeOfDay(hour: 12, minute: 0)),
            ("morning", TimeOfDay(hour: 9, minute: 0)),
            ("afternoon", TimeOfDay(hour: 14, minute: 0)),
            ("evening", TimeOfDay(hour: 18, minute: 0)),
            ("night", TimeOfDay(hour: 20, minute: 0)),
        ]

        // "at 5", "at 5pm", "5:30pm", "17:00", "@ 9am"
        if let match = firstMatchResult(
            pattern: "(?:\\bat\\s+|@\\s*)?\\b(\\d{1,2})(?::(\\d{2}))?\\s*([ap])\\.?m\\.?(?![a-z])",
            in: ns,
            avoiding: consumed
        ) {
            var hour = Int(ns.substring(with: match.range(at: 1))) ?? 0
            let minute = match.range(at: 2).location == NSNotFound ? 0 : Int(ns.substring(with: match.range(at: 2))) ?? 0
            let meridiem = ns.substring(with: match.range(at: 3)).lowercased()
            if meridiem == "p", hour < 12 { hour += 12 }
            if meridiem == "a", hour == 12 { hour = 0 }
            if hour < 24, minute < 60 {
                consumed.append(match.range)
                return TimeOfDay(hour: hour, minute: minute)
            }
        }

        // 24-hour or bare "at 9" — requires the "at"/"@" cue so plain numbers
        // in a task title are never mistaken for a time.
        if let match = firstMatchResult(
            pattern: "(?:\\bat\\s+|@\\s*)(\\d{1,2})(?::(\\d{2}))?\\b",
            in: ns,
            avoiding: consumed
        ) {
            let hour = Int(ns.substring(with: match.range(at: 1))) ?? 0
            let minute = match.range(at: 2).location == NSNotFound ? 0 : Int(ns.substring(with: match.range(at: 2))) ?? 0
            if hour < 24, minute < 60 {
                consumed.append(match.range)
                return TimeOfDay(hour: hour, minute: minute)
            }
        }

        // Bare 24-hour clock such as "18:30".
        if let match = firstMatchResult(pattern: "\\b([01]?\\d|2[0-3]):([0-5]\\d)\\b", in: ns, avoiding: consumed) {
            let hour = Int(ns.substring(with: match.range(at: 1))) ?? 0
            let minute = Int(ns.substring(with: match.range(at: 2))) ?? 0
            consumed.append(match.range)
            return TimeOfDay(hour: hour, minute: minute)
        }

        for (phrase, time) in named {
            let pattern = "\\b(?:in\\s+the\\s+|this\\s+|tomorrow\\s+)?\(NSRegularExpression.escapedPattern(for: phrase))\\b"
            if let range = firstMatch(pattern: pattern, in: ns, avoiding: consumed) {
                consumed.append(range)
                return time
            }
        }

        return nil
    }

    // MARK: - Repeat phrases

    private static func matchRecurrence(in ns: NSString, consumed: inout [NSRange]) -> Recurrence? {
        let names = "sunday|sun|monday|mon|tuesday|tue|tues|wednesday|wed|thursday|thu|thurs|friday|fri|saturday|sat"

        // "every weekday" / "every weekend"
        if let range = firstMatch(pattern: "\\bevery\\s+weekday(?:s)?\\b", in: ns, avoiding: consumed) {
            consumed.append(range)
            return .weekdaysOnly
        }
        if let range = firstMatch(pattern: "\\bevery\\s+weekend(?:s)?\\b", in: ns, avoiding: consumed) {
            consumed.append(range)
            return Recurrence(frequency: .weekly, interval: 1, weekdays: [1, 7])
        }

        // "every monday", "every mon and thu"
        if let match = firstMatchResult(pattern: "\\bevery\\s+((?:\(names))(?:\\s*(?:,|and|&)\\s*(?:\(names)))*)\\b", in: ns, avoiding: consumed) {
            let listText = ns.substring(with: match.range(at: 1)).lowercased()
            let days = listText
                .components(separatedBy: CharacterSet(charactersIn: ",&"))
                .flatMap { $0.components(separatedBy: " and ") }
                .compactMap { weekdayValue($0.trimmingCharacters(in: .whitespaces)) }
            if !days.isEmpty {
                consumed.append(match.range)
                return Recurrence(frequency: .weekly, interval: 1, weekdays: Set(days))
            }
        }

        // "every 2 weeks", "every other day", "every day"
        if let match = firstMatchResult(
            pattern: "\\bevery\\s+(other\\s+|\\d+\\s+|a\\s+|an\\s+)?(day|week|month|year|fortnight)s?\\b",
            in: ns,
            avoiding: consumed
        ) {
            let qualifier = match.range(at: 1).location == NSNotFound
                ? ""
                : ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces).lowercased()
            let unit = ns.substring(with: match.range(at: 2)).lowercased()

            var interval = 1
            if qualifier == "other" { interval = 2 }
            else if let value = numberValue(qualifier), value > 0 { interval = value }

            let frequency: Recurrence.Frequency
            switch unit {
            case "day": frequency = .daily
            case "week": frequency = .weekly
            case "fortnight": frequency = .weekly; interval *= 2
            case "month": frequency = .monthly
            default: frequency = .yearly
            }

            consumed.append(match.range)
            return Recurrence(frequency: frequency, interval: interval)
        }

        // Single-word adverbs.
        let adverbs: [(String, Recurrence)] = [
            ("daily", .daily),
            ("weekly", .weekly),
            ("biweekly", Recurrence(frequency: .weekly, interval: 2)),
            ("fortnightly", Recurrence(frequency: .weekly, interval: 2)),
            ("monthly", .monthly),
            ("quarterly", Recurrence(frequency: .monthly, interval: 3)),
            ("yearly", .yearly),
            ("annually", .yearly),
        ]
        for (word, rule) in adverbs {
            if let range = firstMatch(pattern: "\\b\(word)\\b", in: ns, avoiding: consumed) {
                consumed.append(range)
                return rule
            }
        }

        return nil
    }

    // MARK: - Assembly helpers

    private static func combine(day: Date, time: TimeOfDay, reference: Date, hadExplicitDay: Bool) -> Date? {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = time.hour
        components.minute = time.minute
        guard let candidate = calendar.date(from: components) else { return nil }

        // A bare time that has already passed today rolls to tomorrow.
        if !hadExplicitDay, candidate < reference, calendar.isDate(day, inSameDayAs: reference) {
            return calendar.date(byAdding: .day, value: 1, to: candidate)
        }
        return candidate
    }

    private static func resolveDate(day: Int?, month: Int?, year: Int?, reference: Date, calendar: Calendar) -> Date? {
        guard let day, let month, day >= 1, day <= 31, month >= 1, month <= 12 else { return nil }
        var components = DateComponents()
        components.day = day
        components.month = month
        components.year = year ?? calendar.component(.year, from: reference)
        guard let date = calendar.date(from: components) else { return nil }

        // A bare day/month that already passed this year means next year.
        if year == nil, date < calendar.startOfDay(for: reference) {
            components.year = (components.year ?? 0) + 1
            return calendar.date(from: components)
        }
        return date
    }

    /// The soonest day on or after `start` whose weekday is in `weekdays`.
    private static func firstMatchingDay(from start: Date, weekdays: Set<Int>, calendar: Calendar) -> Date {
        for offset in 0...7 {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            if weekdays.contains(calendar.component(.weekday, from: candidate)) { return candidate }
        }
        return start
    }

    private static func nextOccurrence(of weekday: Int, from date: Date, calendar: Calendar, skipToday: Bool) -> Date? {
        let current = calendar.component(.weekday, from: date)
        var delta = weekday - current
        if delta < 0 { delta += 7 }
        if delta == 0 && skipToday { delta = 7 }
        if delta == 0 && !skipToday { return date }
        return calendar.date(byAdding: .day, value: delta, to: date)
    }

    private static func upcomingWeekend(from date: Date, calendar: Calendar) -> Date? {
        let weekday = calendar.component(.weekday, from: date)
        // During the weekend, "this weekend" still includes today.
        if weekday == 7 || weekday == 1 { return date }
        return nextOccurrence(of: 7, from: date, calendar: calendar, skipToday: false)
    }

    private static func nextWeekend(after date: Date, calendar: Calendar) -> Date? {
        if calendar.component(.weekday, from: date) == 1 {
            return nextOccurrence(of: 7, from: date, calendar: calendar, skipToday: false)
        }
        guard let thisWeekend = upcomingWeekend(from: date, calendar: calendar) else { return nil }
        return calendar.date(byAdding: .day, value: 7, to: thisWeekend)
    }

    private static func endOfWeek(from date: Date, calendar: Calendar) -> Date? {
        nextOccurrence(of: 6, from: date, calendar: calendar, skipToday: false)
    }

    private static func endOfMonth(from date: Date, calendar: Calendar) -> Date? {
        guard let interval = calendar.dateInterval(of: .month, for: date) else { return nil }
        return calendar.date(byAdding: .day, value: -1, to: interval.end)
    }

    // MARK: - Lexicon

    private static func weekdayValue(_ name: String) -> Int? {
        switch name {
        case "sunday", "sun": 1
        case "monday", "mon": 2
        case "tuesday", "tue", "tues": 3
        case "wednesday", "wed": 4
        case "thursday", "thu", "thur", "thurs": 5
        case "friday", "fri": 6
        case "saturday", "sat": 7
        default: nil
        }
    }

    private static func monthValue(_ name: String) -> Int? {
        switch name {
        case "january", "jan": 1
        case "february", "feb": 2
        case "march", "mar": 3
        case "april", "apr": 4
        case "may": 5
        case "june", "jun": 6
        case "july", "jul": 7
        case "august", "aug": 8
        case "september", "sep", "sept": 9
        case "october", "oct": 10
        case "november", "nov": 11
        case "december", "dec": 12
        default: nil
        }
    }

    private static func numberValue(_ text: String) -> Int? {
        if let value = Int(text) { return value }
        switch text {
        case "a", "an", "one": return 1
        case "two": return 2
        case "three": return 3
        case "four": return 4
        case "five": return 5
        case "six": return 6
        case "seven": return 7
        case "eight": return 8
        case "nine": return 9
        case "ten": return 10
        default: return nil
        }
    }

    private static func localePrefersMonthFirst() -> Bool {
        let template = DateFormatter.dateFormat(fromTemplate: "yMd", options: 0, locale: .current) ?? "M/d/y"
        guard let month = template.firstIndex(where: { $0 == "M" }),
              let day = template.firstIndex(where: { $0 == "d" }) else { return true }
        return month < day
    }

    // MARK: - Regex plumbing

    private static let cache = RegexCache(options: [.caseInsensitive])

    private static func firstMatch(pattern: String, in ns: NSString, avoiding consumed: [NSRange]) -> NSRange? {
        firstMatchResult(pattern: pattern, in: ns, avoiding: consumed)?.range
    }

    private static func firstMatchResult(
        pattern: String,
        in ns: NSString,
        avoiding consumed: [NSRange]
    ) -> NSTextCheckingResult? {
        guard let regex = cache.regex(for: pattern) else { return nil }
        let full = NSRange(location: 0, length: ns.length)
        for match in regex.matches(in: ns as String, options: [], range: full) {
            if consumed.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) { continue }
            return match
        }
        return nil
    }
}
