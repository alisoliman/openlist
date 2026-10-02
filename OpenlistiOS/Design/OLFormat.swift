//
//  OLFormat.swift
//  OpenlistiOS
//

import Foundation

/// The phone's own date wording where `CompactText` has none: the
/// eyebrow's full day, and a work range.
enum OLFormat {
    /// "Wednesday 23 September", or "Wednesday, September 23": the day as
    /// Today's eyebrow names it, in the order and punctuation of the locale.
    static func eyebrowDate(_ date: Date, calendar: Calendar = .current) -> String {
        let locale = calendar.locale ?? .current
        // Today, Timeline and Activity's 84 day cells ask on every redraw.
        let key = "\(calendar.identifier)|\(locale.identifier)|\(calendar.timeZone.identifier)"
        if let formatter = eyebrowFormatters[key] { return formatter.string(from: date) }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        eyebrowFormatters[key] = formatter
        return formatter.string(from: date)
    }

    private static var eyebrowFormatters: [String: DateFormatter] = [:]

    /// "10:00–11:30", with an en dash.
    static func range(_ start: Date, _ end: Date, calendar: Calendar = .current) -> String {
        "\(CompactText.clock(start, calendar: calendar))–\(CompactText.clock(end, calendar: calendar))"
    }
}
