import Foundation
import SwiftData
import SwiftUI

var checks = 0

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    guard condition() else { fatalError("FAIL: \(message)") }
}

if CommandLine.arguments.count == 3 {
    let mode = CommandLine.arguments[1]
    let suite = CommandLine.arguments[2]
    let defaults = UserDefaults(suiteName: suite)!
    let preference = AppStorage(wrappedValue: TodaySorting.default, TodaySorting.preferenceKey, store: defaults)
    switch mode {
    case "write":
        defaults.removePersistentDomain(forName: suite)
        check(preference.wrappedValue == .default, "new local preferences use Default")
        for option in TodaySorting.allCases {
            preference.wrappedValue = option
            check(defaults.string(forKey: TodaySorting.preferenceKey) == option.rawValue, "every choice writes through AppStorage")
        }
        defaults.set("unknown-future-order", forKey: TodaySorting.preferenceKey)
        let unknownPreference = AppStorage(wrappedValue: TodaySorting.default, TodaySorting.preferenceKey, store: defaults)
        check(unknownPreference.wrappedValue == .default, "unknown saved preferences fall back to Default")
        preference.wrappedValue = .priority
    case "relaunch":
        check(preference.wrappedValue == .priority, "selected sort survives a new process")
        preference.wrappedValue = .default
    case "reset":
        check(preference.wrappedValue == .default, "reset to Default survives a new process")
        defaults.removePersistentDomain(forName: suite)
    default: fatalError("Unknown preference check")
    }
    check(defaults.synchronize(), "preferences flush for the next process")
    print("✅ \(checks) Today preference checks passed (\(mode))")
    exit(0)
}

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(secondsFromGMT: 0)!
let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 13, hour: 12))!
let today = calendar.startOfDay(for: now)
let yesterday = today.addingTimeInterval(-86_400)
let tomorrow = today.addingTimeInterval(86_400)

let list = TaskList(title: "First")
let secondList = TaskList(title: "Second")
secondList.sortIndex = 1
let archived = TaskList(title: "Archived")
archived.isArchived = true
let alias = TaskList(title: "Merged alias")
alias.mergedIntoID = list.id
let lists = [secondList, archived, alias, list]
var nextID = 0

func task(
    _ title: String, due: Date? = nil, timed: Bool = false,
    priority: TaskPriority = .none, starred: Bool = false,
    selected: Date? = nil, completed: Date? = nil,
    listID: UUID? = nil, order: Double = 0
) -> Block {
    nextID += 1
    let value = Block(kind: .task, text: title, listID: listID ?? list.id, sortIndex: order)
    value.id = UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", nextID))")!
    value.createdAt = yesterday.addingTimeInterval(Double(nextID))
    value.updatedAt = value.createdAt
    value.dueDate = due
    value.includesTime = timed
    value.priority = priority
    value.isStarred = starred
    value.selectedForDay = selected
    value.isCompleted = completed != nil
    value.completedAt = completed
    return value
}

func bucket(_ blocks: [Block], _ sorting: TodaySorting = .default) -> TodayTaskBuckets {
    TodayTaskBuckets(blocks: blocks, lists: lists, sorting: sorting, now: now, calendar: calendar)
}

func groups(_ value: TodayTaskBuckets) -> [[UUID]] {
    [value.overdue, value.dueToday, value.selected, value.starred, value.completedToday].map { $0.map(\.id) }
}

func checkOrder(_ actual: [Block], _ expected: [Block], _ message: String) {
    check(actual.map(\.id) == expected.map(\.id), message)
}

let lateOld = task("Old deadline", due: yesterday, priority: .low)
let lateHigh = task("High at same deadline", due: yesterday, priority: .high)
let elapsed = task("Timed earlier today", due: today.addingTimeInterval(3_600), timed: true, starred: true, selected: today)
let allDay = task("All day high", due: today, priority: .high)
let timedFirst = task("One pm", due: today.addingTimeInterval(13 * 3_600), timed: true)
let timedLast = task("Two pm", due: today.addingTimeInterval(14 * 3_600), timed: true, priority: .high)
let planned = task("Carried forward", starred: true, selected: yesterday)
let futurePlanned = task("Tomorrow planned", selected: tomorrow)
let starred = task("Starred future deadline", due: tomorrow, starred: true)
let plain = task("Unscheduled")
let completedEarly = task("Completed early", due: yesterday, starred: true, completed: today.addingTimeInterval(3_600))
let completedLate = task("Completed late", completed: now)
let completedYesterday = task("Completed yesterday", completed: yesterday)
let archivedTask = task("Archived due", due: yesterday, listID: archived.id)
let aliasTask = task("Merged list due", due: yesterday, listID: alias.id)
let orphanTask = task("Missing list due", due: yesterday, listID: UUID())
let prose = Block(kind: .paragraph, text: "Not a task", listID: list.id)
prose.dueDate = yesterday
let fixtures = [timedLast, lateOld, completedEarly, plain, planned, archivedTask, prose, starred,
                lateHigh, elapsed, allDay, timedFirst, completedLate, completedYesterday,
                futurePlanned, aliasTask, orphanTask]
let original = bucket(fixtures)
checkOrder(original.overdue, [lateHigh, lateOld, elapsed], "Default retains overdue deadline then priority ordering")
checkOrder(original.dueToday, [timedFirst, timedLast, allDay], "Default retains timed-first due-today ordering")
checkOrder(original.selected, [planned], "past planned selections carry forward before starred membership")
checkOrder(original.starred, [starred], "starred future work stays in Today")
checkOrder(original.completedToday, [completedLate, completedEarly], "Default retains newest completion first")

for sorting in TodaySorting.allCases {
    let result = bucket(fixtures, sorting)
    check(groups(result).map(Set.init) == groups(original).map(Set.init), "\(sorting.title) preserves every section membership")
    check(!result.isEmpty(showsCompleted: false), "\(sorting.title) retains active sections with completions hidden")
    let onlyCompleted = bucket([completedLate], sorting)
    check(onlyCompleted.isEmpty(showsCompleted: false), "\(sorting.title) respects hidden completed empty state")
    check(!onlyCompleted.isEmpty(showsCompleted: true), "\(sorting.title) respects shown completed empty state")
    check(bucket([], sorting).isEmpty(showsCompleted: true), "\(sorting.title) handles an empty Today")
    check(groups(bucket(fixtures)) == groups(original), "Default is restored after \(sorting.title)")
}

let zulu = task("Zulu", priority: .high, starred: true, order: 100)
let alpha = task("alpha", due: tomorrow.addingTimeInterval(3_600), timed: true, starred: true, order: 10)
let beta = task("Beta", due: tomorrow, priority: .medium, starred: true, listID: secondList.id, order: -100)
let sameDue = task("Gamma", due: tomorrow, priority: .low, starred: true, order: 20)
let orderFixtures = [beta, zulu, sameDue, alpha]
checkOrder(bucket(orderFixtures, .priority).starred, [zulu, beta, sameDue, alpha], "priority descends from high through none")
checkOrder(bucket(orderFixtures, .dueDate).starred, [beta, sameDue, alpha, zulu], "due dates ascend with stable equal dates and undated last")
checkOrder(bucket(orderFixtures, .alphabetical).starred, [alpha, beta, sameDue, zulu], "alphabetical ignores letter case")
checkOrder(bucket(orderFixtures, .createdAt).starred, [zulu, alpha, beta, sameDue], "creation date puts oldest first")
checkOrder(bucket(orderFixtures, .listOrder).starred, [alpha, sameDue, zulu, beta], "list position precedes stored task position")

let heading = Block(kind: .heading1, text: "Context", listID: list.id, sortIndex: 15)
heading.isCollapsed = true
let nested = task("Nested under prose", starred: true, order: -1_000)
nested.parentID = heading.id
checkOrder(bucket(orderFixtures + [heading, nested], .listOrder).starred, [alpha, nested, sameDue, zulu, beta],
           "nested tasks follow their prose ancestor even when collapsed")

let tieFirst = task("same", starred: true)
let tieSecond = task("SAME", starred: true)
tieSecond.createdAt = tieFirst.createdAt
for sorting in TodaySorting.allCases {
    checkOrder(bucket([tieSecond, tieFirst], sorting).starred, [tieFirst, tieSecond], "\(sorting.title) breaks exact ties by stable identity")
    checkOrder(bucket([tieFirst, tieSecond], sorting).starred, [tieFirst, tieSecond], "\(sorting.title) ignores incoming fetch order for ties")
}

// The same objects are edited between projections, as query-backed views do.
alpha.priority = .high
zulu.priority = .none
checkOrder(bucket(orderFixtures, .priority).starred, [alpha, beta, sameDue, zulu], "priority edits immediately change ordering")
zulu.dueDate = tomorrow.addingTimeInterval(-1)
checkOrder(bucket(orderFixtures, .dueDate).dueToday, [zulu], "due edits immediately change section membership")
sameDue.text = "Aardvark"
checkOrder(bucket(orderFixtures, .alphabetical).starred, [sameDue, alpha, beta], "title edits immediately change ordering")
alpha.isCompleted = true
alpha.completedAt = now
checkOrder(bucket(orderFixtures, .priority).completedToday, [alpha], "completion immediately enters completed-today section")
alpha.isCompleted = false
alpha.completedAt = nil
alpha.selectedForDay = today
checkOrder(bucket(orderFixtures, .priority).selected, [alpha], "reopening and planning immediately restore active membership")
alpha.selectedForDay = nil
alpha.listID = secondList.id
checkOrder(bucket(orderFixtures, .listOrder).starred, [sameDue, beta, alpha], "list edits immediately update list ordering")
secondList.sortIndex = -1
checkOrder(bucket(orderFixtures, .listOrder).starred, [beta, alpha, sameDue], "list position edits immediately update ordering")
secondList.sortIndex = 1

let directory = FileManager.default.temporaryDirectory.appendingPathComponent("openlist-today-sorting-\(UUID())")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
let schema = Schema([TaskList.self, Block.self])
let configuration = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("test.store"))
let persistedOrder: [[UUID]]
do {
    let container = try ModelContainer(for: schema, configurations: [configuration])
    let context = ModelContext(container)
    for item in lists { context.insert(item) }
    for item in fixtures + orderFixtures + [heading, nested, tieFirst, tieSecond] { context.insert(item) }
    try context.save()
    let blocks = try context.fetch(FetchDescriptor<Block>())
    persistedOrder = groups(bucket(blocks))
    for sorting in TodaySorting.allCases {
        _ = bucket(blocks, sorting)
        check(!context.hasChanges, "\(sorting.title) does not mutate persisted task, hierarchy, or list fields")
    }
}
do {
    let container = try ModelContainer(for: schema, configurations: [configuration])
    let context = ModelContext(container)
    let blocks = try context.fetch(FetchDescriptor<Block>())
    let reopenedLists = try context.fetch(FetchDescriptor<TaskList>())
    let reopened = TodayTaskBuckets(blocks: blocks, lists: reopenedLists, now: now, calendar: calendar)
    check(groups(reopened) == persistedOrder, "Default returns the same order after reopening the disk store")
    check(blocks.first { $0.id == nested.id }?.parentID == heading.id, "sorting preserves the stored parent relationship")
    check(blocks.first { $0.id == nested.id }?.sortIndex == -1_000, "sorting preserves fractional document position")
    check(reopenedLists.allSatisfy { $0.sorting == .manual }, "sorting Today preserves per-list sorting preferences")
}

print("✅ \(checks) Today sorting and persistence checks passed")
