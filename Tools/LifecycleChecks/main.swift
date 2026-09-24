import AppKit
import SwiftData

var checks = 0, failures = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !condition() { failures += 1; print("FAIL  \(message)") }
}
let storeURL = URL(fileURLWithPath: CommandLine.arguments[1])
let phase = CommandLine.arguments[3]
let media = MediaStore.shared
let mediaFolder = media.url(for: "sentinel").deletingLastPathComponent()
if phase == "cleanup" {
    try? FileManager.default.removeItem(at: mediaFolder.deletingLastPathComponent().deletingLastPathComponent())
    exit(0)
}
let sentinel = storeURL.deletingLastPathComponent().appendingPathComponent("unrelated.txt")
let schema = Schema([TaskList.self, Block.self, SidebarSection.self, TaskLabel.self, Attachment.self, ActivityEvent.self, WorkSession.self, CompletionRecord.self, SchedulePlacement.self])
let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: storeURL)])
let store = Store(context: container.mainContext)
store.context.autosaveEnabled = false
func allBlocks() throws -> [Block] { try store.context.fetch(FetchDescriptor<Block>()) }
func allAttachments() throws -> [Attachment] { try store.context.fetch(FetchDescriptor<Attachment>()) }
func activityCount() throws -> Int { try store.context.fetchCount(FetchDescriptor<ActivityEvent>()) }
func file(_ name: String, content: String) throws { try media.restoreFile(Data(content.utf8), filename: name) }
func attach(_ filename: String, to block: Block) throws -> Attachment {
    try file(filename, content: filename)
    let value = Attachment(blockID: block.id, filename: filename, displayName: filename, contentType: "text/plain", byteCount: filename.utf8.count)
    store.context.insert(value)
    return value
}
func image(_ filename: String, parent: Block) throws -> Block {
    try file(filename, content: filename)
    let value = store.insertChild(kind: .image, of: parent)
    value.mediaFilename = filename
    return value
}

if phase == "prepare" {
    try "unrelated data".write(to: sentinel, atomically: true, encoding: .utf8)
    store.bootstrap()
    let inbox = store.inboxList()!
    let doomed = store.createList(title: "Delete list")
    let keep = store.createList(title: "Preserve list")
    let archived = store.createList(title: "Archived list")
    let section = store.createSection(title: "Delete section")
    store.move(list: keep, toSection: section.id, above: nil)
    store.move(list: archived, toSection: section.id, above: nil)
    let removeLabel = store.findOrCreateLabel(named: "remove-label")!
    let keepLabel = store.findOrCreateLabel(named: "keep-label")!
    let keepTask = store.appendBlock(kind: .task, text: "Preserve café 日本語 ✅", to: .init(listID: keep.id))
    let rich = NSMutableAttributedString(string: keepTask.text)
    RichTextCodec.toggleTrait(.boldFontMask, in: rich, range: NSRange(location: 0, length: 8), kind: .task)
    store.setContent(keepTask, attributed: rich)
    keepTask.note = "Keep note and metadata"
    keepTask.isStarred = true
    keepTask.priority = .high
    keepTask.dueDate = Date(timeIntervalSince1970: 2_100_000_000)
    keepTask.includesTime = true
    keepTask.reminderAt = keepTask.dueDate!.addingTimeInterval(-600)
    keepTask.recurrence = Recurrence(frequency: .weekly)
    keepTask.labelIDs = [removeLabel.id, keepLabel.id]
    let keepImage = try image("keep-image.png", parent: keepTask)
    let keepAttachment = try attach("keep.txt", to: keepTask)
    let removeAttachment = try attach("remove-attachment.txt", to: keepTask)
    let archivedTask = store.appendBlock(kind: .task, text: "Archived task", to: .init(listID: archived.id))
    archivedTask.labelIDs = [removeLabel.id]
    let inboxTask = store.appendBlock(kind: .task, text: "Inbox fixture", to: .init(listID: inbox.id))
    inboxTask.labelIDs = [removeLabel.id, keepLabel.id]
    _ = try image("inbox-image.png", parent: inboxTask)
    _ = try attach("inbox.txt", to: inboxTask)
    store.setArchived(true, for: archived)

    let doomedTask = store.appendBlock(kind: .task, text: "Doomed parent", to: .init(listID: doomed.id))
    doomedTask.dueDate = keepTask.dueDate
    doomedTask.reminderAt = keepTask.reminderAt
    let doomedImage = try image("delete-list.png", parent: doomedTask)
    _ = try attach("delete-list.txt", to: doomedImage)
    let doomedIDs = [doomedTask.id, doomedImage.id]
    store.refreshAllReminders()
    store.save()
    store.trashList(doomed)
    check(store.list(id: doomed.id) == nil && doomedIDs.allSatisfy { store.block(id: $0) == nil }, "Deleting a list removes parent and descendant blocks")
    check(store.attachments(for: doomedImage.id).count == 1, "Deleting a list retains descendant attachment records")
    check(media.fileContents(filename: "delete-list.png") != nil && media.fileContents(filename: "delete-list.txt") != nil, "Deleting a list retains image and attachment files")
    check(!NotificationService.shared.scheduled.contains(doomedTask.id), "Deleting a list cancels reminders")
    check(store.block(id: keepTask.id) != nil && media.fileContents(filename: "keep-image.png") != nil, "List deletion preserves unrelated list and media")
    store.trashList(inbox)
    check(store.inboxList()?.id == inbox.id && store.block(id: inboxTask.id) != nil, "System Inbox cannot be deleted")

    let removeBlock = store.appendBlock(kind: .task, text: "Delete block", to: .init(listID: keep.id))
    let removeImage = try image("delete-block.png", parent: removeBlock)
    _ = try attach("delete-block.txt", to: removeImage)
    let removedIDs = [removeBlock.id, removeImage.id]
    store.deleteBlocks([removeBlock, removeImage])
    check(removedIDs.allSatisfy { store.block(id: $0) == nil }, "Overlapping parent-child block deletion removes subtree once")
    check(store.attachments(for: removeImage.id).isEmpty && media.fileContents(filename: "delete-block.txt") == nil && media.fileContents(filename: "delete-block.png") == nil, "Subtree deletion removes all owned attachment records and files")
    check(store.block(id: keepImage.id)?.parentID == keepTask.id, "Subtree deletion preserves unrelated child relationship")

    // Exercise the model operations used by AttachmentRow removal. Its button
    // wiring and confirmation are deliberately outside these model checks.
    media.delete(filename: removeAttachment.filename)
    store.context.delete(removeAttachment)
    store.save()
    check(media.fileContents(filename: "remove-attachment.txt") == nil, "Removing an attachment deletes its owned file")
    check(store.attachments(for: keepTask.id).map(\.id) == [keepAttachment.id] && store.block(id: keepTask.id) != nil, "Attachment removal preserves task and other attachments")

    store.deleteLabel(removeLabel)
    let remaining = try allBlocks()
    check(!remaining.contains { $0.labelIDs.contains(removeLabel.id) }, "Label deletion removes references from active, archived and Inbox tasks")
    check(keepTask.labelIDs == [keepLabel.id] && inboxTask.labelIDs == [keepLabel.id], "Label deletion preserves other labels")
    store.deleteSection(section)
    check(store.list(id: keep.id) != nil && store.list(id: archived.id) != nil && keep.sectionID == nil && archived.sectionID == nil, "Section deletion preserves active and archived lists")
    let defaultSection = store.defaultSection()!
    store.deleteSection(defaultSection)
    check(store.defaultSection()?.id == defaultSection.id, "Default sidebar section cannot be deleted")

    // Undo of Delete Section and of a sidebar drag, as the Workbench registers them.
    let unfiled = store.sidebarPlacements()
    let undoSection = store.createSection(title: "Undo section")
    store.move(list: keep, toSection: undoSection.id, above: nil)
    store.move(list: archived, toSection: undoSection.id, above: keep)
    let filed = store.sidebarPlacements()
    let removed = store.removeSection(undoSection)
    check(removed?.lists.count == 2 && keep.sectionID == nil && archived.sectionID == nil && keep.isPinned,
          "Removing a section keeps what Undo needs, and its lists stay in the sidebar")
    check(store.removeSection(defaultSection) == nil, "The default section is never removed")
    store.move(list: archived, toSection: defaultSection.id, above: nil)
    check(removed.map(store.restoreSection) == true && store.allSections().contains { $0.id == undoSection.id && $0.title == "Undo section" },
          "Undo brings the section back under its own id")
    check(keep.sectionID == undoSection.id && keep.sidebarIndex == filed[keep.id]?.sidebarIndex && archived.sectionID == defaultSection.id,
          "Its lists go back in it where they sat, unless filed elsewhere since")
    let beforeDrag = store.sidebarPlacements()
    store.move(list: keep, toSection: defaultSection.id, above: archived)
    let afterDrag = store.sidebarPlacements()
    let dragged = afterDrag.filter { beforeDrag[$0.key] != $0.value }
    store.applySidebarPlacements(beforeDrag.filter { dragged[$0.key] != nil }, expecting: dragged)
    check(!dragged.isEmpty && store.sidebarPlacements() == beforeDrag, "Undoing a sidebar drag puts back exactly what it moved")
    store.applySidebarPlacements(afterDrag, expecting: beforeDrag)
    check(store.sidebarPlacements() == afterDrag, "Redoing it moves them again")
    store.deleteSection(store.allSections().first { $0.id == undoSection.id }!)
    store.applySidebarPlacements(unfiled, expecting: store.sidebarPlacements())
    check(store.sidebarPlacements() == unfiled, "The lists are back where the section checks left them")

    // A drop back where a list was moves nothing the sidebar shows, even when
    // the Store writes it a new index; one past a neighbour does.
    let slotSection = store.createSection(title: "Slot section")
    let slotLists = ["Slot A", "Slot B", "Slot C"].map { store.createList(title: $0) }
    for slotList in slotLists { store.move(list: slotList, toSection: slotSection.id, above: nil) }
    slotLists[1].sidebarIndex = slotLists[0].sidebarIndex + 10
    store.save()
    let slotB = store.sidebarSlot(of: slotLists[1].id), slotC = store.sidebarSlot(of: slotLists[2].id)
    let indexB = slotLists[1].sidebarIndex
    store.move(list: slotLists[1], toSection: slotSection.id, above: slotLists[2])
    check(slotB?.nextID == slotLists[2].id && slotLists[1].sidebarIndex != indexB && store.sidebarSlot(of: slotLists[1].id) == slotB,
          "A list dropped on the one below it keeps its slot, though its index changed")
    store.move(list: slotLists[2], toSection: slotSection.id, above: nil)
    check(slotC?.nextID == nil && store.sidebarSlot(of: slotLists[2].id) == slotC, "and one dropped at the end it's at keeps it too")
    store.move(list: slotLists[0], toSection: slotSection.id, above: slotLists[2])
    check(store.sidebarSlot(of: slotLists[0].id)?.nextID == slotLists[2].id, "One dropped past a neighbour takes a new slot")
    for slotList in slotLists { store.context.delete(slotList) }
    store.save()
    store.deleteSection(slotSection)

    // More than the former UI fetch cap, so clearing cannot silently leave
    // older records behind. Also covers the history step in reset.
    store.clearActivity()
    for index in 0..<10_001 {
        store.context.insert(ActivityEvent(kind: .created, title: "History \(index)"))
    }
    store.save()
    store.clearActivity()
    let count = try activityCount()
    check(count == 0, "Clear history removes all 10,001 events, including older history")
    check(store.block(id: keepTask.id) != nil && media.fileContents(filename: "keep.txt") != nil, "Clearing history preserves live tasks and attachments")
    store.save()
    check(store.persistenceError == nil, "Lifecycle mutations save to isolated disk store")
} else if phase == "reopen" {
    let keep = store.allLists(includeArchived: true).first { $0.title == "Preserve list" }!
    let keepTask = store.blocks(inList: keep.id).first { $0.isTask }!
    let archived = store.allLists(includeArchived: true).first { $0.title == "Archived list" }!
    check(store.allLists(includeArchived: true).count == 3 && archived.isArchived, "Fresh process reopens surviving Inbox, active and archived lists")
    check(keepTask.text == "Preserve café 日本語 ✅" && keepTask.note == "Keep note and metadata", "Unicode text and note survive reopening")
    check(keepTask.isStarred && keepTask.priority == .high && keepTask.includesTime && keepTask.recurrence?.frequency == .weekly && keepTask.dueDate == Date(timeIntervalSince1970: 2_100_000_000), "Schedule, priority, star and recurrence survive reopening")
    let content = store.attributedContent(of: keepTask)
    let font = content.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    check(font.map { NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } == true, "Stored rich-text emphasis survives reopening")
    check(store.allLabels().map(\.name) == ["keep-label"] && keepTask.labelIDs == store.allLabels().map(\.id), "Label deletion and retained references persist")
    let blocks = try allBlocks(), attachments = try allAttachments(), count = try activityCount()
    let blockIDs = Set(blocks.map(\.id))
    check(blocks.allSatisfy { $0.parentID == nil || blockIDs.contains($0.parentID!) } && attachments.allSatisfy { $0.blockID != nil && blockIDs.contains($0.blockID!) }, "Reopened store has no dangling block or attachment relationships")
    check(count == 0 && !blocks.contains { $0.text == "Delete block" || ($0.text == "Doomed parent" && !$0.isTrashed) }, "History and cascade deletions remain durable")
    check(media.fileContents(filename: "keep.txt") == Data("keep.txt".utf8) && media.fileContents(filename: "delete-list.txt") != nil, "Remaining and retained media bytes survive process restart")

    // Compose the same store operations as NXDataSettings.reset. Native
    // destructive confirmation and navigation are covered separately by UI QA.
    check(store.permanentlyResetLibrary(), "Confirmed library reset succeeds")
    let resetBlocks = try allBlocks(), resetAttachments = try allAttachments()
    check(store.allLists(includeArchived: true).count == 1 && store.inboxList() != nil, "Reset retains only the required Inbox")
    check(resetBlocks.isEmpty && resetAttachments.isEmpty && store.allLabels().isEmpty, "Reset clears tasks, notes, images, labels and attachment records")
    _ = media.fileContents(filename: "keep.txt")
    let mediaNames = try FileManager.default.contentsOfDirectory(atPath: mediaFolder.path)
    check(mediaNames.isEmpty, "Reset deletes every fixture media file")
    check(NotificationService.shared.scheduled.isEmpty && store.persistenceError == nil, "Reset cancels reminders and persists successfully")
} else if phase == "verify-reset" {
    let blocks = try allBlocks(), attachments = try allAttachments(), count = try activityCount()
    check(store.allLists(includeArchived: true).count == 1 && store.inboxList() != nil, "Fresh process reopens reset store with required Inbox")
    check(blocks.isEmpty && attachments.isEmpty && store.allLabels().isEmpty && count == 0, "Reset remains empty after separate-process reopening")
    let mediaNames = try FileManager.default.contentsOfDirectory(atPath: mediaFolder.path)
    check(mediaNames.isEmpty, "Reset media deletion persists after reopening")
    let untouched = try String(contentsOf: sentinel, encoding: .utf8)
    check(untouched == "unrelated data", "Destructive operations preserve unrelated files outside owned media")
}
print(failures == 0 ? "✅ \(checks) lifecycle checks passed (\(phase))" : "❌ \(failures)/\(checks) lifecycle checks failed (\(phase))")
exit(failures == 0 ? 0 : 1)
