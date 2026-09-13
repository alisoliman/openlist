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
print("\(checks) Inbox navigation checks passed")
