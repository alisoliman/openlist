//
//  DurationText.swift
//  openlist
//

import Foundation

/// A task's duration as it's typed and shown: "45", "45m", "1h30", "1.5 hours",
/// "1:15" or "2 hours 10 minutes" in, "1 h 30 min" out.
nonisolated enum DurationText {
    /// The longest duration a task keeps, as `Store.setTaskEstimate` does.
    static let maximumMinutes = 60 * 24 * 28

    /// The whole minutes `text` says, or nil when it isn't a duration. A bare
    /// whole number is minutes, as is one after hours ("1h 30"), and a bare
    /// fraction hours; units may be written out, abbreviated or run together
    /// with their number.
    static func minutes(from text: String) -> Int? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: ",", with: ".")
        guard !text.isEmpty else { return nil }
        if let clock = clockMinutes(text) { return clamped(Double(clock)) }

        var total = 0.0
        var rest = Substring(text)
        var sawHours = false
        var sawMinutes = false
        while true {
            rest = rest.drop { $0 == " " }
            if rest.hasPrefix("and ") { rest = rest.dropFirst(4) }
            guard !rest.isEmpty else { break }
            let number = rest.prefix { $0.isNumber || $0 == "." }
            guard let value = Double(number), value.isFinite else { return nil }
            rest = rest.dropFirst(number.count).drop { $0 == " " }
            let unit = rest.prefix { $0.isLetter }
            rest = rest.dropFirst(unit.count)
            switch String(unit) {
            case "h", "hr", "hrs", "hour", "hours":
                guard !sawHours, !sawMinutes else { return nil }
                sawHours = true
                total += value * 60
            case "m", "min", "mins", "minute", "minutes":
                guard !sawMinutes else { return nil }
                sawMinutes = true
                total += value
            case "":
                // Only last: "1h 30" or a lone "45". A lone "1.5" is hours.
                guard !sawMinutes, rest.allSatisfy({ $0 == " " }) else { return nil }
                sawMinutes = true
                total += !sawHours && value.rounded() != value ? value * 60 : value
            default:
                return nil
            }
        }
        return clamped(total)
    }

    /// "30 min", "2 h" or "1 h 15 min".
    static func text(for minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return "\(minutes) min" }
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }

    /// "1:30" as an hour and a half.
    private static func clockMinutes(_ text: String) -> Int? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let hours = Int(parts[0]), let minutes = Int(parts[1]),
              parts[1].count == 2, hours >= 0, (0..<60).contains(minutes) else { return nil }
        return hours * 60 + minutes
    }

    private static func clamped(_ minutes: Double) -> Int? {
        let rounded = Int(minutes.rounded())
        guard minutes.isFinite, rounded >= 1, rounded <= maximumMinutes else { return nil }
        return rounded
    }
}
