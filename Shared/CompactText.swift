//
//  CompactText.swift
//  Shared
//

import Foundation

/// The phone design's compact wording for when things are due and how long
/// ago they arrived: a row's one trailing value ("3d late", "18:00", "Sat"),
/// an Inbox age ("2h"), the triage card's "Captured 4 days ago" and the
/// capture sheet's chips ("Fri 25, 18:00", "15 min"). The Mac's rows name
/// days as `MomentText` does ("Sat 26"); the phone's single trailing slot
/// has room for less.
///
/// Clock times are 24-hour "HH:mm", as everywhere in the app. Day and month
/// names come from the calendar's locale, so tests pin them with a fixed
/// calendar. Foundation only and nonisolated, so iOS widgets and App Intents
/// can use it off the main actor.
nonisolated enum CompactText {
    /// A row's trailing due text and how it's toned.
    struct Due: Equatable, Sendable {
        enum Tone: Equatable, Sendable {
            /// Due on an earlier day: danger, with the late checkbox ring.
            case late
            /// Due today: accent.
            case today
            /// Due on a later day: muted, as the Mac's due chip past today.
            case upcoming
        }

        var text: String
        var tone: Tone
        /// Calendar days from today to the due day; negative when late.
        var dayOffset: Int
    }

    // MARK: - Due dates

    /// "3d late", "18:00" for a timed task due today, "Today", "Tomorrow",
    /// a bare weekday ("Sat") through the next six days, then "Fri 2 Oct",
    /// with the year when it isn't this one. Late goes by day, as the Mac's
    /// rows and the widgets: a timed task whose time passed today is still
    /// today's. Nil for an undated or completed task.
    static func due(_ date: Date?, includesTime: Bool, isCompleted: Bool = false, now: Date,
                    calendar: Calendar = .current) -> Due? {
        guard !isCompleted, let date else { return nil }
        let offset = dayOffset(from: now, to: date, calendar: calendar)
        if offset < 0 { return Due(text: "\(-offset)d late", tone: .late, dayOffset: offset) }
        if offset == 0 { return Due(text: includesTime ? clock(date, calendar: calendar) : "Today", tone: .today, dayOffset: 0) }
        return Due(text: day(date, now: now, calendar: calendar), tone: .upcoming, dayOffset: offset)
    }

    /// "Today", "Tomorrow", "Yesterday", a bare weekday ("Sat") within the
    /// next six days, else "Fri 2 Oct", with the year when it isn't this one.
    static func day(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        switch dayOffset(from: now, to: date, calendar: calendar) {
        case 0: "Today"
        case 1: "Tomorrow"
        case -1: "Yesterday"
        case 2...6: weekday(date, calendar: calendar)
        default: fullDay(date, now: now, calendar: calendar)
        }
    }

    /// A captured task's day and time as the capture sheet's chip reads it:
    /// "Today", "Tomorrow", "Fri 25" within the week, else "Fri 2 Oct", then
    /// ", 18:00" when it has a time.
    static func captureWhen(_ date: Date, includesTime: Bool, now: Date, calendar: Calendar = .current) -> String {
        let offset = dayOffset(from: now, to: date, calendar: calendar)
        let day = switch offset {
        case 0: "Today"
        case 1: "Tomorrow"
        case -1: "Yesterday"
        case 2...6: "\(weekday(date, calendar: calendar)) \(calendar.component(.day, from: date))"
        default: fullDay(date, now: now, calendar: calendar)
        }
        return includesTime ? "\(day), \(clock(date, calendar: calendar))" : day
    }

    /// Whole calendar days from `now` to `date`; negative in the past.
    static func dayOffset(from now: Date, to date: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
    }

    /// "Sat".
    static func weekday(_ date: Date, calendar: Calendar = .current) -> String {
        calendar.shortWeekdaySymbols[calendar.component(.weekday, from: date) - 1]
    }

    /// "09:30".
    static func clock(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// "Fri 2 Oct", or "Fri 2 Oct 2027" in another year than `now`'s.
    private static func fullDay(_ date: Date, now: Date, calendar: Calendar) -> String {
        let month = calendar.shortMonthSymbols[calendar.component(.month, from: date) - 1]
        let text = "\(weekday(date, calendar: calendar)) \(calendar.component(.day, from: date)) \(month)"
        let year = calendar.component(.year, from: date)
        return year == calendar.component(.year, from: now) ? text : "\(text) \(year)"
    }

    // MARK: - Durations

    /// An estimate as the capture chip and the stepper say it: "15 min", "90 min".
    static func estimate(_ minutes: Int) -> String { "\(minutes) min" }

    // MARK: - Ages

    /// How long ago an Inbox capture arrived: "now", "15m", "2h", "1d".
    ///
    /// Minutes count in fives. A widget only redraws at its timeline's
    /// entries, and `ageChange(of:after:)` gives one for every change of this
    /// label, so a finer label would either be wrong between entries or cost
    /// an entry a minute. The phone's Inbox rows read the same as its widget's.
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

    /// How long ago, in words, in the same whole hours and days as `age`:
    /// "just now", "12 minutes ago", "5 hours ago", "yesterday", "4 days ago".
    static func ago(_ date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "just now"
        case ..<3600: return count(Int(seconds / 60), "minute") + " ago"
        case ..<86_400: return count(Int(seconds / 3600), "hour") + " ago"
        default:
            let days = Int(seconds / 86_400)
            return days == 1 ? "yesterday" : "\(days) days ago"
        }
    }

    /// The triage card's line: "Captured 4 days ago", "Captured just now".
    static func captured(_ date: Date, now: Date) -> String { "Captured \(ago(date, now: now))" }

    private static func count(_ value: Int, _ unit: String) -> String { "\(value) \(unit)\(value == 1 ? "" : "s")" }
}
