import Foundation

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    guard condition() else { fatalError("FAIL: \(message)") }
}

let navigator = Navigator()
let listID = UUID()
navigator.go(to: .list(listID))
check(navigator.hasDocumentEditor, "A list retains native outline command ownership")
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
check(navigator.hasDocumentEditor, "Other lists retain Document as their default")
navigator.goBack()
check(!navigator.hasDocumentEditor, "Back restores the original list's Tasks presentation")
navigator.setListViewMode(.document, for: listID)
check(navigator.hasDocumentEditor, "Returning to Document restores native outline commands")
navigator.go(to: .inbox)
check(!navigator.hasDocumentEditor, "Entering the selected queue enables smart-row focus protection")
navigator.openTask(UUID())
check(!navigator.hasDocumentEditor, "An open inspector does not turn the queue into a list editor")
navigator.closeTask()
check(!navigator.hasDocumentEditor, "Closing a queue inspector releases commands to the root handler")
navigator.showsUnfiledInbox = true
check(navigator.hasDocumentEditor, "Unfiled content retains the original editor and caret behavior")
navigator.isReviewingUnfiledInbox = true
check(!navigator.hasDocumentEditor, "Starting review releases the removed Unfiled editor")
navigator.isReviewingUnfiledInbox = false
check(navigator.hasDocumentEditor, "Finishing review returns command ownership to the document")
navigator.showsUnfiledInbox = false
check(!navigator.hasDocumentEditor, "Returning to Selected tasks releases the Unfiled editor")
navigator.goBack()
check(navigator.route == .list(listID) && navigator.hasDocumentEditor,
      "Back restores the list editor independently of the Inbox tab")
navigator.goForward()
check(navigator.route == .inbox && !navigator.hasDocumentEditor,
      "Forward to the selected queue keeps smart-row focus and command behavior")
navigator.showsUnfiledInbox = true
navigator.go(to: .tasks)
check(!navigator.hasDocumentEditor, "A retained Unfiled tab cannot make Tasks an outline editor")

let suite = "openlist-list-mode-checks-\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
let saved = Navigator(defaults: defaults)
saved.setListViewMode(.tasks, for: listID)
let reopened = Navigator(defaults: defaults)
reopened.go(to: .list(listID))
check(!reopened.hasDocumentEditor, "This Mac remembers each list's presentation across relaunch")
let list = TaskList(title: "List")
list.id = listID
let note = Block(kind: .paragraph, text: "Visible source", listID: listID)
let reveal = try ContentReveal.resolve(.block(note.id), blocks: [note], lists: [list])
reopened.reveal(reveal)
check(reopened.hasDocumentEditor && reopened.contentReveal == reveal,
      "Exact-content navigation returns to Document before revealing prose")
let queueScope = UUID(), inspectorScope = UUID()
let a = UUID(), b = UUID(), c = UUID()
navigator.go(to: .inbox)
navigator.showsUnfiledInbox = false
navigator.selectRow(a, gesture: .replace, scope: queueScope, visible: [a, b, c])
navigator.selectRow(c, gesture: .range, scope: queueScope, visible: [a, b, c])
check(navigator.orderedSelection == [a, b, c] && navigator.isSelectingRows, "Inbox range selection follows eager queue order")
navigator.reconcileSelection(scope: inspectorScope, visible: [])
check(navigator.orderedSelection == [a, b, c], "An inactive inspector cannot prune the Inbox queue selection")
navigator.reconcileSelection(scope: queueScope, visible: [c, a])
check(navigator.orderedSelection == [c, a], "Filtered Inbox membership prunes hidden rows and refreshes queue order")
navigator.selectForEditing(c, scope: queueScope, visible: [c, a])
check(navigator.selection == [c] && !navigator.isSelectingRows, "Editing a queue task intentionally returns to single native text selection")
navigator.stepRowSelection(1, extending: true, scope: queueScope, visible: [c, a])
check(navigator.selection == [c, a] && navigator.rowFocusRequest == a, "An arrow extension requests the next gutter without losing its range anchor")
navigator.finishRowFocusRequest(a)
check(navigator.rowFocusRequest == nil && navigator.rowSelection.anchorID == c, "Keyboard focus handoff preserves the range anchor")
let payload = navigator.beginBlockDrag(c, scope: queueScope, visible: [c, a])
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

print("\(checks) Inbox navigation checks passed")
