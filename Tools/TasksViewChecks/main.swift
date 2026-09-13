import Foundation
import Observation
import SwiftData
import os

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    guard condition() else { fatalError("FAIL: \(message)") }
}
func ids(_ tasks: [Block]) -> [UUID] { tasks.map(\.id) }
func checkOrder(_ actual: [Block], _ expected: [Block], _ message: String) {
    check(ids(actual) == ids(expected), message)
}

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(secondsFromGMT: 0)!
let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 13, hour: 12))!
let today = calendar.startOfDay(for: now)
let yesterday = today.addingTimeInterval(-86_400)
let tomorrow = today.addingTimeInterval(86_400)
let firstList = TaskList(title: "List-only needle")
let secondList = TaskList(title: "List-only needle")
let archivedList = TaskList(title: "Archived")
archivedList.isArchived = true
let mergedList = TaskList(title: "Alias")
mergedList.mergedIntoID = firstList.id
let lists = [firstList, secondList, archivedList, mergedList]
let firstLabel = TaskLabel(name: "Label-only needle")
let secondLabel = TaskLabel(name: "Label-only needle")
let labels = [firstLabel, secondLabel]
var nextID = 0

func task(_ title: String, due: Date? = nil, completed: Bool = false, listID: UUID? = nil) -> Block {
    nextID += 1
    let value = Block(kind: .task, text: title, listID: listID ?? firstList.id, sortIndex: Double(nextID))
    value.id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", nextID))!
    value.createdAt = yesterday.addingTimeInterval(Double(nextID))
    value.updatedAt = value.createdAt
    value.dueDate = due
    value.isCompleted = completed
    value.completedAt = completed ? now : nil
    return value
}

func project(_ tasks: [Block], _ options: TasksViewOptions = TasksViewOptions(), labels currentLabels: [TaskLabel] = labels) -> TasksProjection {
    TasksProjection(tasks: tasks, lists: lists, labels: currentLabels, options: options, now: now, calendar: calendar)
}

let zulu = task("Zulu", due: tomorrow)
let alpha = task("alpha")
let beta = task("Beta", due: today, listID: secondList.id)
let delta = task("Delta", due: yesterday, completed: true)
zulu.isStarred = true
zulu.priority = .high
beta.priority = .medium
zulu.labelIDs = [firstLabel.id, secondLabel.id, firstLabel.id]
alpha.labelIDs = [UUID()]
beta.labelIDs = [firstLabel.id, UUID()]
let fixtures = [beta, delta, alpha, zulu]
var all = TasksViewOptions(filter: .all, grouping: .none)

for (sorting, ascending, expected) in [
    (TaskSorting.dueDate, true, [delta, beta, zulu, alpha]),
    (.dueDate, false, [zulu, beta, delta, alpha]),
    (.alphabetical, true, [alpha, beta, delta, zulu]),
    (.alphabetical, false, [zulu, delta, beta, alpha]),
    (.createdAt, true, [zulu, alpha, beta, delta]),
    (.createdAt, false, [delta, beta, alpha, zulu])
] {
    all.sorting = sorting
    all.ascending = ascending
    checkOrder(project(fixtures, all).matching, expected, "\(sorting) direction \(ascending) orders the complete result")
}

let tieEarly = task("Same", due: tomorrow)
let tieLate = task("Same", due: tomorrow)
let tieID = task("Same", due: tomorrow)
tieID.createdAt = tieEarly.createdAt
for sorting in TaskSorting.allCases {
    for ascending in [true, false] {
        let result = sorting.sorted([tieLate, tieID, tieEarly], ascending: ascending)
        let expected = sorting == .createdAt && !ascending ? [tieLate, tieEarly, tieID] : [tieEarly, tieID, tieLate]
        checkOrder(result, expected, "\(sorting) \(ascending) reverses only its primary key, with creation/UUID ties")
        checkOrder(sorting.sorted([tieEarly, tieID, tieLate], ascending: ascending), expected, "ties ignore fetch order")
    }
}
let blank = task(" \n ")
let namedUntitled = task("Untitled")
namedUntitled.createdAt = blank.createdAt
checkOrder(TaskSorting.alphabetical.sorted([namedUntitled, blank], ascending: false), [blank, namedUntitled], "blank titles compare as displayed Untitled with stable ties")

let membershipByGroup: [TaskGrouping: [String: Set<UUID>]] = [
    .none: ["all": Set(ids(fixtures))],
    .dueDate: ["today": [beta.id], "week": [zulu.id], "nodate": [alpha.id], "done": [delta.id]],
    .list: ["list-\(firstList.id)": [zulu.id, alpha.id, delta.id], "list-\(secondList.id)": [beta.id]],
    .label: ["label-\(firstLabel.id)": [zulu.id, beta.id], "label-\(secondLabel.id)": [zulu.id], "label-none": [alpha.id, delta.id]],
    .priority: ["priority-3": [zulu.id], "priority-2": [beta.id], "priority-0": [alpha.id, delta.id]]
]
for grouping in TaskGrouping.allCases {
    for sorting in TaskSorting.allCases {
        for ascending in [true, false] {
            all.grouping = grouping
            all.sorting = sorting
            all.ascending = ascending
            let projection = project(fixtures, all)
            let membership = Dictionary(uniqueKeysWithValues: projection.groups.map { ($0.id, Set(ids($0.tasks))) })
            check(membership == membershipByGroup[grouping], "\(grouping) retains membership under \(sorting) \(ascending)")
            check(projection.uniqueTaskCount == 4, "\(grouping) counts tasks once before label appearances")
            for group in projection.groups {
                let expected = projection.matching.filter { Set(ids(group.tasks)).contains($0.id) }
                checkOrder(group.tasks, expected, "\(group.id) follows selected order, including No date and Completed")
                check(Set(ids(group.tasks)).count == group.tasks.count, "duplicate label IDs never duplicate rows within a group")
            }
        }
    }
}

let needle = task("Café needle")
let completedNeedle = task("Café needle completed", completed: true)
let otherListNeedle = task("Café needle elsewhere", listID: secondList.id)
let noteOnly = task("Unrelated")
noteOnly.note = "Café needle"
noteOnly.labelIDs = [firstLabel.id]
let child = task("Child without a match")
child.parentID = needle.id
let paragraph = Block(kind: .paragraph, text: "Café needle", listID: firstList.id)
let archived = task("Café needle", listID: archivedList.id)
let alias = task("Café needle", listID: mergedList.id)
let orphan = task("Café needle", listID: UUID())
let searchFixtures = [needle, completedNeedle, otherListNeedle, noteOnly, child, paragraph, archived, alias, orphan]
var search = TasksViewOptions(filter: .all, grouping: .none, titleQuery: "  CAFE NEEDLE \n", sorting: .alphabetical)
check(Set(ids(project(searchFixtures, search).matching)) == [needle.id, completedNeedle.id, otherListNeedle.id], "title filter trims whitespace and matches case/diacritics without notes, prose or parent context")
search.titleQuery = "List-only needle"
check(project(searchFixtures, search).matching.isEmpty, "title filter never matches list names")
search.titleQuery = "Label-only needle"
check(project(searchFixtures, search).matching.isEmpty, "title filter never matches label names")
search.titleQuery = " \n "
check(project(searchFixtures, search).uniqueTaskCount == 5, "whitespace query keeps active tasks, excluding archived, aliases, orphans and prose")
search.titleQuery = "needle"
search.listID = firstList.id
needle.isStarred = true
needle.dueDate = tomorrow
for (filter, expected) in [
    (TaskFilter.open, [needle]), (.completed, [completedNeedle]), (.all, [needle, completedNeedle]),
    (.starred, [needle]), (.scheduled, [needle]), (.unscheduled, [])
] {
    search.filter = filter
    checkOrder(project(searchFixtures, search).matching, expected, "title query combines with \(filter) and selected list")
}
search.grouping = .priority
search.sorting = .createdAt
search.ascending = false
check(search.hasCustomFilters && search.hasCustomSorting, "nondefault filters and sorting expose reset state")
search.resetFilters()
check(search.filter == .open && search.listID == nil && search.titleQuery.isEmpty, "reset clears status, list and title filters")
check(search.grouping == .priority && search.sorting == .createdAt && !search.ascending, "reset filters preserves grouping and sorting")
search.resetSorting()
check(!search.hasCustomSorting && search.grouping == .priority, "reset sort restores due ascending without changing grouping")
check(!TasksViewOptions().hasCustomFilters && !TasksViewOptions().hasCustomSorting, "new screen state starts with default transient choices")

// Observe actual SwiftData model properties in the same projection evaluated by body.
let schema = Schema([Block.self, TaskList.self, TaskLabel.self])
let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
let context = ModelContext(container)
for list in lists { context.insert(list) }
for label in labels { context.insert(label) }
for value in fixtures { context.insert(value) }
try context.save()

func observes(_ read: () -> Void, mutation: () -> Void, _ message: String) {
    let changed = OSAllocatedUnfairLock(initialState: false)
    withObservationTracking(read) {
        changed.withLock { $0 = true }
    }
    mutation()
    check(changed.withLock { $0 }, message)
}

var observedOptions = TasksViewOptions(filter: .all, grouping: .none, titleQuery: "Zulu", sorting: .alphabetical)
observes({ _ = project(fixtures, observedOptions) }, mutation: { zulu.text = "Renamed" }, "renaming out of the title filter invalidates the projection")
check(project(fixtures, observedOptions).matching.isEmpty, "renamed task leaves the live query")
observes({ _ = project(fixtures, observedOptions) }, mutation: { zulu.text = "Zulu again" }, "renaming into the title filter invalidates the projection")
checkOrder(project(fixtures, observedOptions).matching, [zulu], "renamed task reenters the live query")
observedOptions.titleQuery = ""
observedOptions.sorting = .dueDate
observedOptions.grouping = .dueDate
observes({ _ = project(fixtures, observedOptions) }, mutation: { alpha.dueDate = yesterday }, "due-date edits invalidate sorting and date grouping")
checkOrder(project(fixtures, observedOptions).groups.first { $0.id == "overdue" }!.tasks, [alpha], "due edit moves task into Overdue")
observes({ _ = project(fixtures, observedOptions) }, mutation: { alpha.isCompleted = true }, "completion invalidates date grouping")
check(project(fixtures, observedOptions).groups.first { $0.id == "done" }!.tasks.contains { $0 === alpha }, "completion keeps the original task identity in Completed")
observedOptions.grouping = .priority
observes({ _ = project(fixtures, observedOptions) }, mutation: { beta.priority = .high }, "priority edits invalidate priority grouping")
check(project(fixtures, observedOptions).groups.first { $0.id == "priority-3" }!.tasks.contains { $0 === beta }, "priority edit moves original task into High")
observedOptions.grouping = .label
observes({ _ = project(fixtures, observedOptions) }, mutation: { zulu.labelIDs = [UUID()] }, "label edits invalidate group membership")
check(project(fixtures, observedOptions).groups.first { $0.id == "label-none" }!.tasks.contains { $0 === zulu }, "stale-only labels remain visible under No label")
observes({ _ = project(fixtures, observedOptions) }, mutation: { firstList.isArchived = true }, "archiving a list invalidates active membership")
checkOrder(project(fixtures, observedOptions).matching, [beta], "archived list tasks leave results")
firstList.isArchived = false
try context.save()
let originalPositions = fixtures.map(\.sortIndex)
let originalParents = fixtures.map(\.parentID)
for sorting in TaskSorting.allCases {
    observedOptions.sorting = sorting
    for grouping in TaskGrouping.allCases {
        observedOptions.grouping = grouping
        _ = project(fixtures, observedOptions)
        check(!context.hasChanges, "\(sorting)/\(grouping) projection never writes SwiftData")
    }
}
check(fixtures.map(\.sortIndex) == originalPositions && fixtures.map(\.parentID) == originalParents, "stored order and parent relationships are preserved")
check(project(fixtures, observedOptions).matching.allSatisfy { task in fixtures.contains { $0 === task } }, "projection returns original model identities")
observedOptions.grouping = .label
let hiddenLabels = project(fixtures, observedOptions, labels: [])
check(hiddenLabels.uniqueTaskCount == fixtures.count, "removing known labels never changes the unique count")
check(hiddenLabels.groups.count == 1 && hiddenLabels.groups.first?.id == "label-none", "removing all known labels keeps every task under No label")

print("✅ \(checks) Tasks view filtering, sorting, grouping and observation checks passed")
