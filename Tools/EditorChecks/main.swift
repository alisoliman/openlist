import AppKit
import CoreText
import SwiftData
import SwiftUI

// Register the bundled display serif as the app does at launch, before
// anything resolves the editor's heading font.
CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: "openlist/Resources/Fonts/InstrumentSerif-Regular.ttf") as CFURL, .process, nil)

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
    checks += 1
}

let schema = Schema([TaskList.self, Block.self, SidebarSection.self, TaskLabel.self, Attachment.self, ActivityEvent.self, WorkSession.self, CompletionRecord.self, SchedulePlacement.self])
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
check(store.blocks(inList: removedListID).isEmpty && store.editorNotice?.contains("unavailable") == true, "Undo waits for a retained list to be restored before applying its edits")

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

// A renderer strikes a task during its completion dwell, before the store
// marks it done. The strike is presentation only.
let unstruckParent = coordinator.parent
let closingAccent = NSColor.systemPurple
let closing = RichTextCodec.decode(nil, plainText: "Closing task", kind: .task)
coordinator.parent = BlockTextView(blockID: UUID(), kind: .task, isCompleted: false, struck: true, strikeColor: closingAccent,
    attributedText: closing, isFocused: false, focusToken: 0, callbacks: coordinator.parent.callbacks)
coordinator.apply(closing, to: native, kind: .task, isCompleted: false, struck: true, strikeColor: closingAccent)
let struckAttributes = native.textStorage!.attributes(at: 0, effectiveRange: nil)
check(struckAttributes[.strikethroughStyle] as? Int == NSUnderlineStyle.single.rawValue
    && struckAttributes[.strikethroughColor] as? NSColor === closingAccent
    && struckAttributes[.foregroundColor] as? NSColor === Theme.Editor.completedInk, "A closing task is struck in the accent before it is stored as done")
check(coordinator.signature == BlockTextView.ContentSignature(attributedText: closing, kind: .task, isCompleted: false, struck: true, strikeColor: closingAccent),
    "A struck presentation keeps the model's content in its signature")
check(coordinator.signature != BlockTextView.ContentSignature(attributedText: closing, kind: .task, isCompleted: false),
    "Starting or cancelling the dwell strike restyles the native editor")
native.textStorage?.append(NSAttributedString(string: "!", attributes: native.typingAttributes))
native.setSelectedRange(NSRange(location: native.string.utf16.count, length: 0))
coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: native))
let struckEcho = RichTextCodec.decode(editedArchive, plainText: native.string, kind: .task)
check(native.string == "Closing task!" && struckEcho.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) == nil,
    "The dwell strike never reaches stored rich text")
check(coordinator.signature == BlockTextView.ContentSignature(attributedText: struckEcho, kind: .task, isCompleted: false, struck: true, strikeColor: closingAccent),
    "Typing during the dwell matches the model's echo without resetting native editing")
coordinator.parent = unstruckParent
coordinator.apply(struckEcho, to: native, kind: .task, isCompleted: false)
check(native.textStorage?.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) == nil, "Cancelling the dwell removes the strike")
let completedTitle = RichTextCodec.decode(nil, plainText: "Done", kind: .quote, isCompleted: true)
check(RichTextCodec.restylingCompletion(of: completedTitle, kind: .quote, struck: true).isEqual(to: completedTitle)
    && RichTextCodec.restylingCompletion(of: completedTitle, kind: .quote, struck: false).isEqual(to: RichTextCodec.decode(nil, plainText: "Done", kind: .quote)),
    "Completion restyling matches decoding in either state")
let userStruck = NSMutableAttributedString(attributedString: RichTextCodec.decode(nil, plainText: "Keep this", kind: .task))
RichTextCodec.toggleStrikethrough(in: userStruck, range: NSRange(location: 0, length: 4))
check(RichTextCodec.restylingCompletion(of: RichTextCodec.restylingCompletion(of: userStruck, kind: .task, struck: true), kind: .task, struck: false).isEqual(to: userStruck),
    "Unstriking a task keeps the user's own strikethrough")

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

// Escape must hand the keyboard back to the window, otherwise the next
// single-key shortcut is typed into the row.
var windowHeldKeyboardOnEscape = false
coordinator.parent.callbacks.onEscape = { windowHeldKeyboardOnEscape = fixtureWindow.firstResponder === fixtureWindow }
fixtureWindow.makeFirstResponder(input)
check(fixtureWindow.firstResponder === input, "The fixture editor holds the keyboard before Escape")
check(coordinator.textView(input, doCommandBy: #selector(NSResponder.cancelOperation(_:))), "Escape is consumed by the editor")
check(windowHeldKeyboardOnEscape && fixtureWindow.firstResponder !== input, "Escape resigns the text view before the outline hears about it")
input.isSlashMenuOpen = true
fixtureWindow.makeFirstResponder(input)
windowHeldKeyboardOnEscape = false
check(coordinator.textView(input, doCommandBy: #selector(NSResponder.cancelOperation(_:))) && fixtureWindow.firstResponder === input && !windowHeldKeyboardOnEscape,
    "Escape with the slash menu open only closes the menu")
input.isSlashMenuOpen = false
coordinator.parent.callbacks.onEscape = {}

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

// One editor typography, the Next list document's. A task title in the
// document's line box measures and sits like a Next row's title, which
// SwiftUI sets the way `NXStrikeText` does.
check(Theme.Editor.nsFont(for: .heading1) == NSFont.systemFont(ofSize: 20, weight: .bold)
    && Theme.Editor.nsFont(for: .heading2) == NSFont.systemFont(ofSize: 15.5, weight: .semibold)
    && Theme.Editor.nsFont(for: .heading3) == NSFont.systemFont(ofSize: 13.8, weight: .semibold)
    && Theme.Editor.nsFont(for: .task) == NSFont.systemFont(ofSize: 13.8)
    && Theme.Editor.nsFont(for: .bullet) == NSFont.systemFont(ofSize: 13.8)
    && Theme.Editor.nsFont(for: .paragraph) == NSFont.systemFont(ofSize: 13.5)
    && Theme.Editor.nsFont(for: .quote) == NSFont.systemFont(ofSize: 13.5)
    && Theme.Editor.nsFont(for: .code) == NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular),
    "Each kind uses the design's document font")
check(Theme.Editor.lineHeight(for: .task) == 13.8 * 1.45 && Theme.Editor.lineHeight(for: .paragraph) == 13.5 * 1.55
    && Theme.Editor.lineHeight(for: .heading1) == 20 * 1.3 && Theme.Editor.lineHeight(for: .heading2) == 15.5 * 1.35,
    "Each kind has the design's line height")
check(RichTextCodec.baseAttributes(for: .heading1)[.kern] as? CGFloat == -0.2 && RichTextCodec.baseAttributes(for: .task)[.kern] == nil,
    "Heading 1 keeps the design's −0.01em letter-spacing")
let spacedHeading = NSMutableAttributedString(attributedString: RichTextCodec.decode(nil, plainText: "Title", kind: .heading1))
RichTextCodec.toggleTrait(.italicFontMask, in: spacedHeading, range: NSRange(location: 0, length: 5), kind: .heading1)
let spacedArchive = RichTextCodec.encode(spacedHeading, kind: .heading1)!
let storedHeading = try! NSAttributedString(data: spacedArchive, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
check(storedHeading.attribute(.kern, at: 0, effectiveRange: nil) == nil, "Letter-spacing is presentation and never stored")
func nextTitleMetrics(_ text: String) -> (height: CGFloat, baseline: CGFloat) {
    let size = Theme.Editor.bodyPointSize
    let font = NSFont.systemFont(ofSize: size)
    let leading = max(0, size * 1.45 - (font.ascender - font.descender + font.leading))
    let host = NSHostingView(rootView: Text(text).font(.system(size: size)).lineSpacing(leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, leading / 2)
        .frame(width: 180, alignment: .leading))
    host.frame = CGRect(origin: .zero, size: host.fittingSize)
    host.layoutSubtreeIfNeeded()
    return (host.frame.height, host.firstBaselineOffsetFromTop)
}
input.textContainerInset = NSSize(width: 0, height: Theme.Editor.lineBoxInset(for: .task))
for (title, next) in [("Task", "Task"), ("Task one\u{2028}Task two", "Task one\nTask two")] {
    coordinator.apply(RichTextCodec.decode(nil, plainText: title, kind: .task), to: input, kind: .task, isCompleted: false)
    input.invalidateIntrinsicContentSize()
    let height = input.height(fittingWidth: 180)
    let baseline = input.layoutManager!.location(forGlyphAt: 0).y + input.textContainerOrigin.y
    let reference = nextTitleMetrics(next)
    check(reference.height > 0 && abs(height - reference.height) <= 0.5,
        "A \(title.contains("\u{2028}") ? "two-line" : "one-line") task in its line box is as tall as a Next row's title (\(height) vs \(reference.height))")
    check(abs(baseline - reference.baseline) <= 0.5,
        "A task in its line box shares a Next row title's first baseline (\(baseline) vs \(reference.baseline))")
}
for kind: BlockKind in [.task, .bullet, .paragraph, .heading1, .heading2, .heading3] {
    input.textContainerInset = NSSize(width: 0, height: Theme.Editor.lineBoxInset(for: kind))
    coordinator.apply(RichTextCodec.decode(nil, plainText: "Line", kind: kind), to: input, kind: kind, isCompleted: false)
    input.invalidateIntrinsicContentSize()
    check(abs(input.height(fittingWidth: 180) - Theme.Editor.lineHeight(for: kind)) < 0.05,
        "\(kind) fills the design's line box of \(Theme.Editor.lineHeight(for: kind))pt")
    coordinator.apply(RichTextCodec.decode(nil, plainText: "Line\u{2028}Line", kind: kind), to: input, kind: kind, isCompleted: false)
    input.invalidateIntrinsicContentSize()
    check(abs(input.height(fittingWidth: 180) - 2 * Theme.Editor.lineHeight(for: kind)) < 0.6,
        "\(kind) wraps onto the design's line pitch")
}
input.textContainerInset = NSSize(width: 0, height: Theme.Editor.textVerticalInset)
coordinator.apply(RichTextCodec.decode(nil, plainText: "Task", kind: .task), to: input, kind: .task, isCompleted: false)
input.invalidateIntrinsicContentSize()
check(input.height(fittingWidth: 180) == 20, "The legacy document's default inset still pads a single line to its gutter's 20pt")
let taskAttributes = RichTextCodec.baseAttributes(for: .task)
check(taskAttributes[.foregroundColor] as? NSColor === Theme.Editor.ink
    && RichTextCodec.baseAttributes(for: .task)[.foregroundColor] as? NSColor === taskAttributes[.foregroundColor] as? NSColor
    && RichTextCodec.baseAttributes(for: .quote)[.foregroundColor] as? NSColor === Theme.Editor.secondaryInk
    && RichTextCodec.baseAttributes(for: .paragraph)[.foregroundColor] as? NSColor === Theme.Editor.secondaryInk
    && RichTextCodec.baseAttributes(for: .task, isCompleted: true)[.strikethroughColor] as? NSColor === Theme.Editor.strikeInk
    && Theme.Editor.link === Theme.Editor.accentViolet,
    "Editor colours are shared ink and accent tokens, so content signatures stay equal")
let closingTitle = RichTextCodec.restylingCompletion(of: RichTextCodec.decode(nil, plainText: "Closing", kind: .task), kind: .task,
                                                     struck: true, strikeColor: Theme.Editor.accentBlue, dimsCompleted: false)
check(closingTitle.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor === Theme.Editor.ink
    && closingTitle.attribute(.strikethroughColor, at: 0, effectiveRange: nil) as? NSColor === Theme.Editor.accentBlue
    && closingTitle.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) != nil,
    "A task struck during its dwell keeps its ink under the accent strike")
check(BlockTextView.ContentSignature(attributedText: closingTitle, kind: .task, isCompleted: false, struck: true,
                                     strikeColor: Theme.Editor.accentBlue, dimsStruck: false).overridesCompletion
    && !BlockTextView.ContentSignature(attributedText: closingTitle, kind: .task, isCompleted: false, dimsStruck: false).overridesCompletion,
    "Keeping the ink only matters while the strike shows")
let styledHeading = NSMutableAttributedString(attributedString: RichTextCodec.decode(nil, plainText: "Title", kind: .heading1))
RichTextCodec.toggleTrait(.italicFontMask, in: styledHeading, range: NSRange(location: 0, length: 5), kind: .heading1)
let headingEcho = RichTextCodec.decode(RichTextCodec.encode(styledHeading, kind: .heading1), plainText: "Title", kind: .heading1)
check((headingEcho.attribute(.font, at: 0, effectiveRange: nil) as? NSFont).map { NSFontManager.shared.traits(of: $0).contains(.italicFontMask) } == true,
    "Italic survives in a heading")
func fontTraits(_ content: NSAttributedString, at index: Int) -> NSFontTraitMask {
    NSFontManager.shared.traits(of: content.attribute(.font, at: index, effectiveRange: nil) as! NSFont)
}
let boldParagraph = NSMutableAttributedString(attributedString: RichTextCodec.decode(nil, plainText: "Title", kind: .paragraph))
RichTextCodec.toggleTrait(.boldFontMask, in: boldParagraph, range: NSRange(location: 0, length: 5), kind: .paragraph)
check(fontTraits(RichTextCodec.decode(RichTextCodec.encode(boldParagraph, kind: .paragraph), plainText: "Title", kind: .paragraph), at: 0).contains(.boldFontMask),
    "Bold the user applies in text survives a round trip")
// Heading 1 used to be system bold at 21pt, so runs styled in an older
// heading were archived bold with it. That weight was the heading's.
let legacyBold = NSFont.systemFont(ofSize: 21, weight: .bold)
let legacyHeading = NSMutableAttributedString(string: "Old title", attributes: [.font: legacyBold])
legacyHeading.addAttribute(.font, value: NSFontManager.shared.convert(legacyBold, toHaveTrait: .italicFontMask), range: NSRange(location: 4, length: 5))
let legacyArchive = legacyHeading.rtf(from: NSRange(location: 0, length: legacyHeading.length),
    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
let legacyDecoded = RichTextCodec.decode(legacyArchive, plainText: "Old title", kind: .heading1)
check(legacyDecoded.attribute(.font, at: 0, effectiveRange: nil) as? NSFont == Theme.Editor.nsFont(for: .heading1),
    "An older heading's own bold reads as the heading")
check(fontTraits(legacyDecoded, at: 4).contains(.italicFontMask), "Italic in an older heading keeps its italic")
check(RichTextCodec.decode(RichTextCodec.encode(legacyDecoded, kind: .heading1), plainText: "Old title", kind: .heading1).isEqual(to: legacyDecoded),
    "The next save stores an older heading's runs corrected")

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

// The outline engine behind every document renderer, driven without a view.
let outlineList = store.createList(title: "Outline engine")
let outlineDocument = DocumentContext(listID: outlineList.id)
let pageTask = store.appendBlock(kind: .task, text: "Parent", to: outlineDocument)
let firstSubtask = store.insertChild(kind: .task, text: "First subtask", of: pageTask, at: .last)
let secondSubtask = store.insertChild(kind: .task, text: "Second subtask", of: pageTask, at: .last)
store.save()
let outlineEnv = AppEnvironment(store: store)
let page = DocumentContext(listID: outlineList.id, rootBlockID: pageTask.id)
let pageEditor = OutlineEditor(env: outlineEnv, document: page)
let listEditor = OutlineEditor(env: outlineEnv, document: outlineDocument)
func outlineRow(_ block: Block, in editor: OutlineEditor) -> BlockRow {
    editor.visibleRows(in: store.blocks(inList: outlineList.id)).first { $0.id == block.id }!
}
func pageRows() -> [BlockRow] { pageEditor.visibleRows(in: store.blocks(inList: outlineList.id)) }
check(pageRows().map(\.id) == [firstSubtask.id, secondSubtask.id] && pageRows().allSatisfy { $0.depth == 0 },
    "A task page projects only its own subtree, from depth 0")

// The page's root is a floor: its children never outdent off the page.
check(pageEditor.actions(for: outlineRow(secondSubtask, in: pageEditor)).editorCallbacks.onTab(true, 0) && secondSubtask.parentID == pageTask.id,
    "Shift-Tab on a task page's direct child is consumed and keeps it on the page")
check(pageEditor.actions(for: outlineRow(secondSubtask, in: pageEditor)).onTab(false, 0) && secondSubtask.parentID == firstSubtask.id,
    "Tab still nests subtasks on a task page")
check(pageEditor.actions(for: outlineRow(secondSubtask, in: pageEditor)).onTab(true, 0) && secondSubtask.parentID == pageTask.id,
    "Shift-Tab still outdents nested subtasks up to the page")
var focusedIDs: [UUID] = []
var escapedIDs: [UUID] = []
pageEditor.hooks.didFocus = { focusedIDs.append($0) }
pageEditor.hooks.didEscape = { escapedIDs.append($0) }
pageEditor.actions(for: outlineRow(firstSubtask, in: pageEditor)).onFocus()
check(pageEditor.focus.blockID == firstSubtask.id && focusedIDs.last == firstSubtask.id && outlineEnv.activeDocument == page,
    "Focusing a row adopts the caret, claims menu commands and tells the host")
outlineEnv.pendingCommand = .outdent
pageEditor.receiveCommand()
check(firstSubtask.parentID == pageTask.id && outlineEnv.pendingCommand == nil, "The Outdent command keeps a task page's children on the page")

// Escape lets go of the caret and tells the host which block it left.
check(outlineEnv.navigator.selection == [firstSubtask.id], "Editing a row makes it the row selection")
pageEditor.actions(for: outlineRow(firstSubtask, in: pageEditor)).onEscape()
check(escapedIDs == [firstSubtask.id] && pageEditor.focus.blockID == nil && outlineEnv.navigator.selection.isEmpty,
    "Escape releases the caret and selection, then reports the block to the host")

// With the window holding the keyboard, Return or an arrow takes it back.
check(pageEditor.escapedBlockID == firstSubtask.id, "The outline remembers the block Escape left")
fixtureWindow.makeFirstResponder(nil)
check(!pageEditor.resumeEditing(onKey: 125, modifiers: .command, in: fixtureWindow)
    && !pageEditor.resumeEditing(onKey: 0, modifiers: [], in: fixtureWindow), "Only a plain Return or arrow resumes editing")
fixtureWindow.makeFirstResponder(input)
check(!pageEditor.resumeEditing(onKey: 36, modifiers: [], in: fixtureWindow), "A key another view holds is left alone")
fixtureWindow.makeFirstResponder(nil)
outlineEnv.activeDocument = outlineDocument
check(!pageEditor.resumeEditing(onKey: 36, modifiers: [], in: fixtureWindow), "Another document taking commands keeps its keys")
outlineEnv.activeDocument = page
let tokenBeforeResume = pageEditor.focus.token
check(pageEditor.resumeEditing(onKey: 125, modifiers: [.numericPad, .function], in: fixtureWindow)
    && pageEditor.focus.blockID == firstSubtask.id && pageEditor.focus.caret == nil && pageEditor.focus.token != tokenBeforeResume,
    "↓ with nothing holding the keyboard puts the caret back where the text view had it")
check(pageEditor.escapedBlockID == nil && !pageEditor.resumeEditing(), "Resuming lets go of the escaped block")
pageEditor.actions(for: outlineRow(firstSubtask, in: pageEditor)).onEscape()
pageEditor.actions(for: outlineRow(secondSubtask, in: pageEditor)).onFocus()
check(pageEditor.escapedBlockID == nil, "Clicking into any row ends the wait to resume")

// Hooks replace host policy; the defaults are the legacy editor's.
var toggledIDs: [UUID] = []
pageEditor.hooks.toggleCompletion = { toggledIDs.append($0) }
pageEditor.actions(for: outlineRow(firstSubtask, in: pageEditor)).onToggleCompletion()
check(toggledIDs == [firstSubtask.id] && !firstSubtask.isCompleted, "A completion hook replaces the direct store write")
listEditor.actions(for: outlineRow(secondSubtask, in: listEditor)).onToggleCompletion()
check(secondSubtask.isCompleted, "Without a hook, completion writes straight to the store")
var openedIDs: [UUID] = []
pageEditor.hooks.openDetails = { openedIDs.append($0) }
pageEditor.actions(for: outlineRow(firstSubtask, in: pageEditor)).onOpenDetails()
check(openedIDs == [firstSubtask.id] && outlineEnv.navigator.openTaskID == nil, "A details hook replaces the navigator's detail panel")
var claimed: [(EditorCommand, [UUID])] = []
pageEditor.hooks.taskCommand = { command, ids in
    claimed.append((command, ids))
    return command == .toggleStar
}
pageEditor.actions(for: outlineRow(firstSubtask, in: pageEditor)).onFocus()
outlineEnv.pendingCommand = .toggleStar
pageEditor.receiveCommand()
check(claimed.last?.0 == .toggleStar && claimed.last?.1 == [firstSubtask.id] && !firstSubtask.isStarred,
    "A host claims task commands for the command targets before the store")
outlineEnv.pendingCommand = .setDueToday
pageEditor.receiveCommand()
check(claimed.last?.0 == .setDueToday && firstSubtask.dueDate != nil, "Commands a host declines fall back to the store")
outlineEnv.activeDocument = outlineDocument
outlineEnv.pendingCommand = .clearDueDate
pageEditor.receiveCommand()
check(outlineEnv.pendingCommand == .clearDueDate && firstSubtask.dueDate != nil, "Only the active document runs menu commands")
outlineEnv.pendingCommand = nil

// Completion visibility is the host's to decide.
pageEditor.showsCompleted = false
check(!pageRows().contains { $0.id == secondSubtask.id }, "Hidden completed tasks leave the visible rows")
pageEditor.completedTasksKeptVisible = [secondSubtask.id]
check(pageRows().map(\.id) == [firstSubtask.id, secondSubtask.id], "The host can keep a completed task on screen")
pageEditor.documentDidChange()
check(pageEditor.completedTasksKeptVisible.isEmpty && pageEditor.focus.blockID == nil,
    "A document changing in place forgets the tasks its host kept visible")
pageEditor.showsCompleted = true
secondSubtask.isCompleted = false
let doneFirst = store.insertChild(kind: .task, text: "Done first", of: pageTask, at: .first)
doneFirst.isCompleted = true
check(pageRows().last?.id == doneFirst.id, "Completed tasks settle below pending siblings")

// The list's floor is the document root: nested rows still outdent there.
listEditor.actions(for: outlineRow(firstSubtask, in: listEditor)).onFocus()
outlineEnv.pendingCommand = .outdent
listEditor.receiveCommand()
check(firstSubtask.parentID == nil, "A list document still outdents nested rows to its top level")

// Slash selection and arrows through void rows.
let noteBlock = store.appendBlock(kind: .paragraph, text: "/div", to: outlineDocument)
let afterNote = store.appendBlock(kind: .paragraph, text: "After", to: outlineDocument)
store.save()
listEditor.actions(for: outlineRow(noteBlock, in: listEditor)).onSlashQuery("div", NSRange(location: 0, length: 4), .zero, .zero)
check(listEditor.isSlashMenuOpen(on: noteBlock.id), "Typing a slash query opens the menu on its row")
listEditor.handleSlashCommand(.confirm)
let dividerRows = listEditor.visibleRows(in: store.blocks(inList: outlineList.id))
let dividerIndex = dividerRows.firstIndex { $0.id == noteBlock.id }!
check(noteBlock.kind == .divider && listEditor.slash == nil && dividerRows[dividerIndex + 1].block.kind == .paragraph
    && listEditor.focus.blockID == dividerRows[dividerIndex + 1].id, "A divider from the slash menu is followed by a focused paragraph")
let beforeDivider = dividerRows[dividerIndex - 1]
// Drawn, then deleted behind the renderer's back: handlers must not reuse it.
_ = listEditor.rowsToDraw(in: store.blocks(inList: outlineList.id))
store.deleteBlock(dividerRows[dividerIndex + 1].block)
store.save()
check(listEditor.actions(for: beforeDivider).onArrowOut(.down, 0) && listEditor.focus.blockID == afterNote.id,
    "Arrows step over dividers to the next text row, past a drawn row that has gone")
let rowsBeforeReturn = listEditor.rowsToDraw(in: store.blocks(inList: outlineList.id))
check(rowsBeforeReturn.last?.id == afterNote.id, "The drawn rows end with the last text row")
check(listEditor.actions(for: outlineRow(afterNote, in: listEditor)).onReturn(5, store.attributedContent(of: afterNote))
    && listEditor.focus.blockID != afterNote.id && store.block(id: listEditor.focus.blockID)?.kind == .paragraph,
    "Return at the end of a row focuses a new row after it")
let returned = listEditor.focus.blockID
check(listEditor.actions(for: outlineRow(afterNote, in: listEditor)).onArrowOut(.down, 0) && listEditor.focus.blockID == returned,
    "An edit made here retires the drawn rows, so the next key sees the new row")

// Between renders, handlers read the drawn rows rather than the store.
let drawnBeforeAppend = listEditor.rowsToDraw(in: store.blocks(inList: outlineList.id))
let undrawn = store.appendBlock(kind: .paragraph, text: "Not drawn yet", to: outlineDocument)
store.save()
check(!listEditor.actions(for: drawnBeforeAppend.last!).onArrowOut(.down, 0), "Handlers between renders reuse the drawn rows")
_ = listEditor.rowsToDraw(in: store.blocks(inList: outlineList.id))
check(listEditor.actions(for: drawnBeforeAppend.last!).onArrowOut(.down, 0) && listEditor.focus.blockID == undrawn.id,
    "The next render's rows reach the handlers")
let shownRows = listEditor.rowsToDraw(in: store.blocks(inList: outlineList.id))
let parentRow = shownRows.first { $0.id == pageTask.id }!
check(shownRows[shownRows.firstIndex { $0.id == pageTask.id }! + 1].id == doneFirst.id, "A completed subtask is drawn under its parent")
listEditor.showsCompleted = false
check(listEditor.actions(for: parentRow).onArrowOut(.down, 0) && listEditor.focus.blockID != doneFirst.id && listEditor.focus.blockID != nil,
    "Hiding completed tasks retires the drawn rows")
listEditor.showsCompleted = true

// The Next list document's rules, from the design.
let nextList = store.createList(title: "Next document")
let nextDocument = DocumentContext(listID: nextList.id)
let nextEditor = OutlineEditor(env: outlineEnv, document: nextDocument, policy: .nextDocument)
var recorded: [(edit: OutlineEdit, name: String)] = []
nextEditor.hooks.nameEdit = { edit in
    switch edit {
    case .added: "Added"
    case .edited: "Edited"
    case .removedEmptyLine: "Removed an empty line"
    default: nil
    }
}
nextEditor.hooks.didRecordEdit = { recorded.append(($0, $1)) }
var addedLines: [UUID] = []
nextEditor.hooks.didAddLine = { addedLines.append($0) }
func nextRows() -> [BlockRow] { nextEditor.visibleRows(in: store.blocks(inList: nextList.id)) }
func nextActions(_ block: Block) -> BlockRowActions { nextEditor.actions(for: nextRows().first { $0.id == block.id }!) }
func nextDepth(_ block: Block) -> Int? { nextRows().first { $0.id == block.id }?.depth }
func nextIndex(_ block: Block) -> Int? { nextRows().firstIndex { $0.id == block.id } }
func content(_ block: Block) -> NSAttributedString { store.attributedContent(of: block) }
let before = store.appendBlock(kind: .heading1, text: "Before we go", to: nextDocument)
let renew = store.appendBlock(kind: .task, text: "Renew passports", to: nextDocument)
let book = store.appendBlock(kind: .task, text: "Book the ryokan", to: nextDocument)
let email = store.appendBlock(kind: .task, text: "Email Kasuga", to: nextDocument)
let pay = store.appendBlock(kind: .task, text: "Pay the deposit", to: nextDocument)
let confirm = store.appendBlock(kind: .task, text: "Confirm", to: nextDocument)
let prose = store.appendBlock(kind: .paragraph, text: "Notes", to: nextDocument)
let item = store.appendBlock(kind: .bullet, text: "JR pass", to: nextDocument)
store.save()

// Only tasks and list items nest, under a task or list item, two levels deep.
check(nextActions(renew).onTab(false, 0) && renew.parentID == nil, "A task right under a heading stays at the top")
check(nextActions(email).onTab(false, 0) && email.parentID == book.id && nextDepth(email) == 1, "A task indents under the task above")
check(nextActions(email).onTab(false, 0) && email.parentID == book.id, "A line goes at most one level deeper than the line above")
check(nextActions(pay).onTab(false, 0) && pay.parentID == book.id && nextIndex(pay) == nextIndex(email)! + 1,
    "The next task indents beside it, under the same task")
check(nextActions(pay).onTab(false, 0) && pay.parentID == email.id && nextDepth(pay) == 2, "A task reaches the second level")
_ = nextActions(confirm).onTab(false, 0)
_ = nextActions(confirm).onTab(false, 0)
check(confirm.parentID == email.id && nextDepth(confirm) == 2, "A task steps in one level at a time")
check(nextActions(confirm).onTab(false, 0) && confirm.parentID == email.id && nextDepth(confirm) == 2, "Two levels is as deep as a line goes")
check(nextActions(before).onTab(false, 0) && before.parentID == nil, "Headings never indent")
check(nextActions(prose).onTab(false, 0) && prose.parentID == nil, "Text never indents")
check(nextActions(item).onTab(false, 0) && item.parentID == nil, "A list item under text stays at the top")
check(nextActions(confirm).onTab(true, 0) && confirm.parentID == book.id && nextDepth(confirm) == 1, "Shift-Tab steps a line out")
_ = nextActions(confirm).onTab(false, 0)
// Tab keeps the caret in its line, so the indents join that line's edit.
nextEditor.commitLine()
check(!recorded.isEmpty && recorded.allSatisfy { $0.name == "Edited" }, "Indenting the line being written is part of its edit")
recorded.removeAll()

// Return, as the design's onEditKey.
check(nextActions(before).onReturn(content(before).length, content(before)) && addedLines.count == 1, "Return at the end of a heading adds a line")
let afterHeading = store.block(id: addedLines[0])!
check(afterHeading.kind == .task && afterHeading.parentID == nil && nextIndex(afterHeading) == 1 && nextEditor.focus.blockID == afterHeading.id,
    "A heading is followed by a task, which takes the caret")
check(nextActions(afterHeading).onReturn(0, NSAttributedString()) && afterHeading.kind == .task && addedLines.count == 1,
    "Return on an empty top-level task does nothing")
nextEditor.commitLine()
check(store.block(id: afterHeading.id) == nil && recorded.isEmpty, "A new line left empty goes without an undo step")
check(nextActions(book).onReturn(content(book).length, content(book)), "Return at the end of a task with subtasks adds a line")
let firstChild = store.block(id: addedLines[1])!
check(firstChild.parentID == book.id && nextIndex(firstChild) == nextIndex(book)! + 1, "It becomes the task's first child")
check(nextActions(firstChild).onReturn(0, NSAttributedString()) && firstChild.parentID == nil && email.parentID == firstChild.id,
    "Return on an empty nested line steps it out, over the lines after it")
nextEditor.commitLine()
check(store.block(id: firstChild.id) == nil && email.parentID == book.id, "Taking the empty line out leaves those lines where they showed")
store.setCollapsed(true, for: book)
check(nextActions(book).onReturn(content(book).length, content(book)), "Return at the end of a collapsed task adds a line")
let afterCollapsed = store.block(id: addedLines[2])!
check(afterCollapsed.parentID == nil && nextIndex(afterCollapsed) == nextIndex(book)! + 1, "A collapsed task's new line follows it at its level")
nextEditor.commitLine()
store.setCollapsed(false, for: book)
check(nextActions(prose).onReturn(content(prose).length, content(prose)) && store.block(id: addedLines[3])?.kind == .paragraph,
    "Text is followed by text")
nextEditor.commitLine()
let emptyHeading = store.appendBlock(kind: .heading2, text: "", to: nextDocument)
store.save()
check(nextActions(emptyHeading).onReturn(0, NSAttributedString()) && emptyHeading.kind == .task, "Return on an empty heading makes it a task")
store.setPlainText(emptyHeading, "Walk the Philosopher's Path")
let split = NSAttributedString(string: "Walk the Philosopher's Path")
check(nextActions(emptyHeading).onReturn(9, split) && emptyHeading.text == "Walk the " && store.block(id: addedLines[4])?.text == "Philosopher's Path",
    "Return mid-line moves the rest of it to a new line")
nextEditor.commitLine()

// Backspace at the start of a line.
let headed = store.appendBlock(kind: .heading2, text: "On the ground", to: nextDocument)
let nestedItem = store.insertChild(kind: .bullet, text: "Nara", of: pay, at: .last)
store.save()
check(nextActions(headed).onBackspaceAtStart(content(headed)) && headed.kind == .paragraph, "Backspace turns a heading into text")
check(nextActions(nestedItem).onBackspaceAtStart(content(nestedItem)) && nestedItem.kind == .paragraph && nestedItem.parentID == nil,
    "A nested list item turns into text at the top level")
check(nextActions(confirm).onBackspaceAtStart(content(confirm)) && confirm.parentID == nil, "Backspace steps a nested task out")
let renewText = renew.text
check(nextActions(book).onBackspaceAtStart(content(book)) && store.block(id: book.id) != nil && renew.text == renewText,
    "Lines never merge")
nextEditor.commitLine()
recorded.removeAll()
let blank = store.appendBlock(kind: .task, text: "", to: nextDocument)
store.save()
nextActions(blank).onFocus()
let aboveBlank = nextRows()[nextIndex(blank)! - 1].id
check(nextActions(blank).onBackspaceAtStart(NSAttributedString()) && store.block(id: blank.id) == nil
    && nextEditor.focus.blockID == aboveBlank && nextEditor.focus.caret == -1,
    "Backspace in an empty line removes it and edits the end of the line above")
check(recorded.map(\.name) == ["Removed an empty line"], "Removing an empty line is its own undo step")

// Markdown shorthands.
nextActions(item).onMarkdownPrefix(.quote)
check(item.kind == .paragraph, "“> ” makes text, as in the design")
let deepItem = store.insertChild(kind: .bullet, text: "Deep", of: pay, at: .last)
store.save()
nextActions(deepItem).onMarkdownPrefix(.heading1)
check(deepItem.kind == .heading1 && deepItem.parentID == nil, "A heading made from a nested line comes out to the top")
nextActions(renew).onMarkdownPrefix(.bullet)
check(renew.kind == .bullet, "“- ” makes a list item")
nextActions(renew).onMarkdownPrefix(.task)
nextEditor.commitLine()

// The `/` menu: the design's five, then the editor's other kinds.
check(Array(nextEditor.slashKinds(matching: "").prefix(5)) == [.task, .heading1, .heading2, .bullet, .paragraph]
    && OutlineSlashOption.all.filter(\.isExtra).map(\.kind) == [.heading3, .numbered, .quote, .code, .divider, .image],
    "Turn into lists the design's kinds first and the rest under More")
check(nextEditor.slashKinds(matching: "sub") == [.heading2] && nextEditor.slashKinds(matching: "text").first == .paragraph
    && nextEditor.slashKinds(matching: "h1") == [.heading1], "Turn into filters by label and the editor's search words")

// Done top-level tasks leave the document; done subtasks stay in place.
email.isCompleted = true
let rowsWithDoneSubtask = nextRows()
check(rowsWithDoneSubtask.contains { $0.id == email.id } && rowsWithDoneSubtask.firstIndex { $0.id == email.id }! < rowsWithDoneSubtask.firstIndex { $0.id == confirm.id }!,
    "A done subtask stays where it was ticked")
book.isCompleted = true
check(!nextRows().contains { $0.id == book.id || $0.id == email.id || $0.id == pay.id }, "A done top-level task leaves with its subtree")
nextEditor.completedTasksKeptVisible = [book.id]
check(nextRows().contains { $0.id == book.id }, "The host can keep a done task in view")
nextEditor.completedTasksKeptVisible = []
book.isCompleted = false
email.isCompleted = false

// A heading's section folds with it.
let later = store.appendBlock(kind: .heading1, text: "Later", to: nextDocument)
let laterTask = store.appendBlock(kind: .task, text: "Pack", to: nextDocument)
store.save()
let everything = BlockTree.flatten(store.blocks(inList: nextList.id), respectCollapse: false)
let sections = BlockTree.sections(in: everything)
check(sections[before.id]?.last?.id != later.id && sections[before.id]?.contains { $0.id == pay.id } == true
    && sections[later.id]?.map(\.id) == [laterTask.id], "A heading's section runs to the next heading of its level")
store.setCollapsed(true, for: before)
let folded = nextRows()
check(folded.first?.id == before.id && folded.dropFirst().first?.block.kind == .heading1
    && !folded.contains { $0.id == renew.id || $0.id == book.id } && folded.contains { $0.id == laterTask.id },
    "A collapsed heading hides its section, up to the next heading of its level")
store.setCollapsed(false, for: before)
check(nextRows().count > folded.count, "Expanding a heading shows its section again")

// Only the tasks, each under the tasks above it.
nextEditor.tasksOnly = true
check(nextRows().allSatisfy(\.block.isTask) && nextRows().first { $0.id == pay.id }?.depth == 2, "The Tasks presentation shows the tasks as an outline")
nextEditor.tasksOnly = false

// A line's edit is one undo step, named for what it was.
recorded.removeAll()
nextActions(prose).onFocus()
nextActions(prose).onChange(NSAttributedString(string: "Notes for the trip"))
nextActions(prose).onEndEditing(NSTextStorage())
check(recorded.count == 1 && recorded[0].edit == .edited(prose.id) && recorded[0].name == "Edited", "Leaving a line commits its edit")
nextEditor.appendTask()
let asked = store.block(id: nextEditor.focus.blockID!)!
nextActions(asked).onChange(NSAttributedString(string: "Ask Mika"))
nextEditor.commitLine()
check(recorded.count == 2 && recorded[1].edit == .added(asked.id), "A new line written and left is an added line")
nextActions(asked).onFocus()
nextActions(asked).onChange(NSAttributedString())
nextActions(asked).onEndEditing(NSTextStorage())
check(store.block(id: asked.id) == nil && recorded.last?.edit == .removedEmptyLine(asked.id), "A line left empty is removed")
nextActions(laterTask).onFocus()
nextActions(laterTask).onEndEditing(NSTextStorage())
check(recorded.count == 3 && nextEditor.focus.blockID == nil, "A line left unchanged records nothing and lets the caret go")
nextActions(laterTask).onFocus()
nextActions(laterTask).onMarkdownPrefix(.bullet)
nextActions(laterTask).onEndEditing(NSTextStorage())
check(recorded.count == 3 && nextEditor.focus.blockID == laterTask.id,
    "The text view a kind change replaces letting go keeps the line's edit and caret")
nextActions(laterTask).onFocus()
nextActions(laterTask).onEndEditing(NSTextStorage())
check(recorded.count == 4 && recorded.last?.edit == .edited(laterTask.id) && laterTask.kind == .bullet,
    "Leaving the line afterwards commits its edit, kind change and all")

// The store half: one Undo restores exactly what the edit touched.
let sessionUndo = UndoManager()
sessionUndo.groupsByEvent = false
let sessionLine = store.appendBlock(kind: .task, text: "Before", to: nextDocument)
let bystander = store.appendBlock(kind: .task, text: "Bystander", to: nextDocument)
store.save()
let session = store.beginEditorSession(in: nextList.id, covering: [sessionLine.id])
store.setPlainText(sessionLine, "After")
let sessionChild = store.recordInEditorSession(session) { store.insertBlock(kind: .task, text: "Created", after: sessionLine) }
store.setPlainText(bystander, "Changed meanwhile")
sessionUndo.beginUndoGrouping()
check(store.commitEditorSession(session, name: "Edited", undoManager: sessionUndo) && sessionUndo.undoActionName == "Edited",
    "A line edit registers one named step")
sessionUndo.endUndoGrouping()
sessionUndo.undo()
check(store.block(id: sessionLine.id)?.text == "Before" && store.block(id: sessionChild.id) == nil && bystander.text == "Changed meanwhile",
    "Undo takes the whole edit back and leaves what else changed")
sessionUndo.redo()
check(store.block(id: sessionLine.id)?.text == "After" && store.block(id: sessionChild.id)?.text == "Created", "Redo puts the edit back")
let unchanged = store.beginEditorSession(in: nextList.id, covering: [bystander.id])
check(!store.commitEditorSession(unchanged, name: "Edited", undoManager: sessionUndo), "An edit that changed nothing registers nothing")

print("✅ \(checks) editor/store checks passed")
