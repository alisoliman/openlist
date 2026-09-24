import Foundation

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    guard condition() else { fatalError("FAIL: \(message)") }
}

let navigator = Navigator()
let listID = UUID()
navigator.go(to: .list(listID))
check(navigator.listViewMode(for: listID) == .document && navigator.documentOwnsEditorCommands && !navigator.legacyDocumentOwnsKeys,
      "A list opens as its Next document, which takes outline commands and leaves the Next keys on")
navigator.setListViewMode(.tasks, for: listID)
check(navigator.documentOwnsEditorCommands && !navigator.legacyDocumentOwnsKeys,
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
check(!unknownInbox.documentOwnsEditorCommands && !unknownInbox.legacyDocumentOwnsKeys, "Without a known Inbox list, Inbox stays a Next screen")
let inboxID = UUID()
navigator.inboxListID = inboxID
navigator.go(to: .inbox)
check(navigator.listViewMode(for: inboxID) == .tasks && !navigator.documentOwnsEditorCommands,
      "Inbox opens as triage until its list chooses Document")
navigator.selection = [UUID()]
navigator.openTask(UUID())
navigator.setListViewMode(.document, for: inboxID)
check(navigator.legacyDocumentOwnsKeys && navigator.documentOwnsEditorCommands && navigator.selection.isEmpty && navigator.openTaskID == nil,
      "The Inbox list's Document mode gives Inbox its legacy document editor, which takes the task panel over")
navigator.openTask(UUID())
check(navigator.legacyDocumentOwnsKeys, "Inspector does not replace Inbox document ownership")
navigator.closeTask()
check(navigator.legacyDocumentOwnsKeys, "Closing details returns to Inbox editing")
navigator.goBack()
check(navigator.route == .list(listID) && navigator.documentOwnsEditorCommands && !navigator.legacyDocumentOwnsKeys,
      "Back restores the list document")
navigator.goForward()
check(navigator.route == .inbox && navigator.legacyDocumentOwnsKeys, "Forward restores Inbox document commands")
navigator.go(to: .tasks)
check(!navigator.documentOwnsEditorCommands && !navigator.legacyDocumentOwnsKeys, "Tasks does not inherit Inbox document ownership")

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
navigator.selectRow(a, gesture: .replace, scope: outlineScope, visible: [a, b, c])
navigator.selectRow(c, gesture: .range, scope: outlineScope, visible: [a, b, c])
check(navigator.orderedSelection == [a, b, c] && navigator.isSelectingRows, "Inbox range selection follows eager outline order")
navigator.reconcileSelection(scope: inspectorScope, visible: [])
check(navigator.orderedSelection == [a, b, c], "An inactive inspector cannot prune the Inbox outline selection")
navigator.reconcileSelection(scope: outlineScope, visible: [c, a])
check(navigator.orderedSelection == [c, a], "Filtered Inbox visibility prunes hidden rows and refreshes outline order")
navigator.selectForEditing(c, scope: outlineScope, visible: [c, a])
check(navigator.selection == [c] && !navigator.isSelectingRows, "Editing a outline task intentionally returns to single native text selection")
navigator.stepRowSelection(1, extending: true, scope: outlineScope, visible: [c, a])
check(navigator.selection == [c, a] && navigator.rowFocusRequest == a, "An arrow extension requests the next gutter without losing its range anchor")
navigator.finishRowFocusRequest(a)
check(navigator.rowFocusRequest == nil && navigator.rowSelection.anchorID == c, "Keyboard focus handoff preserves the range anchor")
let payload = navigator.beginBlockDrag(c, scope: outlineScope, visible: [c, a])
check(DragPayload.blockDrop(payload, session: navigator.blockDragSessionID, activeLegacyID: nil) == .blocks([c, a]),
      "Queue ownership drag carries visible multi-row order without becoming an Inbox reorder")
navigator.go(to: .tasks)
check(navigator.selection.isEmpty && navigator.rowSelection.scopeID == nil && navigator.rowFocusRequest == nil,
      "Navigation clears selection scope and pending gutter focus together")

let listScope = UUID()
navigator.go(to: .list(listID))
navigator.selectRow(a, gesture: .replace, scope: listScope, visible: [a, b, c])
navigator.stepRowSelection(1, extending: true, scope: listScope, visible: [a, b, c])
navigator.setListViewMode(.tasks, for: listID)
check(navigator.listViewMode(for: listID) == .tasks && navigator.selection.isEmpty && navigator.rowSelection.scopeID == nil
      && !navigator.isSelectingRows && navigator.rowFocusRequest == nil,
      "Switching to list Tasks clears the document selection, anchor and pending native focus")
navigator.selectRow(c, gesture: .replace, scope: listScope, visible: [c, b, a])
navigator.selectRow(a, gesture: .range, scope: listScope, visible: [c, b, a])
check(navigator.orderedSelection == [c, b, a], "List Tasks range follows the entire sorted projection")
navigator.reconcileSelection(scope: listScope, visible: [b, a])
check(navigator.orderedSelection == [b, a], "Hiding a completed task prunes it from list Tasks selection")
navigator.setListViewMode(.document, for: listID)
check(navigator.listViewMode(for: listID) == .document && navigator.selection.isEmpty && navigator.rowSelection.scopeID == nil,
      "Returning to Document clears list Tasks row selection before text focus resumes")

check(navigator.scrollOffset(for: .calendar) == nil, "New pages use the native top anchor rather than a raw zero offset")
navigator.rememberScrollOffset(-52, for: .today)
check(navigator.scrollOffset(for: .today) == -52, "The real top retains the toolbar's negative content coordinate")
navigator.rememberScrollOffset(188, for: .tasks)
check(navigator.scrollOffset(for: .tasks) == 188, "A middle position retains its exact native coordinate")
navigator.go(to: .today)
navigator.go(to: .tasks)
navigator.goBack()
check(navigator.scrollOffset(for: .today) == -52, "Back cannot accumulate a toolbar-height offset")
check(navigator.scrollOffset(for: .tasks) == 188, "Routes retain independent native reading positions")
navigator.rememberScrollOffset(.infinity, for: .tasks)
check(navigator.scrollOffset(for: .tasks) == 188, "Invalid scroll geometry cannot replace a saved position")
navigator.rememberScrollOffset(0, for: .tasks)
check(navigator.scrollOffset(for: .tasks) == 0, "A saved raw zero remains distinct from an unvisited page")

// The inspector belongs to the window: it stays open across screens and
// closes only when a document takes the list over or the route is replaced.
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
check(inspecting.openTaskID == nil, "Handing the Inbox to its legacy document editor closes the inspector")
inspecting.openTask(inspected)
inspecting.replace(with: .today)
check(inspecting.openTaskID == nil, "Stepping off a deleted list closes the inspector")

print("\(checks) Inbox navigation checks passed")
