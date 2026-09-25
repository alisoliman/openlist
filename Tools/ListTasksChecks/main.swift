import Foundation
import SwiftData

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    guard condition() else { fatalError("FAIL: \(message)") }
}
func ids(_ blocks: [Block]) -> [UUID] { blocks.map(\.id) }

let schema = Schema([TaskList.self, Block.self, SidebarSection.self, TaskLabel.self, Attachment.self,
                     ActivityEvent.self, SchedulePlacement.self, WorkSession.self, CompletionRecord.self])
let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
let store = Store(context: container.mainContext)
store.context.autosaveEnabled = false
let list = store.createList(title: "Mixed document")
list.summary = "Keep the description"
let date = Date(timeIntervalSince1970: 1_700_000_000)
func block(_ kind: BlockKind, _ title: String, _ order: Double, parent: Block? = nil) -> Block {
    let value = Block(kind: kind, text: title, listID: list.id, parentID: parent?.id, sortIndex: order)
    value.createdAt = date
    value.updatedAt = date
    store.context.insert(value)
    return value
}

let heading = block(.heading1, "Section", 0)
heading.isCollapsed = true
let charlie = block(.task, "Charlie", 0, parent: heading)
let zulu = block(.task, "Zulu", 10)
zulu.isCollapsed = true
zulu.isCompleted = true
zulu.completedAt = date
let alpha = block(.task, "Alpha", 0, parent: zulu)
let childNote = block(.paragraph, "Nested note", 1, parent: zulu)
let delta = block(.task, "Delta", 15)
let echo = block(.task, "Echo", 17)
let prose = block(.paragraph, "Prose separating tasks", 20)
prose.richData = Data("Formatted rich text".utf8)
prose.note = "Keep attached notes"
let beta = block(.task, "Beta", 30)
let image = block(.image, "", 40)
image.mediaData = Data([1, 2, 3, 4])
image.mediaFilename = "fixture-image.png"
image.mediaCaption = "Keep the caption"
image.mediaWidth = 200
image.mediaHeight = 100
alpha.dueDate = date.addingTimeInterval(2 * 86_400)
beta.dueDate = date
echo.dueDate = date.addingTimeInterval(-86_400)
alpha.priority = .medium
beta.priority = .high
echo.priority = .low
store.save()
let blocks = [image, beta, prose, echo, delta, childNote, alpha, zulu, charlie, heading]
let original = blocks.map(BackupBlock.init)
let originalList = BackupTaskList(list)
let outline = BlockTree.flatten(blocks, respectCollapse: false)
let manual = [charlie, zulu, alpha, delta, echo, beta]

/// A list's tasks in the order its page draws them, as the document, Tasks
/// mode and the List widget take them: the whole outline, folded branches
/// included, with the Sort reordering each run of top-level tasks.
func pageTasks(_ sorting: ListSorting = .manual, source: [Block] = blocks) -> [Block] {
    BlockTree.sortingTaskRuns(in: BlockTree.flatten(source, respectCollapse: false), by: sorting).map(\.block).filter(\.isTask)
}

check(ids(pageTasks()) == ids(manual), "Document order includes every descendant once despite collapsed ancestors")
check(ids(pageTasks(.alphabetical)) == ids([charlie, delta, echo, zulu, alpha, beta]),
      "Alphabetical sort reorders the run of top-level tasks between the heading and the prose, carrying subtasks")
check(ids(pageTasks(.dueDate)) == ids([charlie, echo, zulu, alpha, delta, beta]),
      "Due-date sort puts a dated task first in its run, before stable undated ties")
check(ids(pageTasks(.priority)) == ids([charlie, echo, zulu, alpha, delta, beta]),
      "Priority sort puts the higher priority first in its run, and never moves a subtask")
check(ids(pageTasks(.createdAt)) == ids(manual), "Creation-date ties retain original outline order")

for sorting in ListSorting.allCases {
    _ = pageTasks(sorting)
    check(blocks.map(BackupBlock.init) == original && BackupTaskList(list) == originalList,
          "\(sorting) never mutates document payload, hierarchy, or indices")
}

// Every actual comparator tie falls back to outline order, never fetch order.
let firstTie = block(.task, "Same", 50)
let nestedTie = block(.task, "Same", -1, parent: firstTie)
let lastTie = block(.task, "Same", 60)
for sorting in ListSorting.allCases {
    let result = pageTasks(sorting, source: [lastTie, nestedTie, firstTie])
    check(ids(result) == ids([firstTie, nestedTie, lastTie]), "\(sorting) retains outline order for equal keys")
}

// The orders Today's and a list's Completed groups, the label screen, the
// Due date sort and the widget's Today and completed rows take from the
// model's comparators.
func loose(_ title: String, due: Date? = nil, priority: TaskPriority = .none, completed: Date? = nil) -> Block {
    let value = Block(kind: .task, text: title, listID: list.id)
    value.dueDate = due
    value.priority = priority
    value.isCompleted = completed != nil
    value.completedAt = completed
    return value
}
let finishedEarly = loose("Finished early", completed: date)
let finishedLate = loose("Finished late", completed: date.addingTimeInterval(3_600))
let unfinished = loose("Not finished")
check(ids([finishedEarly, unfinished, finishedLate].sorted(by: Block.byCompletionDate)) == ids([finishedLate, finishedEarly, unfinished]),
      "Completion order puts the newest completion first")
let sameDayLow = loose("Same day, low", due: date, priority: .low)
let sameDayHigh = loose("Same day, high", due: date, priority: .high)
let sooner = loose("Sooner", due: date.addingTimeInterval(-86_400))
let undated = loose("Undated", priority: .high)
check(ids([undated, sameDayLow, sooner, sameDayHigh].sorted(by: Block.byDueDate)) == ids([sooner, sameDayHigh, sameDayLow, undated]),
      "Due-date order breaks a shared date by priority and puts undated tasks last")

check(pageTasks(source: [heading, prose, image]).isEmpty, "A notes-only list has no tasks")

// The document itself sorts the same runs, prose and all.
let sortedOutline = BlockTree.sortingTaskRuns(in: outline, by: .alphabetical)
check(sortedOutline.map(\.id) == ids([heading, charlie, delta, echo, zulu, alpha, childNote, prose, beta, image]),
      "Document sorting preserves prose boundaries and carries each task's original subtree")
check(BlockTree.sortingTaskRuns(in: outline, by: .manual).map(\.id) == outline.map(\.id),
      "Returning to manual Document order restores the exact rich outline")
check(blocks.map(BackupBlock.init) == original, "Document sorting also leaves stored models unchanged")

// Mutation through a sorted row targets the original model, never a copy.
let sortedAlpha = pageTasks(.alphabetical).first { $0.id == alpha.id }!
check(sortedAlpha === alpha, "A sorted task is the original SwiftData object")
store.setText("Renamed child", for: sortedAlpha)
store.toggleCompletion(sortedAlpha)
store.save()
check(store.block(id: alpha.id)?.text == "Renamed child" && alpha.isCompleted,
      "Editing and completing a sorted task updates the original child")
check(alpha.parentID == zulu.id && alpha.sortIndex == original.first { $0.id == alpha.id }!.sortIndex,
      "Sorted task mutations retain original ownership, parent, and insertion position")
check([heading, childNote, prose, image].allSatisfy { value in
    original.first { $0.id == value.id } == BackupBlock(value)
}, "Task mutations leave headings, notes, rich formatting, and image payloads unchanged")

print("\(checks) list Tasks checks passed")
