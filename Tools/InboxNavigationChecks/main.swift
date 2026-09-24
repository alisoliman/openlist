import Foundation

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    guard condition() else { fatalError("FAIL: \(message)") }
}

let navigator = Navigator()
let listID = UUID()
navigator.go(to: .list(listID))
check(navigator.listViewMode(for: listID) == .document && navigator.documentOwnsEditorCommands && navigator.documentListID == listID,
      "A list opens as its Next document, which takes outline commands")
navigator.setListViewMode(.tasks, for: listID)
check(navigator.documentOwnsEditorCommands && navigator.documentListID == listID,
      "List Tasks mode is the same document, filtered, and keeps outline commands")
navigator.selection = [UUID()]
let inspectedInTasks = UUID()
navigator.openTask(inspectedInTasks)
navigator.setListViewMode(.document, for: listID)
check(navigator.selection.isEmpty && navigator.openTaskID == inspectedInTasks,
      "Switching a list's presentation clears stale document selection and keeps the inspector")
navigator.closeTask()
check(navigator.documentOwnsEditorCommands, "Closing the inspector keeps the list document's commands")
let otherListID = UUID()
navigator.go(to: .list(otherListID))
check(navigator.listViewMode(for: otherListID) == .document, "Other lists open as their document too")
navigator.goBack()
check(navigator.documentOwnsEditorCommands && navigator.listViewMode(for: listID) == .document,
      "Back restores the original list's document")
let unknownInbox = Navigator()
unknownInbox.go(to: .inbox)
check(!unknownInbox.documentOwnsEditorCommands && unknownInbox.documentListID == nil, "Without a known Inbox list, Inbox stays a Next screen")
let inboxID = UUID()
navigator.inboxListID = inboxID
navigator.go(to: .inbox)
check(navigator.listViewMode(for: inboxID) == .tasks && !navigator.documentOwnsEditorCommands,
      "Inbox opens as triage until its list chooses Document")
navigator.selection = [UUID()]
navigator.openTask(UUID())
navigator.setListViewMode(.document, for: inboxID)
check(navigator.documentListID == inboxID && navigator.documentOwnsEditorCommands && navigator.selection.isEmpty
      && navigator.openTaskID != nil,
      "The Inbox list's Document mode shows the Inbox as its Next document, and the inspector stays open")
navigator.openTask(UUID())
check(navigator.documentListID == inboxID, "Inspector does not replace Inbox document ownership")
navigator.closeTask()
check(navigator.documentListID == inboxID, "Closing details returns to Inbox editing")
navigator.goBack()
check(navigator.route == .list(listID) && navigator.documentOwnsEditorCommands && navigator.documentListID == listID,
      "Back restores the list document")
navigator.goForward()
check(navigator.route == .inbox && navigator.documentListID == inboxID, "Forward restores Inbox document commands")
navigator.go(to: .tasks)
check(!navigator.documentOwnsEditorCommands && navigator.documentListID == nil, "Tasks does not inherit Inbox document ownership")

// The widget's Triage link shows the Inbox as triage for that visit, whatever this Mac shows it as.
let triageSuite = "openlist-triage-visit-checks-\(UUID().uuidString)"
let triageDefaults = UserDefaults(suiteName: triageSuite)!
defer { triageDefaults.removePersistentDomain(forName: triageSuite) }
let triaging = Navigator(defaults: triageDefaults)
let triageInbox = UUID()
triaging.inboxListID = triageInbox
triaging.go(to: .inbox)
triaging.setListViewMode(.document, for: triageInbox)
triaging.selection = [UUID()]
let triageInspected = UUID()
triaging.openTask(triageInspected)
triaging.showInboxTriage()
check(triaging.listViewMode(for: triageInbox) == .tasks && !triaging.documentOwnsEditorCommands && triaging.documentListID == nil
      && triaging.selection.isEmpty && triaging.openTaskID == triageInspected,
      "Triage turns the Inbox's document to triage for this visit, dropping its selection and keeping the inspector")
let relaunched = Navigator(defaults: triageDefaults)
relaunched.inboxListID = triageInbox
relaunched.go(to: .inbox)
check(relaunched.documentListID == triageInbox, "The triage visit is never saved")
triaging.go(to: .today)
triaging.go(to: .inbox)
check(triaging.documentListID == triageInbox, "Coming back to the Inbox follows this Mac's choice again")
triaging.showInboxTriage()
triaging.goBack()
triaging.goForward()
check(triaging.documentListID == triageInbox, "Back and Forward end the triage visit")
triaging.showInboxTriage()
triaging.setListViewMode(.document, for: triageInbox)
check(triaging.documentListID == triageInbox && triaging.documentOwnsEditorCommands, "Show as Document ends the triage visit")
triaging.showInboxTriage()
triaging.replace(with: .inbox)
check(triaging.documentListID == triageInbox, "Replacing the route ends the triage visit")
triaging.showInboxTriage()
// The widget's Inbox link, as RootView takes it, while the triage visit is on show.
triaging.selection = [UUID()]
triaging.openTask(triageInspected)
triaging.go(to: .inbox)
triaging.followInboxPresentation()
check(triaging.route == .inbox && triaging.documentListID == triageInbox && triaging.documentOwnsEditorCommands
      && triaging.selection.isEmpty && triaging.openTaskID == triageInspected,
      "The Inbox link after Triage follows this Mac's choice again, dropping triage's selection")
let documentSelection: Set<UUID> = [UUID()]
triaging.selection = documentSelection
triaging.followInboxPresentation()
check(triaging.documentListID == triageInbox && triaging.selection == documentSelection,
      "The Inbox link leaves the Inbox's document as it is")
triaging.setListViewMode(.tasks, for: triageInbox)
triaging.showInboxTriage()
check(triaging.listViewMode(for: triageInbox) == .tasks && triaging.documentListID == nil, "Where the Inbox is triage already, it stays triage")

let suite = "openlist-list-mode-checks-\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
let saved = Navigator(defaults: defaults)
saved.setListViewMode(.tasks, for: listID)
let reopened = Navigator(defaults: defaults)
reopened.go(to: .list(listID))
check(reopened.listViewMode(for: listID) == .tasks, "This Mac remembers each list's presentation across relaunch")
reopened.setListViewMode(.document, for: listID)
check(Navigator(defaults: defaults).listViewMode(for: listID) == .document,
      "Choosing Document again is remembered too")
reopened.setListViewMode(.tasks, for: listID)
let list = TaskList(title: "List")
list.id = listID
let note = Block(kind: .paragraph, text: "Visible source", listID: listID)
let reveal = try ContentReveal.resolve(.block(note.id), blocks: [note], lists: [list])
reopened.reveal(reveal)
check(reopened.listViewMode(for: listID) == .document && reopened.contentReveal == reveal,
      "Exact-content navigation returns to Document before revealing prose")
let outlineScope = UUID(), inspectorScope = UUID()
let a = UUID(), b = UUID(), c = UUID()
navigator.go(to: .inbox)
navigator.selectForEditing(a, scope: outlineScope, visible: [a, b, c])
check(navigator.selection == [a] && navigator.rowSelection.scopeID == outlineScope,
      "Editing an Inbox line selects it in the document's scope")
navigator.reconcileSelection(scope: inspectorScope, visible: [])
check(navigator.selection == [a], "An inactive inspector cannot prune the Inbox document's selection")
navigator.reconcileSelection(scope: outlineScope, visible: [c, b])
check(navigator.selection.isEmpty, "Filtered Inbox visibility prunes a hidden line")
navigator.selectForEditing(c, scope: outlineScope, visible: [c, a])
check(navigator.selection == [c], "Editing another line selects it alone")
navigator.go(to: .tasks)
check(navigator.selection.isEmpty && navigator.rowSelection.scopeID == nil, "Navigation clears the selection and its scope together")

let listScope = UUID()
navigator.go(to: .list(listID))
navigator.selectForEditing(a, scope: listScope, visible: [a, b, c])
navigator.setListViewMode(.tasks, for: listID)
check(navigator.listViewMode(for: listID) == .tasks && navigator.selection.isEmpty && navigator.rowSelection.scopeID == nil,
      "Switching to list Tasks clears the document selection and its scope")
navigator.selectForEditing(c, scope: listScope, visible: [c, b, a])
navigator.reconcileSelection(scope: listScope, visible: [b, a])
check(navigator.selection.isEmpty, "A line that stops showing, as a completed one hidden, leaves the selection")
navigator.selectForEditing(b, scope: listScope, visible: [b, a])
navigator.setListViewMode(.document, for: listID)
check(navigator.listViewMode(for: listID) == .document && navigator.selection.isEmpty && navigator.rowSelection.scopeID == nil,
      "Returning to Document clears list Tasks selection before text focus resumes")

check(navigator.scrollOffset(for: .calendar) == nil, "New pages use the native top anchor rather than a raw zero offset")
navigator.go(to: .today)
navigator.rememberScrollOffset(-52, for: .today)
check(navigator.scrollOffset(for: .today) == -52, "The real top retains the toolbar's negative content coordinate")
navigator.go(to: .tasks)
navigator.rememberScrollOffset(188, for: .tasks)
check(navigator.scrollOffset(for: .tasks) == 188, "A middle position retains its exact native coordinate")
navigator.goBack()
check(navigator.scrollOffset(for: .today) == -52 && navigator.takeScrollRestoration(for: .today) == -52,
      "Back cannot accumulate a toolbar-height offset")
navigator.goForward()
check(navigator.scrollOffset(for: .tasks) == 188 && navigator.scrollOffset(for: .today) == -52,
      "Routes retain independent native reading positions")
navigator.rememberScrollOffset(.infinity, for: .tasks)
check(navigator.scrollOffset(for: .tasks) == 188, "Invalid scroll geometry cannot replace a saved position")
navigator.rememberScrollOffset(0, for: .tasks)
check(navigator.scrollOffset(for: .tasks) == 0, "A saved raw zero remains distinct from an unvisited page")

// Back and Forward return each page to where it was left; a new visit starts at the top.
let scrolling = Navigator()
scrolling.rememberScrollOffset(420, for: .today)
scrolling.go(to: .tasks)
check(scrolling.scrollOffset(for: .tasks) == nil && scrolling.takeScrollRestoration(for: .tasks) == nil,
      "A new visit starts at the top")
scrolling.rememberScrollOffset(90, for: .tasks)
scrolling.go(to: .today)
check(scrolling.takeScrollRestoration(for: .today) == nil, "Going to a page again starts it at the top, wherever it was before")
scrolling.rememberScrollOffset(30, for: .today)
scrolling.goBack()
check(scrolling.takeScrollRestoration(for: .today) == nil && scrolling.takeScrollRestoration(for: .tasks) == 90,
      "Back returns the page it goes to to where it was left")
check(scrolling.takeScrollRestoration(for: .tasks) == nil, "Only the page Back returned to scrolls back, once")
scrolling.goBack()
check(scrolling.takeScrollRestoration(for: .today) == 420, "Each visit in the history keeps its own place")
scrolling.goForward()
check(scrolling.takeScrollRestoration(for: .tasks) == 90, "Forward returns a page to where it was left too")
scrolling.goForward()
check(scrolling.takeScrollRestoration(for: .today) == 30, "Forward to a later visit of a page returns to that visit's place")
scrolling.goBack()
scrolling.go(to: .calendar)
check(!scrolling.canGoForward && scrolling.takeScrollRestoration(for: .calendar) == nil, "A new visit from the history starts at the top")
scrolling.replace(with: .inbox)
check(scrolling.scrollOffset(for: .inbox) == nil && scrolling.takeScrollRestoration(for: .inbox) == nil,
      "A page that replaces a deleted one starts at the top")

// The inspector belongs to the window: it stays open across screens and
// presentations, and closes only when the route is replaced.
let inspecting = Navigator()
let inspected = UUID(), inspectedListID = UUID()
inspecting.openTask(inspected)
inspecting.go(to: .calendar)
check(inspecting.openTaskID == inspected, "Going to another screen keeps the inspector on the same task")
inspecting.goBack()
check(inspecting.openTaskID == inspected, "Back keeps the inspector open")
inspecting.goForward()
check(inspecting.openTaskID == inspected, "Forward keeps the inspector open")
inspecting.go(to: .list(inspectedListID))
inspecting.setListViewMode(.tasks, for: inspectedListID)
check(inspecting.openTaskID == inspected, "A list's presentation is its document either way, so the inspector stays")
let inspectingInbox = UUID()
inspecting.inboxListID = inspectingInbox
inspecting.go(to: .inbox)
inspecting.setListViewMode(.document, for: inspectingInbox)
check(inspecting.openTaskID == inspected, "The Inbox's document is the Next document too, so the inspector stays")
inspecting.replace(with: .today)
check(inspecting.openTaskID == nil, "Stepping off a deleted list closes the inspector")

// A reminder, a link or a search hit on Inbox content lands on the Inbox, as
// everywhere else, never on the Inbox drawn as an ordinary list page.
let revealing = Navigator()
let revealInbox = TaskList(title: "Inbox", isSystemInbox: true)
revealing.inboxListID = revealInbox.id
let inboxLine = Block(kind: .heading1, text: "Errands", listID: revealInbox.id)
let inboxTask = Block(kind: .task, text: "Buy stamps", listID: revealInbox.id)
let inboxBlocks = [inboxLine, inboxTask]
revealing.go(to: .today)
let lineReveal = try ContentReveal.resolve(.block(inboxLine.id), query: "errands", blocks: inboxBlocks, lists: [revealInbox])
revealing.reveal(lineReveal)
check(revealing.route == .inbox && revealing.shows(revealInbox.id) && !revealing.shows(UUID())
      && revealing.listViewMode(for: revealInbox.id) == .document && revealing.documentListID == revealInbox.id
      && revealing.contentReveal == lineReveal && revealing.selection == [inboxLine.id],
      "A line in the Inbox reveals in the Inbox's document for that visit, even where it shows as triage")
revealing.goBack()
check(revealing.route == .today && revealing.contentReveal == nil, "Back leaves the reveal for the page it came from")
revealing.goForward()
check(revealing.route == .inbox && revealing.listViewMode(for: revealInbox.id) == .tasks,
      "Back on the Inbox, it shows as this Mac chose again")
revealing.go(to: .today)
revealing.reveal(lineReveal)
revealing.showInboxTriage()
check(revealing.listViewMode(for: revealInbox.id) == .tasks && revealing.contentReveal == nil,
      "The widget's Triage link turns a revealed Inbox back to triage")
revealing.go(to: .today)
let taskReveal = try ContentReveal.resolve(.block(inboxTask.id), blocks: inboxBlocks, lists: [revealInbox])
revealing.reveal(taskReveal)
check(revealing.route == .inbox && revealing.listViewMode(for: revealInbox.id) == .tasks
      && revealing.openTaskID == inboxTask.id && revealing.contentReveal == taskReveal && revealing.selection.isEmpty,
      "An Inbox task opens in the inspector over the Inbox as this Mac shows it, with no line selected")
revealing.go(to: .today)
let inboxReveal = try ContentReveal.resolve(.list(revealInbox.id), blocks: inboxBlocks, lists: [revealInbox])
revealing.reveal(inboxReveal)
check(revealing.route == .inbox && revealing.listViewMode(for: revealInbox.id) == .tasks,
      "A link to the Inbox opens the Inbox as this Mac shows it")
let otherList = TaskList(title: "Other")
let otherLine = Block(kind: .paragraph, text: "Notes", listID: otherList.id)
revealing.setListViewMode(.tasks, for: otherList.id)
revealing.reveal(try ContentReveal.resolve(.block(otherLine.id), blocks: [otherLine], lists: [otherList]))
check(revealing.route == .list(otherList.id) && revealing.listViewMode(for: otherList.id) == .document
      && revealing.shows(otherList.id) && !revealing.shows(revealInbox.id),
      "Any other list's content reveals on its own page")

print("\(checks) Inbox navigation checks passed")
