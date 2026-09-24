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

    /// The app's overdue rule (`Block.isOverdue`, TasksProjection): a timed task is late once its
    /// time passes, an all-day task once its day ends. Ignores completion, so a task still closing
    /// keeps its place; callers decide where finished tasks go.
    static func isPastDue(_ task: Block, now: Date = .now) -> Bool {
        guard let due = task.dueDate else { return false }
        return due < (task.includesTime ? now : calendar.startOfDay(for: now))
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

    static func relativeDay(_ date: Date, now: Date = .now) -> String {
        let offset = dayOffset(date, now: now)
        if offset == 0 { return "today" }
        if offset == 1 { return "tomorrow" }
        if offset < 0 { return "\(-offset) days ago" }
        return "in \(offset) days"
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

    var hasPriority: Bool { priority != nil }

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
}
