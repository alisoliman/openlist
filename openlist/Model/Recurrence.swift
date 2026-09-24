//
//  Recurrence.swift
//  openlist
//

import Foundation

/// A repeat rule for a task. Stored as JSON on the owning block.
///
/// Declared `nonisolated` so `Block`'s computed accessors — which SwiftData
/// generates outside the actor — can encode and decode it directly.
nonisolated struct Recurrence: Codable, Hashable, Sendable {
    enum Frequency: String, Codable, CaseIterable, Sendable {
        case daily, weekly, monthly, yearly

        var singular: String {
            switch self {
            case .daily: "day"
            case .weekly: "week"
            case .monthly: "month"
            case .yearly: "year"
            }
        }

        var plural: String { singular + "s" }
    }

    /// Whether the next occurrence is measured from the original due date or
    /// from the moment the task was actually ticked off.
    enum Anchor: String, Codable, CaseIterable, Sendable {
        case dueDate
        case completionDate

        var title: String {
            switch self {
            case .dueDate: "On schedule"
            case .completionDate: "After completion"
            }
        }
    }

    var frequency: Frequency = .daily
    /// Repeat every `interval` units of `frequency`.
    var interval: Int = 1
    /// For weekly rules: 1 = Sunday … 7 = Saturday, matching `Calendar` weekday.
    var weekdays: Set<Int> = []
    /// For monthly rules: day of month. `nil` keeps the day of the due date.
    var dayOfMonth: Int?
    var anchor: Anchor = .dueDate
    /// Stop repeating after this date.
    var endDate: Date?
    /// Stop repeating after this many occurrences.
    var occurrenceLimit: Int?
    /// How many times this rule has already fired.
    var completedOccurrences: Int = 0

    static let daily = Recurrence(frequency: .daily, interval: 1)
    static let weekdaysOnly = Recurrence(frequency: .weekly, interval: 1, weekdays: [2, 3, 4, 5, 6])
    static let weekly = Recurrence(frequency: .weekly, interval: 1)
    static let monthly = Recurrence(frequency: .monthly, interval: 1)
    static let yearly = Recurrence(frequency: .yearly, interval: 1)

    /// Pins `dayOfMonth` for monthly rules so the series remembers that it
    /// started on, say, the 31st even after a February clamps it to the 28th.
    func anchored(to dueDate: Date?, calendar: Calendar = .current) -> Recurrence {
        guard frequency == .monthly, dayOfMonth == nil, let dueDate else { return self }
        var copy = self
        copy.dayOfMonth = calendar.component(.day, from: dueDate)
        return copy
    }

    var isFinished: Bool {
        if let occurrenceLimit, completedOccurrences >= occurrenceLimit { return true }
        return false
    }

    // MARK: - Description

    var displayText: String {
        var base: String
        switch frequency {
        case .daily:
            base = interval == 1 ? "Every day" : "Every \(interval) days"
        case .weekly:
            if !weekdays.isEmpty {
                if weekdays == [2, 3, 4, 5, 6] {
                    base = "Every weekday"
                } else if weekdays == [1, 7] {
                    base = "Every weekend"
                } else if weekdays.count == 1, let weekday = weekdays.first {
                    // One day in full, as the design's "Every Wednesday".
                    base = "Every \(Recurrence.weekdayName(weekday))"
                } else {
                    let names = weekdays.sorted().map { Recurrence.shortWeekdayName($0) }
                    base = "Every \(names.formatted(.list(type: .and)))"
                }
                if interval > 1 { base += " every \(interval) weeks" }
            } else {
                base = interval == 1 ? "Every week" : "Every \(interval) weeks"
            }
        case .monthly:
            base = interval == 1 ? "Every month" : "Every \(interval) months"
            if let dayOfMonth { base += " on the \(dayOfMonth.ordinalString)" }
        case .yearly:
            base = interval == 1 ? "Every year" : "Every \(interval) years"
        }
        if anchor == .completionDate { base += ", after completion" }
        return base
    }

    static func shortWeekdayName(_ weekday: Int) -> String {
        symbol(weekday, in: Calendar.current.shortWeekdaySymbols)
    }

    static func weekdayName(_ weekday: Int) -> String {
        symbol(weekday, in: Calendar.current.weekdaySymbols)
    }

    private static func symbol(_ weekday: Int, in symbols: [String]) -> String {
        symbols[max(0, min(symbols.count - 1, weekday - 1))]
    }

    // MARK: - Codable payload

    var jsonData: Data? { try? JSONEncoder().encode(self) }

    static func decode(_ data: Data?) -> Recurrence? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(Recurrence.self, from: data)
    }
}

nonisolated extension Int {
    /// "1st", "2nd", "3rd", …
    var ordinalString: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}
