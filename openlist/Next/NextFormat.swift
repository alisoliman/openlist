//
//  NextFormat.swift
//  openlist
//

import Foundation

/// Wording shared by rows, the tray and the inspector.
enum NXFormat {
    static var calendar: Calendar { Calendar.current }

    static func dayOffset(_ date: Date, now: Date = .now) -> Int {
        let start = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: start, to: day).day ?? 0
    }

    static func day(offset: Int, now: Date = .now) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) ?? now
    }

    /// `day` at the hour and minute of `time`, for a timed task moved to another day.
    static func day(_ day: Date, at time: Date) -> Date {
        let parts = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0, of: day) ?? day
    }

    /// Days from today to "Next week", the coming Monday (`Store.nextWeekDay`).
    static func nextWeekOffset(now: Date = .now) -> Int {
        dayOffset(Store.nextWeekDay(from: now, calendar: calendar), now: now)
    }

    /// "Today", "Tomorrow", "Yesterday", "Fri 25" within the week, else "3 Oct".
    static func dueLabel(_ date: Date?, now: Date = .now) -> String {
        guard let date else { return "No date" }
        let offset = dayOffset(date, now: now)
        switch offset {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        case 2..<7: return date.formatted(.dateTime.weekday(.abbreviated).day())
        default: return date.formatted(.dateTime.day().month(.abbreviated))
        }
    }

    /// `dueLabel`, with the year for a day past the week in another year, for
    /// dates that may be far off, like a reminder or a repeat's next days.
    static func dayLabel(_ date: Date, now: Date = .now) -> String {
        let offset = dayOffset(date, now: now)
        guard !(-1..<7).contains(offset),
              calendar.component(.year, from: date) != calendar.component(.year, from: now) else {
            return dueLabel(date, now: now)
        }
        return date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    /// A day and time in the Due row's words, as the inspector's Reminder
    /// pill reads: "Fri 25 09:00".
    static func dueAndClock(_ date: Date, now: Date = .now) -> String {
        "\(dueLabel(date, now: now)) \(clock(date))"
    }

    /// A day and time with `dayLabel`'s year, as saved history writes when
    /// something happened: "Today 14:05", "25 Sep 2025 09:00".
    static func dayAndClock(_ date: Date, now: Date = .now) -> String {
        "\(dayLabel(date, now: now)) \(clock(date))"
    }

    /// A day, and its time when it has one, as saved history writes a due
    /// date: "Fri 25 09:00", "3 Oct".
    static func dayText(_ date: Date, includesTime: Bool, now: Date = .now) -> String {
        includesTime ? dayAndClock(date, now: now) : dayLabel(date, now: now)
    }

    /// A new due date as the tray and Changes name it: its day, and its time
    /// only when the change set that time. A timed task moved to another day
    /// keeps its time unnamed, as the design's date pills name only the day.
    static func dueChange(_ due: Date, includesTime: Bool, from old: Date?, oldIncludesTime: Bool,
                          now: Date = .now) -> String {
        let keepsTime = oldIncludesTime && old.map { clock($0) } == clock(due)
        return dueLabel(due, now: now) + (includesTime && !keepsTime ? " \(clock(due))" : "")
    }

    static func relativeDay(_ date: Date, now: Date = .now) -> String {
        let offset = dayOffset(date, now: now)
        if offset == 0 { return "today" }
        if offset == 1 { return "tomorrow" }
        if offset < 0 { return "\(-offset) days ago" }
        return "in \(offset) days"
    }

    /// A typed day as capture's chip names it: "Fri 25 · in 2 days".
    static func typedDay(_ date: Date, now: Date = .now) -> String {
        "\(dueLabel(date, now: now)) · \(relativeDay(date, now: now))"
    }

    /// A schedule typed in words, as capture's chips read it, in one line:
    /// "Fri 25 · in 2 days · 09:00 · Every week".
    static func typedSchedule(_ date: Date, includesTime: Bool, repeat rule: String? = nil, now: Date = .now) -> String {
        ([typedDay(date, now: now)] + (includesTime ? [clock(date)] : []) + [rule].compactMap(\.self))
            .joined(separator: " · ")
    }

    static func relative(_ date: Date, now: Date = .now) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 45 { return "just now" }
        if seconds < 3600 { return "\(Int((seconds / 60).rounded())) min ago" }
        if seconds < 86_400 { return "\(Int((seconds / 3600).rounded())) h ago" }
        let days = Int((seconds / 86_400).rounded())
        return days == 1 ? "yesterday" : "\(days) days ago"
    }

    static func clock(_ date: Date) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    static func short(_ text: String) -> String {
        text.count > 30 ? String(text.prefix(29)) + "…" : text
    }

    static func quoted(_ text: String) -> String { "“\(short(text))”" }

    /// Files kept with a task as the tray names them: "Attached “a.pdf” to
    /// “Task”", or "Attached 3 files to “Task”", counting only those kept.
    static func attached(_ names: [String], to task: String) -> String {
        "Attached \(names.count == 1 ? quoted(names[0]) : "\(names.count) files") to \(task)"
    }

    /// "“a.pdf” and “b.pdf” could not be attached.", with the first one's
    /// reason: up to three names, or two and "N other files" past that.
    static func attachFailures(_ failures: [(name: String, error: Error)]) -> String? {
        guard let first = failures.first else { return nil }
        let named = failures.count > 3 ? 2 : failures.count
        var names = failures.prefix(named).map { quoted($0.name) }
        if failures.count > named { names.append("\(failures.count - named) other files") }
        let who = ListFormatter.localizedString(byJoining: names)
        return "\(who) could not be attached. \(first.error.localizedDescription)"
    }

    /// Elapsed time as the notch and the Stopped tray show it: "07:42", and "1:05:12" past an hour.
    static func mmss(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let rest = String(format: "%02d:%02d", total % 3600 / 60, total % 60)
        return hours > 0 ? "\(hours):\(rest)" : rest
    }

    static func minutes(_ value: Int) -> String {
        value >= 60 && value % 60 == 0 ? "\(value / 60)h" : value > 60 ? "\(value / 60)h \(value % 60)m" : "\(value)m"
    }
}

/// The capture grammar: the tokens coloured as you type are exactly the ones
/// Return saves. Dates, times and repeat rules are whatever `DateParser` reads
/// (none while natural-language dates are off); labels, priority and
/// estimates are the design's tokens.
struct CaptureParse {
    enum Kind: String { case repeatRule, date, time, label, priority, estimate }

    struct Mark {
        var kind: Kind
        var range: Range<String.Index>
        var raw: String
    }

    struct Segment: Identifiable {
        let id: Int
        var text: String
        var kind: Kind?
    }

    let text: String
    let marks: [Mark]
    let segments: [Segment]
    /// The text without its tokens: the title Return saves.
    let title: String
    /// The due date, time and repeat rule read from the text; nil when there are none.
    let schedule: ParsedSchedule?

    /// Labels need whitespace or the start before `#`, as in the store's capture draft,
    /// so `issue#42` and URL fragments stay plain text.
    private static let sources: [(Kind, String)] = [
        (.label, #"(?<!\S)#[\p{L}0-9_-]+"#),
        (.priority, #"!(?:high|med|medium|low|[1-3])\b"#),
        (.estimate, #"~\d+\s?(?:m|min|h)\b"#),
    ]

    /// Compiled once rather than on every keystroke.
    private static let patterns: [(Kind, NSRegularExpression)] = sources.compactMap { kind, pattern in
        (try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])).map { (kind, $0) }
    }

    init(_ text: String, parsesDates: Bool = true, reference: Date = .now) {
        self.text = text
        var marks: [Mark] = []
        for (kind, regex) in Self.patterns {
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range, in: text) else { continue }
                if marks.contains(where: { $0.range.overlaps(range) }) { continue }
                marks.append(Mark(kind: kind, range: range, raw: String(text[range])))
            }
        }
        var schedule: ParsedSchedule?
        if parsesDates {
            // The tokens above are blanked with a character that is neither a
            // word nor a space, so a date phrase can't reach into or across one.
            let masked = NSMutableString(string: text)
            for mark in marks {
                let range = NSRange(mark.range, in: text)
                masked.replaceCharacters(in: range, with: String(repeating: "\u{FFFC}", count: range.length))
            }
            let parsed = DateParser.parse(masked as String, reference: reference)
            if !parsed.isEmpty {
                schedule = parsed
                for (range, part) in zip(parsed.consumedRanges, parsed.consumedParts) {
                    guard var found = Range(range, in: text) else { continue }
                    // A space the phrase took with it stays plain text.
                    while !found.isEmpty, text[found.lowerBound].isWhitespace {
                        found = text.index(after: found.lowerBound)..<found.upperBound
                    }
                    while !found.isEmpty, text[text.index(before: found.upperBound)].isWhitespace {
                        found = found.lowerBound..<text.index(before: found.upperBound)
                    }
                    guard !found.isEmpty else { continue }
                    let kind: Kind = switch part {
                    case .recurrence: .repeatRule
                    case .day: .date
                    case .time: .time
                    }
                    marks.append(Mark(kind: kind, range: found, raw: String(text[found])))
                }
            }
        }
        marks.sort { $0.range.lowerBound < $1.range.lowerBound }
        var segments: [Segment] = []
        var cursor = text.startIndex
        for mark in marks {
            if mark.range.lowerBound > cursor {
                segments.append(Segment(id: segments.count, text: String(text[cursor..<mark.range.lowerBound])))
            }
            segments.append(Segment(id: segments.count, text: mark.raw, kind: mark.kind))
            cursor = mark.range.upperBound
        }
        if cursor < text.endIndex { segments.append(Segment(id: segments.count, text: String(text[cursor...]))) }
        var title = text
        for mark in marks.reversed() { title.removeSubrange(mark.range) }
        title = title.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        // As the date parser tidies what it strips: "meet by friday" is "meet".
        if schedule != nil {
            title = title.replacingOccurrences(of: #"\s+(?:on|at|by|due)\s*$"#, with: "",
                                               options: [.regularExpression, .caseInsensitive])
        }
        self.marks = marks
        self.segments = segments
        self.title = title.trimmingCharacters(in: .whitespaces)
        self.schedule = schedule
    }

    func first(_ kind: Kind) -> Mark? { marks.first { $0.kind == kind } }

    var labels: [String] { marks.filter { $0.kind == .label }.map { String($0.raw.dropFirst()).lowercased() } }

    /// `!high`/`!3`, `!med`/`!medium`/`!2` and `!low`/`!1`; nil without a token.
    var priority: TaskPriority? {
        guard let raw = first(.priority)?.raw else { return nil }
        switch raw.dropFirst().lowercased() {
        case "high", "3": return .high
        case "med", "medium", "2": return .medium
        case "low", "1": return .low
        default: return nil
        }
    }

    /// Minutes from `~45m`/`~2h`, capped at the store's four-week limit so a huge number can't overflow.
    var estimateMinutes: Int? {
        guard let raw = first(.estimate)?.raw else { return nil }
        let cap = 60 * 24 * 28
        let value = raw.compactMap(\.wholeNumberValue).reduce(0) { min($0 * 10 + $1, cap) }
        return min(raw.lowercased().contains("h") ? value * 60 : value, cap)
    }

    /// What Return saves, which the capture card's chips preview. A task with
    /// no date of its own is due today when `dueToday`; `labels` join the ones
    /// the text names, as a label screen's own label does.
    func snapshot(dueToday: Bool = false, labels extra: [String] = []) -> CaptureSnapshot {
        CaptureSnapshot(
            title: title,
            date: schedule?.date ?? (dueToday ? NXFormat.day(offset: 0) : nil),
            includesTime: schedule?.includesTime ?? false,
            recurrence: schedule?.recurrence,
            labels: Array(Set(labels + extra)).sorted())
    }

    /// The capture card's chips for `preview`, what this text saves, as the
    /// design's capChips: each token's where it was typed, a typed day as
    /// "Fri 25 · in 2 days", and Today first when the task is due today with
    /// no day typed and `forToday`. A time or repeat typed alone shows no day,
    /// unless the day it saves isn't today: a time already past, or a repeat's
    /// first day, which the design never saves.
    func chips(for preview: CaptureSnapshot, forToday: Bool, now: Date = .now) -> [CaptureChip] {
        var chips: [CaptureChip] = []
        var showsDay = false, showsTime = false, showsRepeat = false, showsPriority = false
        let typesDay = first(.date) != nil
        func day(_ date: Date) -> CaptureChip {
            let label = NXFormat.typedDay(date, now: now)
            return CaptureChip(id: "date-\(label)", kind: .day, label: label)
        }
        func impliedDay() {
            guard !typesDay, !showsDay, let date = preview.date, NXFormat.dayOffset(date, now: now) != 0 else { return }
            chips.append(day(date))
            showsDay = true
        }
        for (index, mark) in marks.enumerated() {
            let id = "\(index)-\(mark.kind.rawValue)-\(mark.raw.lowercased())"
            switch mark.kind {
            case .date:
                guard !showsDay, let date = preview.date else { continue }
                chips.append(day(date))
                showsDay = true
            case .time:
                guard !showsTime, preview.includesTime, let date = preview.date else { continue }
                impliedDay()
                chips.append(CaptureChip(id: "time", kind: .time, label: NXFormat.clock(date)))
                showsTime = true
            case .repeatRule:
                guard !showsRepeat, preview.recurrence != nil else { continue }
                impliedDay()
                chips.append(CaptureChip(id: "repeat", kind: .repeatRule, label: mark.raw))
                showsRepeat = true
            case .label:
                chips.append(CaptureChip(id: id, kind: .label, label: String(mark.raw.dropFirst())))
            case .priority:
                // The first one, which is the one Return saves.
                guard !showsPriority, let priority else { continue }
                chips.append(CaptureChip(id: "priority", kind: .priority(priority), label: priority.title))
                showsPriority = true
            case .estimate:
                chips.append(CaptureChip(id: id, kind: .estimate, label: "\(mark.raw.dropFirst()) estimate"))
            }
        }
        if forToday, !showsDay, let date = preview.date, NXFormat.dayOffset(date, now: now) == 0 {
            chips.insert(CaptureChip(id: "date-Today", kind: .day, label: "Today"), at: 0)
        }
        return chips
    }
}

/// One of the capture card's chips: what it says and what it stands for,
/// which gives it its icon and tone.
struct CaptureChip: Equatable {
    enum Kind: Equatable { case day, time, repeatRule, label, priority(TaskPriority), estimate }
    let id: String
    let kind: Kind
    let label: String
}
