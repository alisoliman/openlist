import AppKit
import SwiftData

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
    checks += 1
}

let schema = Schema([TaskList.self, Block.self, SidebarSection.self, TaskLabel.self, Attachment.self, ActivityEvent.self])
let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
let store = Store(context: container.mainContext)
store.context.autosaveEnabled = false
store.bootstrap()
let list = store.createList(title: "Undo fixtures")
check(store.blocks(inList: list.id).isEmpty, "Creating a list must not persist placeholder tasks")
let document = DocumentContext(listID: list.id)
let first = store.appendBlock(kind: .task, text: "First", to: document)
let second = store.appendBlock(kind: .task, text: "Second", to: document)
let secondID = second.id
let child = store.insertChild(kind: .task, text: "Child", of: second)
let childID = child.id
let due = Date.now.addingTimeInterval(100_000)
second.dueDate = due
second.reminderAt = due.addingTimeInterval(-600)
second.includesTime = true
second.note = "Keep this note"
second.priority = .high
second.isStarred = true
let label = store.findOrCreateLabel(named: "undo-fixture")!
second.labelIDs = [label.id]
second.recurrence = Recurrence(frequency: .daily)
let rich = NSMutableAttributedString(string: "Second")
RichTextCodec.toggleTrait(.boldFontMask, in: rich, range: NSRange(location: 0, length: rich.length), kind: .task)
store.setContent(second, attributed: rich)
let richData = second.richData
let filename = "editor-undo-\(UUID().uuidString).txt"
let bytes = Data("attachment survives undo and redo".utf8)
try MediaStore.shared.restoreFile(bytes, filename: filename)
defer { MediaStore.shared.delete(filename: filename) }
let attachment = Attachment(blockID: second.id, filename: filename, displayName: "note.txt", contentType: "text/plain", byteCount: bytes.count)
let attachmentID = attachment.id
store.context.insert(attachment)
store.save()

let undo = UndoManager()
undo.groupsByEvent = false
undo.beginUndoGrouping()
store.undoableEditorEdit(in: list.id, name: "Merge blocks", undoManager: undo) {
    _ = store.backspaceAtStart(second, content: store.attributedContent(of: second), in: document)
    store.save()
}
undo.endUndoGrouping()
check(store.block(id: secondID) == nil, "Merge removes second row")
check(store.block(id: childID)?.parentID == first.id, "Merge adopts child")
check(first.note == "Keep this note" && first.dueDate == due && first.isStarred, "Merge preserves task details")
check(store.attachments(for: first.id).first?.id == attachmentID && MediaStore.shared.fileContents(filename: filename) == bytes, "Merge moves attachments without deleting their files")
check(undo.canUndo, "Merge registers an undo action")
// A later unrelated metadata edit to the surviving task must not be rolled back.
first.mediaCaption = "Unrelated later caption"
store.save()
undo.undo()
let restored = store.block(id: secondID)!
check(first.text == "First" && restored.text == "Second", "Undo restores separate texts")
check(restored.richData == richData, "Undo restores rich content")
check(restored.note == "Keep this note" && first.note.isEmpty && first.mediaCaption == "Unrelated later caption", "Undo restores notes without overwriting unrelated fields")
check(restored.dueDate == due && restored.reminderAt == due.addingTimeInterval(-600), "Undo restores schedule and reminder")
check(restored.isStarred && restored.priority == .high && restored.labelIDs == [label.id], "Undo restores flags and labels")
check(restored.recurrence?.frequency == .daily, "Undo restores recurrence")
check(store.block(id: childID)?.parentID == secondID, "Undo restores original child relationship")
check(store.attachments(for: secondID).first?.id == attachmentID, "Undo restores original attachment identity")
check(MediaStore.shared.fileContents(filename: filename) == bytes, "Undo restores deleted attachment bytes")
check(undo.canRedo, "Undo registers redo")
undo.redo()
check(store.block(id: secondID) == nil && first.text == "FirstSecond", "Redo reapplies merge")
undo.undo()
check(store.attachments(for: secondID).first?.filename == filename && MediaStore.shared.fileContents(filename: filename) == bytes, "Repeated undo restores attachment again")

undo.removeAllActions()
undo.beginUndoGrouping()
store.undoableEditorEdit(in: list.id, name: "Split block", undoManager: undo) {
    _ = store.splitBlock(first, at: 2, content: store.attributedContent(of: first))
    store.save()
}
undo.endUndoGrouping()
let countAfterSplit = store.blocks(inList: list.id).count
undo.undo()
check(first.text == "First" && store.blocks(inList: list.id).count == countAfterSplit - 1, "Split undo restores original block")
undo.redo()
check(store.blocks(inList: list.id).count == countAfterSplit, "Split redo restores new block")

undo.removeAllActions()
let destination = store.createList(title: "Move destination")
undo.beginUndoGrouping()
store.undoableEditorEdit(in: Set([list.id, destination.id]), name: "Move task", undoManager: undo) {
    _ = store.move(store.block(id: secondID)!, toParent: nil, above: nil, in: destination.id)
    store.save()
}
undo.endUndoGrouping()
check(store.block(id: secondID)?.listID == destination.id && store.block(id: childID)?.listID == destination.id, "Cross-list move includes descendants")
undo.undo()
check(store.block(id: secondID)?.listID == list.id && store.block(id: childID)?.listID == list.id, "Cross-list undo returns task and descendants to source")
undo.redo()
check(store.block(id: secondID)?.listID == destination.id && store.attachments(for: secondID).first?.id == attachmentID, "Cross-list redo retains attachments")
undo.undo()

let conflictList = store.createList(title: "Conflicting schedules")
let conflictDocument = DocumentContext(listID: conflictList.id)
let earlier = store.appendBlock(kind: .task, text: "Earlier", to: conflictDocument)
earlier.dueDate = due
let conflict = store.appendBlock(kind: .task, text: "Conflicting", to: conflictDocument)
conflict.dueDate = due.addingTimeInterval(86_400)
let conflictID = conflict.id
let beforeConflict = store.blocks(inList: conflictList.id).count
_ = store.backspaceAtStart(conflict, content: store.attributedContent(of: conflict), in: conflictDocument)
check(store.block(id: conflictID) != nil && store.blocks(inList: conflictList.id).count == beforeConflict && store.editorNotice != nil, "Conflicting task schedules do not lose a row")
_ = store.backspaceAtStart(earlier, content: store.attributedContent(of: earlier), in: conflictDocument)
check(earlier.isTask && earlier.dueDate == due, "Backspace at first task preserves its kind and schedule")

undo.removeAllActions()
let image = store.appendBlock(kind: .image, to: document)
let imageID = image.id
let imageFile = "editor-image-\(UUID().uuidString).png"
try MediaStore.shared.restoreFile(bytes, filename: imageFile)
defer { MediaStore.shared.delete(filename: imageFile) }
image.mediaFilename = imageFile
store.save()
undo.beginUndoGrouping()
store.undoableEditorEdit(in: list.id, name: "Delete image", undoManager: undo) {
    store.deleteBlock(image)
}
undo.endUndoGrouping()
check(MediaStore.shared.fileContents(filename: imageFile) == nil, "Deleting image removes file")
undo.undo()
check(store.block(id: imageID)?.mediaFilename == imageFile && MediaStore.shared.fileContents(filename: imageFile) == bytes, "Image undo restores row and file")
undo.redo()
check(store.block(id: imageID) == nil && MediaStore.shared.fileContents(filename: imageFile) == nil, "Image redo removes restored file")

let removedList = store.createList(title: "Permanent deletion fixture")
undo.removeAllActions()
undo.beginUndoGrouping()
store.undoableEditorEdit(in: removedList.id, name: "New task", undoManager: undo) {
    _ = store.appendBlock(kind: .task, text: "Cannot resurrect", to: DocumentContext(listID: removedList.id))
    store.save()
}
undo.endUndoGrouping()
let removedListID = removedList.id
store.deleteList(removedList)
undo.undo()
check(store.blocks(inList: removedListID).isEmpty && store.editorNotice?.contains("permanently deleted") == true, "Undo cannot recreate orphan tasks after permanent list deletion")

store.setArchived(true, for: list)
check(!NotificationService.shared.scheduled.contains(secondID), "Archiving cancels reminders")
store.setArchived(false, for: list)
check(NotificationService.shared.scheduled.contains(secondID), "Unarchiving restores future reminders")

let plain = RichTextCodec.decode(nil, plainText: "Remote formatting", kind: .task)
let formatted = NSMutableAttributedString(attributedString: plain)
RichTextCodec.toggleTrait(.boldFontMask, in: formatted, range: NSRange(location: 0, length: 6), kind: .task)
let plainSignature = BlockTextView.ContentSignature(attributedText: plain, kind: .task, isCompleted: false)
let formattedSignature = BlockTextView.ContentSignature(attributedText: formatted, kind: .task, isCompleted: false)
check(plainSignature != formattedSignature, "Formatting-only imports invalidate the native editor content signature")
let decoded = RichTextCodec.decode(RichTextCodec.encode(formatted, kind: .task), plainText: formatted.string, kind: .task)
check(formattedSignature == BlockTextView.ContentSignature(attributedText: decoded, kind: .task, isCompleted: false), "A local formatting round trip does not unnecessarily rewrite native text storage")
formatted.replaceCharacters(in: NSRange(location: 0, length: 6), with: "Edited")
check(formattedSignature.attributedText.string == "Remote formatting", "Editor signatures retain immutable content snapshots")

let editor = BlockTextView(blockID: UUID(), kind: .task, isCompleted: false, attributedText: plain, isFocused: false, focusToken: 0, callbacks: BlockEditorCallbacks())
let coordinator = editor.makeCoordinator()
let native = BlockNSTextView(frame: .zero)
coordinator.apply(plain, to: native, kind: .task, isCompleted: false)
native.setSelectedRange(NSRange(location: 3, length: 2))
coordinator.apply(decoded, to: native, kind: .task, isCompleted: false)
let remoteFont = native.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
check(remoteFont.map { NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } == true, "The native text storage receives imported formatting")
check(native.selectedRange() == NSRange(location: 3, length: 2), "Applying remote formatting preserves the user's selection")

native.coordinator = coordinator
var editedArchive: Data?
coordinator.parent.callbacks.onChange = { editedArchive = RichTextCodec.encode($0, kind: .task) }
coordinator.apply(plain, to: native, kind: .task, isCompleted: false)
native.setSelectedRange(NSRange(location: 0, length: 6))
native.toggleBold(nil)
let formattingEcho = RichTextCodec.decode(editedArchive, plainText: native.string, kind: .task)
check(coordinator.signature == BlockTextView.ContentSignature(attributedText: formattingEcho, kind: .task, isCompleted: false), "Native formatting updates its signature before the model echo, avoiding a redundant restyle")
native.textStorage?.append(NSAttributedString(string: "!", attributes: RichTextCodec.baseAttributes(for: .task)))
native.setSelectedRange(NSRange(location: native.string.utf16.count, length: 0))
coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: native))
let typingEcho = RichTextCodec.decode(editedArchive, plainText: native.string, kind: .task)
check(coordinator.signature == BlockTextView.ContentSignature(attributedText: typingEcho, kind: .task, isCompleted: false), "Ordinary typing still produces a matching model echo without resetting native editing")

let inlineRange = NSRange(location: 0, length: 6)
let inlineEdits: [(String, (NSMutableAttributedString) -> Void)] = [
    ("italic", { RichTextCodec.toggleTrait(.italicFontMask, in: $0, range: inlineRange, kind: .task) }),
    ("strikethrough", { RichTextCodec.toggleStrikethrough(in: $0, range: inlineRange) }),
    ("inline code", { RichTextCodec.toggleInlineCode(in: $0, range: inlineRange, kind: .task) }),
    ("link", { RichTextCodec.setLink(URL(string: "https://example.invalid"), in: $0, range: inlineRange) }),
]
for (name, edit) in inlineEdits {
    let content = NSMutableAttributedString(attributedString: plain)
    edit(content)
    let signature = BlockTextView.ContentSignature(attributedText: content, kind: .task, isCompleted: false)
    let roundTrip = RichTextCodec.decode(RichTextCodec.encode(content, kind: .task), plainText: content.string, kind: .task)
    check(signature != plainSignature, "Remote \(name) changes invalidate the editor signature")
    check(signature == BlockTextView.ContentSignature(attributedText: roundTrip, kind: .task, isCompleted: false), "Local \(name) echoes preserve native editing without a redundant restyle")
}
// The popup belongs to the actual wrapped caret and the scroll viewport.
let viewport = CGRect(x: -40, y: -500, width: 420, height: 700)
let popup = SlashMenuLayout.frame(caret: CGRect(x: 320, y: 170, width: 1, height: 20), viewport: viewport, preferredHeight: 264)!
check(viewport.contains(popup) && popup.maxY < 170, "Bottom-edge popup opens above the caret within the viewport")
let narrowViewport = CGRect(x: 0, y: 0, width: 180, height: 140)
let narrowPopup = SlashMenuLayout.frame(caret: CGRect(x: 140, y: 20, width: 1, height: 18), viewport: narrowViewport, preferredHeight: 264)!
check(narrowViewport.contains(narrowPopup) && narrowPopup.width == 164 && narrowPopup.height < 264, "Narrow inspectors constrain popup width and scrolling height")
check(SlashMenuLayout.frame(caret: CGRect(x: 0, y: 800, width: 1, height: 20), viewport: viewport, preferredHeight: 264) == nil, "A caret scrolled outside the viewport does not leave a detached menu")

let textStorage = NSTextStorage()
let layoutManager = NSLayoutManager()
let textContainer = NSTextContainer(size: CGSize(width: 180, height: CGFloat.greatestFiniteMagnitude))
textContainer.lineFragmentPadding = 0
layoutManager.addTextContainer(textContainer)
textStorage.addLayoutManager(layoutManager)
let input = BlockNSTextView(frame: CGRect(x: 0, y: 0, width: 180, height: 300), textContainer: textContainer)
input.textContainerInset = .zero
input.coordinator = coordinator
input.delegate = coordinator
let wrapped = RichTextCodec.decode(nil, plainText: "A long line that wraps across several visual rows with a /h2 suffix", kind: .task)
coordinator.apply(wrapped, to: input, kind: .task, isCompleted: false)
_ = input.height(fittingWidth: 180)
let trigger = (wrapped.string as NSString).range(of: "/h2").location
let wrappedCaret = input.caretRectLocal(at: trigger + 3)
check(wrappedCaret.minY > input.caretRectLocal(at: 0).minY && wrappedCaret.height > 0, "Caret geometry includes the wrapped line and a nonzero line height")
check(!input.isOnFirstLine(trigger) && input.isOnLastLine(wrapped.length), "Arrow boundaries use visual lines")
var lastQuery: String?
var queryRange = NSRange()
coordinator.parent.callbacks.onSlashQuery = { query, range, _, _ in lastQuery = query; queryRange = range }
input.setSelectedRange(NSRange(location: trigger + 3, length: 0))
coordinator.updateSlashQuery(in: input)
check(lastQuery == "h2" && queryRange == NSRange(location: trigger, length: 3), "Slash query removes only its trigger and filter before a suffix")
input.isSlashMenuOpen = true
coordinator.dismissSlash(in: input)
lastQuery = nil
coordinator.updateSlashQuery(in: input)
check(lastQuery == nil, "Escape suppresses the same slash trigger during subsequent selection or layout updates")
input.isSlashMenuOpen = false
input.setSelectedRange(NSRange(location: 0, length: 0))
coordinator.updateSlashQuery(in: input)
input.setSelectedRange(NSRange(location: trigger + 3, length: 0))
coordinator.updateSlashQuery(in: input)
check(lastQuery == "h2", "Moving away from a dismissed trigger allows a later command session")
coordinator.parent = BlockTextView(blockID: UUID(), kind: .code, isCompleted: false, attributedText: wrapped, isFocused: false, focusToken: 0, callbacks: coordinator.parent.callbacks)
lastQuery = nil
coordinator.updateSlashQuery(in: input)
check(lastQuery == nil, "Code blocks keep slash characters literal")
coordinator.parent = editor

let selectedText = RichTextCodec.decode(nil, plainText: "Before DELETE After", kind: .task)
coordinator.apply(selectedText, to: input, kind: .task, isCompleted: false)
input.setSelectedRange(NSRange(location: 7, length: 7))
var returnedText = ""
var returnedCaret = -1
coordinator.parent.callbacks.onReturn = { caret, content in returnedCaret = caret; returnedText = content.string; return true }
check(coordinator.textView(input, doCommandBy: #selector(NSResponder.insertNewline(_:))), "Return is routed to the outline")
check(returnedText == "Before After" && returnedCaret == 7, "Return replaces selected text before splitting, preserving the suffix")
var tabCaret = -1
coordinator.parent.callbacks.onTab = { _, caret in tabCaret = caret; return true }
check(coordinator.textView(input, doCommandBy: #selector(NSResponder.insertTab(_:))) && tabCaret == 7, "Indentation receives the original mid-text caret")
input.setSelectedRange(NSRange(location: 0, length: 2))
check(!coordinator.textView(input, doCommandBy: #selector(NSResponder.moveUp(_:))), "Up with selected text retains native selection behavior")

coordinator.apply(RichTextCodec.decode(nil, plainText: "Line\u{2028}", kind: .task), to: input, kind: .task, isCompleted: false)
_ = input.height(fittingWidth: 180)
check(input.caretRectLocal(at: 5).minY > input.caretRectLocal(at: 0).minY, "A trailing soft break positions the caret on the empty line")
check(!input.isOnLastLine(2) && input.isOnLastLine(5) && !input.isOnFirstLine(5), "Arrows reach a trailing empty line before leaving the block")

// Use an unshown window: verify AppKit focus and clip coordinates without
// taking over the coordinating task's visible application.
_ = NSApplication.shared
let fixtureWindow = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 320, height: 200), styleMask: .borderless, backing: .buffered, defer: false)
let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
let scrollDocument = NSView(frame: CGRect(x: 0, y: 0, width: 320, height: 800))
fixtureWindow.contentView = scroll
scroll.documentView = scrollDocument
scrollDocument.addSubview(input)
input.frame = CGRect(x: 40, y: 300, width: 260, height: 100)
let originalViewport = input.editorViewport
scroll.contentView.scroll(to: CGPoint(x: 0, y: 200))
check(input.editorViewport != originalViewport && input.editorViewport.height == scroll.contentView.bounds.height, "Native viewport follows scrolling in text-view coordinates")
coordinator.parent = BlockTextView(blockID: UUID(), kind: .task, isCompleted: false, attributedText: plain, isFocused: true, focusToken: 2, callbacks: BlockEditorCallbacks())
coordinator.apply(plain, to: input, kind: .task, isCompleted: false)
coordinator.syncFocus(view: input, shouldFocus: true, caret: 0, token: 1)
coordinator.syncFocus(view: input, shouldFocus: true, caret: 4, token: 2)
await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
    DispatchQueue.main.async { continuation.resume() }
}
check(input.selectedRange().location == 4, "A newer programmatic focus request supersedes an older deferred request")
input.insertText("X", replacementRange: input.selectedRange())
coordinator.syncFocus(view: input, shouldFocus: true, caret: 4, token: 2)
await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
    DispatchQueue.main.async { continuation.resume() }
}
check(input.selectedRange().location == 5, "Typing in the middle of a focused block does not reapply its pending caret")

// The title's visible cap-height center must agree with its row center. A
// paragraph line-height multiplier previously shifted that baseline downward.
input.textContainerInset = NSSize(width: 0, height: Theme.Editor.textVerticalInset)
for kind: BlockKind in [.task, .paragraph, .heading1, .heading2, .heading3, .code] {
    coordinator.apply(RichTextCodec.decode(nil, plainText: "Task", kind: kind), to: input, kind: kind, isCompleted: false)
    let singleHeight = input.height(fittingWidth: 180)
    let font = Theme.Editor.nsFont(for: kind)
    let baseline = input.layoutManager!.location(forGlyphAt: 0).y + input.textContainerOrigin.y
    let opticalCenter = baseline - font.capHeight / 2
    check(abs(opticalCenter - singleHeight / 2) < 1.5, "\(kind) text is optically centered in its measured editor height")
    coordinator.apply(RichTextCodec.decode(nil, plainText: "", kind: kind), to: input, kind: kind, isCompleted: false)
    check(input.height(fittingWidth: 180) == singleHeight, "\(kind) empty and populated single-line editors have equal height")
}
coordinator.apply(RichTextCodec.decode(nil, plainText: "Line\u{2028}", kind: .task), to: input, kind: .task, isCompleted: false)
let trailingLineHeight = input.height(fittingWidth: 180)
check(input.caretRectLocal(at: 5).maxY <= trailingLineHeight, "Balanced insets still contain the caret after a trailing soft break")

// Completion changes presentation, never manual order or parentage.
let section = Block(kind: .heading1, text: "Section", sortIndex: 0)
let doneParent = Block(kind: .task, text: "Done parent", sortIndex: 1)
let attachedNote = Block(kind: .paragraph, text: "Attached note", parentID: doneParent.id, sortIndex: 0)
let pendingParent = Block(kind: .task, text: "Pending parent", sortIndex: 2)
let doneChild = Block(kind: .task, text: "Done child", parentID: pendingParent.id, sortIndex: 0)
let pendingChild = Block(kind: .task, text: "Pending child", parentID: pendingParent.id, sortIndex: 1)
let secondDone = Block(kind: .task, text: "Second done", sortIndex: 3)
doneParent.isCompleted = true
doneChild.isCompleted = true
secondDone.isCompleted = true
let completionBlocks = [section, doneParent, attachedNote, pendingParent, doneChild, pendingChild, secondDone]
let originalCompletionRows = BlockTree.flatten(completionBlocks)
let projected = BlockTree.prioritizingPendingTasks(in: originalCompletionRows)
check(projected.map(\.id) == [section.id, pendingParent.id, pendingChild.id, doneChild.id, doneParent.id, attachedNote.id, secondDone.id], "Pending siblings precede completed branches at every outline depth")
check(projected.first(where: { $0.id == attachedNote.id })?.depth == 1 && attachedNote.parentID == doneParent.id, "A completed task carries its attached note and nesting")
check(BlockTree.flatten(completionBlocks).map(\.id) == originalCompletionRows.map(\.id) && doneParent.sortIndex == 1, "Completion projection leaves stored manual order unchanged")
check(BlockTree.prioritizingPendingTasks(in: projected).map(\.id) == projected.map(\.id), "Pending-first projection is stable and idempotent")
doneParent.isCompleted = false
check(BlockTree.prioritizingPendingTasks(in: BlockTree.flatten(completionBlocks)).prefix(3).map(\.id) == [section.id, doneParent.id, attachedNote.id], "Reopening restores the original manual position with the whole subtree")
pendingParent.isCollapsed = true
let collapsedProjection = BlockTree.prioritizingPendingTasks(in: BlockTree.flatten(completionBlocks))
check(!collapsedProjection.contains(where: { $0.id == doneChild.id || $0.id == pendingChild.id }), "Completion ordering respects collapsed subtrees")
check(BlockTree.prioritizingPendingTasks(in: []).isEmpty, "Empty outline has no completion projection")
check(Set(projected.map(\.id)).count == completionBlocks.count, "Completion ordering never loses or duplicates a block")

print("✅ \(checks) editor/store checks passed")
