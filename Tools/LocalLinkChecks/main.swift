import CoreData
import Foundation
import SwiftData

var checks = 0
func check(_ value: Bool, _ message: String) {
    precondition(value, message)
    checks += 1
}
func rejects(_ text: String, _ error: LocalLinkError, scheme: String = LocalLink.scheme) {
    do { _ = try LocalLink.parse(URL(string: text)!, scheme: scheme); preconditionFailure("Accepted \(text)") }
    catch let actual as LocalLinkError { check(actual == error, "Precise validation: \(text)") }
    catch { preconditionFailure("Unexpected error \(error)") }
}

let libraryID = UUID()
let taskID = UUID()
let listID = UUID()
for scheme in [LocalLink.productionScheme, LocalLink.developmentScheme] {
    for target in [LocalLink.Target.task(taskID), .list(listID)] {
        let link = LocalLink(libraryID: libraryID, target: target)
        let url = link.url(scheme: scheme)
        check(try LocalLink.parse(url, scheme: scheme) == link, "Task/list round trip in each edition")
        check(url.absoluteString == "\(scheme)://v1/\(libraryID.uuidString.lowercased())/\(target.route)/\(target.id.uuidString.lowercased())", "Canonical link contains only scheme, version and identities")
        check(LocalLink.isLocal(url), "Both editions are recognized as internal links")
    }
}
let base = LocalLink(libraryID: libraryID, target: .task(taskID)).url().absoluteString
for suffix in ["?", "?action=delete", "?task=foo", "#", "#note", "/", "/extra"] {
    rejects(base + suffix, .malformed)
}
for path in ["//\(libraryID)/task/\(taskID)", "/\(libraryID)//\(taskID)", "/bad/task/\(taskID)",
             "/\(libraryID)/task/bad", "/\(libraryID)/task", "/\(libraryID)/task/\(taskID)/..",
             "/\(libraryID)/task/%41\(taskID.uuidString.dropFirst())"] {
    rejects("\(LocalLink.scheme)://v1" + path, .malformed)
}
rejects(base.replacingOccurrences(of: "/task/", with: "/delete/"), .unsupported)
rejects(base.replacingOccurrences(of: "://v1/", with: "://v2/"), .unsupported)
rejects(base.replacingOccurrences(of: "://v1/", with: "://user@v1/"), .malformed)
rejects(base.replacingOccurrences(of: "://v1/", with: "://v1:99/"), .malformed)
rejects(base.replacingOccurrences(of: "://v1/", with: "://%76%31/"), .malformed)
rejects("https://example.com", .wrongApp)
rejects(LocalLink(libraryID: libraryID, target: .task(taskID)).url(scheme: "openlist-dev").absoluteString, .wrongApp, scheme: "openlist")
check(!LocalLink.isLocal(URL(string: "https://example.com/openlist")!), "External URLs are not internal commands")

let listURL = LocalLink(libraryID: libraryID, target: .list(listID)).url()
let noteText = "Résumé 🧑🏽‍💻 (\(base)).\nAgain \(base)\nAnother: \(listURL.absoluteString)\nhttps://example.com"
let references = NoteItemLink.references(in: noteText)
check(references.count == 2, "Task notes detect local references and deduplicate repeated links, excluding external URLs")
check(references[0].url.absoluteString == base && references[1].url == listURL, "Unicode/parentheses/punctuation keep complete exact URLs in note order")
check(references.map(\.title) == ["Open task link 1", "Open list link 2"], "Multiple note controls have distinct accessible names")
check(NoteItemLink.references(in: base).first?.title == "Open task link", "Single reference has a concise control name")
check(NoteItemLink.references(in: "ordinary note, https://example.com, mailto:hello@example.com").isEmpty, "External links and ordinary notes add no internal controls")
check(NoteItemLink.references(in: "openlist://v9/unknown").first?.title == "Open Openlist link", "Malformed local reference can show the shared unavailable explanation")
check(NoteItemLink.references(in: LocalLink(libraryID: libraryID, target: .task(taskID)).url(scheme: "openlist-dev").absoluteString).count == 1, "Wrong-edition reference stays internal for an explicit edition error")
check(NoteItemLink.references(in: "").isEmpty, "Clearing a note removes link controls")
check(noteText.hasPrefix("Résumé 🧑🏽‍💻") && noteText.contains("Again \(base)"), "Detection preserves the exact note text")

let fixture = URL.temporaryDirectory.appendingPathComponent("OpenlistLinks-\(UUID())", isDirectory: true)
try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: fixture) }
let storeURL = fixture.appendingPathComponent("library.store")
let schema = Schema([TaskList.self, Block.self, SidebarSection.self])
let configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
let container = try ModelContainer(for: schema, configurations: configuration)
let context = container.mainContext
context.autosaveEnabled = false
let firstIdentity = try LibraryIdentity.read(at: storeURL)
let list = TaskList(title: "Secret original title"); list.id = listID
let task = Block(kind: .task); task.id = taskID; task.listID = listID; task.text = "Duplicate title"
let parent = Block(kind: .task); parent.listID = listID; parent.text = "Closed parent"; parent.isCompleted = true; parent.isCollapsed = true
task.parentID = parent.id
let duplicate = Block(kind: .task); duplicate.listID = listID; duplicate.text = task.text
let paragraph = Block(kind: .paragraph); paragraph.listID = listID
for block in [task, parent, duplicate, paragraph] { context.insert(block) }
context.insert(list)
try context.save()
check(try LibraryIdentity.read(at: storeURL) == firstIdentity, "Library identity survives saves")
func resolve(_ target: LocalLink.Target) throws -> ContentReveal {
    try LocalLinkNavigation.resolve(target, blocks: context.fetch(FetchDescriptor<Block>()), lists: context.fetch(FetchDescriptor<TaskList>()))
}
let target = try resolve(.task(taskID))
check(target.taskID == taskID && target.listID == listID && target.ancestorIDs == [parent.id], "Nested exact task and completed/collapsed ancestor path")
check(target.source == .localLink && target.query.isEmpty, "Link reveal has no search or title dependency")
check(parent.isCompleted && parent.isCollapsed, "Reveal never rewrites completion or collapse")
let navigator = Navigator()
let unrelatedListID = UUID()
navigator.setListViewMode(.tasks, for: listID)
navigator.setListViewMode(.tasks, for: unrelatedListID)
let links = LocalLinkNavigation(libraryID: firstIdentity, navigator: navigator)
let taskURL = LocalLink(libraryID: firstIdentity, target: .task(taskID)).url()
links.receive(taskURL)
check(navigator.contentReveal == nil, "Cold delivery waits for initialization")
links.windowReady(true)
check(navigator.contentReveal == nil, "Window readiness alone cannot resolve before bootstrap")
navigator.replace(with: .today) // Existing bootstrap default.
links.storeReady(resolve: resolve)
check(navigator.openTaskID == taskID && navigator.contentReveal?.source == .localLink, "Delivery after bootstrap overrides Today exactly once")
check(navigator.listViewMode(for: listID) == .document && navigator.contentReveal?.ancestorIDs == [parent.id],
      "Exact nested task link exits Tasks mode and reveals its original document hierarchy")
check(navigator.listViewMode(for: unrelatedListID) == .tasks,
      "Revealing one list leaves another list's Tasks preference unchanged")
let linkSelectionScope = UUID()
navigator.selectForEditing(duplicate.id, scope: linkSelectionScope, visible: [task.id, duplicate.id])
check(navigator.selection == [duplicate.id] && navigator.rowSelection.scopeID == linkSelectionScope,
      "Fixture starts with another line selected in a document")
links.receive(taskURL)
check(navigator.rowSelection.scopeID == nil, "Exact task link clears the stale selection's scope")
check(navigator.selection == [taskID] && navigator.openTaskID == taskID, "Exact task link selects its target for editing")

let firstActivation = navigator.searchActivation
links.windowReady(true)
links.storeReady(resolve: resolve)
check(navigator.searchActivation == firstActivation, "Repeated readiness does not replay a delivery")
links.windowReady(false)
navigator.setListViewMode(.tasks, for: listID)
links.receive(LocalLink(libraryID: firstIdentity, target: .list(listID)).url())
check(navigator.contentReveal == nil && navigator.listViewMode(for: listID) == .tasks,
      "Closed main window queues a list link without prematurely leaving Tasks mode")
links.windowReady(true)
check(navigator.openTaskID == nil && navigator.contentReveal?.destination == .list(listID), "Reopened window consumes pending list link")
check(navigator.listViewMode(for: listID) == .document && navigator.documentOwnsEditorCommands,
      "Queued whole-list link reopens the original document from Tasks mode")

// Both entry points share one navigator after integration. Readiness must not
// lose either queue, replay a delivery, or let bootstrap reset a revealed item.
let sharedNavigator = Navigator()
let sharedLinks = LocalLinkNavigation(libraryID: firstIdentity, navigator: sharedNavigator)
let sharedReminders = ReminderNavigation(navigator: sharedNavigator)
var linkResolutions = 0
var reminderResolutions = 0
var windowOpenRequests = 0
sharedReminders.openMainWindow = { windowOpenRequests += 1 }
sharedLinks.receive(taskURL)
sharedReminders.receive(duplicate.id)
sharedLinks.windowReady(true)
sharedReminders.windowReady(true)
check(sharedNavigator.contentReveal == nil, "Both cold entry points wait for the shared store bootstrap")
sharedNavigator.replace(with: .today)
sharedReminders.storeReady { id in
    reminderResolutions += 1
    return try resolve(.task(id))
}
sharedLinks.storeReady { target in
    linkResolutions += 1
    return try resolve(target)
}
check(linkResolutions == 1 && reminderResolutions == 1 && sharedNavigator.route == .list(listID),
      "Shared bootstrap resolves each queued entry once after the Today default")
let sharedActivation = sharedNavigator.searchActivation
sharedReminders.windowReady(true)
sharedLinks.windowReady(true)
check(sharedNavigator.searchActivation == sharedActivation && linkResolutions == 1 && reminderResolutions == 1,
      "Repeated window attachment cannot replay either queue")
sharedReminders.windowReady(false)
sharedLinks.windowReady(false)
sharedReminders.receive(duplicate.id)
check(windowOpenRequests == 2 && reminderResolutions == 1, "Closed-window reminder requests reopening without resolving early")
sharedReminders.windowReady(true)
sharedLinks.windowReady(true)
check(sharedNavigator.openTaskID == duplicate.id && reminderResolutions == 2, "Window reopening reveals the queued reminder exactly")
sharedReminders.windowReady(false)
sharedLinks.windowReady(false)
sharedLinks.receive(LocalLink(libraryID: firstIdentity, target: .list(listID)).url())
sharedReminders.windowReady(true)
sharedLinks.windowReady(true)
check(sharedNavigator.openTaskID == nil && sharedNavigator.contentReveal?.destination == .list(listID)
      && linkResolutions == 2 && reminderResolutions == 2,
      "Later closed-window list link resolves without replaying the reminder")

let beforeFailure = navigator.contentReveal
links.receive(LocalLink(libraryID: UUID(), target: .task(taskID)).url())
check(links.error == .wrongLibrary && navigator.contentReveal == beforeFailure, "Wrong-library UUID cannot resolve coincidentally identical target IDs")
links.receive(LocalLink(libraryID: firstIdentity, target: .task(UUID())).url())
check(links.error == .targetUnavailable && navigator.contentReveal == beforeFailure, "Missing target explains failure without navigation")
links.receive(LocalLink(libraryID: firstIdentity, target: .task(paragraph.id)).url())
check(links.error == .targetUnavailable, "Non-task block cannot masquerade as task URL")
let renamed = TaskList(title: "Different destination"); context.insert(renamed)
task.text = "Renamed résumé 🧑🏽‍💻"; task.listID = renamed.id; task.parentID = nil
list.title = "Renamed list"
try context.save()
links.receive(taskURL)
check(navigator.openTaskID == taskID && navigator.route == .list(renamed.id), "Saved URL survives rename, move and duplicate titles")
check(links.error == nil, "Successful delivery clears previous failure")
renamed.isArchived = true; renamed.completedVisibility = .hide; task.isCompleted = true
try context.save()
links.receive(taskURL)
check(navigator.contentReveal?.isArchived == true && task.isCompleted && renamed.isArchived && renamed.completedVisibility == .hide, "Archived/completed task opens explicitly without restore or preference writes")
check(try links.link(to: .task(taskID)) == taskURL, "Copy canonical link remains stable after model changes")

// Retention can arrive between copying a link and opening it, including while
// the main window is closed. Navigation must not become an implicit restore.
let retainedMetadata = try JSONEncoder().encode(TrashMetadata(deletedAt: .now,
    listTitle: renamed.title, parentTitle: nil, labels: []))
task.trashID = task.id
task.trashMetadataData = retainedMetadata
try context.save()
navigator.replace(with: .today)
let retainedRoute = navigator.route
links.receive(taskURL)
check(links.error == .targetUnavailable && navigator.route == retainedRoute && navigator.contentReveal == nil,
      "A retained task link reports unavailability without leaving the current route")
check(task.trashID == taskID && task.trashMetadataData == retainedMetadata && task.isCompleted && renamed.isArchived,
      "Opening a retained task link cannot restore it or change retained metadata")
check(!context.hasChanges, "Rejected retained task navigation performs no model writes")
do { _ = try links.link(to: .task(taskID)); preconditionFailure("Copied retained task") }
catch { check(error as? LocalLinkError == .targetUnavailable, "Stale Copy Link rejects a retained task") }
task.trashID = nil
try context.save()
check(navigator.route == retainedRoute && navigator.contentReveal == nil,
      "Restoring a task does not replay its previously rejected link")
links.receive(taskURL)
check(links.error == nil && navigator.openTaskID == taskID && navigator.contentReveal?.isArchived == true,
      "The original saved URL works again after restoring the same task identity")

let retainedListURL = LocalLink(libraryID: firstIdentity, target: .list(renamed.id)).url()
renamed.trashID = renamed.id
renamed.trashMetadataData = retainedMetadata
try context.save()
navigator.replace(with: .trash)
links.windowReady(false)
links.receive(retainedListURL)
check(navigator.route == .trash && navigator.contentReveal == nil,
      "A closed-window retained-list delivery waits without navigating")
links.windowReady(true)
check(links.error == .targetUnavailable && navigator.route == .trash && navigator.contentReveal == nil,
      "Opening the window rejects a retained list without revealing or restoring it")
links.receive(taskURL)
check(links.error == .targetUnavailable && navigator.route == .trash,
      "A task whose owner is retained is unavailable even before its own retention flag arrives")
check(renamed.trashID == renamed.id && renamed.trashMetadataData == retainedMetadata && !context.hasChanges,
      "Rejected list and child navigation preserve the retained store")
do { _ = try links.link(to: .list(renamed.id)); preconditionFailure("Copied retained list") }
catch { check(error as? LocalLinkError == .targetUnavailable, "Stale Copy Link rejects a retained list") }
renamed.trashID = nil
try context.save()
links.receive(retainedListURL)
check(links.error == nil && navigator.contentReveal?.destination == .list(renamed.id) && renamed.isArchived,
      "The original list URL works after restore without unarchiving its owner")
links.receive(taskURL)
check(navigator.openTaskID == taskID && task.trashMetadataData == retainedMetadata,
      "The restored child URL still reveals its exact original identity")

// Child document ownership never changes what a saved task/list URL targets.
let owningParent = TaskList(title: "Owning parent")
context.insert(owningParent)
renamed.parentListID = owningParent.id
renamed.isArchived = false
owningParent.isArchived = true
try context.save()
links.receive(retainedListURL)
check(navigator.route == .list(renamed.id) && navigator.contentReveal?.isArchived == true,
      "A child list URL reveals its exact document and inherited archive status")
links.receive(taskURL)
check(navigator.openTaskID == taskID && navigator.contentReveal?.listID == renamed.id && !renamed.isArchived,
      "A linked child task stays in its own document without changing its archive choice")
owningParent.trashID = owningParent.id
owningParent.trashMetadataData = retainedMetadata
try context.save()
navigator.replace(with: .today)
links.receive(retainedListURL)
check(links.error == .targetUnavailable && navigator.route == .today,
      "A late child list under a retained ancestor cannot open through its saved URL")
links.receive(taskURL)
check(links.error == .targetUnavailable && navigator.route == .today && task.trashID == nil,
      "A late child task link rejects inherited Trash without rewriting the task")
owningParent.trashID = nil; owningParent.isArchived = false
try context.save()
links.receive(taskURL)
check(links.error == nil && navigator.contentReveal?.isArchived == false && navigator.openTaskID == taskID,
      "Restoring an owning ancestor revives the same exact child-task URL")
context.delete(owningParent); try context.save()
links.receive(retainedListURL)
check(links.error == nil && navigator.route == .list(renamed.id) && renamed.parentListID == owningParent.id,
      "A missing owning parent preserves recoverable child document access and the original reference")
renamed.parentListID = nil; renamed.isArchived = true; try context.save()

let persistedIdentity = try LibraryIdentity.read(at: storeURL)
let reopened = try ModelContainer(for: schema, configurations: configuration)
check(try LibraryIdentity.read(at: storeURL) == firstIdentity && persistedIdentity == firstIdentity, "Reopened library retains identity")
let reopenedTask = try reopened.mainContext.fetch(FetchDescriptor<Block>(predicate: #Predicate { $0.id == taskID })).first!
check(reopenedTask.text == task.text && reopenedTask.listID == renamed.id && reopenedTask.isCompleted, "Reopened target keeps UUID and move/completion state")
let otherURL = fixture.appendingPathComponent("different.store")
let other = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: otherURL, cloudKitDatabase: .none))
check(try LibraryIdentity.read(at: otherURL) != firstIdentity, "A separately created library has a different identity")
withExtendedLifetime(other) {}
context.delete(task); try context.save()
links.receive(taskURL)
check(links.error == .targetUnavailable, "Deleted target does not restore or recreate itself")
do { _ = try links.link(to: .task(taskID)); preconditionFailure("Copied deleted target") }
catch { check(error as? LocalLinkError == .targetUnavailable, "Copying a stale menu target is rejected") }
let noIdentity = LocalLinkNavigation(libraryID: nil, navigator: Navigator())
noIdentity.storeReady(resolve: resolve); noIdentity.windowReady(true); noIdentity.receive(taskURL)
check(noIdentity.error == .identityUnavailable, "Missing store identity fails closed")
print("Passed \(checks) local link parsing, library identity, queued navigation and exact reveal checks")
