import AppKit
import SwiftData

/// These are user operations against an isolated persistent library, including
/// later deletion between a move/completion and its old Undo action.
func runBulkTrashChecks(at directory: URL) throws {
    func checkThrowing(_ result: @autoclosure () throws -> Bool, _ message: String) rethrows {
        let value = try result()
        check(value, message)
    }
    let schema = Schema([TaskList.self, Block.self, SidebarSection.self, TaskLabel.self, Attachment.self,
                         ActivityEvent.self, WorkSession.self, CompletionRecord.self, SchedulePlacement.self])
    let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema,
        url: directory.appendingPathComponent("BulkTrash.store"), cloudKitDatabase: .none)])
    try MediaStore.shared.selectStartupDirectory(directory.appendingPathComponent("BulkTrashMedia"))
    var failNextSave = false
    let store = Store(context: container.mainContext) { context in
        if failNextSave { failNextSave = false; throw InjectedFailure.save }
        try context.save()
    }
    store.bootstrap()
    let source = store.createList(title: "Trash source")
    let otherList = store.createList(title: "Other Trash source")
    let destination = store.createList(title: "Live destination")
    func task(_ title: String, in list: TaskList) -> Block {
        store.appendBlock(kind: .task, text: title, to: DocumentContext(listID: list.id))
    }
    func records() throws -> [BackupBlock] {
        try store.context.fetch(FetchDescriptor<Block>()).map(BackupBlock.init).sorted { $0.id.uuidString < $1.id.uuidString }
    }
    func grouped(_ manager: UndoManager, _ body: () throws -> Void) rethrows {
        manager.beginUndoGrouping()
        defer { manager.endUndoGrouping() }
        try body()
    }
    let undo = UndoManager()
    undo.groupsByEvent = false
    let parent = task("Trash parent", in: source)
    let child = store.insertChild(text: "Trash child", of: parent)
    let other = task("Trash other list", in: otherList)
    let survivor = task("Unselected survivor", in: source)
    parent.note = "Keep parent note"
    child.isCompleted = true
    child.completedAt = .now
    child.richData = Data("rich child".utf8)
    let file = Attachment(blockID: child.id, filename: "bulk-retained.txt", displayName: "Retained file",
        contentType: "text/plain", byteCount: 4, contentData: Data("kept".utf8))
    store.context.insert(file)
    try store.persistChanges()
    let original = try records()
    let originalFile = BackupAttachment(file)
    var removed = Set<UUID>()
    store.onEditorBlocksRemoved = { removed.formUnion($0) }
    try grouped(undo) {
        let succeeded = try store.trashSelection([other.id, child.id, parent.id, other.id], undoManager: undo)
        check(succeeded, "Multi-list bulk Delete succeeds with repeated and parent-child selection")
    }
    check(removed == [parent.id, child.id, other.id], "Bulk Delete reports every removed descendant exactly once")
    let entries = try store.trashEntries()
    check(Set(entries.map(\.id)) == [parent.id, other.id] && child.trashID == parent.id,
          "Selected parent owns child once while each other-list root has its own recovery entry")
    check(store.block(id: survivor.id) != nil && undo.canUndo,
          "Successful bulk Delete leaves unselected content available and registers one Undo")
    let reader = ModelContext(container)
    let retained = try reader.fetch(FetchDescriptor<Block>()).filter { $0.isTrashed }
    check(Set(retained.map(\.id)) == [parent.id, child.id, other.id], "Independent reader sees the complete committed multi-list deletion")
    undo.undo()
    let recovered = try records().map { value in
        var value = value
        value.trashMetadataData = nil
        return value
    }
    check(recovered == original && BackupAttachment(file) == originalFile,
          "One bulk Delete Undo restores every persisted block field and attachment identity across both lists")
    try checkThrowing(try store.trashEntries().isEmpty, "Bulk Delete Undo removes both recovery entries")
    undo.redo()
    try checkThrowing(try store.trashEntries().count == 2 && child.trashID == parent.id,
          "One Redo retains canonical roots again without duplicating the selected child")
    undo.removeAllActions()

    let retainedState = try records()
    rejects("Stale retained selection cannot partially complete a live task") {
        _ = try store.setBulkCompletion(true, ids: [survivor.id, parent.id])
    }
    rejects("Stale retained selection cannot partially move a live task") {
        _ = try store.moveSelection([survivor.id, child.id], to: destination.id)
    }
    rejects("Stale retained selection cannot partially delete a live task") {
        _ = try store.trashSelection([survivor.id, other.id], undoManager: undo)
    }
    rejects("Retained parent cannot accept moved content") {
        _ = try store.moveSelection([survivor.id], to: source.id, parentID: parent.id)
    }
    rejects("Retained ordering anchor cannot accept a positional drop") {
        _ = try store.moveSelection([survivor.id], to: source.id, above: parent.id)
    }
    try checkThrowing(try records() == retainedState && !undo.canUndo,
          "Unavailable selections and destinations leave all persisted fields and Undo unchanged")
    let erasedIDs = [parent.id, child.id]
    check(store.permanentlyEraseTrash(ids: [parent.id]), "Selected subtree can be permanently erased after retention")
    let afterErase = try records()
    rejects("Permanently erased selection cannot partially move surviving content") {
        _ = try store.moveSelection([survivor.id, erasedIDs[0]], to: destination.id)
    }
    rejects("Permanently erased selection cannot partially delete surviving content") {
        _ = try store.trashSelection([survivor.id, erasedIDs[1]])
    }
    try checkThrowing(try records() == afterErase, "Stale identities after permanent erase cannot recreate or change content")

    // Save failure reports failure without registering recovery Undo or changing
    // any live retained fields; the caller can keep the same row selection.
    try store.persistChanges()
    failNextSave = true
    let failed = try store.trashSelection([survivor.id], undoManager: undo)
    check(!failed && store.trashError != nil && !undo.canUndo && !survivor.isTrashed,
          "Failed bulk Delete retains the row and reports failure without an Undo")
    try store.persistChanges()

    let undoRoot = task("Bulk Delete Undo root", in: source)
    let undoOther = task("Bulk Delete Undo other root", in: otherList)
    try grouped(undo) {
        let succeeded = try store.trashSelection([undoRoot.id, undoOther.id], undoManager: undo)
        check(succeeded, "A multi-list Delete is available for stale recovery Undo")
    }
    check(store.permanentlyEraseTrash(ids: [undoRoot.id]), "One bulk-deleted root is erased before Delete Undo")
    let beforeTrashUndo = try records()
    undo.undo()
    try checkThrowing(try records() == beforeTrashUndo && undoOther.isTrashed && !undo.canRedo && store.trashError != nil,
          "Old bulk Delete Undo cannot partially recover the remaining root after another was erased")
    undo.removeAllActions()

    // Move Undo may refer to an unchanged parent or to a list that was deleted
    // after moving out; neither old position is authority to revive that owner.
    for eraseOwner in [false, true] {
        let owner = task("Former parent \(eraseOwner)", in: source)
        let moved = store.insertChild(text: "Moved child \(eraseOwner)", of: owner)
        try store.persistChanges()
        try grouped(undo) { _ = try store.moveSelection([moved.id], to: destination.id, undoManager: undo) }
        check(store.trashBlocks([owner]), "Former parent is retained after its child moves out")
        if eraseOwner { check(store.permanentlyEraseTrash(ids: [owner.id]), "Former parent is permanently erased before move Undo") }
        let beforeUndo = try records()
        store.editorNotice = nil
        undo.undo()
        try checkThrowing(try records() == beforeUndo && store.editorNotice != nil && !undo.canRedo,
              "Move Undo refuses a retained or erased original parent without changing its live child")
        undo.removeAllActions()
    }
    for eraseList in [false, true] {
        let formerList = store.createList(title: "Former list \(eraseList)")
        let moved = task("Moved from list \(eraseList)", in: formerList)
        try grouped(undo) { _ = try store.moveSelection([moved.id], to: destination.id, undoManager: undo) }
        check(store.trashList(formerList), "Former list is retained after its task moves out")
        rejects("Retained list is unavailable to toolbar Move") { _ = try store.moveSelection([survivor.id], to: formerList.id) }
        if eraseList { check(store.permanentlyEraseTrash(ids: [formerList.id]), "Former list is erased before move Undo") }
        let beforeUndo = try records()
        store.editorNotice = nil
        undo.undo()
        try checkThrowing(try records() == beforeUndo && store.editorNotice != nil && !undo.canRedo,
              "Move Undo cannot put a task into a retained or erased original list")
        undo.removeAllActions()
    }

    for eraseMoved in [false, true] {
        let one = task("Moved root \(eraseMoved)", in: source)
        let two = task("Other moved root \(eraseMoved)", in: otherList)
        try grouped(undo) { _ = try store.moveSelection([one.id, two.id], to: destination.id, undoManager: undo) }
        check(store.trashBlocks([one]), "A moved root is retained before the earlier bulk Undo")
        if eraseMoved { check(store.permanentlyEraseTrash(ids: [one.id]), "Moved root is permanently erased before bulk Undo") }
        let beforeUndo = try records()
        store.editorNotice = nil
        undo.undo()
        try checkThrowing(try records() == beforeUndo && two.listID == destination.id && store.editorNotice != nil,
              "Bulk move Undo cannot partially restore surviving roots when another is retained or erased")
        undo.removeAllActions()
    }

    for eraseCompleted in [false, true] {
        let one = task("Completed root \(eraseCompleted)", in: source)
        let two = task("Other completed root \(eraseCompleted)", in: otherList)
        _ = try store.setBulkCompletion(true, ids: [one.id, two.id])
        let action = store.completionUndo!
        check(store.trashBlocks([one]), "Completed root is retained before completion Undo")
        if eraseCompleted { check(store.permanentlyEraseTrash(ids: [one.id]), "Completed root is erased before completion Undo") }
        let beforeUndo = try records()
        let historyIDs = Set(store.completionRecords().map(\.id))
        check(!store.undoCompletion(action.id), "Bulk completion Undo refuses retained or erased selected roots")
        try checkThrowing(try records() == beforeUndo && Set(store.completionRecords().map(\.id)) == historyIDs && two.isCompleted,
              "Rejected completion Undo preserves retained content, the other root and recorded history")
    }

    // A separately retained descendant stays with its recovery entry while the
    // active parent moves/completes; it never joins the transaction implicitly.
    let activeParent = task("Live parent with retained child", in: source)
    let retainedChild = store.insertChild(text: "Separately retained child", of: activeParent)
    try store.persistChanges()
    check(store.trashBlocks([retainedChild]), "A child can be retained separately from its live parent")
    let childState = BackupBlock(retainedChild)
    _ = try store.setBulkCompletion(true, ids: [activeParent.id])
    try grouped(undo) { _ = try store.moveSelection([activeParent.id], to: destination.id, undoManager: undo) }
    check(BackupBlock(retainedChild) == childState, "Moving and completing an active parent never rewrites its separately retained child")
    undo.undo()
    check(BackupBlock(retainedChild) == childState && activeParent.listID == source.id,
          "Move Undo also leaves separately retained descendants untouched")
}
