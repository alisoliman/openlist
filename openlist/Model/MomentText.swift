//
//  MomentText.swift
//  openlist
//

import Foundation

/// A day and a time as the app writes them, the design's `dueLabel` and
/// 24-hour `clock`, for the screens (through `NXFormat`) and for the lines
/// saved history reads as.
nonisolated enum MomentText {
    /// "Today", "Tomorrow", "Yesterday", "Fri 25" within the week, else
    /// "3 Oct", and with `year` "3 Oct 2025" for a day in another year.
    static func day(_ date: Date, now: Date = .now, year: Bool = false) -> String {
        let calendar = Calendar.current
        let offset = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                             to: calendar.startOfDay(for: date)).day ?? 0
        switch offset {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        case 2..<7: return date.formatted(.dateTime.weekday(.abbreviated).day())
        default:
            guard year, calendar.component(.year, from: date) != calendar.component(.year, from: now) else {
                return date.formatted(.dateTime.day().month(.abbreviated))
            }
            return date.formatted(.dateTime.day().month(.abbreviated).year())
        }
    }

    /// "09:05": always 24-hour, as the design's clock.
    static func clock(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// A moment in the plan or in history: its day, with the year only when
    /// it isn't this one, then its time, "Today 10:00", "Fri 25 10:00" or
    /// "3 Oct 2025 10:00". In a sentence the relative days go lower case, as
    /// "Due today 18:00".
    static func moment(_ date: Date, includesTime: Bool = true, inSentence: Bool = false, now: Date = .now) -> String {
        var day = day(date, now: now, year: true)
        if inSentence, ["Today", "Tomorrow", "Yesterday"].contains(day) { day = day.lowercased() }
        return includesTime ? "\(day) \(clock(date))" : day
    }
}
