import AppKit
import SwiftData
import SwiftUI

var checks = 0
func check(_ value: Bool, _ message: String) {
    precondition(value, message)
    checks += 1
}
let app = NSApplication.shared

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
    var body: some View {
        VStack {
            LabelPicker(block: block)
            AttachmentRow(attachment: attachment, onDelete: {})
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
    check(retained.text == "Do the weekly shop", "Fresh copy retains literal recurrence words")
    let retainedAttachment = store.attachments(for: id).first!
    let copiedFilename = retainedAttachment.filename
    check(copiedFilename != attachment.filename, "Copy attachment uses independent media filename")
    check(MediaStore.shared.fileContents(filename: copiedFilename) == attachment.contentData, "Copied file is readable before Undo")
    let descendants = BlockTree.descendants(of: id, in: store.blocks(inList: list.id))
    let retainedChild = descendants.first!
    let ids = Set([id] + descendants.map(\.id))
    let env = AppEnvironment(store: store)
    let host = NSHostingView(rootView: RetainedInspector(block: retained, attachment: retainedAttachment).environment(env))
    let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 380, height: 600),
                          styleMask: .borderless, backing: .buffered, defer: false)
    // Never order/activate this window or alter the coordinating native app.
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    check(host.fittingSize.height > 30, "Copied task's actual labels and file render before Undo")
    var removed: Set<UUID> = []
    store.onEditorBlocksRemoved = { values in
        removed = values
        check(store.block(id: id)?.modelContext != nil, "Inspector can close before copied models are invalidated")
    }
    undo.undo()
    check(removed == ids, "Structural Undo publishes the complete removed subtree")
    check(store.block(id: id) == nil, "Undo removes the inspected copied task")
    check(MediaStore.shared.fileContents(filename: copiedFilename) == nil, "Undo removes only the copied media file")
    check(retainedChild.modelContext == nil || retainedChild.isDeleted, "Undo invalidates the retained copied child task")
    check(retainedAttachment.modelContext == nil || retainedAttachment.isDeleted, "Undo invalidates the retained copied attachment")
    check(retained.modelContext == nil || retained.isDeleted, "Retained inspector model is invalidated by the saved deletion")
    check(store.labels(for: retained).isEmpty, "Late label lookup does not fault an invalidated model")
    // Force the retained views to render after the inspector would normally
    // disappear. Deleted models must neither fault nor show stale controls.
    host.rootView = RetainedInspector(block: retained, attachment: retainedAttachment).environment(env)
    host.layoutSubtreeIfNeeded()
    await Task.yield()
    host.layoutSubtreeIfNeeded()
    // A fresh host also evaluates every retained view after invalidation;
    // its intrinsic size is independent of the old window's fixed height.
    let invalidHost = NSHostingView(rootView: RetainedInspector(block: retained, attachment: retainedAttachment).environment(env))
    check(invalidHost.fittingSize.height < 30, "Deleted label picker and attachment render empty")
    let attachmentHost = NSHostingView(rootView: AttachmentRow(attachment: retainedAttachment, onDelete: {}))
    check(attachmentHost.fittingSize.height == 0, "Retained attachment renders empty independently")
    check(undo.canRedo, "Inspector invalidation leaves Redo available")
    undo.redo()
    let restored = store.block(id: id)!
    check(restored.text == "Do the weekly shop", "Redo keeps the complete literal title")
    if case .template = mode {
        check(restored.dueDate == nil && restored.recurrence == nil, "Opening restored template preserves its fresh schedule defaults")
    }
    host.rootView = RetainedInspector(block: restored, attachment: store.attachments(for: id).first!).environment(env)
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
// A row kept from before Undo of the paste that made its block, as the list
// document keeps the rows it last drew, answers identity and hashing from
// what it stored: the saved deletion leaves no model to read.
let destination = store.createList(title: "Retained pasted rows")
let fragment = try FragmentContent.capture([source.id], store: store)
for _ in 0..<3 {
    let undo = UndoManager()
    undo.groupsByEvent = false
    undo.beginUndoGrouping()
    let rootID = store.undoableEditorEdit(in: destination.id, name: "Paste content", undoManager: undo, includingNewLabels: true) {
        try! store.pasteFragment(fragment, in: .init(listID: destination.id), after: nil)[0]
    }
    undo.endUndoGrouping()
    let row = BlockRow(block: store.block(id: rootID)!, depth: 0, ordinal: 0, hasChildren: true, isCollapsed: false)
    undo.undo()
    check(store.block(id: rootID) == nil, "Undo takes the pasted subtree away")
    check(row.id == rootID && Set([row]).contains(row), "Retained row identity and hashing require no deleted model reads")
    undo.redo()
    check(store.block(id: rootID) != nil && store.attachments(for: rootID).count == 1, "Redo brings back a fresh model and its attachment")
    undo.undo()
}
// Exercise the actual native editor callbacks for typed and single-line pasted
// titles. A private pasteboard avoids changing the user's clipboard.
func nativeTextView(in view: NSView) -> BlockNSTextView? {
    if let text = view as? BlockNSTextView { return text }
    return view.subviews.lazy.compactMap { nativeTextView(in: $0) }.first
}
final class InlineEditorFixture {
    var textChanges = 0
    var commits = 0
    let block: Block
    init(block: Block) { self.block = block }
    func change(_ content: NSAttributedString) {
        textChanges += 1
        store.setContent(block, attributed: content)
    }
    func commit() { commits += 1 }
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
    check(textView.coordinator!.textView(textView, doCommandBy: #selector(NSTextView.insertNewline(_:))) && fixture.commits == 1,
        "Native Return invokes the line's commit callback")
    check(block.text == "Call mum tomorrow" && block.dueDate == nil, "A typed or pasted title stays as written, as a document line's does")
    window.contentView = nil
}

// The inspector's title, note and a label made in its picker go through the
// workbench as editor edits: Undo puts back only what the edit changed, and a
// label the edit made leaves with it and comes back, the same one, on Redo.
do {
    let undo = UndoManager()
    undo.groupsByEvent = false
    func edit(_ name: String, labels: Bool = false, _ body: () -> Void) {
        undo.beginUndoGrouping()
        store.undoableEditorEdit(in: list.id, name: name, undoManager: undo, includingNewLabels: labels, body)
        undo.endUndoGrouping()
    }
    let task = store.appendBlock(kind: .task, text: "Book flights", to: .init(listID: list.id))
    store.save()
    edit("Edited “Book trains”") { store.setText("Book trains", for: task) }
    // A popover schedules it meanwhile.
    store.setDueDate(.now, for: task)
    undo.undo()
    check(store.block(id: task.id)?.text == "Book flights", "Undoing an inspector title edit puts the title back")
    check(store.block(id: task.id)?.dueDate != nil, "Undoing an inspector title edit leaves a date set since")
    edit("Edited note on “Book flights”") { store.setNote("Window seat", for: task) }
    store.setPriority(.high, for: task)
    undo.undo()
    check(store.block(id: task.id)?.note == "", "Undoing an inspector note edit puts the note back")
    check(store.block(id: task.id)?.priority == .high, "Undoing an inspector note edit leaves a priority set since")
    edit("Added #travel · “Book flights”", labels: true) {
        if let label = store.findOrCreateLabel(named: "travel") { store.addLabel(label, to: task) }
    }
    let created = store.matchingLabels(named: "travel").first
    check(created.map { store.block(id: task.id)?.labelIDs.contains($0.id) == true } == true, "The picker's new label is on the task")
    undo.undo()
    check(store.matchingLabels(named: "travel").isEmpty, "Undo takes back the label the picker made")
    check(store.block(id: task.id)?.labelIDs.isEmpty == true, "Undo takes the new label off the task")
    undo.redo()
    check(store.matchingLabels(named: "travel").first?.id == created?.id, "Redo brings back the same label")
    check(created.map { store.block(id: task.id)?.labelIDs == [$0.id] } == true, "Redo puts the label back on the task")
}

// A design action's snapshot Undo and Redo, as the workbench runs them, write
// back only the fields the step changed: an estimate, label or due date set
// outside the undo stack meanwhile stays, and a repeat rule round-trips.
do {
    let task = store.appendBlock(kind: .task, text: "Water the plants", to: .init(listID: list.id))
    let monday = Calendar.current.date(byAdding: .day, value: 4, to: Calendar.current.startOfDay(for: .now))!
    store.setDueDate(monday, for: task)
    store.setTaskEstimate(30, for: task)
    let before = TaskFields(task)
    store.setPriority(.high, for: task)
    store.setRecurrence(.weekly, for: task)
    let after = TaskFields(task)
    let rule = task.recurrenceData
    // Meanwhile, with no step of their own: the estimate stepper, a label and a date.
    store.setTaskEstimate(45, for: task)
    let garden = store.findOrCreateLabel(named: "garden")!
    store.addLabel(garden, to: task)
    let friday = Calendar.current.date(byAdding: .day, value: 8, to: monday)!
    store.setDueDate(friday, for: task)
    before.apply(to: task, replacing: after)
    check(task.priority == .none && task.recurrence == nil, "Undo takes back the priority and repeat the step set")
    check(task.schedulingEstimateMinutes == 45 && task.labelIDs == [garden.id] && task.dueDate == friday,
          "Undo leaves the estimate, label and date set since")
    after.apply(to: task, replacing: before)
    check(task.priority == .high && task.recurrenceData == rule, "Redo puts back the priority and the same repeat rule")
    check(task.schedulingEstimateMinutes == 45 && task.labelIDs == [garden.id] && task.dueDate == friday,
          "Redo leaves the estimate, label and date set since")

    // Planning selects a task for its day; its Undo takes back only that.
    let plant = store.appendBlock(kind: .task, text: "Repot the fern", to: .init(listID: list.id))
    store.setTaskEstimate(30, for: plant)
    let unplanned = TaskFields(plant)
    let start = Calendar.current.date(byAdding: .hour, value: 10, to: monday)!
    store.setPlacement(for: plant, start: start, end: start.addingTimeInterval(1800), isPinned: true)
    let placed = TaskFields(plant)
    check(plant.selectedForDay != nil, "A placement selects an unselected task for its day")
    store.setTaskEstimate(60, for: plant)
    unplanned.apply(to: plant, replacing: placed)
    check(plant.selectedForDay == nil, "Undoing the plan takes back the day it selected")
    check(plant.schedulingEstimateMinutes == 60, "Undoing the plan leaves an estimate stepped since")
    store.save()
}
print("✅ \(checks) hidden inspector copy/Undo/Redo lifetime checks passed")
