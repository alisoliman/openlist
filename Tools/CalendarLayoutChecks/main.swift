import Foundation

var checks = 0
@MainActor func expect(_ value: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !value() { fatalError(message) }
}
typealias Item = CalendarOverlapLayout.Item
let independent = CalendarOverlapLayout.arrange([
    Item(id: "a", top: 0, height: 30), Item(id: "b", top: 30, height: 30)
])
expect(independent.allSatisfy { $0.lane == 0 && $0.laneCount == 1 }, "Touching blocks use full width")
let overlap = [Item(id: "completed", top: 60, height: 30), Item(id: "planned", top: 60, height: 60)]
let lanes = CalendarOverlapLayout.arrange(overlap)
expect(lanes.count == 2 && lanes.allSatisfy { $0.laneCount == 2 }, "Completed and reused planned time get side-by-side lanes")
expect(Set(lanes.map(\.lane)).count == 2, "Coincident rectangles never share a lane")
expect(lanes == CalendarOverlapLayout.arrange(overlap.reversed()), "Input order cannot change visual lane assignment")
let chain = CalendarOverlapLayout.arrange([
    Item(id: "a", top: 0, height: 30), Item(id: "b", top: 20, height: 30),
    Item(id: "c", top: 40, height: 30), Item(id: "d", top: 70, height: 20)
])
expect(chain.prefix(3).allSatisfy { $0.laneCount == 2 }, "Overlap chains use consistent widths")
expect(chain[0].lane == chain[2].lane, "Lanes are reused after their earlier interval ends")
expect(chain[3].laneCount == 1, "Width recovers after the overlap group")
let markers = CalendarOverlapLayout.arrange([
    Item(id: "legacy-marker", top: 200, height: 38), Item(id: "next-task", top: 215, height: 30)
])
expect(markers.allSatisfy { $0.laneCount == 2 }, "Minimum rendered height participates in marker collisions")
let shortTasks = CalendarOverlapLayout.arrange([
    Item(id: "one-minute-tracked", top: 200, height: 20), Item(id: "following-task", top: 206, height: 20)
])
expect(shortTasks.allSatisfy { $0.laneCount == 2 }, "Recorded work keeps its drawn box, so the following task cannot cover it")
expect(shortTasks.map(\.top) == [200, 206], "Readable minimum height does not move the actual start positions")
// The design's lanes follow the items' times: a 15-minute meeting at 09:30
// (drawn 16pt from 61) and a task at its 09:45 end (from 71) keep full width,
// the later one drawn over the meeting's minimum-height bottom.
let backToBack = CalendarOverlapLayout.arrange([
    Item(id: "meeting", top: 61, height: 16, end: 71), Item(id: "task", top: 71, height: 18, end: 81)
])
expect(backToBack.allSatisfy { $0.lane == 0 && $0.laneCount == 1 }, "An item starting when another's time ends keeps full width")
expect(backToBack.map(\.height) == [16, 18], "Minimum heights are still drawn over time-based lanes")
let slots = CalendarOverlapLayout.arrange((0..<3).map {
    Item(id: "slot-\($0)", top: 41 + Double($0) * 20 / 3, height: 18, end: 41 + Double($0 + 1) * 20 / 3)
})
expect(slots.allSatisfy { $0.laneCount == 1 }, "Consecutive 10-minute slots keep full width")
let minuteOverlap = CalendarOverlapLayout.arrange([
    Item(id: "long", top: 41, height: 38, end: 81), Item(id: "early", top: 80.4, height: 18, end: 100)
])
expect(minuteOverlap.allSatisfy { $0.laneCount == 2 }, "Times that overlap by a minute still share the width")
let reused = CalendarOverlapLayout.arrange([
    Item(id: "a", top: 0, height: 18, end: 10), Item(id: "b", top: 0, height: 40, end: 40),
    Item(id: "c", top: 10, height: 18, end: 20)
])
let reusedLanes = Dictionary(uniqueKeysWithValues: reused.map { ($0.id, $0) })
expect(reused.allSatisfy { $0.laneCount == 2 }, "A time-based group sizes its lanes by overlapping time")
expect(reusedLanes["b"]?.lane == 0 && reusedLanes["a"]?.lane == 1 && reusedLanes["c"]?.lane == 1,
       "The longer of two same-start items takes the first lane, and a lane is reused once its time ends")
// A zero-length item has only its start, as the design's: longer time at the
// same start goes first and pushes it to another lane, and what comes after
// it keeps the full width.
let zeroLength = CalendarOverlapLayout.arrange([
    Item(id: "instant", top: 100, height: 16, end: 100), Item(id: "task", top: 100, height: 30, end: 130)
])
let zeroLengthLanes = Dictionary(uniqueKeysWithValues: zeroLength.map { ($0.id, $0) })
expect(zeroLength.allSatisfy { $0.laneCount == 2 } && zeroLengthLanes["task"]?.lane == 0,
       "A zero-length item within another's time takes the next lane")
let afterInstant = CalendarOverlapLayout.arrange([
    Item(id: "instant", top: 100, height: 16, end: 100), Item(id: "task", top: 105, height: 30, end: 135)
])
expect(afterInstant.allSatisfy { $0.laneCount == 1 }, "What starts after a zero-length item keeps the full width")
let mixed = CalendarOverlapLayout.arrange([
    Item(id: "recorded", top: 200, height: 18), Item(id: "planned", top: 203, height: 18, end: 213),
    Item(id: "after", top: 213, height: 18, end: 223)
])
expect(mixed.allSatisfy { $0.laneCount == 2 }, "Recorded work's box and planned time join one group")
// Items as the day column builds them, with 40pt hours from 08:00.
let eight = Date(timeIntervalSinceReferenceDate: 800_000_000)
@MainActor func at(_ hours: Double) -> Date { eight.addingTimeInterval(hours * 3_600) }
@MainActor func y(_ time: Date) -> Double { time.timeIntervalSince(eight) / 3_600 * 40 }
@MainActor func block(_ id: String, _ start: Double, _ end: Double, placed: Bool = false, done: Bool = false,
                      tracked: Bool = false, keepsSlot: Bool = false) -> Item {
    .block(PlannedBlock(id: id, taskID: UUID(), occurrenceID: UUID(), start: at(start), end: at(end), isPinned: false,
                        placementID: placed ? UUID() : nil, conflicts: [], completionID: done ? UUID() : nil,
                        isTimeTracked: tracked, keepsSlot: keepsSlot), y: y)
}
@MainActor func event(_ id: String, _ start: Double, _ end: Double) -> Item {
    .event(FixedBusyTime(id: id, title: id, start: at(start), end: at(end)), y: y)
}
@MainActor func widths(_ items: [Item]) -> [String: Int] {
    Dictionary(uniqueKeysWithValues: CalendarOverlapLayout.arrange(items).map { ($0.id, $0.laneCount) })
}
// Two quarter-hour Plan slots in a row, the first worked in and done: its
// done block keeps the slot's time, as the design's done placement, so the
// layout doesn't change when the work is done.
expect(widths([block("working", 1.5, 1.75, placed: true), block("next", 1.75, 2, placed: true)]).values.allSatisfy { $0 == 1 },
       "Work running in a slot, followed by the next slot, keeps the full width")
expect(widths([block("done", 1.5, 1.75, done: true, tracked: true, keepsSlot: true),
               block("next", 1.75, 2, placed: true)]).values.allSatisfy { $0 == 1 },
       "Tracked work done in a slot, followed by the next slot, keeps the full width")
expect(widths([block("done", 1.5, 1.75, done: true, keepsSlot: true),
               block("next", 1.75, 2, placed: true)]).values.allSatisfy { $0 == 1 },
       "A slot ticked done without tracking, followed by the next slot, keeps the full width")
expect(widths([block("away", 2, 2.05, done: true, tracked: true), block("next", 2.05, 2.5, placed: true)]).values.allSatisfy { $0 == 2 },
       "Three minutes tracked outside any slot keep their box beside the work after them")
expect(widths([block("unslotted", 2, 2.1), block("next", 2.1, 2.5, placed: true)]).values.allSatisfy { $0 == 2 },
       "Work running or paused with no slot keeps its box beside the work after it")
expect(widths([event("standup", 1.5, 1.75), block("task", 1.75, 2, placed: true)]).values.allSatisfy { $0 == 1 },
       "A task at a short meeting's end keeps the full width")
// A meeting over the same times as a block goes first, as the design lists
// meetings before blocks, whatever their ids or minimum heights.
for (start, end) in [(3.0, 3.25), (3.0, 4.0)] {
    let tie = CalendarOverlapLayout.arrange([block("a-block", start, end, placed: true), event("z-meeting", start, end)])
    expect(tie.first { $0.id == "z-meeting" }?.lane == 0 && tie.first { $0.id == "a-block" }?.lane == 1,
           "A meeting takes the first lane over a block with the same times")
}
let sameStart = (0..<12).map { Item(id: "item-\($0)", top: 200, height: Double(10 + $0)) }
let dense = CalendarOverlapLayout.arrange(sameStart)
expect(dense.allSatisfy { $0.laneCount == 12 }, "Dense history keeps every item in a separate lane")
expect(Set(dense.map(\.lane)).count == 12, "Dense lane identities are unique")
let invalid = CalendarOverlapLayout.arrange([
    Item(id: "nan", top: .nan, height: 2), Item(id: "infinite", top: 0, height: .infinity),
    Item(id: "empty", top: 0, height: 0), Item(id: "valid", top: 0, height: 3)
])
expect(invalid.map(\.id) == ["valid"], "Malformed display rectangles cannot poison layout")
// Deterministic varied intervals: no pair in a lane can visually intersect.
let varied: [Item] = (0..<80).map { index in
    let top = Double((index * 37) % 600)
    let height = Double(3 + (index * 13) % 100)
    return Item(id: "block-\(index)", top: top, height: height)
}
let arranged = CalendarOverlapLayout.arrange(varied)
expect(arranged.count == varied.count, "Layout never hides historical or upcoming rectangles")
expect(arranged == CalendarOverlapLayout.arrange(varied.reversed()), "Varied layout is independent of fetch order")
for (index, left) in arranged.enumerated() {
    for right in arranged.dropFirst(index + 1) where left.top < right.top + right.height && right.top < left.top + left.height {
        expect(left.lane != right.lane, "Overlapping rectangles have distinct lanes")
        expect(left.laneCount == right.laneCount, "Connected rectangles have matching widths")
    }
}
// The same with time-based ends: no two items whose times overlap share a lane.
let timed: [Item] = (0..<80).map { index in
    let top = Double((index * 37) % 600)
    return Item(id: "timed-\(index)", top: top, height: 18, end: top + Double(1 + (index * 7) % 30))
}
let ends = Dictionary(uniqueKeysWithValues: timed.map { ($0.id, $0.end) })
let arrangedTimes = CalendarOverlapLayout.arrange(timed)
expect(arrangedTimes == CalendarOverlapLayout.arrange(timed.reversed()), "Time-based layout is independent of fetch order")
for (index, left) in arrangedTimes.enumerated() {
    for right in arrangedTimes.dropFirst(index + 1) where left.top < ends[right.id]! && right.top < ends[left.id]! {
        expect(left.lane != right.lane, "Items whose times overlap have distinct lanes")
        expect(left.laneCount == right.laneCount, "Items whose times connect have matching widths")
    }
}
// The scheduling grid respects first weekday, leap years and local day
// boundaries, including the short/long days when Amsterdam changes clocks.
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
for firstWeekday in [1, 2, 7] {
    calendar.firstWeekday = firstWeekday
    for (year, month) in [(2024, 2), (2026, 3), (2026, 10), (2026, 12)] {
        let date = calendar.date(from: DateComponents(year: year, month: month, day: 15))!
        let days = CalendarMonthGrid.days(in: date, calendar: calendar)
        expect(days.count == 42 && Set(days).count == 42, "Grid keeps six complete, unique weeks")
        expect(calendar.component(.weekday, from: days[0]) == firstWeekday, "Grid starts on the preferred weekday")
        expect(days.allSatisfy { calendar.startOfDay(for: $0) == $0 }, "Every day uses local midnight")
        let inMonth = days.filter { calendar.isDate($0, equalTo: date, toGranularity: .month) }
        expect(inMonth.count == calendar.range(of: .day, in: .month, for: date)!.count, "Grid includes every day of the month")
        for (previous, next) in zip(days, days.dropFirst()) {
            expect(calendar.dateComponents([.day], from: previous, to: next).day == 1, "Adjacent cells remain consecutive across DST")
        }
    }
}
// The Next date and time pills: days before the earliest can't be picked, and
// a time lands on the wall clock of its day, never before the earliest.
calendar.firstWeekday = 2
let earliest = calendar.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 14, minute: 37))!
let dayBefore = calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 23, minute: 59))!
expect(CalendarMonthGrid.isBefore(dayBefore, earliest: earliest, calendar: calendar), "The day before the earliest can't be picked")
expect(!CalendarMonthGrid.isBefore(calendar.startOfDay(for: earliest), earliest: earliest, calendar: calendar),
       "The earliest's own day can be picked, from its midnight")
expect(!CalendarMonthGrid.isBefore(dayBefore, earliest: nil, calendar: calendar), "Without an earliest every day can be picked")
expect(CalendarMonthGrid.minute(of: earliest, calendar: calendar) == 14 * 60 + 37, "A time reads as minutes after midnight")
let nine = CalendarMonthGrid.date(earliest, atMinute: 9 * 60, calendar: calendar)
expect(calendar.isDate(nine, inSameDayAs: earliest) && CalendarMonthGrid.minute(of: nine, calendar: calendar) == 540,
       "A time lands on its own day")
expect(CalendarMonthGrid.date(earliest, atMinute: 9 * 60, notBefore: earliest, calendar: calendar) == earliest,
       "A time earlier than the earliest becomes the earliest")
// Arrow keys stop at the earliest day, a cell of its month's grid, and never
// take focus, or the month shown, before it.
@MainActor func moved(_ day: Date, _ amount: Int, earliest: Date?) -> Date? {
    CalendarMonthGrid.day(day, movedBy: amount, earliest: earliest, calendar: calendar)
}
let earliestDay = calendar.startOfDay(for: earliest)
expect(moved(earliestDay, -1, earliest: earliest) == earliestDay, "Left from the earliest day stays on it")
expect(CalendarMonthGrid.days(in: earliest, calendar: calendar).contains(earliestDay),
       "The earliest day focus stops at is one of the grid's own cells")
let monday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28))!
expect(moved(monday, -7, earliest: earliest) == earliestDay, "Up past the earliest day stops on it")
expect(moved(earliestDay, 1, earliest: earliest) == calendar.date(byAdding: .day, value: 1, to: earliestDay),
       "Right from the earliest day moves on")
expect(moved(earliestDay, -1, earliest: nil) == calendar.date(byAdding: .day, value: -1, to: earliestDay),
       "Without an earliest the arrows go back freely")
let firstOfOctober = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 9))!
let thirdOfOctober = calendar.date(from: DateComponents(year: 2026, month: 10, day: 3))!
expect(moved(thirdOfOctober, -7, earliest: firstOfOctober).map {
    calendar.isDate($0, equalTo: firstOfOctober, toGranularity: .month)
} == true, "Up from the earliest month's first week stays in that month")
let later = CalendarMonthGrid.date(earliest, atMinute: 16 * 60, notBefore: earliest, calendar: calendar)
expect(CalendarMonthGrid.minute(of: later, calendar: calendar) == 960, "A time after the earliest stays as picked")
// Amsterdam skips 02:00–03:00 on 29 March 2026.
let springForward = calendar.date(from: DateComponents(year: 2026, month: 3, day: 29))!
let skipped = CalendarMonthGrid.date(springForward, atMinute: 2 * 60 + 30, calendar: calendar)
expect(calendar.isDate(skipped, inSameDayAs: springForward) && CalendarMonthGrid.minute(of: skipped, calendar: calendar) >= 180,
       "A time the clock skips becomes the next one there is, that day")
let fallBack = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25))!
expect(CalendarMonthGrid.minute(of: CalendarMonthGrid.date(fallBack, atMinute: 23 * 60 + 45, calendar: calendar), calendar: calendar) == 1425,
       "A late time on the long day stays on the wall clock")
// The day column reads times on the clock, as its hour labels and now line do:
// on the days Amsterdam changes clocks 10:00 is 9 or 11 hours after midnight,
// yet a meeting then still draws on the 10:00 row, and lunch on the 12:00 one.
@MainActor func clockHours(_ time: Date, on day: Date) -> Double { CalendarOverlapLayout.hours(time, on: day, calendar: calendar) }
for day in [springForward, fallBack] {
    let ten = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: day)!
    let eleven = calendar.date(bySettingHour: 11, minute: 0, second: 0, of: day)!
    expect(ten.timeIntervalSince(calendar.startOfDay(for: day)) != 10 * 3_600, "The day changes clocks before 10:00")
    expect(clockHours(ten, on: day) == 10, "10:00 reads 10 on a day the clocks change")
    let late = calendar.date(bySettingHour: 10, minute: 40, second: 30, of: day)!
    expect(abs(clockHours(late, on: day) - (10 + 40.0 / 60 + 30.0 / 3_600)) < 1e-9, "Minutes and seconds count on the clock too")
    let meeting = Item.event(FixedBusyTime(id: "meeting", title: "meeting", start: ten, end: eleven)) {
        (clockHours($0, on: day) - 8) * 40
    }
    expect(meeting.top == 81 && meeting.height == 38, "A meeting at 10:00 draws on the 10:00 row, an hour tall")
    let noon = CalendarOverlapLayout.time(minute: 12 * 60, on: day, calendar: calendar)
    let one = CalendarOverlapLayout.time(minute: 13 * 60, on: day, calendar: calendar)
    expect(clockHours(noon, on: day) == 12 && clockHours(one, on: day) == 13, "Lunch stays on 12:00–13:00 by the clock")
    expect(one.timeIntervalSince(noon) == 3_600, "Lunch is an hour long")
    let midnight = CalendarOverlapLayout.time(minute: 1_440, on: day, calendar: calendar)
    expect(midnight == calendar.date(byAdding: .day, value: 1, to: day) && clockHours(midnight, on: day) == 24,
           "A break to 24:00 ends at the next midnight, the day's last row")
}
expect(clockHours(CalendarOverlapLayout.time(minute: 2 * 60 + 30, on: springForward, calendar: calendar), on: springForward) == 3,
       "A break from a time the clocks skip starts at the next one there is")
let halfPastOne = calendar.date(byAdding: .minute, value: 90, to: calendar.date(byAdding: .day, value: 1, to: fallBack)!)!
expect(clockHours(halfPastOne, on: fallBack) == 25.5, "Past midnight the hours go on counting")
print("Calendar layout: \(checks) checks passed")
