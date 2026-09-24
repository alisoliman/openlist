import Foundation
import SwiftData

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    guard condition() else { fatalError("FAIL: \(message)") }
}

let schema = Schema([TaskList.self, Block.self, SidebarSection.self, TaskLabel.self, Attachment.self,
                     ActivityEvent.self, SchedulePlacement.self, WorkSession.self, CompletionRecord.self])
let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
let store = Store(context: container.mainContext)
store.context.autosaveEnabled = false
let list = store.createList(title: "Trip")
func block(_ kind: BlockKind, _ title: String, _ order: Double, parent: Block? = nil) -> Block {
    let value = Block(kind: kind, text: title, listID: list.id, parentID: parent?.id, sortIndex: order)
    store.context.insert(value)
    return value
}

// Tasks beneath headings and nested prose, and one on its own.
let first = block(.heading1, "Before", 0)
let zebra = block(.task, "Zebra", 0, parent: first)
let second = block(.heading1, "During", 10)
let mango = block(.task, "Mango", 0, parent: second)
let apple = block(.task, "Apple", 20)
let outer = block(.paragraph, "Outer", 30)
let inner = block(.paragraph, "Inner", 0, parent: outer)
_ = block(.task, "Kiwi", 0, parent: inner)
store.save()

// The widget's rows follow the list's own order however the publisher keeps
// it between rebuilds.
let publisher = WidgetSnapshotPublisher(store: store)
func rows() -> [String] { publisher.buildSnapshot().lists.first { $0.id == list.id }?.openItems.map(\.title) ?? [] }
func listOrder() -> [String] {
    ListTasksProjection(blocks: store.blocks(inList: list.id), listID: list.id, sorting: list.sorting, showsCompleted: false)
        .tasks.prefix(7).map(\.displayTitle)
}
func after(_ message: String, _ expected: [String], _ change: () -> Void) {
    change()
    store.save()
    let shown = rows()
    check(shown == expected && shown == listOrder(), "\(message): \(shown)")
}

after("Rows follow the outline", ["Zebra", "Mango", "Apple", "Kiwi"]) {}
after("Typing in a heading changes nothing", ["Zebra", "Mango", "Apple", "Kiwi"]) { first.text = "Before we go" }
after("Headings trading places move their tasks", ["Mango", "Zebra", "Apple", "Kiwi"]) {
    first.sortIndex = 10
    second.sortIndex = 0
}
after("A task moved under a heading", ["Mango", "Apple", "Zebra", "Kiwi"]) {
    apple.parentID = first.id
    apple.sortIndex = -5
}
after("Prose two levels up moving first", ["Kiwi", "Mango", "Apple", "Zebra"]) { outer.sortIndex = -10 }
after("The prose between moving out", ["Mango", "Apple", "Zebra", "Kiwi"]) {
    inner.parentID = nil
    inner.sortIndex = 40
}
after("A completion leaves the rows", ["Mango", "Apple", "Kiwi"]) {
    zebra.isCompleted = true
    zebra.completedAt = .now
}
after("An alphabetical list sorts its rows", ["Apple", "Kiwi", "Mango"]) { list.sorting = .alphabetical }
after("and sorts them again after a rename", ["Kiwi", "Mango", "Zulu"]) { apple.text = "Zulu" }
after("Back in manual order", ["Mango", "Zulu", "Kiwi"]) { list.sorting = .manual }
after("A new task joins at its place", ["Mango", "Zulu", "Kiwi", "Fig"]) { _ = block(.task, "Fig", 50) }
after("A heading moved down takes its task", ["Zulu", "Kiwi", "Mango", "Fig"]) { second.sortIndex = 45 }
after("A heading in the trash leaves its task where it sat", ["Mango", "Zulu", "Kiwi", "Fig"]) { second.trashID = UUID() }

// Due work is counted by day, and still the version 1 way for its widget.
check(publisher.buildSnapshot().dueDays.isEmpty, "Nothing dated, nothing due")
let today = Calendar.current.startOfDay(for: .now)
let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
apple.dueDate = yesterday
mango.dueDate = today
store.save()
let dated = publisher.buildSnapshot()
check(dated.dueDays == [WidgetSnapshot.DueDay(day: yesterday, count: 1), WidgetSnapshot.DueDay(day: today, count: 1)],
      "A day each for yesterday's and today's work")
check(dated.overdueCount == 1 && dated.dueTodayCount == 1, "Version 1's counts are written too")

// Icons and colours as the app draws them: Inbox's own blue and glyph, and
// the default icon for a list without one.
store.bootstrap()
let filed = Block(kind: .task, text: "Filed later", listID: store.inboxList()!.id, sortIndex: 0)
filed.dueDate = today
store.context.insert(filed)
list.icon = ""
store.save()
let drawn = publisher.buildSnapshot()
let filedRow = drawn.todayItems.first { $0.id == filed.id }
check(filedRow?.accent == "#3A7BD8" && filedRow?.listIcon == "📥", "An Inbox task takes Inbox's own colour and glyph")
check(drawn.lists.first { $0.id == list.id }?.icon == "📋" && drawn.todayItems.first { $0.id == mango.id }?.listIcon == "📋",
      "A list without an icon shows the default one")

// The List widget's picker and its default follow the sidebar: by section,
// then place, nested lists after their parent, and lists no section holds last.
let work = store.createSection(title: "Work")
let alpha = store.createList(title: "Alpha", in: work)
let beta = store.createList(title: "Beta", in: work)
_ = store.createList(title: "Home")
store.createChildList(in: alpha)!.title = "Alpha notes"
store.move(list: beta, toSection: work.id, above: alpha)
store.save()
let picker = publisher.buildSnapshot().lists.map(\.title)
check(picker == ["Home", "Beta", "Alpha", "Alpha notes", "Trip"], "Lists come in sidebar order, not creation order: \(picker)")

// Every active list is published, with its rows, so a List widget's list in a
// later section stays however many new lists join the sidebar ahead of it.
store.context.insert(Block(kind: .task, text: "Plan offsite", listID: beta.id, sortIndex: 0))
for index in 1...60 { store.createList(title: "More \(index)") }
let crowded = publisher.buildSnapshot().lists
store.createList(title: "Newest")
let pushed = publisher.buildSnapshot().lists
check(crowded.count == 65 && pushed.count == 66 && pushed.last?.id == list.id, "Past 60 lists, every one is published")
check(pushed.first { $0.id == beta.id }?.openItems.map(\.title) == ["Plan offsite"],
      "A later section's list keeps its place and rows after a new list is made")

print("Passed \(checks) widget publisher checks")
