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
let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
let store = Store(context: container.mainContext)
store.context.autosaveEnabled = false
store.bootstrap()
let list = store.createList(title: "Inspector lifetime fixture")
let source = store.appendBlock(kind: .task, text: "Copied task", to: .init(listID: list.id))
source.dueDate = .now.addingTimeInterval(3600)
source.recurrence = .weekly
let child = store.insertChild(of: source)
child.text = "Nested task"
let label = TaskLabel(name: "Fixture", accent: .blue)
store.context.insert(label)
source.labelIDs = [label.id]
try store.persistChanges()

struct RetainedInspector: View {
    let block: Block
    var body: some View {
        VStack {
            TaskInspectorMetadata(block: block)
            DueDateChip(block: block)
            TaskMetadataChips(block: block, labels: [], progress: nil)
            LabelPicker(block: block)
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
    let descendants = BlockTree.descendants(of: id, in: store.blocks(inList: list.id))
    let ids = Set([id] + descendants.map(\.id))
    let env = AppEnvironment(store: store)
    let host = NSHostingView(rootView: RetainedInspector(block: retained).environment(env))
    let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 380, height: 600),
                          styleMask: .borderless, backing: .buffered, defer: false)
    // Never order/activate this window or alter the coordinating native app.
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    check(host.fittingSize.height > 30, "Copied task's real metadata and label picker render before Undo")
    var removed: Set<UUID> = []
    store.onEditorBlocksRemoved = { values in
        removed = values
        check(store.block(id: id)?.modelContext != nil, "Inspector can close before copied models are invalidated")
    }
    undo.undo()
    check(removed == ids, "Structural Undo publishes the complete removed subtree")
    check(store.block(id: id) == nil, "Undo removes the inspected copied task")
    check(retained.modelContext == nil || retained.isDeleted, "Retained inspector model is invalidated by the saved deletion")
    check(store.labels(for: retained).isEmpty, "Late label lookup does not fault an invalidated model")
    // Force a retained child to render independently after the parent would
    // normally disappear. This reproduced the native SwiftData getter crash.
    host.rootView = RetainedInspector(block: retained).environment(env)
    host.layoutSubtreeIfNeeded()
    await Task.yield()
    host.layoutSubtreeIfNeeded()
    // A fresh host also evaluates every retained view after invalidation;
    // its intrinsic size is independent of the old window's fixed height.
    let invalidHost = NSHostingView(rootView: RetainedInspector(block: retained).environment(env))
    check(invalidHost.fittingSize.height < 30, "Deleted metadata/chips/picker render empty without touching persisted fields")
    check(undo.canRedo, "Inspector invalidation leaves Redo available")
    undo.redo()
    let restored = store.block(id: id)!
    host.rootView = RetainedInspector(block: restored).environment(env)
    host.layoutSubtreeIfNeeded()
    check(host.fittingSize.height > 30, "Redo's freshly resolved model renders in the inspector again")
    check(BlockTree.descendants(of: id, in: store.blocks(inList: list.id)).count == 1, "Redo restores the nested procedure")
    check(store.block(id: source.id)?.labelIDs == [label.id], "Undo/Redo leaves the source intact")
    store.onEditorBlocksRemoved = nil
    window.contentView = nil
}
print("✅ \(checks) hidden inspector copy/Undo/Redo lifetime checks passed")
