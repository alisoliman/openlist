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
    Item(id: "one-minute-planned", top: 200, height: 20), Item(id: "following-task", top: 206, height: 20)
])
expect(shortTasks.allSatisfy { $0.laneCount == 2 }, "Readable short-task targets cannot cover the following task")
expect(shortTasks.map(\.top) == [200, 206], "Readable minimum height does not move the actual start positions")
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
print("Calendar layout: \(checks) checks passed")
