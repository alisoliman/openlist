//
//  CaptureDueDate.swift
//  OpenlistiOS
//

import Foundation

/// A date picked in Capture, distinct from leaving the typed date (or
/// Today's default) alone. Clearing explicitly keeps an undated task undated.
enum CaptureDueDate: Equatable {
    case automatic
    case chosen(Date, includesTime: Bool)
    case cleared

    func snapshot(_ parse: CaptureParse, dueToday: Bool, now: Date, calendar: Calendar) -> CaptureSnapshot {
        var snapshot = parse.snapshot()
        switch self {
        case .automatic:
            if snapshot.date == nil, dueToday { snapshot.date = calendar.startOfDay(for: now) }
        case let .chosen(date, includesTime):
            snapshot.date = includesTime ? date : calendar.startOfDay(for: date)
            snapshot.includesTime = includesTime
            // An unspecified weekly rule follows the picked weekday, while
            // a rule naming its own weekdays keeps them.
            if let repeatMark = parse.first(.repeatRule) {
                snapshot.recurrence = DateParser.parse(repeatMark.raw, reference: date).recurrence
            }
        case .cleared:
            snapshot.date = nil
            snapshot.includesTime = false
        }
        return snapshot
    }

    /// Editing the title or other metadata keeps the picked date. A newly
    /// typed day or time takes over from the picked date. Deleting superseded
    /// date words keeps the choice, including an explicitly cleared date.
    func afterEditing(from old: CaptureParse, to new: CaptureParse) -> Self {
        func tokens(_ parse: CaptureParse) -> [String] {
            parse.marks.filter {
                $0.kind == .date || $0.kind == .time || (self == .cleared && $0.kind == .repeatRule)
            }.map { $0.kind.rawValue + ":" + $0.raw.lowercased() }
        }
        let previous = tokens(old)
        return tokens(new).allSatisfy { previous.contains($0) } ? self : .automatic
    }
}
