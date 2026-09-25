import Foundation
import SwiftData

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    guard condition() else { fatalError("FAIL: \(message)") }
}
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let reopen = CommandLine.arguments[2] == "reopen"
let schema = Schema([TaskList.self, Block.self, SidebarSection.self, TaskLabel.self, Attachment.self,
    ActivityEvent.self, WorkSession.self, CompletionRecord.self, SchedulePlacement.self])
let container = try ModelContainer(for: schema, configurations: [.init(schema: schema, url: url, cloudKitDatabase: .none)])
var failSave = false
let store = Store(context: container.mainContext, commitContext: { context in
    if failSave { throw CocoaError(.fileWriteNoPermission) }
    try context.save()
})
let service = NotificationService.shared
if reopen {
    store.refreshAllReminders(); await service.reminders.waitUntilIdle()
    let tasks = try store.context.fetch(FetchDescriptor<Block>())
    let future = tasks.first { $0.text == "Survives restart" }!
    let expired = tasks.first { $0.text == "Expired" }!
    check(service.client.requests[future.id] != nil, "Restart rebuilds eligible future saved request")
    check(service.reminders.statuses[future.id] == .accepted, "Restart acceptance comes from newly queried OS inventory")
    check(service.reminders.statuses[expired.id] == .expired && service.client.requests[expired.id] == nil, "Restart never replays expired saved reminder")
    print("\(checks) reminder reopen checks passed")
    exit(0)
}
store.bootstrap()
let list = store.createList(title: "Personal")
let task = store.appendBlock(kind: .task, text: "Original", to: DocumentContext(listID: list.id))
store.save()
let date = Date.now.addingTimeInterval(3600)
store.setReminder(date, for: task); await service.reminders.waitUntilIdle()
check(service.reminders.intents[task.id]?.date == date && service.client.requests[task.id]?.date == date, "Only saved task reminder enters recovery/OS snapshot")
failSave = true
let changedDate = date.addingTimeInterval(600)
store.setReminder(changedDate, for: task); await service.reminders.waitUntilIdle()
check(task.reminderAt == changedDate && store.context.hasChanges, "Failed save retains pending editor reminder")
check(service.reminders.intents[task.id]?.date == date && service.client.requests[task.id]?.date == date, "Failed save preserves prior accepted reminder and saved intent")
store.refreshAllReminders(); await service.reminders.waitUntilIdle()
check(service.reminders.intents[task.id]?.date == date, "Explicit retry reads committed values even with unsaved live model")
failSave = false; store.save(); await service.reminders.waitUntilIdle()
check(service.client.requests[task.id]?.date == changedDate, "Successful save replaces prior OS reminder")
failSave = true
store.toggleCompletion(task); await service.reminders.waitUntilIdle()
check(service.client.requests[task.id] != nil, "Failed completion save cannot prematurely cancel prior OS request")
failSave = false; store.save(); await service.reminders.waitUntilIdle()
check(service.client.requests[task.id] == nil && service.reminders.statuses[task.id] == .inactive("task completed"), "Committed completion cancels and explains inactive reminder")
store.toggleCompletion(task); await service.reminders.waitUntilIdle()
check(service.client.requests[task.id] != nil, "Reopen re-registers a still-future reminder")
store.setArchived(true, for: list); await service.reminders.waitUntilIdle()
check(service.client.requests[task.id] == nil, "Archive removes future request")
store.setArchived(false, for: list); await service.reminders.waitUntilIdle()
check(service.client.requests[task.id] != nil, "Unarchive restores eligible request")
store.rename(list, to: "Changed list"); store.setText("Changed title", for: task); store.save()
await service.reminders.waitUntilIdle()
check(service.client.requests[task.id]?.title == "Changed title" && service.client.requests[task.id]?.listName == "Changed list", "Saved task and list renames refresh pending text")
store.setDueDate(date, includesTime: true, for: task)
store.setReminder(date.addingTimeInterval(-600), for: task)
store.setRecurrence(.daily, for: task)
let priorOccurrence = task.occurrenceID
store.toggleCompletion(task, now: date); await service.reminders.waitUntilIdle()
check(abs(task.reminderAt!.timeIntervalSince(task.dueDate!) + 600) < 0.001, "Recurrence preserves custom reminder offset")
check(task.occurrenceID != priorOccurrence && service.client.requests[task.id]?.occurrenceID == task.occurrenceID, "Recurring completion replaces same UUID request for next occurrence")
store.setRecurrence(nil, for: task)
store.setDueDate(nil, for: task)
store.setText("Survives restart", for: task)
store.setReminder(Date.now.addingTimeInterval(7200), for: task)
let expired = store.appendBlock(kind: .task, text: "Expired", to: DocumentContext(listID: list.id))
store.setReminder(Date.now.addingTimeInterval(-30), for: expired)
await service.reminders.waitUntilIdle()
check(service.client.requests[expired.id] == nil && service.reminders.statuses[expired.id] == .expired, "Saved expired intent remains observable but unscheduled")
let deleted = store.appendBlock(kind: .task, text: "Delete me", to: DocumentContext(listID: list.id))
store.setReminder(date, for: deleted); await service.reminders.waitUntilIdle()
let deletedID = deleted.id
store.deleteBlock(deleted); store.save(); await service.reminders.waitUntilIdle()
check(service.client.requests[deletedID] == nil, "Committed deletion removes request")

let navigator = Navigator()
let navigation = ReminderNavigation(navigator: navigator)
var opens = 0
navigation.openMainWindow = { opens += 1 }
navigation.receive(task.id)
check(navigator.openTaskID == nil && opens == 1, "Cold notification click waits for storage/window and requests main window")
navigation.storeReady { id in
    guard let block = store.block(id: id), block.isTask else { throw ContentReveal.Unavailable.deleted }
    return try ContentReveal.resolve(.block(id), blocks: store.blocks(inList: list.id), lists: [list])
}
check(navigator.openTaskID == nil, "Bootstrap alone cannot consume reveal before window is ready")
navigation.windowReady(true)
check(navigator.openTaskID == task.id && navigator.contentReveal?.blockID == task.id, "Ready notification routes exact task through shared reveal")
let revealID = navigator.contentReveal?.id
navigation.windowReady(true)
check(navigator.contentReveal?.id == revealID, "Repeated layout does not replay consumed click")
navigation.receive(deletedID)
check(navigation.unavailableMessage != nil && store.block(id: deletedID) == nil, "Missing notification target is visible and never creates a replacement")
navigation.windowReady(false); navigation.receive(task.id)
check(opens == 3, "Click requests reopening a closed main window")
navigation.windowReady(true)
check(navigation.unavailableMessage == nil && navigator.contentReveal?.id != revealID, "Later surviving click clears error and performs fresh reveal")
print("\(checks) reminder store/navigation checks passed")
