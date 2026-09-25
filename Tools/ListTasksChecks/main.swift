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
alpha.priority = .medium
beta.priority = .high
store.save()
let blocks = [image, beta, prose, delta, childNote, alpha, zulu, charlie, heading]
let original = blocks.map(BackupBlock.init)
let originalList = BackupTaskList(list)
let outline = BlockTree.flatten(blocks, respectCollapse: false)
let manual = [charlie, zulu, alpha, delta, beta]

func projection(_ sorting: ListSorting = .manual, showsCompleted: Bool = true,
                source: [Block] = blocks) -> ListTasksProjection {
    ListTasksProjection(blocks: source, listID: list.id, sorting: sorting, showsCompleted: showsCompleted)
}

check(ids(projection().tasks) == ids(manual), "Document order includes every descendant once despite collapsed ancestors")
check(ids(projection(.alphabetical).tasks) == ids([alpha, beta, charlie, delta, zulu]),
      "Alphabetical sort crosses headings, prose, and task parent boundaries")
check(ids(projection(.dueDate).tasks) == ids([beta, alpha, charlie, zulu, delta]),
      "Due-date sort orders dated tasks before stable undated ties")
check(ids(projection(.priority).tasks) == ids([beta, alpha, charlie, zulu, delta]),
      "Priority sort compares the complete queue")
check(ids(projection(.createdAt).tasks) == ids(manual), "Creation-date ties retain original outline order")
check(ids(projection(.manual, showsCompleted: false).tasks) == ids([charlie, alpha, delta, beta]),
      "Hide completed filters each task independently and keeps an open child of a completed parent")

for sorting in ListSorting.allCases {
    for visible in [true, false] {
        _ = projection(sorting, showsCompleted: visible)
        check(blocks.map(BackupBlock.init) == original && BackupTaskList(list) == originalList,
              "\(sorting) with completion visibility \(visible) never mutates document payload, hierarchy, or indices")
    }
}

// Every actual comparator tie falls back to outline order, never fetch order.
let firstTie = block(.task, "Same", 50)
let nestedTie = block(.task, "Same", -1, parent: firstTie)
let lastTie = block(.task, "Same", 60)
for sorting in ListSorting.allCases {
    let result = projection(sorting, source: [lastTie, nestedTie, firstTie]).tasks
    check(ids(result) == ids([firstTie, nestedTie, lastTie]), "\(sorting) retains outline order for equal keys")
}

// The orders Today's and a list's Completed groups, the label screen, the
// Due date sort and the widget take from the model's comparators.
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

let foreign = Block(kind: .task, text: "Other list", listID: UUID())
check(ids(projection(source: blocks + [foreign, alpha]).tasks) == ids(manual),
      "A foreign-list block and repeated input cannot duplicate or contaminate the queue")
let noteOnly = projection(source: [heading, prose, image])
check(noteOnly.tasks.isEmpty, "A notes-only list projects no tasks")
check(projection(showsCompleted: false, source: [zulu]).tasks.isEmpty,
      "A completed-only list has an empty open-task projection")

// The production document path continues to sort contiguous root-task runs.
let sortedOutline = BlockTree.sortingTaskRuns(in: outline, by: .alphabetical)
check(sortedOutline.map(\.id) == ids([heading, charlie, delta, zulu, alpha, childNote, prose, beta, image]),
      "Document sorting preserves prose boundaries and carries each task's original subtree")
check(BlockTree.sortingTaskRuns(in: outline, by: .manual).map(\.id) == outline.map(\.id),
      "Returning to manual Document order restores the exact rich outline")
check(blocks.map(BackupBlock.init) == original, "Document sorting also leaves stored models unchanged")

// Mutation through a projected row targets the original model, never a copy.
let projectedAlpha = projection(.alphabetical).tasks.first { $0.id == alpha.id }!
check(projectedAlpha === alpha, "Projected task identity is the original SwiftData object")
store.setText("Renamed child", for: projectedAlpha)
store.toggleCompletion(projectedAlpha)
store.save()
check(store.block(id: alpha.id)?.text == "Renamed child" && alpha.isCompleted,
      "Editing and completing a projected task updates the original child")
check(alpha.parentID == zulu.id && alpha.sortIndex == original.first { $0.id == alpha.id }!.sortIndex,
      "Projected task mutations retain original ownership, parent, and insertion position")
check([heading, childNote, prose, image].allSatisfy { value in
    original.first { $0.id == value.id } == BackupBlock(value)
}, "Task mutations leave headings, notes, rich formatting, and image payloads unchanged")

print("\(checks) list Tasks checks passed")
