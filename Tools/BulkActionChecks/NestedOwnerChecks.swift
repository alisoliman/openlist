import AppKit
import SwiftData

/// A remote parent deletion can precede the child and its external cover bytes.
/// Exercise the normal sync-preparation path and real UndoManager while that
/// child is effectively unavailable but has not received its own Trash flag.
func runBulkNestedOwnerChecks(at directory: URL) throws {
    let schema = Schema([TaskList.self, Block.self, SidebarSection.self, TaskLabel.self, Attachment.self,
                         ActivityEvent.self, WorkSession.self, CompletionRecord.self, SchedulePlacement.self])
    let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema,
        url: directory.appendingPathComponent("BulkNestedOwners.store"), cloudKitDatabase: .none)])
    try MediaStore.shared.selectStartupDirectory(directory.appendingPathComponent("BulkNestedOwnerMedia"))
    let store = Store(context: container.mainContext)
    store.bootstrap()
    let live = store.createList(title: "Active document")
    func task(_ title: String, in list: TaskList) -> Block {
        store.appendBlock(kind: .task, text: title, to: DocumentContext(listID: list.id))
    }
    func documents(_ title: String) -> (parent: TaskList, child: TaskList) {
        let parent = store.createList(title: title)
        let child = store.createChildList(in: parent)!
        return (parent, child)
    }
    func records() throws -> [BackupBlock] {
        try store.context.fetch(FetchDescriptor<Block>()).map(BackupBlock.init).sorted { $0.id.uuidString < $1.id.uuidString }
    }
    func retainParentBeforeChild(_ parent: TaskList, child: TaskList) throws {
        parent.trashID = parent.id
        parent.trashMetadataData = try JSONEncoder().encode(TrashMetadata(deletedAt: .now,
            listTitle: parent.title, parentTitle: nil, labels: []))
        child.coverFilename = "pending-\(child.id).png"
        child.coverMetadataData = try JSONEncoder().encode(ListCoverMetadata(displayName: "Pending cover.png",
            contentType: "image/png", byteCount: 12, pixelWidth: 10, pixelHeight: 10))
        try store.persistChanges()
        store.prepareForSync()
        check(store.syncPreparationError != nil && child.trashID == nil && child.isEffectivelyTrashed
            && store.list(id: child.id) == nil, "Normal remote preparation keeps a child hidden while its cover bytes are unavailable")
    }
    func finishChildImport(_ parent: TaskList, child: TaskList) throws {
        child.coverData = Data(repeating: 0x35, count: 12)
        try store.persistChanges()
        store.prepareForSync()
        check(store.syncPreparationError == nil && child.trashID == parent.id,
            "Arriving cover bytes allow the original child to join its retained parent")
    }
    func grouped(_ manager: UndoManager, _ body: () throws -> Void) rethrows {
        manager.beginUndoGrouping()
        defer { manager.endUndoGrouping() }
        try body()
    }

    let owner = documents("Late source and destination")
    let late = task("Unavailable late task", in: owner.child)
    let active = task("Active task", in: live)
    try retainParentBeforeChild(owner.parent, child: owner.child)
    let before = try records()
    let undo = UndoManager(); undo.groupsByEvent = false
    rejects("A bulk destination under inherited Trash is unavailable before reconciliation") {
        _ = try store.moveSelection([active.id], to: owner.child.id, undoManager: undo)
    }
    rejects("A stale inherited-Trash source cannot escape or partially move active content") {
        _ = try store.moveSelection([active.id, late.id], to: live.id, undoManager: undo)
    }
    rejects("A stale inherited-Trash selection cannot partially complete active content") {
        _ = try store.setBulkCompletion(true, ids: [active.id, late.id])
    }
    rejects("A stale inherited-Trash selection cannot create a separate deletion group") {
        _ = try store.trashSelection([active.id, late.id], undoManager: undo)
    }
    let after = try records()
    check(after == before && !undo.canUndo, "Rejected stale bulk actions preserve every selected field and register no Undo")
    try finishChildImport(owner.parent, child: owner.child)
    check(active.listID == live.id && active.trashID == nil && late.trashID == owner.parent.id,
        "Later reconciliation neither absorbs the active task nor loses the retained source task")

    let undoOwner = documents("Undo destination")
    let undoTask = task("Moved before parent deletion", in: undoOwner.child)
    try grouped(undo) { _ = try store.moveSelection([undoTask.id], to: live.id, undoManager: undo) }
    try retainParentBeforeChild(undoOwner.parent, child: undoOwner.child)
    let beforeUndo = try records()
    store.editorNotice = nil
    undo.undo()
    let afterUndo = try records()
    check(afterUndo == beforeUndo && undoTask.listID == live.id && store.editorNotice != nil && !undo.canRedo,
        "Real move Undo refuses a former child document hidden by inherited Trash")
    try finishChildImport(undoOwner.parent, child: undoOwner.child)
    check(undoTask.listID == live.id && undoTask.trashID == nil && store.block(id: undoTask.id) != nil,
        "A rejected Undo cannot cause later sync to retain the active task")
    undo.removeAllActions()

    let redoOwner = documents("Redo destination")
    let redoTask = task("Task with a stale Redo destination", in: live)
    try grouped(undo) { _ = try store.moveSelection([redoTask.id], to: redoOwner.child.id, undoManager: undo) }
    undo.undo()
    check(redoTask.listID == live.id && undo.canRedo, "Control Undo leaves a real Redo to the child document")
    try retainParentBeforeChild(redoOwner.parent, child: redoOwner.child)
    let beforeRedo = try records()
    store.editorNotice = nil
    undo.redo()
    let afterRedo = try records()
    check(afterRedo == beforeRedo && redoTask.listID == live.id && redoTask.trashID == nil && store.editorNotice != nil,
        "Real Redo refuses an inherited-Trash destination without moving active content")
    try finishChildImport(redoOwner.parent, child: redoOwner.child)
    check(redoTask.trashID == nil, "Later sync also preserves active content after rejected Redo")
    undo.removeAllActions()

    let sourceOwner = documents("Redo source")
    let sourceTask = task("Task with a stale Redo source", in: sourceOwner.child)
    try grouped(undo) { _ = try store.moveSelection([sourceTask.id], to: live.id, undoManager: undo) }
    undo.undo()
    check(sourceTask.listID == sourceOwner.child.id && undo.canRedo, "Control Undo restores a future retained source")
    try retainParentBeforeChild(sourceOwner.parent, child: sourceOwner.child)
    let beforeSourceRedo = try records()
    store.editorNotice = nil
    undo.redo()
    let afterSourceRedo = try records()
    check(afterSourceRedo == beforeSourceRedo && sourceTask.listID == sourceOwner.child.id && sourceTask.trashID == nil && store.editorNotice != nil,
        "Real Redo cannot extract content from an inherited-Trash source")
    try finishChildImport(sourceOwner.parent, child: sourceOwner.child)
    check(sourceTask.trashID == sourceOwner.parent.id, "Rejected source Redo preserves eventual parent retention ownership")
}
