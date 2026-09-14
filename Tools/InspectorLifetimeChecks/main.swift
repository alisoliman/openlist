import AppKit
import SwiftData
import SwiftUI

var checks = 0
func check(_ value: Bool, _ message: String) {
    precondition(value, message)
    checks += 1
}
let app = NSApplication.shared

for event: NSEvent.EventType? in [nil, .keyDown, .keyUp, .flagsChanged, .mouseMoved, .scrollWheel, .applicationDefined] {
    check(!Theme.Motion.allowsAnimation(reduceMotion: false, eventType: event),
        "Keyboard, scrolling, hovering and background updates never opt into motion")
}
for event: NSEvent.EventType in [.leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp] {
    check(Theme.Motion.allowsAnimation(reduceMotion: false, eventType: event), "Pointer actions allow brief feedback")
    check(!Theme.Motion.allowsAnimation(reduceMotion: true, eventType: event), "Reduce Motion removes pointer movement too")
}
check(Theme.Motion.feedbackDuration >= 0.1 && Theme.Motion.feedbackDuration <= 0.16,
    "Press feedback stays within 100-160 milliseconds")
check(Theme.Motion.rearrangementDuration <= 0.25, "Task movement is brief and has no added delay")

var selectionPresses = 0
var lastSelectionStep: (Int, Bool)?
func selectionConfiguration(revealed: Bool = false, selected: Bool = false, focused: Bool = false) -> RowSelectionControl {
    RowSelectionControl(title: "Selection fixture", isSelected: selected, isSelectionFocus: focused,
        requestsKeyboardFocus: false, defersPlainClick: false, isRevealed: revealed,
        onSelect: { if case .toggle = $0 { selectionPresses += 1 } },
        onStep: { lastSelectionStep = ($0, $1) }, onClear: {}, onFocusRequestHandled: {},
        onDrag: { "" }, onDragEnd: {})
}
let selectionControl = RowSelectionNSControl(frame: NSRect(x: 0, y: 0, width: 22, height: 26))
selectionControl.appearance = NSAppearance(named: .aqua)
func selectionImage() -> Data {
    let image = NSImage(size: selectionControl.bounds.size)
    image.lockFocus()
    NSColor.clear.setFill()
    selectionControl.bounds.fill(using: .copy)
    selectionControl.draw(selectionControl.bounds)
    image.unlockFocus()
    return image.tiffRepresentation!
}
selectionControl.configuration = selectionConfiguration()
let quietGutter = selectionImage()
selectionControl.configuration = selectionConfiguration(revealed: true)
check(selectionImage() != quietGutter, "Hover reveals the native selection glyph without replacing the control")
selectionControl.configuration = selectionConfiguration(selected: true)
check(selectionImage() != quietGutter, "Selected rows retain a visible native selection glyph")
selectionControl.configuration = selectionConfiguration(focused: true)
check(selectionImage() != quietGutter, "Keyboard row focus retains the visible selection ring")
selectionControl.configuration = selectionConfiguration()
check(selectionImage() == quietGutter, "An idle, unselected gutter returns to its quiet appearance")
check(selectionControl.bounds.size == CGSize(width: 22, height: 26), "Gutter hit target never shrinks or shifts")
check(selectionControl.isAccessibilityElement() && selectionControl.acceptsFirstResponder,
    "Quiet glyphs remain in accessibility and keyboard navigation")
check(selectionControl.accessibilityPerformPress() && selectionPresses == 1,
    "Accessibility can activate an idle selection handle")
let space = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
    windowNumber: 0, context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49)!
selectionControl.keyDown(with: space)
check(selectionPresses == 2, "Space still toggles an idle selection handle")
let down = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .shift, timestamp: 0,
    windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 125)!
selectionControl.keyDown(with: down)
check(lastSelectionStep?.0 == 1 && lastSelectionStep?.1 == true, "Shift-arrow still extends row selection")

let schema = Schema([TaskList.self, Block.self, SidebarSection.self, TaskLabel.self, Attachment.self,
    ActivityEvent.self, WorkSession.self, CompletionRecord.self, SchedulePlacement.self])
let fixtureDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("OpenlistInspectorLifetime-\(UUID())")
try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: fixtureDirectory) }
let configuration = ModelConfiguration(schema: schema, url: fixtureDirectory.appendingPathComponent("fixture.store"), cloudKitDatabase: .none)
let container = try ModelContainer(for: schema, configurations: [configuration])
let store = Store(context: container.mainContext)
store.context.autosaveEnabled = false
store.bootstrap()
let list = store.createList(title: "Inspector lifetime fixture")
let source = store.appendBlock(kind: .task, text: "Do the weekly shop", to: .init(listID: list.id))
source.dueDate = .now.addingTimeInterval(3600)
source.recurrence = .weekly
let child = store.insertChild(of: source)
child.text = "Nested task"
let label = TaskLabel(name: "Fixture", accent: .blue)
store.context.insert(label)
source.labelIDs = [label.id]
let attachment = Attachment(blockID: source.id, filename: "fixture.txt", displayName: "Instructions.txt",
    contentType: "text/plain", byteCount: 7, contentData: Data("fixture".utf8))
store.context.insert(attachment)
try store.persistChanges()

struct RetainedInspector: View {
    let block: Block
    let attachment: Attachment
    let child: Block
    var body: some View {
        VStack {
            InboxMembershipButton(block: block)
            TaskInspectorMetadata(block: block)
            DueDateChip(block: block)
            TaskMetadataChips(block: block, labels: [], progress: nil)
            LabelPicker(block: block)
            AttachmentRow(attachment: attachment, onDelete: {})
            BlockRowView(row: BlockRow(block: child, depth: 0, ordinal: 0, hasChildren: false, isCollapsed: false),
                listAccent: .blue, labels: [], progress: nil, isFocused: false, isSelected: false,
                pendingCaret: nil, focusToken: 0, isSlashMenuOpen: false, onSlashCommand: { _ in },
                attributedText: NSAttributedString(string: "Nested task"), placeholder: "", showsPlaceholder: false,
                actions: BlockRowActions())
            BlockContextMenu(block: child, actions: BlockRowActions())
        }
    }
}

for mode in [CopyMode.duplicate, .template(keepingRecurrence: false)] {
    let undo = UndoManager()
    undo.groupsByEvent = false
    undo.beginUndoGrouping()
    let id = try store.undoableEditorEdit(in: list.id, name: "Copy task", undoManager: undo) {
        Result { try store.copyBlock(source, mode: mode) }
    }.get()
    undo.endUndoGrouping()
    let retained = store.block(id: id)!
    var inlineEdits = InlineMetadataEdits()
    check(!inlineEdits.consume(for: retained), "Opening a fresh copy preserves literal title without parsing")
    check(retained.text == "Do the weekly shop", "Fresh copy retains literal recurrence words")
    let retainedAttachment = store.attachments(for: id).first!
    let copiedFilename = retainedAttachment.filename
    check(copiedFilename != attachment.filename, "Copy attachment uses independent media filename")
    check(MediaStore.shared.fileContents(filename: copiedFilename) == attachment.contentData, "Copied file is readable before Undo")
    let descendants = BlockTree.descendants(of: id, in: store.blocks(inList: list.id))
    let retainedChild = descendants.first!
    let ids = Set([id] + descendants.map(\.id))
    let env = AppEnvironment(store: store)
    let host = NSHostingView(rootView: RetainedInspector(block: retained, attachment: retainedAttachment, child: retainedChild).environment(env))
    let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 380, height: 600),
                          styleMask: .borderless, backing: .buffered, defer: false)
    // Never order/activate this window or alter the coordinating native app.
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    check(host.fittingSize.height > 30, "Copied task's actual metadata, file and nested row render before Undo")
    var removed: Set<UUID> = []
    store.onEditorBlocksRemoved = { values in
        removed = values
        check(store.block(id: id)?.modelContext != nil, "Inspector can close before copied models are invalidated")
    }
    // A pending local edit from the removed model must not authorize a later
    // Redo instance with the same UUID, even if its title is identical.
    store.setText("Draft title", for: retained)
    inlineEdits.recordTextChange(for: retained, to: "Do the weekly shop")
    store.setText("Do the weekly shop", for: retained)
    var beforeUndoEdits = inlineEdits
    check(beforeUndoEdits.consume(for: retained), "Original copied model has a pending local edit before Undo")
    undo.undo()
    check(removed == ids, "Structural Undo publishes the complete removed subtree")
    check(store.block(id: id) == nil, "Undo removes the inspected copied task")
    check(MediaStore.shared.fileContents(filename: copiedFilename) == nil, "Undo removes only the copied media file")
    check(retainedChild.modelContext == nil || retainedChild.isDeleted, "Undo invalidates the retained copied child task")
    check(retainedAttachment.modelContext == nil || retainedAttachment.isDeleted, "Undo invalidates the retained copied attachment")
    check(retained.modelContext == nil || retained.isDeleted, "Retained inspector model is invalidated by the saved deletion")
    check(store.labels(for: retained).isEmpty, "Late label lookup does not fault an invalidated model")
    // Force a retained child to render independently after the parent would
    // normally disappear. Deleted models must neither fault nor show stale controls.
    host.rootView = RetainedInspector(block: retained, attachment: retainedAttachment, child: retainedChild).environment(env)
    host.layoutSubtreeIfNeeded()
    await Task.yield()
    host.layoutSubtreeIfNeeded()
    // A fresh host also evaluates every retained view after invalidation;
    // its intrinsic size is independent of the old window's fixed height.
    let invalidHost = NSHostingView(rootView: RetainedInspector(block: retained, attachment: retainedAttachment, child: retainedChild).environment(env))
    check(invalidHost.fittingSize.height < 30, "Deleted metadata, chips, label picker, attachment, nested row and menu render empty")
    let attachmentHost = NSHostingView(rootView: AttachmentRow(attachment: retainedAttachment, onDelete: {}))
    check(attachmentHost.fittingSize.height == 0, "Retained attachment renders empty independently")
    let menuHost = NSHostingView(rootView: BlockContextMenu(block: retainedChild, actions: BlockRowActions()).environment(env))
    check(menuHost.fittingSize.height == 0, "Retained nested task menu renders empty independently")
    check(undo.canRedo, "Inspector invalidation leaves Redo available")
    undo.redo()
    let restored = store.block(id: id)!
    check(!inlineEdits.consume(for: restored), "Opening Redo's restored copy does not authorize parsing")
    check(restored.text == "Do the weekly shop", "Redo keeps the complete literal title")
    if case .template = mode {
        check(restored.dueDate == nil && restored.recurrence == nil, "Opening restored template preserves its fresh schedule defaults")
    }
    host.rootView = RetainedInspector(block: restored, attachment: store.attachments(for: id).first!, child: BlockTree.descendants(of: id, in: store.blocks(inList: list.id)).first!).environment(env)
    host.layoutSubtreeIfNeeded()
    check(host.fittingSize.height > 30, "Redo's freshly resolved model renders in the inspector again")
    check(MediaStore.shared.fileContents(filename: copiedFilename) == attachment.contentData, "Redo restores independent copied media")
    check(store.attachments(for: id).first?.filename == copiedFilename, "Redo restores the original copied attachment identity")
    check(BlockTree.descendants(of: id, in: store.blocks(inList: list.id)).count == 1, "Redo restores the nested procedure")
    check(store.attachments(for: source.id).first?.id == attachment.id, "Undo/Redo leaves the source attachment intact")
    check(store.block(id: source.id)?.labelIDs == [label.id], "Undo/Redo leaves the source intact")
    store.onEditorBlocksRemoved = nil
    window.contentView = nil
}
// Keep the actual outer DocumentView/@Query/ForEach alive while its inserted
// models are invalidated. The row's own liveness guard cannot protect label
// lookup and rich-content reads performed by this parent builder.
let destination = store.createList(title: "Retained pasted document")
let fragment = try FragmentContent.capture([source.id], store: store)
let documentEnvironment = AppEnvironment(store: store)
func documentFixture(_ identity: Int) -> some View {
    DocumentView(document: .init(listID: destination.id))
        .frame(width: 540, height: 600, alignment: .top)
        .environment(documentEnvironment).modelContainer(container)
        .environment(\.modelContext, store.context).id(identity)
}
let documentHost = NSHostingView(rootView: documentFixture(0))
let documentWindow = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 540, height: 600),
    styleMask: .borderless, backing: .buffered, defer: false)
documentWindow.contentView = documentHost
documentHost.layoutSubtreeIfNeeded()
for iteration in 0..<3 {
    let undo = UndoManager(); undo.groupsByEvent = false
    undo.beginUndoGrouping()
    let rootID = store.undoableEditorEdit(in: destination.id, name: "Paste content", undoManager: undo, includingNewLabels: true) {
        try! store.pasteFragment(fragment, in: .init(listID: destination.id), after: nil)[0]
    }
    undo.endUndoGrouping()
    // A hidden window has no display-link driven lazy materialization. Mount
    // the actual query after insertion, then retain it throughout invalidation.
    documentHost.rootView = documentFixture(iteration + 1)
    try await Task.sleep(for: .milliseconds(100))
    _ = documentHost.fittingSize
    documentHost.layoutSubtreeIfNeeded()
    _ = documentHost.accessibilityChildren()
    func nativeTextViews(in view: NSView) -> [BlockNSTextView] {
        (view as? BlockNSTextView).map { [$0] } ?? view.subviews.flatMap { nativeTextViews(in: $0) }
    }
    // NSView's subview order is not the document's reading order.
    check(nativeTextViews(in: documentHost).contains { $0.string == fragment.blocks[0].text },
        "Actual DocumentView materializes the pasted row before invalidation")
    let retained = store.block(id: rootID)!
    let row = BlockRow(block: retained, depth: 0, ordinal: 0, hasChildren: true, isCollapsed: false)
    documentEnvironment.navigator.openTask(rootID)
    undo.undo()
    documentHost.layoutSubtreeIfNeeded()
    _ = documentHost.accessibilityChildren()
    await Task.yield()
    documentHost.layoutSubtreeIfNeeded()
    check(store.block(id: rootID) == nil, "Actual retained DocumentView survives pasted subtree Undo and accessibility layout")
    check(row.id == rootID && Set([row]).contains(row), "Retained row identity and hashing require no deleted model reads")
    undo.redo()
    await Task.yield()
    documentHost.layoutSubtreeIfNeeded()
    _ = documentHost.accessibilityChildren()
    check(store.block(id: rootID) != nil && store.attachments(for: rootID).count == 1,
        "Retained document renders Redo's fresh model and attachment")
    undo.undo()
    await Task.yield()
}
documentWindow.contentView = nil
// Exercise the actual native editor callbacks for typed and single-line pasted
// capture. A private pasteboard avoids changing the user's clipboard.
func nativeTextView(in view: NSView) -> BlockNSTextView? {
    if let text = view as? BlockNSTextView { return text }
    return view.subviews.lazy.compactMap { nativeTextView(in: $0) }.first
}
final class InlineEditorFixture {
    var edits = InlineMetadataEdits()
    var textChanges = 0
    let block: Block
    init(block: Block) { self.block = block }
    func change(_ content: NSAttributedString) {
        textChanges += 1
        edits.recordTextChange(for: block, to: content.string)
        store.setContent(block, attributed: content)
    }
    func commit() {
        if edits.consume(for: block) {
            store.applyInlineMetadata(to: block, parsesNaturalLanguage: true)
        }
    }
}
for paste in [false, true] {
    let block = store.appendBlock(kind: .task, to: .init(listID: list.id))
    store.save()
    let fixture = InlineEditorFixture(block: block)
    let editor = BlockTextView(blockID: block.id, kind: .task, isCompleted: false,
        attributedText: NSAttributedString(string: ""), isFocused: false, pendingCaret: nil, focusToken: 0,
        callbacks: BlockEditorCallbacks(onChange: fixture.change, onReturn: { _, _ in fixture.commit(); return true }))
    let host = NSHostingView(rootView: editor)
    let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 380, height: 80),
        styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    let textView = nativeTextView(in: host)!
    check(fixture.textChanges == 0, "Mounting an editor does not mark a title as locally edited")
    if paste {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("Call mum tomorrow", forType: .string)
        check(textView.readSelection(from: pasteboard, type: .string), "Native single-line paste accepts task text")
    } else {
        textView.insertText("Call mum tomorrow", replacementRange: NSRange(location: 0, length: 0))
    }
    check(fixture.textChanges > 0 && block.text == "Call mum tomorrow", "Native typing or single-line paste reports a local text change")
    check(textView.coordinator!.textView(textView, doCommandBy: #selector(NSTextView.insertNewline(_:))),
        "Native Return invokes the inline commit callback")
    check(block.text == "Call mum" && block.dueDate != nil, "Typed or pasted capture still applies date metadata on Return")
    check(!fixture.edits.consume(for: block), "A later Open Details action cannot reparse committed capture")
    window.contentView = nil
}
print("✅ \(checks) hidden inspector copy/Undo/Redo lifetime checks passed")
