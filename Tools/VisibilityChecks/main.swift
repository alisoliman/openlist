import Foundation
import SwiftData

var checks = 0

@MainActor
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    guard condition() else { fatalError("FAIL: \(message)") }
}

let directory = FileManager.default.temporaryDirectory.appendingPathComponent("openlist-visibility-\(UUID())")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
let schema = Schema([TaskList.self, Block.self])
let configuration = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("test.store"))
let archivedListID: UUID
let taskID: UUID

do {
    let container = try ModelContainer(for: schema, configurations: [configuration])
    let context = ModelContext(container)
    let active = TaskList(title: "Active")
    let archived = TaskList(title: "Retained archive")
    let inbox = TaskList(title: "Inbox", isSystemInbox: true)
    check(active.completedVisibility == .inherit, "new lists inherit the app default")
    check(active.showsCompleted(default: true) && !active.showsCompleted(default: false), "inherited visibility follows a changing global default")
    active.completedVisibility = .show
    check(active.showsCompleted(default: false), "explicit show overrides a hidden global default")
    active.completedVisibility = .hide
    check(!active.showsCompleted(default: true), "explicit hide overrides a shown global default")
    active.completedVisibility = .inherit
    check(active.showsCompleted(default: true), "reset to inheritance immediately follows the global default")
    active.completedVisibilityRaw = nil
    active.showsCompleted = false
    check(active.completedVisibility == .hide, "legacy hidden lists retain their override")
    active.showsCompleted = true
    check(active.completedVisibility == .inherit, "legacy default lists adopt inheritance")
    inbox.completedVisibilityRaw = nil
    inbox.showsCompleted = false
    check(inbox.completedVisibility == .inherit, "legacy Inbox retains its global preference behavior")
    active.completedVisibilityRaw = "future-value"
    check(active.completedVisibility == .inherit, "unknown preference values use a safe legacy fallback")
    active.completedVisibility = .hide
    archived.completedVisibility = .show
    archived.isArchived = true
    archivedListID = archived.id
    for list in [active, archived, inbox] { context.insert(list) }

    let activeTask = Block(kind: .task, text: "Visible", listID: active.id)
    let archivedTask = Block(kind: .task, text: "Archived task", listID: archived.id)
    archivedTask.dueDate = .now
    archivedTask.isStarred = true
    archivedTask.note = "Preserve this note"
    archivedTask.reminderAt = Date.now.addingTimeInterval(3_600)
    taskID = archivedTask.id
    let child = Block(kind: .task, text: "Archived child", listID: archived.id, parentID: archivedTask.id)
    let inboxTask = Block(kind: .task, text: "Inbox task", listID: inbox.id)
    let paragraph = Block(kind: .paragraph, text: "Context", listID: active.id)
    let orphan = Block(kind: .task, text: "Orphan", listID: UUID())
    let tasks = [activeTask, archivedTask, child, inboxTask, paragraph, orphan]
    for task in tasks { context.insert(task) }
    try context.save()

    let policy = ActiveTaskPolicy(lists: [active, archived, inbox])
    check(Set(policy.tasks(in: tasks).map(\.id)) == Set([activeTask.id, inboxTask.id]), "active work excludes archived parents, children, non-tasks and missing lists")
    check(policy.includes(activeTask), "unpinned lists still contribute active work")
    check(policy.includes(inboxTask), "Inbox tasks remain active")
    activeTask.isCompleted = true
    check(policy.includes(activeTask), "completion filtering remains a surface choice")
    check(archivedTask.dueDate != nil && archivedTask.reminderAt != nil && archivedTask.isStarred, "archiving hides tasks without clearing scheduling or flags")
    try context.save()
}

do {
    let container = try ModelContainer(for: schema, configurations: [configuration])
    let context = ModelContext(container)
    let lists = try context.fetch(FetchDescriptor<TaskList>())
    let tasks = try context.fetch(FetchDescriptor<Block>())
    let archive = lists.first { $0.id == archivedListID }!
    let task = tasks.first { $0.id == taskID }!
    check(archive.completedVisibility == .show && archive.showsCompleted(default: false), "explicit shown preference survives reopening")
    let active = lists.first { $0.title == "Active" }!
    check(active.completedVisibility == .hide && !active.showsCompleted(default: true), "explicit hidden preference survives reopening")
    check(tasks.first { $0.listID == active.id && $0.isTask }?.isCompleted == true, "visibility preferences preserve completed task data")
    check(archive.isArchived && !ActiveTaskPolicy(lists: lists).includes(task), "archive visibility survives reopening a disk store")
    check(task.note == "Preserve this note" && task.reminderAt != nil, "archived content and reminder intent survive reopening")
    check(tasks.contains { $0.parentID == task.id }, "archived subtask relationship survives reopening")
    archive.isArchived = false
    try context.save()
    check(ActiveTaskPolicy(lists: lists).includes(task), "unarchiving immediately restores active task membership")
    check(ActiveTaskPolicy(lists: lists).tasks(in: tasks).contains { $0.parentID == task.id }, "unarchiving restores subtasks too")
}

// The Completed groups fold as one, whatever each screen's default: the
// design's single completedOpen, not a flip of each screen's own default.
do {
    let shown = TaskList(title: "Shown")
    shown.completedVisibility = .show
    let inherits = TaskList(title: "Inherits")
    let setting = false
    func open(_ fold: NXCompletedFold?, _ screenDefault: Bool, setting: Bool = setting) -> Bool {
        NXCompletedFold.isOpen(fold, default: screenDefault, showsCompleted: setting)
    }
    check(open(nil, shown.showsCompleted(default: setting)) && !open(nil, inherits.showsCompleted(default: setting)),
          "until a fold, each screen opens Completed as its own setting says")
    // Folded closed on the shown list: closed there, on a label screen and on an inheriting list.
    var fold = NXCompletedFold(open: false, showsCompleted: setting)
    check(!open(fold, shown.showsCompleted(default: setting)), "a fold closed stays closed where it was made")
    check(!open(fold, setting) && !open(fold, inherits.showsCompleted(default: setting)),
          "a fold closed on a shown list doesn't open Completed on labels or other lists")
    // Folded open on a label screen: open there and on the shown list too.
    fold = NXCompletedFold(open: !open(fold, setting), showsCompleted: setting)
    check(open(fold, setting) && open(fold, shown.showsCompleted(default: setting)),
          "a fold opened on a label opens Completed on the lists too")
    let hidden = TaskList(title: "Hidden")
    hidden.completedVisibility = .hide
    check(open(fold, hidden.showsCompleted(default: true), setting: false), "the last fold holds over a list set to hide")
    check(!open(fold, hidden.showsCompleted(default: true), setting: true) && open(fold, true, setting: true),
          "changing Show completed tasks lapses the fold, so each screen's default shows")
}

print("✅ \(checks) visibility and persistence checks passed")
