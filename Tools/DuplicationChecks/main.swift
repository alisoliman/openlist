import AppKit
import SwiftData

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
let media = MediaStore.shared
let mediaFolder = media.url(for: "sentinel").deletingLastPathComponent()
defer { try? FileManager.default.removeItem(at: mediaFolder.deletingLastPathComponent().deletingLastPathComponent()) }
let originalImage = "source.png", originalFile = "source.txt"
let imageBytes = Data([0, 12, 250, 255]), fileBytes = Data("Original attachment".utf8)
try media.restoreFile(imageBytes, filename: originalImage)
try media.restoreFile(fileBytes, filename: originalFile)
let list = store.createList(title: "Duplication fixtures")
list.completedVisibility = .hide
list.availabilityCategoryRaw = "personal"
let document = DocumentContext(listID: list.id)
let parent = store.appendBlock(kind: .task, text: "Parent", to: document)
parent.note = "Preserve this note"
parent.dueDate = Date.now.addingTimeInterval(3600)
parent.isStarred = true
parent.priority = .high
let child = store.insertChild(kind: .image, of: parent)
child.mediaFilename = originalImage
child.mediaCaption = "Original caption"
child.mediaWidth = 512
child.mediaHeight = 256
let attachment = Attachment(blockID: child.id, filename: originalFile, displayName: "Shared name.txt", contentType: "text/plain", byteCount: fileBytes.count, sortIndex: 9)
attachment.createdAt = Date(timeIntervalSince1970: 1000)
store.context.insert(attachment)
store.save()

let duplicatedList = store.duplicateList(list)
check(duplicatedList.id != list.id && !duplicatedList.showsCompleted, "Duplicate list preserves display preferences")
check(duplicatedList.completedVisibility == .hide && !duplicatedList.showsCompleted(default: true), "Duplicate list preserves explicit completed visibility")
check(duplicatedList.availabilityCategoryRaw == "personal", "Duplicate list preserves calendar availability alongside completed visibility")
store.setCompletedVisibility(.inherit, for: duplicatedList)
check(duplicatedList.showsCompleted(default: true) && !duplicatedList.showsCompleted(default: false), "Store can reset a list to the changing global default")
let listCopies = store.blocks(inList: duplicatedList.id)
check(listCopies.count == 2, "Duplicate list contains complete tree")
let copiedParent = listCopies.first { $0.kind == .task }!
let copiedImage = listCopies.first { $0.kind == .image }!
check(copiedImage.parentID == copiedParent.id, "Duplicate list rekeys parent relationship")
check(copiedParent.note == parent.note && copiedParent.dueDate == parent.dueDate && copiedParent.isStarred && copiedParent.priority == .high, "Duplicate task preserves metadata")
check(copiedImage.mediaFilename != originalImage && media.fileContents(filename: copiedImage.mediaFilename!) == imageBytes, "List image has independent complete file")
check(copiedImage.mediaCaption == child.mediaCaption && copiedImage.mediaWidth == 512 && copiedImage.mediaHeight == 256, "Image caption and dimensions preserved")
let copiedAttachment = store.attachments(for: copiedImage.id).first!
check(copiedAttachment.filename != originalFile && media.fileContents(filename: copiedAttachment.filename) == fileBytes, "List attachment has independent complete file")
check(copiedAttachment.displayName == attachment.displayName && copiedAttachment.createdAt == attachment.createdAt && copiedAttachment.contentType == attachment.contentType && copiedAttachment.sortIndex == attachment.sortIndex, "Attachment metadata preserved")
store.trashList(duplicatedList)
check(media.fileContents(filename: originalImage) == imageBytes && media.fileContents(filename: originalFile) == fileBytes, "Deleting duplicate list leaves original media intact")

let blockCopy = store.duplicateBlock(child)
check(blockCopy.id != child.id && blockCopy.parentID == parent.id, "Block duplicate preserves tree position")
check(blockCopy.mediaFilename != originalImage && media.fileContents(filename: blockCopy.mediaFilename!) == imageBytes, "Block duplicate owns its image")
check(store.attachments(for: blockCopy.id).first?.filename != originalFile, "Block duplicate owns its attachment")
store.deleteBlock(blockCopy)
check(media.fileContents(filename: originalImage) == imageBytes && media.fileContents(filename: originalFile) == fileBytes, "Deleting duplicate block leaves original media intact")

// Missing attachment is reached after successfully copying the image, forcing
// rollback of staged files rather than merely testing an initial precondition.
attachment.filename = "missing-file.txt"
let namesBefore = try FileManager.default.contentsOfDirectory(atPath: mediaFolder.path).sorted()
let listIDsBefore = store.allLists(includeArchived: true).map(\.id)
let blockIDsBefore = store.blocks(inList: list.id).map(\.id)
let failedList = store.duplicateList(list)
_ = media.fileContents(filename: originalImage) // Drain the media cleanup queue.
check(failedList.id == list.id && store.allLists(includeArchived: true).map(\.id) == listIDsBefore, "Missing attachment creates no partial duplicate list")
check(store.blocks(inList: list.id).map(\.id) == blockIDsBefore, "Failed list copy does not mutate original tree")
check(store.actionError?.contains("not duplicated") == true && store.editorNotice == nil, "Failed list copy surfaces the red failure card")
let namesAfterListFailure = try FileManager.default.contentsOfDirectory(atPath: mediaFolder.path).sorted()
check(namesAfterListFailure == namesBefore, "Failed list copy removes staged image files")
store.actionError = nil
let failedBlock = store.duplicateBlock(child)
_ = media.fileContents(filename: originalImage)
check(failedBlock.id == child.id && store.blocks(inList: list.id).map(\.id) == blockIDsBefore, "Missing attachment creates no partial duplicate block")
check(store.actionError?.contains("was not duplicated") == true && store.actionError?.contains("block") == false,
      "Failed block copy surfaces the red failure card, naming what it is")
let namesAfterBlockFailure = try FileManager.default.contentsOfDirectory(atPath: mediaFolder.path).sorted()
check(namesAfterBlockFailure == namesBefore, "Failed block copy removes staged image files")
check(attachment.filename == "missing-file.txt" && parent.note == "Preserve this note", "Failed copy preserves existing unsaved changes")

// A missing image must not fall back to shared ownership or a partial copy.
child.mediaFilename = "missing-image.png"
let failedImage = store.duplicateBlock(child)
check(failedImage.id == child.id && store.blocks(inList: list.id).map(\.id) == blockIDsBefore, "Missing image does not create a duplicate sharing the source filename")
print("✅ \(checks) duplication checks passed")
