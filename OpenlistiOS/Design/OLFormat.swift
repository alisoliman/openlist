//
//  OLFormat.swift
//  OpenlistiOS
//

import Foundation

/// The phone's own date wording where `CompactText` has none: the
/// eyebrow's full day, and a work range.
enum OLFormat {
    /// "Wednesday 23 September": the day as Today's eyebrow names it.
    static func eyebrowDate(_ date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEEE d MMMM"
        return formatter.string(from: date)
    }

    /// "10:00–11:30", with an en dash.
    static func range(_ start: Date, _ end: Date, calendar: Calendar = .current) -> String {
        "\(CompactText.clock(start, calendar: calendar))–\(CompactText.clock(end, calendar: calendar))"
    }
}
