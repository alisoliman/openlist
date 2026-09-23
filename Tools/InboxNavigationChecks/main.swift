import Foundation

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    guard condition() else { fatalError("FAIL: \(message)") }
}

let navigator = Navigator()
let listID = UUID()
navigator.go(to: .list(listID))
check(!navigator.hasDocumentEditor, "A list opens as a task list until this Mac chooses Document")
navigator.setListViewMode(.document, for: listID)
check(navigator.hasDocumentEditor, "Document mode gives the list native outline command ownership")
navigator.selection = [UUID()]
navigator.openTask(UUID())
navigator.setListViewMode(.tasks, for: listID)
check(!navigator.hasDocumentEditor, "List Tasks mode releases outline command ownership")
check(navigator.selection.isEmpty && navigator.openTaskID == nil, "Switching presentation clears stale document and inspector selection")
navigator.openTask(UUID())
navigator.closeTask()
check(!navigator.hasDocumentEditor, "Closing a Tasks-mode inspector keeps global task commands available")
let otherListID = UUID()
navigator.go(to: .list(otherListID))
check(!navigator.hasDocumentEditor, "Other lists keep Tasks as their default")
navigator.goBack()
check(!navigator.hasDocumentEditor, "Back restores the original list's Tasks presentation")
navigator.setListViewMode(.document, for: listID)
check(navigator.hasDocumentEditor, "Returning to Document restores native outline commands")
let unknownInbox = Navigator()
unknownInbox.go(to: .inbox)
check(!unknownInbox.hasDocumentEditor, "Without a known Inbox list, Inbox stays a Next screen")
let inboxID = UUID()
navigator.inboxListID = inboxID
navigator.go(to: .inbox)
check(!navigator.hasDocumentEditor, "Inbox opens as triage until its list chooses Document")
navigator.selection = [UUID()]
navigator.setListViewMode(.document, for: inboxID)
check(navigator.hasDocumentEditor && navigator.selection.isEmpty, "The Inbox list's Document mode gives Inbox its rich document editor")
navigator.openTask(UUID())
check(navigator.hasDocumentEditor, "Inspector does not replace Inbox document ownership")
navigator.closeTask()
check(navigator.hasDocumentEditor, "Closing details returns to Inbox editing")
navigator.goBack()
check(navigator.route == .list(listID) && navigator.hasDocumentEditor, "Back restores the list editor")
navigator.goForward()
check(navigator.route == .inbox && navigator.hasDocumentEditor, "Forward restores Inbox document commands")
navigator.go(to: .tasks)
check(!navigator.hasDocumentEditor, "Tasks does not inherit Inbox document ownership")

let suite = "openlist-list-mode-checks-\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
let saved = Navigator(defaults: defaults)
saved.setListViewMode(.document, for: listID)
let reopened = Navigator(defaults: defaults)
reopened.go(to: .list(listID))
check(reopened.hasDocumentEditor, "This Mac remembers each list's presentation across relaunch")
reopened.setListViewMode(.tasks, for: listID)
check(!reopened.hasDocumentEditor && Navigator(defaults: defaults).listViewMode(for: listID) == .tasks,
      "Choosing Tasks again is remembered too")
let list = TaskList(title: "List")
list.id = listID
let note = Block(kind: .paragraph, text: "Visible source", listID: listID)
let reveal = try ContentReveal.resolve(.block(note.id), blocks: [note], lists: [list])
reopened.reveal(reveal)
check(reopened.hasDocumentEditor && reopened.contentReveal == reveal,
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
check(!navigator.hasDocumentEditor && navigator.selection.isEmpty && navigator.rowSelection.scopeID == nil
      && !navigator.isSelectingRows && navigator.rowFocusRequest == nil,
      "Switching to list Tasks clears the document selection, anchor and pending native focus")
navigator.selectRow(c, gesture: .replace, scope: listScope, visible: [c, b, a])
navigator.selectRow(a, gesture: .range, scope: listScope, visible: [c, b, a])
check(navigator.orderedSelection == [c, b, a], "List Tasks range follows the entire sorted projection")
navigator.reconcileSelection(scope: listScope, visible: [b, a])
check(navigator.orderedSelection == [b, a], "Hiding a completed task prunes it from list Tasks selection")
navigator.setListViewMode(.document, for: listID)
check(navigator.hasDocumentEditor && navigator.selection.isEmpty && navigator.rowSelection.scopeID == nil,
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

print("\(checks) Inbox navigation checks passed")
