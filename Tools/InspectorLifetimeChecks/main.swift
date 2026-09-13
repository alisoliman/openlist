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
let source = store.appendBlock(kind: .task, text: "Copied task", to: .init(listID: list.id))
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
print("✅ \(checks) hidden inspector copy/Undo/Redo lifetime checks passed")
