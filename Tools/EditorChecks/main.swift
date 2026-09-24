import AppKit
import CoreText
import SwiftData
import SwiftUI

// Register the bundled display serif as the app does at launch, before
// anything resolves the editor's heading font.
CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: "Shared/Fonts/InstrumentSerif-Regular.ttf") as CFURL, .process, nil)

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
store.undoableEditorEdit(in: list.id, name: "Delete", undoManager: undo) {
    store.deleteBlock(second, liftChildren: true)
    store.save()
}
undo.endUndoGrouping()
check(store.block(id: secondID) == nil, "Deleting a line removes its row")
check(store.block(id: childID)?.parentID == nil, "What was under the line stays, a level up")
check(store.attachments(for: secondID).isEmpty && MediaStore.shared.fileContents(filename: filename) == nil, "Deleting a line removes its files")
check(undo.canUndo, "Deleting registers an undo action")
// A later unrelated metadata edit to another task must not be rolled back.
first.mediaCaption = "Unrelated later caption"
store.save()
undo.undo()
let restored = store.block(id: secondID)!
check(first.text == "First" && restored.text == "Second", "Undo restores the line's text")
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
check(store.block(id: secondID) == nil && store.block(id: childID)?.parentID == nil, "Redo deletes the line again")
undo.undo()
check(store.attachments(for: secondID).first?.filename == filename && MediaStore.shared.fileContents(filename: filename) == bytes, "Repeated undo restores attachment again")

undo.removeAllActions()
undo.beginUndoGrouping()
store.undoableEditorEdit(in: list.id, name: "Added a line", undoManager: undo) {
    _ = store.insertBlock(kind: .task, text: "Added", after: first)
    store.save()
}
undo.endUndoGrouping()
let countAfterAdd = store.blocks(inList: list.id).count
undo.undo()
check(first.text == "First" && store.blocks(inList: list.id).count == countAfterAdd - 1, "Undoing an added line removes it")
undo.redo()
check(store.blocks(inList: list.id).count == countAfterAdd, "Redo adds the line again")

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
store.trashList(removedList)
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
    && struckAttributes[.foregroundColor] as? NSColor === NXEditor.completedInk, "A closing task is struck in the accent before it is stored as done")
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

// The list document converts a line only on the design's prefixes.
func typedPrefix(_ text: String) -> BlockKind? {
    MarkdownInputRules.matchBlockPrefix(in: NSTextStorage(string: text), caret: (text as NSString).length,
                                        wasInsertion: true, kind: .task)?.kind
}
check(typedPrefix("## ") == .heading2 && typedPrefix("# ") == .heading1 && typedPrefix("- ") == .bullet
    && typedPrefix("* ") == .bullet && typedPrefix("[ ] ") == .task && typedPrefix("[] ") == .task
    && typedPrefix("> ") == .quote, "The design's prefixes convert a line")
check(["### ", "1. ", "1) ", "+ ", "``` ", "--- "].allSatisfy { typedPrefix($0) == nil },
    "Other Markdown prefixes stay as typed")
var prefixedKinds: [BlockKind] = []
coordinator.parent.callbacks.onMarkdownPrefix = { prefixedKinds.append($0) }
for typed in ["1. ", "## "] {
    coordinator.apply(NSAttributedString(), to: native, kind: .task, isCompleted: false)
    native.textStorage?.append(NSAttributedString(string: typed, attributes: RichTextCodec.baseAttributes(for: .task)))
    native.setSelectedRange(NSRange(location: native.string.utf16.count, length: 0))
    coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: native))
}
check(prefixedKinds == [.heading2] && native.string.isEmpty, "A line typed “1. ” keeps it; “## ” makes a subheading")
coordinator.parent.callbacks.onMarkdownPrefix = { _ in }

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
// The list document's Turn into card opens under its line whenever it fits on the page.
let cardPage = CGRect(x: 0, y: 300, width: 800, height: 600)
check(!SlashMenuLayout.cardOpensAbove(line: CGRect(x: 40, y: 500, width: 600, height: 20), height: 200, viewport: cardPage),
    "The Turn into card opens under a line with room below it, as the design places it")
check(SlashMenuLayout.cardOpensAbove(line: CGRect(x: 40, y: 800, width: 600, height: 20), height: 200, viewport: cardPage),
    "Near the bottom of the page, the card opens above its line, where it can be seen")
check(!SlashMenuLayout.cardOpensAbove(line: CGRect(x: 40, y: 330, width: 600, height: 20), height: 580, viewport: cardPage)
    && SlashMenuLayout.cardOpensAbove(line: CGRect(x: 40, y: 860, width: 600, height: 20), height: 580, viewport: cardPage),
    "With room on neither side, the card takes the side with more")
check(!SlashMenuLayout.cardOpensAbove(line: CGRect(x: 40, y: 800, width: 600, height: 20), height: 200, viewport: .zero),
    "A line not on a page yet keeps the card under it")

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
check(lastQuery == nil, "A slash after a space mid-line stays as typed; only one that starts the line opens Turn into")
let slashLine = RichTextCodec.decode(nil, plainText: "/h2 then a suffix", kind: .task)
coordinator.apply(slashLine, to: input, kind: .task, isCompleted: false)
input.setSelectedRange(NSRange(location: 3, length: 0))
coordinator.updateSlashQuery(in: input)
check(lastQuery == "h2" && queryRange == NSRange(location: 0, length: 3), "Slash query removes only its trigger and filter before a suffix")
input.isSlashMenuOpen = true
coordinator.dismissSlash(in: input)
lastQuery = nil
coordinator.updateSlashQuery(in: input)
check(lastQuery == nil, "Escape suppresses the same slash trigger during subsequent selection or layout updates")
input.isSlashMenuOpen = false
input.setSelectedRange(NSRange(location: 0, length: 0))
coordinator.updateSlashQuery(in: input)
input.setSelectedRange(NSRange(location: 3, length: 0))
coordinator.updateSlashQuery(in: input)
check(lastQuery == "h2", "Moving away from a dismissed trigger allows a later command session")
coordinator.parent = BlockTextView(blockID: UUID(), kind: .code, isCompleted: false, attributedText: slashLine, isFocused: false, focusToken: 0, callbacks: coordinator.parent.callbacks)
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
// The list document's Return finishes the whole line, a selection and all.
check(coordinator.textView(input, doCommandBy: #selector(NSResponder.insertNewline(_:))), "Return is routed to the outline")
check(returnedText == "Before DELETE After" && returnedCaret == 7 && input.string == "Before DELETE After",
    "Return that finishes the line leaves its selected text in it")
var tabCaret = -1
coordinator.parent.callbacks.onTab = { _, caret in tabCaret = caret; return true }
check(coordinator.textView(input, doCommandBy: #selector(NSResponder.insertTab(_:))) && tabCaret == 7, "Indentation receives the original mid-text caret")
input.setSelectedRange(NSRange(location: 0, length: 2))
check(!coordinator.textView(input, doCommandBy: #selector(NSResponder.moveUp(_:))), "Up with selected text retains native selection behavior")
// ← and → off a line's ends stay in it, as the design's lines are single inputs.
var arrowsOut: [EditorArrow] = []
coordinator.parent.callbacks.onArrowOut = { direction, _ in arrowsOut.append(direction); return true }
input.setSelectedRange(NSRange(location: 0, length: 0))
let leftTaken = coordinator.textView(input, doCommandBy: #selector(NSResponder.moveLeft(_:)))
input.setSelectedRange(NSRange(location: input.string.utf16.count, length: 0))
let rightTaken = coordinator.textView(input, doCommandBy: #selector(NSResponder.moveRight(_:)))
check(!leftTaken && !rightTaken && arrowsOut.isEmpty, "← at a line's start and → at its end never leave the line")
coordinator.parent.callbacks.onArrowOut = { _, _ in false }
// ⇧↩ asks the outline first, with the / menu showing too, and types a break only when it declines.
var lineBreaksAsked = 0
coordinator.parent.callbacks.onLineBreak = { lineBreaksAsked += 1; return true }
input.isSlashMenuOpen = true
check(coordinator.textView(input, doCommandBy: #selector(NSResponder.insertLineBreak(_:))) && lineBreaksAsked == 1
    && !input.string.contains("\u{2028}"), "⇧↩ with the / menu showing is the outline's, and a claimed one types no break")
input.isSlashMenuOpen = false
coordinator.parent.callbacks.onLineBreak = { false }
input.setSelectedRange(NSRange(location: 6, length: 0))
check(coordinator.textView(input, doCommandBy: #selector(NSResponder.insertLineBreak(_:))) && input.string == "Before\u{2028} DELETE After",
    "⇧↩ the outline declines still types a soft break")

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

// SwiftUI can redraw a line from inside the model's write of a keystroke,
// with the text the model held before it. That must neither take the
// keystroke back nor move the caret.
let focusedCallbacks = coordinator.parent.callbacks
let typed = RichTextCodec.decode(nil, plainText: "Ask", kind: .task)
coordinator.apply(typed, to: input, kind: .task, isCompleted: false)
input.setSelectedRange(NSRange(location: 3, length: 0))
var redrawnMidWrite = false
coordinator.parent.callbacks.onChange = { _ in
    coordinator.parent = BlockTextView(blockID: UUID(), kind: .task, isCompleted: false, attributedText: typed,
                                       isFocused: true, focusToken: 2, callbacks: focusedCallbacks)
    coordinator.updateContent(of: input)
    redrawnMidWrite = true
}
input.insertText("k", replacementRange: input.selectedRange())
check(redrawnMidWrite && input.string == "Askk" && input.selectedRange().location == 4,
    "A redraw from inside the text view's own write keeps the keystroke and the caret")
coordinator.parent = BlockTextView(blockID: UUID(), kind: .task, isCompleted: false,
                                   attributedText: RichTextCodec.decode(nil, plainText: "Ask about", kind: .task),
                                   isFocused: true, focusToken: 2, callbacks: focusedCallbacks)
coordinator.updateContent(of: input)
check(input.string == "Ask about", "Once the write is over, a change from outside still reaches the text view")

// A focus move tells the outline once it's carried out, including for a
// line SwiftUI puts in its window only after the update that sent the caret.
var appliedFocusTokens: [Int] = []
var landingCallbacks = focusedCallbacks
landingCallbacks.onFocusApplied = { appliedFocusTokens.append($0) }
coordinator.parent = BlockTextView(blockID: UUID(), kind: .task, isCompleted: false, attributedText: plain,
                                   isFocused: true, focusToken: 3, callbacks: landingCallbacks)
coordinator.apply(plain, to: input, kind: .task, isCompleted: false)
fixtureWindow.makeFirstResponder(nil)
input.removeFromSuperview()
coordinator.syncFocus(view: input, shouldFocus: true, caret: 2, token: 3)
await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
    DispatchQueue.main.async { continuation.resume() }
}
check(appliedFocusTokens.isEmpty && fixtureWindow.firstResponder !== input, "A line not in a window yet can't take the caret")
scrollDocument.addSubview(input)
await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
    DispatchQueue.main.async { continuation.resume() }
}
check(appliedFocusTokens == [3] && fixtureWindow.firstResponder === input && input.selectedRange().location == 2,
    "Put in its window later, the line takes the caret it was sent, and says so")
coordinator.parent = BlockTextView(blockID: UUID(), kind: .task, isCompleted: false, attributedText: plain,
                                   isFocused: true, focusToken: 2, callbacks: focusedCallbacks)

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
for kind: BlockKind in [.task, .paragraph, .heading1, .heading2, .heading3, .code] {
    input.textContainerInset = NSSize(width: 0, height: NXEditor.lineBoxInset(for: kind))
    coordinator.apply(RichTextCodec.decode(nil, plainText: "Task", kind: kind), to: input, kind: kind, isCompleted: false)
    let singleHeight = input.height(fittingWidth: 180)
    let font = NXEditor.nsFont(for: kind)
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
check(NXEditor.nsFont(for: .heading1) == NSFont.systemFont(ofSize: 20, weight: .bold)
    && NXEditor.nsFont(for: .heading2) == NSFont.systemFont(ofSize: 15.5, weight: .semibold)
    && NXEditor.nsFont(for: .heading3) == NSFont.systemFont(ofSize: 13.8, weight: .semibold)
    && NXEditor.nsFont(for: .task) == NSFont.systemFont(ofSize: 13.8)
    && NXEditor.nsFont(for: .bullet) == NSFont.systemFont(ofSize: 13.8)
    && NXEditor.nsFont(for: .paragraph) == NSFont.systemFont(ofSize: 13.5)
    && NXEditor.nsFont(for: .quote) == NSFont.systemFont(ofSize: 13.5)
    && NXEditor.nsFont(for: .code) == NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular),
    "Each kind uses the design's document font")
check(NXEditor.lineHeight(for: .task) == 13.8 * 1.45 && NXEditor.lineHeight(for: .paragraph) == 13.5 * 1.55
    && NXEditor.lineHeight(for: .heading1) == 20 * 1.3 && NXEditor.lineHeight(for: .heading2) == 15.5 * 1.35,
    "Each kind has the design's line height")
check(RichTextCodec.baseAttributes(for: .heading1)[.kern] as? CGFloat == -0.2 && RichTextCodec.baseAttributes(for: .task)[.kern] == nil,
    "Heading 1 keeps the design's −0.01em letter-spacing")
let spacedHeading = NSMutableAttributedString(attributedString: RichTextCodec.decode(nil, plainText: "Title", kind: .heading1))
RichTextCodec.toggleTrait(.italicFontMask, in: spacedHeading, range: NSRange(location: 0, length: 5), kind: .heading1)
let spacedArchive = RichTextCodec.encode(spacedHeading, kind: .heading1)!
let storedHeading = try! NSAttributedString(data: spacedArchive, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
check(storedHeading.attribute(.kern, at: 0, effectiveRange: nil) == nil, "Letter-spacing is presentation and never stored")
func nextTitleMetrics(_ text: String) -> (height: CGFloat, baseline: CGFloat) {
    let size = NXEditor.bodyPointSize
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
input.textContainerInset = NSSize(width: 0, height: NXEditor.lineBoxInset(for: .task))
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
    input.textContainerInset = NSSize(width: 0, height: NXEditor.lineBoxInset(for: kind))
    coordinator.apply(RichTextCodec.decode(nil, plainText: "Line", kind: kind), to: input, kind: kind, isCompleted: false)
    input.invalidateIntrinsicContentSize()
    check(abs(input.height(fittingWidth: 180) - NXEditor.lineHeight(for: kind)) < 0.05,
        "\(kind) fills the design's line box of \(NXEditor.lineHeight(for: kind))pt")
    coordinator.apply(RichTextCodec.decode(nil, plainText: "Line\u{2028}Line", kind: kind), to: input, kind: kind, isCompleted: false)
    input.invalidateIntrinsicContentSize()
    check(abs(input.height(fittingWidth: 180) - 2 * NXEditor.lineHeight(for: kind)) < 0.6,
        "\(kind) wraps onto the design's line pitch")
}
let taskAttributes = RichTextCodec.baseAttributes(for: .task)
check(taskAttributes[.foregroundColor] as? NSColor === NXEditor.ink
    && RichTextCodec.baseAttributes(for: .task)[.foregroundColor] as? NSColor === taskAttributes[.foregroundColor] as? NSColor
    && RichTextCodec.baseAttributes(for: .quote)[.foregroundColor] as? NSColor === NXEditor.secondaryInk
    && RichTextCodec.baseAttributes(for: .paragraph)[.foregroundColor] as? NSColor === NXEditor.secondaryInk
    && RichTextCodec.baseAttributes(for: .task, isCompleted: true)[.strikethroughColor] as? NSColor === NXEditor.strikeInk
    && NXEditor.link === NXEditor.accentViolet,
    "Editor colours are shared ink and accent tokens, so content signatures stay equal")
let closingTitle = RichTextCodec.restylingCompletion(of: RichTextCodec.decode(nil, plainText: "Closing", kind: .task), kind: .task,
                                                     struck: true, strikeColor: NXEditor.accentBlue, dimsCompleted: false)
check(closingTitle.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor === NXEditor.ink
    && closingTitle.attribute(.strikethroughColor, at: 0, effectiveRange: nil) as? NSColor === NXEditor.accentBlue
    && closingTitle.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) != nil,
    "A task struck during its dwell keeps its ink under the accent strike")
check(BlockTextView.ContentSignature(attributedText: closingTitle, kind: .task, isCompleted: false, struck: true,
                                     strikeColor: NXEditor.accentBlue, dimsStruck: false).overridesCompletion
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
check(legacyDecoded.attribute(.font, at: 0, effectiveRange: nil) as? NSFont == NXEditor.nsFont(for: .heading1),
    "An older heading's own bold reads as the heading")
check(fontTraits(legacyDecoded, at: 4).contains(.italicFontMask), "Italic in an older heading keeps its italic")
check(RichTextCodec.decode(RichTextCodec.encode(legacyDecoded, kind: .heading1), plainText: "Old title", kind: .heading1).isEqual(to: legacyDecoded),
    "The next save stores an older heading's runs corrected")

// The outline engine behind the list document, driven without a view.
let outlineList = store.createList(title: "Outline engine")
let outlineDocument = DocumentContext(listID: outlineList.id)
let parentTask = store.appendBlock(kind: .task, text: "Parent", to: outlineDocument)
let firstSubtask = store.insertChild(kind: .task, text: "First subtask", of: parentTask, at: .last)
let secondSubtask = store.insertChild(kind: .task, text: "Second subtask", of: parentTask, at: .last)
store.save()
let outlineEnv = AppEnvironment(store: store)
let listEditor = OutlineEditor(env: outlineEnv, document: outlineDocument)
func outlineRow(_ block: Block, in editor: OutlineEditor) -> BlockRow {
    editor.visibleRows(in: store.blocks(inList: outlineList.id)).first { $0.id == block.id }!
}
func listRows() -> [BlockRow] { listEditor.visibleRows(in: store.blocks(inList: outlineList.id)) }
check(listRows().map(\.id) == [parentTask.id, firstSubtask.id, secondSubtask.id] && listRows().map(\.depth) == [0, 1, 1],
    "A list document projects the whole list, from depth 0")

// The list is a floor: its top-level lines never outdent out of it.
check(listEditor.actions(for: outlineRow(parentTask, in: listEditor)).editorCallbacks.onTab(true, 0) && parentTask.parentID == nil,
    "Shift-Tab on a top-level line is consumed and keeps it at the top level")
check(listEditor.actions(for: outlineRow(secondSubtask, in: listEditor)).onTab(false, 0) && secondSubtask.parentID == firstSubtask.id,
    "Tab nests a subtask under the one above it")
check(listEditor.actions(for: outlineRow(secondSubtask, in: listEditor)).onTab(true, 0) && secondSubtask.parentID == parentTask.id,
    "Shift-Tab outdents a nested subtask one level")
var focusedIDs: [UUID] = []
var escapedIDs: [UUID] = []
listEditor.hooks.didFocus = { focusedIDs.append($0) }
listEditor.hooks.didEscape = { escapedIDs.append($0) }
listEditor.actions(for: outlineRow(parentTask, in: listEditor)).onFocus()
check(listEditor.focus.blockID == parentTask.id && focusedIDs.last == parentTask.id && outlineEnv.activeDocument == outlineDocument,
    "Focusing a row adopts the caret, claims menu commands and tells the host")
outlineEnv.pendingCommand = .outdent
listEditor.receiveCommand()
check(parentTask.parentID == nil && outlineEnv.pendingCommand == nil, "The Outdent command keeps a top-level line in the list")
listEditor.actions(for: outlineRow(firstSubtask, in: listEditor)).onFocus()

// Escape lets go of the caret and tells the host which block it left.
check(outlineEnv.navigator.selection == [firstSubtask.id], "Editing a row makes it the row selection")
listEditor.actions(for: outlineRow(firstSubtask, in: listEditor)).onEscape()
check(escapedIDs == [firstSubtask.id] && listEditor.focus.blockID == nil && outlineEnv.navigator.selection.isEmpty,
    "Escape releases the caret and selection, then reports the block to the host")

// With the caret gone, the host's keys can put it back.
check(listEditor.escapedBlockID == firstSubtask.id, "The outline remembers the block Escape left")
outlineEnv.activeDocument = nil
let tokenBeforeResume = listEditor.focus.token
check(listEditor.resumeEditing() && listEditor.focus.blockID == firstSubtask.id && listEditor.focus.caret == nil
    && listEditor.focus.token != tokenBeforeResume && outlineEnv.activeDocument == outlineDocument,
    "Resuming puts the caret back where the text view had it, and claims menu commands")
check(listEditor.escapedBlockID == nil && !listEditor.resumeEditing(), "Resuming lets go of the escaped block")
listEditor.actions(for: outlineRow(firstSubtask, in: listEditor)).onEscape()
listEditor.forgetEscape()
check(!listEditor.resumeEditing() && listEditor.focus.blockID == nil, "Once the host's keys move on, Escape's block is forgotten")
listEditor.actions(for: outlineRow(firstSubtask, in: listEditor)).onEscape()
listEditor.actions(for: outlineRow(secondSubtask, in: listEditor)).onFocus()
check(listEditor.escapedBlockID == nil, "Clicking into any row ends the wait to resume")

// Hooks replace host policy; without one, the store or navigator acts.
var openedIDs: [UUID] = []
listEditor.hooks.openDetails = { openedIDs.append($0) }
outlineEnv.pendingCommand = .openDetails
listEditor.receiveCommand()
check(openedIDs == [secondSubtask.id] && outlineEnv.navigator.openTaskID == nil, "A details hook opens the task in the navigator's place")
var claimed: [(EditorCommand, [UUID])] = []
listEditor.hooks.taskCommand = { command, ids in
    claimed.append((command, ids))
    return command == .toggleStar
}
listEditor.actions(for: outlineRow(firstSubtask, in: listEditor)).onFocus()
outlineEnv.pendingCommand = .toggleStar
listEditor.receiveCommand()
check(claimed.last?.0 == .toggleStar && claimed.last?.1 == [firstSubtask.id] && !firstSubtask.isStarred,
    "A host claims task commands for the command targets before the store")
outlineEnv.pendingCommand = .setDueToday
listEditor.receiveCommand()
check(claimed.last?.0 == .setDueToday && firstSubtask.dueDate != nil, "Commands a host declines fall back to the store")
let menuElsewhere = store.createList(title: "Menu targets elsewhere")
outlineEnv.activeDocument = DocumentContext(listID: menuElsewhere.id)
outlineEnv.pendingCommand = .clearDueDate
listEditor.receiveCommand()
check(outlineEnv.pendingCommand == .clearDueDate && firstSubtask.dueDate != nil, "Only the active document runs menu commands")
outlineEnv.pendingCommand = nil

// The Task menu reads the tasks a command sent now would reach.
check(listEditor.commandTaskIDs == [firstSubtask.id], "The menu's targets are the task holding the caret")
let menuNote = store.insertChild(kind: .paragraph, text: "A text line", of: parentTask, at: .last)
let menuOtherTask = store.appendBlock(kind: .task, text: "Another list's task", to: DocumentContext(listID: menuElsewhere.id))
store.save()
listEditor.hooks.commandTargets = { [secondSubtask.id] }
listEditor.actions(for: outlineRow(menuNote, in: listEditor)).onFocus()
check(listEditor.commandTaskIDs.isEmpty, "A text line holding the caret leaves the menu no task, whatever the host targets")
listEditor.actions(for: outlineRow(menuNote, in: listEditor)).onEscape()
check(listEditor.commandTaskIDs == [secondSubtask.id], "With no caret, the menu reads the host's targets")
listEditor.hooks.commandTargets = { [menuOtherTask.id] }
check(listEditor.commandTaskIDs.isEmpty, "The host's targets count only in the document's list")
listEditor.hooks = OutlineHooks()
store.deleteBlock(menuNote)
store.save()

// Done tasks at the document's top level are the host's to list apart.
let doneAtTop = store.appendBlock(kind: .task, text: "Done at the top level", to: outlineDocument)
doneAtTop.isCompleted = true
store.save()
check(!listRows().contains { $0.id == doneAtTop.id }, "A done top-level task leaves the visible rows")
listEditor.completedTasksKeptVisible = [doneAtTop.id]
check(listRows().last?.id == doneAtTop.id, "The host can keep a done task on screen")
listEditor.documentDidChange()
check(listEditor.completedTasksKeptVisible.isEmpty && listEditor.focus.blockID == nil,
    "A document changing in place forgets the tasks its host kept visible")
store.deleteBlock(doneAtTop)
store.save()
let doneFirst = store.insertChild(kind: .task, text: "Done first", of: parentTask, at: .first)
doneFirst.isCompleted = true

// Nested rows outdent to the list's top level.
listEditor.actions(for: outlineRow(firstSubtask, in: listEditor)).onFocus()
outlineEnv.pendingCommand = .outdent
listEditor.receiveCommand()
check(firstSubtask.parentID == nil, "A list document outdents nested rows to its top level")

// Slash selection and arrows through void rows.
let noteBlock = store.appendBlock(kind: .paragraph, text: "/div", to: outlineDocument)
let afterNote = store.appendBlock(kind: .paragraph, text: "After", to: outlineDocument)
store.save()
listEditor.actions(for: outlineRow(noteBlock, in: listEditor)).onSlashQuery("div", NSRange(location: 0, length: 4), .zero, .zero)
check(listEditor.slash?.blockID == noteBlock.id, "Typing a slash query opens the menu on its row")
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
let returned = listEditor.focus.blockID!
listEditor.actions(for: outlineRow(store.block(id: returned)!, in: listEditor)).onChange(NSAttributedString(string: "Returned"))
check(listEditor.actions(for: outlineRow(afterNote, in: listEditor)).onArrowOut(.down, 0) && listEditor.focus.blockID == returned
    && store.block(id: returned) != nil, "An edit made here retires the drawn rows, so the next key sees the new row")

// Between renders, handlers read the drawn rows rather than the store.
let drawnBeforeAppend = listEditor.rowsToDraw(in: store.blocks(inList: outlineList.id))
let undrawn = store.appendBlock(kind: .paragraph, text: "Not drawn yet", to: outlineDocument)
store.save()
check(!listEditor.actions(for: drawnBeforeAppend.last!).onArrowOut(.down, 0), "Handlers between renders reuse the drawn rows")
_ = listEditor.rowsToDraw(in: store.blocks(inList: outlineList.id))
check(listEditor.actions(for: drawnBeforeAppend.last!).onArrowOut(.down, 0) && listEditor.focus.blockID == undrawn.id,
    "The next render's rows reach the handlers")
let shownRows = listEditor.rowsToDraw(in: store.blocks(inList: outlineList.id))
check(shownRows[shownRows.firstIndex { $0.id == parentTask.id }! + 1].id == doneFirst.id, "A completed subtask is drawn under its parent")
let doneTop = store.appendBlock(kind: .task, text: "Done at the top", to: outlineDocument)
doneTop.isCompleted = true
store.save()
let lastDrawn = listEditor.rowsToDraw(in: store.blocks(inList: outlineList.id)).last!
check(lastDrawn.id == undrawn.id && !listEditor.actions(for: lastDrawn).onArrowOut(.down, 0), "A done top-level task isn't drawn")
listEditor.completedTasksKeptVisible = [doneTop.id]
check(listEditor.actions(for: lastDrawn).onArrowOut(.down, 0) && listEditor.focus.blockID == doneTop.id,
    "Keeping a done task on screen retires the drawn rows")
listEditor.completedTasksKeptVisible = []

// The list document's rules, from the design.
let nextList = store.createList(title: "List document")
let nextDocument = DocumentContext(listID: nextList.id)
let nextEditor = OutlineEditor(env: outlineEnv, document: nextDocument)
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
let whole = NSAttributedString(string: "Walk the Philosopher's Path")
check(nextActions(emptyHeading).onReturn(9, whole) && emptyHeading.text == "Walk the Philosopher's Path"
    && store.block(id: addedLines[4])?.text == "" && nextEditor.focus.blockID == addedLines[4] && nextEditor.focus.caret == 0,
    "Return mid-line finishes the whole line and opens an empty one, as the design's does")
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

// The `/` menu: the design's five, and the editor's other kinds by name.
check(nextEditor.slashKinds(matching: "") == [.task, .heading1, .heading2, .bullet, .paragraph]
    && OutlineSlashOption.all.filter(\.isExtra).map(\.kind) == [.heading3, .numbered, .quote, .code, .divider, .image],
    "Turn into opens on the design's five kinds alone")
check(nextEditor.slashKinds(matching: "sub") == [.heading2] && nextEditor.slashKinds(matching: "text").first == .paragraph
    && nextEditor.slashKinds(matching: "h1") == [.heading1], "Turn into filters by label and the editor's search words")
check(nextEditor.slashKinds(matching: "u") == [.heading2, .bullet] && nextEditor.slashKinds(matching: "e") == [.heading1, .heading2, .bullet, .paragraph],
    "A letter brings up what the design's filter does, not every other kind whose name holds it")
// The design's slashOpts: its five, whose label holds the query.
let designSlashOptions: [(kind: BlockKind, label: String)] = [(.task, "Task"), (.heading1, "Heading"), (.heading2, "Subheading"),
                                                              (.bullet, "Bullet"), (.paragraph, "Text")]
func designSlashKinds(_ query: String) -> [BlockKind] {
    designSlashOptions.filter { query.isEmpty || $0.label.lowercased().contains(query) }.map { $0.kind }
}
check(nextEditor.slashKinds(matching: "s") == [.task, .heading2] && nextEditor.slashKinds(matching: "t") == [.task, .bullet, .paragraph]
    && nextEditor.slashKinds(matching: "l") == [.bullet] && nextEditor.slashKinds(matching: "h") == [.heading1, .heading2]
    && nextEditor.slashKinds(matching: "c").isEmpty,
    "A letter brings up no kind for its search words alone")
check("abcdefghijklmnopqrstuvwxyz0123456789".allSatisfy { nextEditor.slashKinds(matching: String($0)) == designSlashKinds(String($0)) },
    "Every letter filters Turn into as the design's slashOpts does")
check(nextEditor.slashKinds(matching: "todo") == [.task] && nextEditor.slashKinds(matching: "hr") == [.divider]
    && nextEditor.slashKinds(matching: "co") == [.code],
    "From the second letter the editor's search words and the other kinds' names come in")
check(nextEditor.slashKinds(matching: "code") == [.code] && nextEditor.slashKinds(matching: "quo") == [.quote]
    && nextEditor.slashKinds(matching: "num") == [.numbered] && nextEditor.slashKinds(matching: "heading") == [.heading1, .heading2, .heading3]
    && nextEditor.slashKinds(matching: "div") == [.divider] && nextEditor.slashKinds(matching: "ima") == [.image],
    "The editor's other kinds come up for their names")

// ⇧↩ writes a task's note. The design's other lines hold one line each,
// and its Turn into card takes ⇧↩ as it takes Return.
var notesWritten: [UUID] = []
nextEditor.hooks.editNote = { notesWritten.append($0) }
nextActions(prose).onFocus()
check(nextActions(prose).onLineBreak() && notesWritten.isEmpty && nextEditor.focus.blockID == prose.id,
    "⇧↩ in text takes the key and types no break")
nextActions(confirm).onFocus()
check(nextActions(confirm).onLineBreak() && notesWritten == [confirm.id] && nextEditor.focus.blockID == nil,
    "⇧↩ in a task leaves its title for its note")
nextEditor.appendTask()
let untitledNew = nextEditor.focus.blockID!
check(nextEditor.actions(for: nextRows().first { $0.id == untitledNew }!).onLineBreak() && store.block(id: untitledNew) == nil
    && notesWritten == [confirm.id], "⇧↩ in a new empty task takes the line away and opens no note, as the design's")
let snippet = store.appendBlock(kind: .code, text: "let fare = 14_000", to: nextDocument)
store.save()
check(!nextActions(snippet).onLineBreak(), "A code line, one of the editor's own kinds, keeps ⇧↩'s soft break")
store.deleteBlock(snippet)
let slashed = store.appendBlock(kind: .task, text: "/", to: nextDocument)
store.save()
nextActions(slashed).onFocus()
nextActions(slashed).onSlashQuery("", NSRange(location: 0, length: 1), .zero, .zero)
nextEditor.handleSlashCommand(.next)
check(nextActions(slashed).onLineBreak() && slashed.kind == .heading1 && slashed.text.isEmpty && nextEditor.slash == nil
    && notesWritten == [confirm.id], "⇧↩ with the Turn into card open turns the line into the highlighted kind")
nextEditor.commitLine()
store.deleteBlock(slashed)
store.save()
nextEditor.hooks.editNote = nil

// Done top-level tasks leave the document; done subtasks stay in place.
email.isCompleted = true
let rowsWithDoneSubtask = nextRows()
check(rowsWithDoneSubtask.contains { $0.id == email.id } && rowsWithDoneSubtask.firstIndex { $0.id == email.id }! < rowsWithDoneSubtask.firstIndex { $0.id == confirm.id }!,
    "A done subtask stays where it was ticked")
book.isCompleted = true
check(nextRows().contains { $0.id == book.id } && nextRows().contains { $0.id == pay.id },
    "A done top-level task stays while a task under it is still open, so that task shows")
check(BlockTree.completedTasksHoldingOpenTasks(in: store.blocks(inList: nextList.id)) == [book.id],
    "The done tasks held on show are those with an open task below")
pay.isCompleted = true
check(!nextRows().contains { $0.id == book.id || $0.id == email.id || $0.id == pay.id }, "A done top-level task leaves with its subtree")
nextEditor.completedTasksKeptVisible = [book.id]
check(nextRows().contains { $0.id == book.id }, "The host can keep a done task in view")
nextEditor.completedTasksKeptVisible = []
book.isCompleted = false
email.isCompleted = false
pay.isCompleted = false

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
store.writeInEditorSession(session, to: sessionLine) { store.setPlainText(sessionLine, "After") }
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

// A heading's section sits inside the sections of the headings above it
// with higher levels.
let sectionList = store.createList(title: "Sections")
let sectionDocument = DocumentContext(listID: sectionList.id)
let outerHeading = store.appendBlock(kind: .heading1, text: "Trip", to: sectionDocument)
let middleHeading = store.appendBlock(kind: .heading2, text: "Before", to: sectionDocument)
let sectionTask = store.appendBlock(kind: .task, text: "Renew passports", to: sectionDocument)
let otherHeading = store.appendBlock(kind: .heading2, text: "During", to: sectionDocument)
let innerHeading = store.appendBlock(kind: .heading3, text: "Kyoto", to: sectionDocument)
let innerTask = store.appendBlock(kind: .task, text: "Book the ryokan", to: sectionDocument)
let innerSubtask = store.insertChild(kind: .task, text: "Compare Gion", of: innerTask, at: .last)
let nextTopHeading = store.appendBlock(kind: .heading1, text: "Home", to: sectionDocument)
store.save()
let sectionRows = BlockTree.flatten(store.blocks(inList: sectionList.id), respectCollapse: false)
check(BlockTree.enclosingSections(of: sectionTask.id, in: sectionRows) == [middleHeading.id, outerHeading.id]
    && BlockTree.enclosingSections(of: innerSubtask.id, in: sectionRows) == [innerHeading.id, otherHeading.id, outerHeading.id],
    "A line sits in the section of the heading above it and of each higher heading above that")
check(BlockTree.enclosingSections(of: otherHeading.id, in: sectionRows) == [outerHeading.id]
    && BlockTree.enclosingSections(of: nextTopHeading.id, in: sectionRows).isEmpty,
    "A heading sits only in the sections of higher-level headings")

// The inspector's Add subtask writes a line at the end of the task's subtasks.
let addList = store.createList(title: "Add subtask")
let addDocument = DocumentContext(listID: addList.id)
let addEditor = OutlineEditor(env: outlineEnv, document: addDocument)
var addRecorded: [(edit: OutlineEdit, name: String)] = []
addEditor.hooks.didRecordEdit = { addRecorded.append(($0, $1)) }
func addRows() -> [BlockRow] { addEditor.visibleRows(in: store.blocks(inList: addList.id)) }
func addRow(_ block: Block) -> BlockRow { addRows().first { $0.id == block.id }! }
let foldingHeading = store.appendBlock(kind: .heading1, text: "Before we go", to: addDocument)
let ryokan = store.appendBlock(kind: .task, text: "Book the ryokan", to: addDocument)
let compare = store.insertChild(kind: .task, text: "Compare Gion", of: ryokan, at: .last)
let annex = store.insertChild(kind: .task, text: "Ask about the annex", of: compare, at: .last)
store.save()
store.setCollapsed(true, for: ryokan)
store.setCollapsed(true, for: foldingHeading)
check(!addRows().contains { $0.id == ryokan.id }, "The task starts folded away under its heading")
addEditor.appendSubtask(to: ryokan.id)
let added = addEditor.focus.blockID.flatMap { store.block(id: $0) }
check(added?.kind == .task && added?.parentID == compare.id
    && store.children(of: compare.id, listID: addList.id).last?.id == added?.id
    && addRows().firstIndex { $0.id == added?.id } == addRows().firstIndex { $0.id == annex.id }.map { $0 + 1 }
    && addRows().first { $0.id == added?.id }?.depth == 2,
    "Add subtask puts a task line, with the caret, after the task's last line and at its depth, as the design's Return there")
check(!ryokan.isCollapsed && !foldingHeading.isCollapsed && addRows().contains { $0.id == added?.id },
    "The task and the heading folding it open, so the new line shows")
addEditor.actions(for: addRow(added!)).onChange(NSAttributedString(string: "Pay the deposit"))
addEditor.commitLine()
check(addRecorded.last?.edit == .added(added!.id) && added?.text == "Pay the deposit", "The new subtask is one added line")
let annexChildren = store.children(of: annex.id, listID: addList.id).count
addEditor.appendSubtask(to: annex.id)
check(store.children(of: annex.id, listID: addList.id).count == annexChildren, "A task two levels down takes no subtask")

// Drags follow the design's nesting rules.
let heading = store.appendBlock(kind: .heading1, text: "On the ground", to: addDocument)
let pass = store.appendBlock(kind: .bullet, text: "JR pass", to: addDocument)
let loose = store.appendBlock(kind: .task, text: "Reserve the market tour", to: addDocument)
let pack = store.appendBlock(kind: .task, text: "Pack", to: addDocument)
let socks = store.insertChild(kind: .task, text: "Socks", of: pack, at: .last)
store.save()
addRecorded.removeAll()
addEditor.move([loose.id], relativeTo: addRow(ryokan), position: .inside)
check(loose.parentID == ryokan.id && addRecorded.map(\.edit) == [.dragged([loose.id])] && addRecorded.last?.name == "Move",
    "A task dragged into a task becomes its subtask, as one named move")
addEditor.move([heading.id], relativeTo: addRow(pass), position: .inside)
let rootOrder = store.children(of: nil, listID: addList.id).map(\.id)
check(heading.parentID == nil && rootOrder.firstIndex(of: heading.id) == rootOrder.firstIndex(of: pass.id)! + 1,
    "A heading dropped into a list item lands after it, at the top")
store.editorNotice = nil
let recordedMoves = addRecorded.count
addEditor.move([heading.id], relativeTo: addRow(compare), position: .before)
check(heading.parentID == nil && store.editorNotice != nil && addRecorded.count == recordedMoves,
    "A heading never goes beside a nested line")
store.editorNotice = nil
addEditor.move([pack.id], relativeTo: addRow(annex), position: .before)
check(pack.parentID == nil && socks.parentID == pack.id && store.editorNotice != nil,
    "A task whose subtasks would go past two levels stays where it is")
store.editorNotice = nil
let unmoved = store.children(of: nil, listID: addList.id).map(\.id)
addEditor.move([pass.id], relativeTo: addRow(heading), position: .before)
check(store.children(of: nil, listID: addList.id).map(\.id) == unmoved && addRecorded.count == recordedMoves,
    "A drop that changes nothing records nothing")

// Add subtask on a task with none makes its first; a last line past two
// levels, or under a line that holds no tasks, has the new one step up.
let depthList = store.createList(title: "Add subtask depth")
let depthDocument = DocumentContext(listID: depthList.id)
let depthEditor = OutlineEditor(env: outlineEnv, document: depthDocument)
func depthRows() -> [BlockRow] { depthEditor.visibleRows(in: store.blocks(inList: depthList.id)) }
func depthAdded() -> Block? { depthEditor.focus.blockID.flatMap { store.block(id: $0) } }
let yen = store.appendBlock(kind: .task, text: "Exchange yen", to: depthDocument)
let older = store.appendBlock(kind: .task, text: "Older outline", to: depthDocument)
let olderOne = store.insertChild(kind: .task, text: "One", of: older, at: .last)
let olderTwo = store.insertChild(kind: .task, text: "Two", of: olderOne, at: .last)
let olderThree = store.insertChild(kind: .task, text: "Three", of: olderTwo, at: .last)
let noted = store.appendBlock(kind: .task, text: "Noted", to: depthDocument)
let nestedText = store.insertChild(kind: .paragraph, text: "Nested text", of: noted, at: .last)
let underText = store.insertChild(kind: .task, text: "Under the text", of: nestedText, at: .last)
store.save()
depthEditor.appendSubtask(to: yen.id)
check(depthAdded()?.parentID == yen.id, "A task with no subtasks gets its first")
depthEditor.commitLine()
depthEditor.appendSubtask(to: older.id)
check(depthAdded()?.parentID == olderOne.id && depthRows().firstIndex { $0.id == depthAdded()?.id }
        == depthRows().firstIndex { $0.id == olderThree.id }.map { $0 + 1 },
    "After a line deeper than two levels, the new subtask goes no deeper than two")
depthEditor.commitLine()
depthEditor.appendSubtask(to: noted.id)
check(depthAdded()?.parentID == noted.id && depthRows().firstIndex { $0.id == depthAdded()?.id }
        == depthRows().firstIndex { $0.id == underText.id }.map { $0 + 1 },
    "After a line under text, the new subtask goes beside the text, under a task")
depthEditor.commitLine()

// A search hit shows through the heading folding it away.
let revealList = store.createList(title: "Reveal")
let revealDocument = DocumentContext(listID: revealList.id)
let revealEditor = OutlineEditor(env: outlineEnv, document: revealDocument)
let foldedHeading = store.appendBlock(kind: .heading1, text: "Before we go", to: revealDocument)
let foldedText = store.appendBlock(kind: .paragraph, text: "Kasuga replies in about a day", to: revealDocument)
store.save()
store.setCollapsed(true, for: foldedHeading)
func revealRows() -> [BlockRow] { revealEditor.visibleRows(in: store.blocks(inList: revealList.id)) }
check(!revealRows().contains { $0.id == foldedText.id }, "A folded heading hides the text under it")
let request = try ContentReveal.resolve(.block(foldedText.id), query: "Kasuga",
                                        blocks: store.blocks(inList: revealList.id), lists: [revealList])
outlineEnv.navigator.reveal(request)
check(revealEditor.reveal?.blockID == foldedText.id && revealRows().contains { $0.id == foldedText.id } && foldedHeading.isCollapsed,
    "A search hit shows through the heading folding it, which stays folded")
outlineEnv.navigator.finishReveal()
check(!revealRows().contains { $0.id == foldedText.id }, "Finishing the reveal folds the text away again")

// New lines never open out of sight, conversions carry what's under them,
// and a line's undo step is only what the line itself did.
let fixList = store.createList(title: "Document fixes")
let fixDocument = DocumentContext(listID: fixList.id)
let fixEditor = OutlineEditor(env: outlineEnv, document: fixDocument)
var fixRecorded: [OutlineEdit] = []
fixEditor.hooks.didRecordEdit = { edit, _ in fixRecorded.append(edit) }
func fixRows() -> [BlockRow] { fixEditor.visibleRows(in: store.blocks(inList: fixList.id)) }
func fixActions(_ block: Block) -> BlockRowActions { fixEditor.actions(for: fixRows().first { $0.id == block.id }!) }
func fixShows(_ id: UUID?) -> Bool { id.map { id in fixRows().contains { $0.id == id } } ?? false }

let foldHeading = store.appendBlock(kind: .heading1, text: "Kyoto", to: fixDocument)
let foldTask = store.appendBlock(kind: .task, text: "Book the ryokan", to: fixDocument)
store.save()
store.setCollapsed(true, for: foldHeading)
check(!fixShows(foldTask.id), "A folded heading hides its section")
check(fixActions(foldHeading).onReturn(content(foldHeading).length, content(foldHeading)) && fixShows(fixEditor.focus.blockID)
    && !foldHeading.isCollapsed, "Return at the end of a folded heading opens it, so the new line and its caret show")
fixEditor.commitLine()
store.setCollapsed(true, for: foldHeading)
fixEditor.appendTask()
check(fixShows(fixEditor.focus.blockID) && !foldHeading.isCollapsed, "A line added at the end of a folded last section shows")
fixEditor.commitLine()
store.setCollapsed(true, for: foldHeading)
store.setPlainText(foldHeading, "Kyoto trip")
check(fixActions(foldHeading).onReturn(5, content(foldHeading)) && fixShows(fixEditor.focus.blockID) && foldHeading.text == "Kyoto trip",
    "Return inside a folded heading keeps it whole and opens a line that shows")
fixEditor.commitLine()

// A line turned into a kind that doesn't nest takes what was under it out beside it.
let packing = store.appendBlock(kind: .task, text: "Pack", to: fixDocument)
let packedSocks = store.insertChild(kind: .task, text: "Socks", of: packing, at: .last)
let adapters = store.insertChild(kind: .task, text: "Adapters", of: packing, at: .last)
let typeA = store.insertChild(kind: .task, text: "Type A", of: adapters, at: .last)
store.save()
fixActions(packing).onFocus()
fixActions(packing).onMarkdownPrefix(.heading1)
let packed = fixRows().map(\.id)
check(packing.kind == .heading1 && packing.parentID == nil && packedSocks.parentID == nil && adapters.parentID == nil
    && typeA.parentID == adapters.id, "“# ” on a task with subtasks makes a heading with them beside it, a level up")
check(packed.firstIndex(of: packedSocks.id) == packed.firstIndex(of: packing.id)! + 1
    && packed.firstIndex(of: adapters.id) == packed.firstIndex(of: packedSocks.id)! + 1, "They follow the heading in their order")
fixEditor.commitLine()
let groceries = store.appendBlock(kind: .task, text: "Groceries", to: fixDocument)
let market = store.insertChild(kind: .bullet, text: "Market", of: groceries, at: .last)
let yuba = store.insertChild(kind: .task, text: "Yuba", of: market, at: .last)
store.save()
fixActions(market).onFocus()
check(fixActions(market).onBackspaceAtStart(content(market)) && market.kind == .paragraph && market.parentID == nil
    && yuba.parentID == nil, "Backspace on a nested list item makes text at the top, with what was under it beside it")
fixEditor.commitLine()

// Something else changing the line's task isn't the line's edit.
fixRecorded.removeAll()
let ticked = store.appendBlock(kind: .task, text: "Ticked", to: fixDocument)
store.save()
fixActions(ticked).onFocus()
store.toggleCompletion(ticked)
fixEditor.commitLine()
check(ticked.isCompleted && fixRecorded.isEmpty, "A line whose task completes from elsewhere while it's open records no edit")
let netUndo = UndoManager()
netUndo.groupsByEvent = false
let netLine = store.appendBlock(kind: .task, text: "Draft", to: fixDocument)
store.save()
let net = store.beginEditorSession(in: fixList.id, covering: [netLine.id])
store.writeInEditorSession(net, to: netLine) { store.setPlainText(netLine, "Draft two") }
netLine.isStarred = true
netLine.dueDate = due
store.writeInEditorSession(net, to: netLine) { store.setPlainText(netLine, "Draft three") }
netUndo.beginUndoGrouping()
check(store.commitEditorSession(net, name: "Edited", undoManager: netUndo), "The line's own typing is still one step")
netUndo.endUndoGrouping()
netUndo.undo()
check(netLine.text == "Draft" && netLine.isStarred && netLine.dueDate == due,
    "Undoing it takes back the typing and leaves the star and date set meanwhile")
let bystanderChange = store.beginEditorSession(in: fixList.id, covering: [netLine.id])
netLine.isStarred = false
check(!store.commitEditorSession(bystanderChange, name: "Edited", undoManager: netUndo), "Only something else's change registers nothing")

// Only a line emptied in its edit, holding nothing but text, goes.
let untitled = store.appendBlock(kind: .task, text: "", to: fixDocument)
untitled.note = "Call before noon"
let spacer = store.appendBlock(kind: .paragraph, text: "", to: fixDocument)
let belowSpacer = store.appendBlock(kind: .task, text: "Last", to: fixDocument)
store.save()
fixRecorded.removeAll()
fixActions(untitled).onFocus()
fixActions(untitled).onEndEditing(NSTextStorage())
check(store.block(id: untitled.id) != nil && fixRecorded.isEmpty, "An untitled task with a note survives the caret passing")
fixActions(spacer).onFocus()
check(fixActions(spacer).onArrowOut(.down, 0) && store.block(id: spacer.id) != nil,
    "A blank line the caret passes through stays")
check(fixEditor.focus.blockID == belowSpacer.id && fixEditor.focus.caret == -1, "↓ puts the caret at the end of the next line")
fixEditor.commitLine()
let watering = store.appendBlock(kind: .task, text: "Water plants", to: fixDocument)
watering.dueDate = due
let trip = store.appendBlock(kind: .task, text: "Trip", to: fixDocument)
let tickets = store.insertChild(kind: .task, text: "Tickets", of: trip, at: .last)
store.save()
for emptied in [watering, trip] {
    fixActions(emptied).onFocus()
    fixActions(emptied).onChange(NSAttributedString())
    fixActions(emptied).onEndEditing(NSTextStorage())
}
check(store.block(id: watering.id) != nil && store.block(id: trip.id) != nil && tickets.parentID == trip.id,
    "A task emptied that holds a date, or has lines under it, keeps its line")
fixEditor.appendTask()
let labelled = store.block(id: fixEditor.focus.blockID!)!
fixActions(labelled).onChange(NSAttributedString(string: "#errands"))
fixEditor.commitLine()
check(store.block(id: labelled.id) != nil && !labelled.labelIDs.isEmpty, "A new line of only a label keeps its line and label")

// Taken out, a line's lines go where they show: not under a done task the document lists apart.
let doneAbove = store.appendBlock(kind: .task, text: "Done already", to: fixDocument)
let emptiedParent = store.appendBlock(kind: .task, text: "", to: fixDocument)
let stillOpen = store.insertChild(kind: .task, text: "Still open", of: emptiedParent, at: .last)
store.save()
doneAbove.isCompleted = true
store.save()
fixActions(emptiedParent).onFocus()
check(fixActions(emptiedParent).onBackspaceAtStart(NSAttributedString()) && store.block(id: emptiedParent.id) == nil
    && stillOpen.parentID == nil && fixShows(stillOpen.id), "Backspace in an empty line lifts its lines a level, past a done task above")

// A line that stops showing while it holds the caret lets the caret go.
fixActions(belowSpacer).onFocus()
fixEditor.visibleRowsDidChange(fixRows().map(\.id), from: fixRows().map(\.id).filter { $0 != belowSpacer.id })
check(fixEditor.focus.blockID == belowSpacer.id, "A line not drawn before keeps the caret sent to it")
fixEditor.visibleRowsDidChange(fixRows().map(\.id).filter { $0 != belowSpacer.id }, from: fixRows().map(\.id))
check(fixEditor.focus.blockID == nil, "A line folded or settled away while being written lets the caret go")

// The menu of a line that isn't a task.
let turned = store.appendBlock(kind: .heading2, text: "Food", to: fixDocument)
let underTurned = store.appendBlock(kind: .task, text: "Taste the yuba", to: fixDocument)
store.save()
fixEditor.turn(turned.id, into: .bullet)
check(turned.kind == .bullet, "Turn Into changes a line's kind")
_ = fixActions(underTurned).onTab(false, 0)
fixEditor.commitLine()
check(underTurned.parentID == turned.id, "A task goes under the list item it became")
fixEditor.deleteLine(turned.id)
check(store.block(id: turned.id) == nil && store.block(id: underTurned.id) != nil && fixShows(underTurned.id),
    "Delete takes the line out and keeps what was under it on show")

// Backspace in an empty first line takes the caret to the line below.
let firstList = store.createList(title: "Empty first line")
let firstDocument = DocumentContext(listID: firstList.id)
let firstEditor = OutlineEditor(env: outlineEnv, document: firstDocument)
let emptyFirst = store.appendBlock(kind: .task, text: "", to: firstDocument)
let secondLine = store.appendBlock(kind: .task, text: "Second", to: firstDocument)
store.save()
let firstRows = firstEditor.visibleRows(in: store.blocks(inList: firstList.id))
firstEditor.actions(for: firstRows[0]).onFocus()
check(firstEditor.actions(for: firstRows[0]).onBackspaceAtStart(NSAttributedString()) && store.block(id: emptyFirst.id) == nil
    && firstEditor.focus.blockID == secondLine.id && firstEditor.focus.caret == 0,
    "Backspace in an empty first line removes it and starts the line below")

// Showing only tasks, what headings and list items fold away still shows.
let tasksList = store.createList(title: "Tasks only")
let tasksDocument = DocumentContext(listID: tasksList.id)
let tasksEditor = OutlineEditor(env: outlineEnv, document: tasksDocument)
tasksEditor.tasksOnly = true
let laterSection = store.appendBlock(kind: .heading1, text: "Later", to: tasksDocument)
let inSection = store.appendBlock(kind: .task, text: "Pack", to: tasksDocument)
let shops = store.appendBlock(kind: .bullet, text: "Shops", to: tasksDocument)
let underShops = store.insertChild(kind: .task, text: "Tenugui", of: shops, at: .last)
let foldedTask = store.appendBlock(kind: .task, text: "Folded", to: tasksDocument)
let underFoldedTask = store.insertChild(kind: .task, text: "Hidden", of: foldedTask, at: .last)
store.save()
store.setCollapsed(true, for: laterSection)
store.setCollapsed(true, for: shops)
store.setCollapsed(true, for: foldedTask)
let onlyTasks = tasksEditor.visibleRows(in: store.blocks(inList: tasksList.id)).map(\.id)
check(onlyTasks == [inSection.id, underShops.id, foldedTask.id] && !onlyTasks.contains(underFoldedTask.id),
    "Showing only tasks, a folded heading or list item hides none, and a folded task still folds")

// A caret move is on its way until the line's text view carries it out,
// or a click puts the caret in another line. The list document holds the
// keys typed meanwhile for that line.
let movingList = store.createList(title: "Caret moves")
let movingDocument = DocumentContext(listID: movingList.id)
let movingEditor = OutlineEditor(env: outlineEnv, document: movingDocument)
let movingFirst = store.appendBlock(kind: .task, text: "First", to: movingDocument)
let movingSecond = store.appendBlock(kind: .task, text: "Second", to: movingDocument)
store.save()
func movingActions(_ block: Block) -> BlockRowActions {
    movingEditor.actions(for: movingEditor.visibleRows(in: store.blocks(inList: movingList.id)).first { $0.id == block.id }!)
}
check(movingEditor.appliedFocusToken == movingEditor.focus.token && !movingEditor.isMovingCaret, "No caret move is on its way before any is sent")
movingEditor.edit(movingFirst.id)
check(movingEditor.appliedFocusToken != movingEditor.focus.token && movingEditor.isMovingCaret, "A caret move is on its way once sent")
movingActions(movingFirst).onFocusApplied(movingEditor.focus.token)
check(movingEditor.appliedFocusToken == movingEditor.focus.token, "The line's text view carrying it out ends it")
movingEditor.edit(movingFirst.id, caret: 0)
check(movingEditor.appliedFocusToken != movingEditor.focus.token, "A move within the line holding the caret, as Tab's, is on its way too")
movingActions(movingSecond).onFocus()
check(movingEditor.appliedFocusToken == movingEditor.focus.token && movingEditor.focus.blockID == movingSecond.id,
    "A click into another line overtakes a move on its way")
movingActions(movingSecond).onMarkdownPrefix(.bullet)
check(movingSecond.kind == .bullet && movingEditor.focus.blockID == movingSecond.id
    && movingEditor.appliedFocusToken != movingEditor.focus.token,
    "A line turned into another kind sends the caret on to the text view that draws it")
movingEditor.commitLine()

print("✅ \(checks) editor/store checks passed")
