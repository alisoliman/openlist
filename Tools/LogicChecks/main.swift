// Headless checks for the pure-logic layer: natural-language date parsing and
// the recurrence engine. Compiled and run by Tools/run-logic-checks.sh.

import Foundation

var failures = 0
var checks = 0

@MainActor
func check(_ condition: Bool, _ label: String, _ detail: @autoclosure () -> String = "") {
    checks += 1
    if !condition {
        failures += 1
        let extra = detail()
        print("FAIL  \(label)\(extra.isEmpty ? "" : " — \(extra)")")
    }
}

let calendar = Calendar.current
// A fixed reference so results never depend on when the checks run:
// Wednesday 3 June 2026, 10:00 local time.
var referenceComponents = DateComponents()
referenceComponents.year = 2026
referenceComponents.month = 6
referenceComponents.day = 3
referenceComponents.hour = 10
let reference = calendar.date(from: referenceComponents)!

func day(_ date: Date?) -> DateComponents? {
    guard let date else { return nil }
    return calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
}

func describe(_ date: Date?) -> String {
    guard let date else { return "nil" }
    return date.formatted(date: .abbreviated, time: .shortened)
}

// Weekend presets and free-text capture must agree, including both days
// of the current weekend rather than silently deferring a week.
do {
    for (referenceDay, expectedThis, expectedNext) in [(3, 6, 13), (6, 6, 13), (7, 7, 13)] {
        let current = calendar.date(bySetting: .day, value: referenceDay, of: reference)!
        let thisWeekend = DateParser.parse("plan this weekend", reference: current)
        let nextWeekend = DateParser.parse("plan next weekend", reference: current)
        check(day(thisWeekend.date)?.day == expectedThis,
              "this weekend from June \(referenceDay) resolves June \(expectedThis)", describe(thisWeekend.date))
        check(day(nextWeekend.date)?.day == expectedNext,
              "next weekend from June \(referenceDay) resolves June \(expectedNext)", describe(nextWeekend.date))
    }
}

// MARK: - DateParser

print("── DateParser ──")

do {
    let parsed = DateParser.parse("buy milk tomorrow", reference: reference)
    let d = day(parsed.date)
    check(d?.day == 4 && d?.month == 6, "tomorrow resolves to the next day", describe(parsed.date))
    check(parsed.cleanedText == "buy milk", "tomorrow is stripped", "got “\(parsed.cleanedText)”")
    check(!parsed.includesTime, "bare day has no time")
}

do {
    let parsed = DateParser.parse("call mum tomorrow at 6pm", reference: reference)
    let d = day(parsed.date)
    check(d?.day == 4 && d?.hour == 18, "tomorrow at 6pm", describe(parsed.date))
    check(parsed.includesTime, "time flag set")
    check(parsed.cleanedText == "call mum", "phrase stripped", "got “\(parsed.cleanedText)”")
}

do {
    let parsed = DateParser.parse("standup at 9:30am", reference: reference)
    let d = day(parsed.date)
    check(d?.hour == 9 && d?.minute == 30, "9:30am parsed", describe(parsed.date))
    check(parsed.cleanedText == "standup", "cleaned", "got “\(parsed.cleanedText)”")
}

do {
    // 08:00 has already passed at the 10:00 reference, so it rolls to tomorrow.
    let parsed = DateParser.parse("gym at 8am", reference: reference)
    let d = day(parsed.date)
    check(d?.day == 4 && d?.hour == 8, "past bare time rolls to tomorrow", describe(parsed.date))
}

do {
    let parsed = DateParser.parse("pay rent in 3 days", reference: reference)
    let d = day(parsed.date)
    check(d?.day == 6, "in 3 days", describe(parsed.date))
    check(parsed.cleanedText == "pay rent", "cleaned", "got “\(parsed.cleanedText)”")
}

do {
    // Wednesday → next Friday is the 5th.
    let parsed = DateParser.parse("submit report on friday", reference: reference)
    let d = day(parsed.date)
    check(d?.day == 5, "upcoming friday", describe(parsed.date))
    check(parsed.cleanedText == "submit report", "on + weekday stripped", "got “\(parsed.cleanedText)”")
}

do {
    // "next monday" skips ahead rather than picking the nearest one.
    let parsed = DateParser.parse("review next monday", reference: reference)
    let d = day(parsed.date)
    check(d?.day == 8, "next monday", describe(parsed.date))
}

do {
    let parsed = DateParser.parse("dentist 25 december", reference: reference)
    let d = day(parsed.date)
    check(d?.day == 25 && d?.month == 12, "day + month name", describe(parsed.date))
}

do {
    let parsed = DateParser.parse("launch 2026-11-05", reference: reference)
    let d = day(parsed.date)
    check(d?.year == 2026 && d?.month == 11 && d?.day == 5, "ISO date", describe(parsed.date))
}

do {
    let parsed = DateParser.parse("water plants every 2 days", reference: reference)
    check(parsed.recurrence?.frequency == .daily, "every 2 days → daily")
    check(parsed.recurrence?.interval == 2, "interval 2")
    check(parsed.cleanedText == "water plants", "cleaned", "got “\(parsed.cleanedText)”")
}

do {
    let parsed = DateParser.parse("team sync every monday", reference: reference)
    check(parsed.recurrence?.frequency == .weekly, "every monday → weekly")
    check(parsed.recurrence?.weekdays == [2], "monday captured", "\(parsed.recurrence?.weekdays ?? [])")
}

do {
    let parsed = DateParser.parse("standup every weekday", reference: reference)
    check(parsed.recurrence?.weekdays == [2, 3, 4, 5, 6], "weekdays only")
}

do {
    let parsed = DateParser.parse("invoices monthly", reference: reference)
    check(parsed.recurrence?.frequency == .monthly, "monthly adverb")
}

do {
    // Ordinary prose must survive untouched.
    let parsed = DateParser.parse("email marching band about may flowers", reference: reference)
    check(parsed.date == nil, "no false positive on prose", describe(parsed.date))
    check(parsed.recurrence == nil, "no false recurrence")
}

do {
    let parsed = DateParser.parse("plain task with no date", reference: reference)
    check(parsed.isEmpty, "nothing matched")
    check(parsed.cleanedText == "plain task with no date", "text untouched")
}

// MARK: - RecurrenceEngine

print("── RecurrenceEngine ──")

func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 9) -> Date {
    var c = DateComponents()
    c.year = y; c.month = m; c.day = d; c.hour = h
    return calendar.date(from: c)!
}

do {
    let rule = Recurrence(frequency: .daily, interval: 1)
    let next = RecurrenceEngine.nextDate(rule: rule, dueDate: date(2026, 6, 3), completedAt: date(2026, 6, 3, 11))
    check(day(next)?.day == 4, "daily advances one day", describe(next))
}

do {
    let rule = Recurrence(frequency: .weekly, interval: 1, weekdays: [2])
    // From Wednesday 3 June, the next Monday is the 8th.
    let next = RecurrenceEngine.nextDate(rule: rule, dueDate: date(2026, 6, 3), completedAt: date(2026, 6, 3, 11))
    check(day(next)?.day == 8, "weekly-on-monday finds next monday", describe(next))
}

do {
    let rule = Recurrence(frequency: .weekly, interval: 1, weekdays: [2, 4, 6])
    let next = RecurrenceEngine.nextDate(rule: rule, dueDate: date(2026, 6, 3), completedAt: date(2026, 6, 3, 11))
    // Wednesday is in the set, so the next hit is Friday the 5th.
    check(day(next)?.day == 5, "multi-weekday picks the nearest next", describe(next))
}

do {
    let rule = Recurrence(frequency: .monthly, interval: 1)
    let next = RecurrenceEngine.nextDate(rule: rule, dueDate: date(2026, 1, 31), completedAt: date(2026, 1, 31, 11))
    // Adding a month to 31 January must not overflow into March.
    check(day(next)?.month == 2, "monthly from the 31st stays in February", describe(next))
}

do {
    // A schedule-anchored rule that has fallen weeks behind catches up to the future.
    let rule = Recurrence(frequency: .weekly, interval: 1)
    let next = RecurrenceEngine.nextDate(
        rule: rule,
        dueDate: date(2026, 4, 1),
        completedAt: date(2026, 6, 3, 11)
    )
    check(next != nil && next! > date(2026, 6, 3, 11), "overdue repeat catches up", describe(next))
}

do {
    // Completion-anchored rules measure from when the task was ticked off.
    var rule = Recurrence(frequency: .daily, interval: 7)
    rule.anchor = .completionDate
    let next = RecurrenceEngine.nextDate(
        rule: rule,
        dueDate: date(2026, 4, 1),
        completedAt: date(2026, 6, 3, 11)
    )
    check(day(next)?.month == 6 && day(next)?.day == 10, "completion anchor uses tick-off date", describe(next))
}

do {
    var rule = Recurrence(frequency: .daily, interval: 1)
    rule.endDate = date(2026, 6, 3)
    let next = RecurrenceEngine.nextDate(rule: rule, dueDate: date(2026, 6, 3), completedAt: date(2026, 6, 3, 11))
    check(next == nil, "rule past its end date stops", describe(next))
}

do {
    var rule = Recurrence(frequency: .daily, interval: 1)
    rule.occurrenceLimit = 3
    rule.completedOccurrences = 3
    let next = RecurrenceEngine.nextDate(rule: rule, dueDate: date(2026, 6, 3), completedAt: date(2026, 6, 3, 11))
    check(next == nil, "occurrence limit stops the rule", describe(next))
}

do {
    let upcoming = RecurrenceEngine.upcoming(rule: .weekly, from: date(2026, 6, 3), count: 3)
    check(upcoming.count == 3, "three previews", "\(upcoming.count)")
    check(day(upcoming.first)?.day == 10, "first preview a week out", describe(upcoming.first))
}

// MARK: - Regressions found by code review

print("── Regressions ──")

do {
    // A decimal in a title must not be read as a date.
    for text in ["upgrade to swift 6.2", "buy 2.5 kg flour", "read chapter 3.1"] {
        let parsed = DateParser.parse(text, reference: reference)
        check(parsed.date == nil, "no date from “\(text)”", describe(parsed.date))
        check(parsed.cleanedText == text, "“\(text)” left intact", "got “\(parsed.cleanedText)”")
    }
    // A slash date still parses.
    let slash = DateParser.parse("ship it 25/12", reference: reference)
    check(day(slash.date)?.day == 25 && day(slash.date)?.month == 12, "25/12 still parses", describe(slash.date))
}

do {
    // Dotted meridiem: "\\b" after a "." can never match.
    let parsed = DateParser.parse("call at 9 p.m.", reference: reference)
    check(day(parsed.date)?.hour == 21, "9 p.m. is 21:00", describe(parsed.date))
    check(!parsed.cleanedText.lowercased().contains("p.m"), "meridiem stripped", "got “\(parsed.cleanedText)”")

    let plain = DateParser.parse("call at 9pm", reference: reference)
    check(day(plain.date)?.hour == 21, "9pm still 21:00", describe(plain.date))
    let morning = DateParser.parse("call at 9 a.m.", reference: reference)
    check(day(morning.date)?.hour == 9, "9 a.m. is 09:00", describe(morning.date))
}

do {
    // "tonight" is today with no time of its own, as the design's capture reads it.
    let parsed = DateParser.parse("dinner tonight", reference: reference)
    let d = day(parsed.date)
    check(d?.day == 3 && d?.hour == 0, "tonight is due today", describe(parsed.date))
    check(!parsed.includesTime, "tonight carries no time")
    check(parsed.cleanedText == "dinner", "tonight stripped", "got “\(parsed.cleanedText)”")
    check(parsed.consumedParts == [.day], "tonight is read as a day")

    let timed = DateParser.parse("dinner tonight at 7pm", reference: reference)
    check(day(timed.date)?.day == 3 && day(timed.date)?.hour == 19 && timed.includesTime,
          "tonight takes a time typed with it", describe(timed.date))
}

do {
    // "next week" is next Monday: from Wednesday 3 June that's the 8th, and
    // from Monday 8 June the Monday after.
    let parsed = DateParser.parse("plan the offsite next week", reference: reference)
    check(day(parsed.date)?.day == 8 && !parsed.includesTime, "next week is next Monday", describe(parsed.date))
    check(parsed.cleanedText == "plan the offsite", "next week stripped", "got “\(parsed.cleanedText)”")
    let monday = calendar.date(bySetting: .day, value: 8, of: reference)!
    let fromMonday = DateParser.parse("plan next week", reference: monday)
    check(day(fromMonday.date)?.day == 15, "next week from a Monday is the following Monday", describe(fromMonday.date))
}

do {
    // Each consumed range says what it was read as, so capture can tint and
    // preview exactly what it saves.
    let parsed = DateParser.parse("call mum tomorrow at 6pm every week", reference: reference)
    check(parsed.consumedParts == [.recurrence, .day, .time], "parts follow the consumed ranges", "\(parsed.consumedParts)")
    let ns = "call mum tomorrow at 6pm every week" as NSString
    check(parsed.consumedRanges.map { ns.substring(with: $0) } == ["every week", "tomorrow", "at 6pm"],
          "consumed ranges cover the phrases", "\(parsed.consumedRanges.map { ns.substring(with: $0) })")
    check(DateParser.parse("plain task", reference: reference).consumedParts.isEmpty, "nothing consumed, no parts")
}

do {
    // A repeat rule must not count as an explicit day: 06:00 has passed at the
    // 10:00 reference, so this should roll to tomorrow.
    let parsed = DateParser.parse("standup every day at 6am", reference: reference)
    let d = day(parsed.date)
    check(d?.day == 4 && d?.hour == 6, "repeat + past time rolls forward", describe(parsed.date))
    check(parsed.recurrence?.frequency == .daily, "still daily")
}

do {
    // Monthly with no explicit day-of-month used to stick after clamping:
    // Jan 31 → Feb 28 → Mar 28 → Apr 28 forever.
    // `anchored(to:)` is what the store applies when the rule is attached.
    let rule = Recurrence(frequency: .monthly, interval: 1).anchored(to: date(2026, 1, 31))
    check(rule.dayOfMonth == 31, "monthly rule pins the intended day", "\(rule.dayOfMonth ?? -1)")
    var cursor = date(2026, 1, 31)
    var seen: [Int] = []
    for _ in 0..<3 {
        guard let next = RecurrenceEngine.nextDate(rule: rule, dueDate: cursor, completedAt: cursor) else { break }
        seen.append(day(next)?.day ?? 0)
        cursor = next
    }
    check(seen == [28, 31, 30], "monthly recovers the 31st after clamping", "\(seen)")
}

do {
    // (year - startYear) * 52 drifts: 3-weekly from mid-December.
    let rule = Recurrence(frequency: .weekly, interval: 3, weekdays: [3])
    let start = date(2026, 12, 15)
    let next = RecurrenceEngine.nextDate(rule: rule, dueDate: start, completedAt: start)
    let gap = calendar.dateComponents([.day], from: start, to: next ?? start).day ?? 0
    check(gap == 21, "every 3 weeks across a year boundary is 21 days", "\(gap) days")
}

do {
    // Reference is a Wednesday. A Monday-only rule should start next Monday,
    // not today.
    let parsed = DateParser.parse("book flights every monday", reference: reference)
    let d = day(parsed.date)
    check(d?.day == 8, "weekday rule starts on its first matching day", describe(parsed.date))
    check(parsed.recurrence?.weekdays == [2], "monday captured")

    // A rule that matches today starts today.
    let wed = DateParser.parse("standup every wednesday", reference: reference)
    check(day(wed.date)?.day == 3, "rule matching today starts today", describe(wed.date))

    // Weekday-agnostic rules still start today.
    let daily = DateParser.parse("water plants every day", reference: reference)
    check(day(daily.date)?.day == 3, "daily rule still starts today", describe(daily.date))

    // Reference is Wednesday; "every weekend" should reach Saturday.
    let weekend = DateParser.parse("tidy up every weekend", reference: reference)
    check(day(weekend.date)?.day == 6, "weekend rule starts Saturday", describe(weekend.date))
}

// MARK: - Recurrence descriptions

print("── Recurrence display ──")

check(Recurrence.daily.displayText == "Every day", "daily text", Recurrence.daily.displayText)
check(Recurrence.weekdaysOnly.displayText == "Every weekday", "weekday text", Recurrence.weekdaysOnly.displayText)
check(
    Recurrence(frequency: .daily, interval: 3).displayText == "Every 3 days",
    "interval text",
    Recurrence(frequency: .daily, interval: 3).displayText
)

do {
    let encoded = Recurrence.weekdaysOnly.jsonData
    let decoded = Recurrence.decode(encoded)
    check(decoded == Recurrence.weekdaysOnly, "round-trips through JSON")
}

// MARK: - Summary

print("")
if failures == 0 {
    print("✅ \(checks) checks passed")
} else {
    print("❌ \(failures) of \(checks) checks failed")
}
exit(failures == 0 ? 0 : 1)
