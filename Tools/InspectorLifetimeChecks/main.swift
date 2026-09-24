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
    let attachmentHost = NSHostingView(rootView: AttachmentRow(attachment: retainedAttachment, onDelete: {}).environment(env))
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
    /// What each Return handed over as the line's content.
    var commits: [String] = []
    let block: Block
    init(block: Block) { self.block = block }
    func change(_ content: NSAttributedString) {
        textChanges += 1
        store.setContent(block, attributed: content)
    }
    func commit(_ content: NSAttributedString) { commits.append(content.string) }
}
for paste in [false, true] {
    let block = store.appendBlock(kind: .task, to: .init(listID: list.id))
    store.save()
    let fixture = InlineEditorFixture(block: block)
    let editor = BlockTextView(blockID: block.id, kind: .task, isCompleted: false,
        attributedText: NSAttributedString(string: ""), isFocused: false, pendingCaret: nil, focusToken: 0,
        callbacks: BlockEditorCallbacks(onChange: fixture.change, onReturn: { _, content in fixture.commit(content); return true }))
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
    check(textView.coordinator!.textView(textView, doCommandBy: #selector(NSTextView.insertNewline(_:))) && fixture.commits.count == 1,
        "Native Return invokes the line's commit callback")
    check(fixture.commits == ["Call mum tomorrow"] && block.text == "Call mum tomorrow",
        "Native Return hands the whole typed or pasted title to its callback, and leaves it as the text view reported it")
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

// A file taken off a task in the inspector's Files is one Undo step: Undo
// puts the file back, its bytes and its cached copy too, and Redo takes it
// off again. Nothing goes for good in one click.
do {
    let undo = UndoManager()
    undo.groupsByEvent = false
    let task = store.appendBlock(kind: .task, text: "File the receipts", to: .init(listID: list.id))
    let original = fixtureDirectory.appendingPathComponent("Receipt.txt")
    try Data("receipt".utf8).write(to: original)
    let media = try MediaStore.shared.importFile(at: original)
    let file = Attachment(blockID: task.id, filename: media.filename, displayName: media.displayName,
        contentType: media.contentType, byteCount: media.byteCount, contentData: media.data)
    store.context.insert(file)
    store.save()
    let fileID = file.id
    var reported = 0
    undo.beginUndoGrouping()
    store.removeAttachment(file, name: "Removed “Receipt.txt” from “File the receipts”", undoManager: undo) { reported += 1 }
    undo.endUndoGrouping()
    check(reported == 1 && undo.canUndo, "Removing a file registers one Undo step and reports it")
    check(store.attachments(for: task.id).isEmpty, "Removing a file takes it off the task")
    check(MediaStore.shared.fileContents(filename: media.filename) == nil, "Removing a file lets its cached copy go")
    undo.undo()
    let restored = store.attachments(for: task.id)
    check(restored.map(\.id) == [fileID] && restored.first?.contentData == media.data, "Undo puts the same file back with its bytes")
    check(MediaStore.shared.fileContents(filename: media.filename) == media.data, "Undo puts the file's cached copy back")
    undo.redo()
    check(store.attachments(for: task.id).isEmpty, "Redo takes the file off again")
    undo.undo()
    check(store.attachments(for: task.id).first?.id == fileID, "Undo after Redo brings the file back again")
    // One on no live task just goes, with no step to take it back.
    let orphan = Attachment(blockID: UUID(), filename: "orphan.txt", displayName: "Orphan.txt",
        contentType: "text/plain", byteCount: 1, contentData: Data("o".utf8))
    store.context.insert(orphan)
    store.save()
    store.removeAttachment(orphan, name: "Removed “Orphan.txt”", undoManager: undo) { reported += 1 }
    check(reported == 1 && (orphan.modelContext == nil || orphan.isDeleted), "A file on no live task goes without a step")
}

// Defer… and its Clear, as the plan card's Workbench steps write them: the
// deferral takes the day and the slots, and its Undo, putting back only the
// fields it changed, restores the day it replaced. Clear lets a day still
// ahead go with the deferral; one that has come stays, as the task is
// planned for today by then.
do {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: .now)
    let later = calendar.date(byAdding: .day, value: 3, to: today)!
    let task = store.appendBlock(kind: .task, text: "Draft the report", to: .init(listID: list.id))
    store.selectForToday(task)
    let start = calendar.date(byAdding: .hour, value: 10, to: later)!
    store.setPlacement(for: task, start: start, end: start.addingTimeInterval(1800), isPinned: true)
    let planned = TaskFields(task)
    store.deferTask(task, to: later)
    let deferred = TaskFields(task)
    check(task.selectedForDay == later && task.deferredUntil == later, "Deferring selects the later day and waits for it")
    check(store.placements(taskID: task.id).isEmpty, "Deferring takes the task's slots on the calendar")
    planned.apply(to: task, replacing: deferred)
    check(task.selectedForDay == today && task.deferredUntil == nil, "Undoing a deferral puts back the day it replaced")
    deferred.apply(to: task, replacing: planned)
    let cleared = TaskFields(task)
    store.clearDeferral(task)
    check(task.deferredUntil == nil && task.selectedForDay == nil, "Clearing a deferral still ahead lets its day go with it")
    cleared.apply(to: task, replacing: TaskFields(task))
    check(task.deferredUntil == later && task.selectedForDay == later, "Undoing Clear defers the task again")
    store.clearDeferral(task, now: calendar.date(byAdding: .day, value: 1, to: later)!)
    check(task.deferredUntil == nil && task.selectedForDay == later, "Clearing a deferral whose day has come keeps the task planned")
    store.clearDeferral(task)
    check(task.selectedForDay == later, "Clear on a task with no deferral changes nothing")
}

// Defer…'s Undo and Redo, in the order Workbench.deferWork registers them:
// Undo rebuilds the occurrence's slots as `Workbench.setPlacements` does,
// then puts back the fields; Redo defers again. Any number of steps leaves
// one set, as it was, and another task's slot alone.
do {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: .now)
    let later = calendar.date(byAdding: .day, value: 2, to: today)!
    let task = store.appendBlock(kind: .task, text: "Book the venue", to: .init(listID: list.id))
    let other = store.appendBlock(kind: .task, text: "Send the invites", to: .init(listID: list.id))
    store.selectForToday(task)
    let pinnedStart = calendar.date(byAdding: .hour, value: 14, to: today)!
    let autoStart = calendar.date(byAdding: .hour, value: 16, to: today)!
    store.setPlacement(for: task, start: pinnedStart, end: pinnedStart.addingTimeInterval(2700), isPinned: true)
    store.setPlacement(for: task, start: autoStart, end: autoStart.addingTimeInterval(1800))
    store.setPlacement(for: other, start: pinnedStart, end: pinnedStart.addingTimeInterval(900), isPinned: true)
    let id = task.id
    let occurrenceID = task.occurrenceID
    typealias Span = (start: Date, end: Date, isPinned: Bool)
    func spans() -> [Span] {
        store.placements(taskID: id).filter { $0.occurrenceID == occurrenceID }.map { ($0.start, $0.end, $0.isPinned) }
    }
    func same(_ lhs: [Span], _ rhs: [Span]) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { $0.start == $1.start && $0.end == $1.end && $0.isPinned == $1.isPinned }
    }
    // Workbench.setPlacements: the occurrence's whole set, replaced in one save.
    func rebuild(_ spans: [Span]) {
        guard let task = store.block(id: id), task.occurrenceID == occurrenceID else { return }
        store.batch {
            for placement in store.placements(taskID: id) where placement.occurrenceID == occurrenceID {
                store.removePlacement(placement)
            }
            for span in spans { store.setPlacement(for: task, start: span.start, end: span.end, isPinned: span.isPinned) }
        }
    }
    let fields = TaskFields(task)
    let previous = spans()
    check(previous.count == 2, "The task to defer has a pinned and a planned slot")
    store.deferTask(task, to: later)
    let deferred = TaskFields(task)
    check(spans().isEmpty, "Deferring takes both of the task's slots")
    for step in 1...2 {
        rebuild(previous)
        fields.apply(to: task, replacing: deferred)
        store.save()
        check(same(spans(), previous), "Undoing a deferral puts back its slots as they were, pinned or not (step \(step))")
        check(task.selectedForDay == today && task.deferredUntil == nil, "Undoing a deferral puts back today over the rebuilt slots (step \(step))")
        store.deferTask(task, to: later)
        check(spans().isEmpty && task.selectedForDay == later && task.deferredUntil == later,
              "Redoing a deferral takes the slots and the day again (step \(step))")
    }
    check(store.placements(taskID: other.id).count == 1, "A deferral's Undo and Redo leave another task's slot alone")
}
// The label picker's rows, which Return picks from: the best match first,
// Create last and only for a name no label has.
do {
    let labels = ["Extra", "Travel", "tra", "Work"].map { TaskLabel(name: $0, accent: .blue) }
    let partial = LabelPicker.choices(for: "tra", in: [labels[0], labels[1]])
    check(partial.matches.map(\.name) == ["Travel", "Extra"] && partial.create == "tra",
          "Part of a name lists the label starting with it first, with Create after the matches")
    let exact = LabelPicker.choices(for: "#TRA", in: labels)
    check(exact.matches.map(\.name) == ["tra", "Travel", "Extra"] && exact.create == nil,
          "The name itself comes first, in any case, and offers no Create")
    let none = LabelPicker.choices(for: "home", in: labels)
    check(none.matches.isEmpty && none.create == "home", "With no match, Create is the only row")
    let all = LabelPicker.choices(for: "  ", in: labels)
    check(all.matches.map(\.name) == labels.map(\.name) && all.create == nil, "An empty query lists every label, in order")
    // Its highlight alone greys a row: the pointer resting on another row
    // doesn't add a second grey there after ↓ moves on.
    check(!NXPanelRowStyle.greys(highlighted: false, hovering: true, pressed: false)
            && NXPanelRowStyle.greys(highlighted: true, hovering: false, pressed: false),
          "In the label picker only the row Return picks is grey, wherever the pointer rests")
    check(NXPanelRowStyle.greys(highlighted: nil, hovering: true, pressed: false)
            && !NXPanelRowStyle.greys(highlighted: nil, hovering: false, pressed: false),
          "A menu row with no highlight to follow greys on hover")
}
print("✅ \(checks) hidden inspector copy/Undo/Redo lifetime checks passed")
