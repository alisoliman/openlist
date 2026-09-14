import AppKit
import SwiftData

var checks = 0
func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    guard try condition() else { fatalError("FAIL: \(message)") }
    checks += 1
}
func rejects(_ message: String, _ body: () throws -> Void) {
    do { try body(); fatalError("FAIL: \(message)") } catch { checks += 1 }
}
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let phase = CommandLine.arguments[2]
let manager = FileManager.default
try manager.createDirectory(at: root, withIntermediateDirectories: true)
try MediaStore.shared.selectStartupDirectory(root.appendingPathComponent("Media"))
let media = MediaStore.shared
let schema = Schema([TaskList.self, Block.self, SidebarSection.self, TaskLabel.self, Attachment.self,
    ActivityEvent.self, WorkSession.self, CompletionRecord.self, SchedulePlacement.self])
let url = root.appendingPathComponent("Covers.store")
let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
let context = container.mainContext
let store = Store(context: context)
func files() throws -> Set<String> {
    _ = media.fileContents(filename: "sentinel")
    return Set(try manager.contentsOfDirectory(atPath: root.appendingPathComponent("Media").path))
}
func png(_ color: UInt8, name: String) throws -> URL {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 32, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    for i in 0..<(bitmap.bytesPerRow * 32) { bitmap.bitmapData![i] = color }
    let path = root.appendingPathComponent(name)
    try bitmap.representation(using: .png, properties: [:])!.write(to: path)
    return path
}

if phase == "write" {
    let source = try png(255, name: "source image.png")
    let replacement = try png(127, name: "replacement.png")
    let bytes = try Data(contentsOf: source)
    let list = store.createList(title: "Cover source", icon: "🪴", accent: .green)
    try check(list.coverFilename == nil && list.coverPresentation == .compact, "Lists remain usable without cover and use compact default")
    try store.setListCover(list, from: source)
    let originalName = list.coverFilename!
    try check(list.coverData == bytes && media.readFile(filename: originalName) == bytes, "Import retains exact bytes in model and independent local cache")
    try check(list.coverMetadata?.pixelWidth == 64 && list.coverMetadata?.pixelHeight == 32, "Imported cover stores decoded dimensions")
    try check(list.icon == "🪴" && list.accent == .green, "Image cover preserves emoji and accent")
    try store.setListCoverPresentation(list, presentation: .hidden)
    let copy = store.list(id: try store.copyList(list, mode: .duplicate))!
    let copyName = copy.coverFilename!
    try check(copyName != originalName && copy.coverData == bytes && copy.coverPresentation == .hidden, "List duplicate owns fresh media and preserves hidden presentation")
    let template = store.list(id: try store.copyList(list, mode: .template(keepingRecurrence: false)))!
    try check(template.coverFilename != copyName && template.coverFilename != originalName && template.coverData == bytes,
        "Template copy also has independent cover ownership")
    let markdown = root.appendingPathComponent("Hidden list.md")
    try MarkdownExporter.write(list: copy, store: store, to: markdown)
    let text = try String(contentsOf: markdown, encoding: .utf8)
    try check(text.contains("![Cover source copy cover]") && text.contains("Hidden%20list.assets/source%20image.png"), "Hidden cover is portable in Markdown export")
    try check(Data(contentsOf: root.appendingPathComponent("Hidden list.assets/source image.png")) == bytes, "Markdown package includes actual cover bytes")
    try check(MarkdownExporter.markdown(for: copy, store: store).contains("file://"), "Clipboard export points at materialized cover")
    try store.setListCover(list, from: replacement)
    try check(!files().contains(originalName) && media.readFile(filename: copyName) == bytes, "Replacement cleans only the old unreferenced import")
    try store.removeListCover(list)
    try check(list.coverFilename == nil && list.coverData == nil && list.coverMetadataData == nil && list.coverPresentationRaw == nil,
        "Remove clears cover payload and resets compact default")
    try check(media.readFile(filename: copyName) == bytes, "Removing source cover leaves copied cover intact")

    let corrupt = root.appendingPathComponent("broken.png")
    try Data("not an image".utf8).write(to: corrupt)
    let before = try files()
    rejects("Corrupt image rejected before mutation") { try store.setListCover(copy, from: corrupt) }
    let truncated = root.appendingPathComponent("truncated.png")
    try bytes.prefix(33).write(to: truncated)
    rejects("Truncated image rejected before mutation") { try store.setListCover(copy, from: truncated) }
    let oversized = root.appendingPathComponent("oversized.png")
    _ = manager.createFile(atPath: oversized.path, contents: nil)
    let handle = try FileHandle(forWritingTo: oversized)
    try handle.truncate(atOffset: 20 * 1_024 * 1_024 + 1); try handle.close()
    rejects("Oversize local image rejected before read or mutation") { try store.setListCover(copy, from: oversized) }
    rejects("Oversized decoded dimensions rejected") { try ListCoverMetadata(displayName: "x", contentType: "image/png", byteCount: 10, pixelWidth: 16_385, pixelHeight: 1).validate() }
    try check(copy.coverFilename == copyName && copy.coverData == bytes && files() == before, "Invalid imports keep model and cache unchanged")

    let metadata = copy.coverMetadataData
    copy.coverMetadataData = Data("unknown metadata".utf8)
    try store.persistChanges()
    rejects("Copy refuses corrupt metadata without dropping asset") { _ = try store.copyList(copy, mode: .duplicate) }
    let suite = "CoverChecks-\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    rejects("Backup refuses corrupt cover metadata") {
        try LibraryBackup(context: context, libraryID: UUID(), settings: .init(defaults: defaults)).validate()
    }
    var futureMetadata = try JSONDecoder().decode(ListCoverMetadata.self, from: metadata!)
    futureMetadata.version = 99
    copy.coverMetadataData = try JSONEncoder().encode(futureMetadata)
    try store.persistChanges()
    rejects("Copy refuses unknown cover metadata version") { _ = try store.copyList(copy, mode: .duplicate) }
    copy.coverMetadataData = metadata
    copy.coverPresentationRaw = "future-presentation"
    try store.persistChanges()
    rejects("Copy refuses unknown cover presentation") { _ = try store.copyList(copy, mode: .duplicate) }
    copy.coverPresentationRaw = "hidden"
    try store.persistChanges()

    // Exercise actual shared references introduced by old/synced records.
    let image = Block(kind: .image, listID: list.id)
    image.mediaFilename = copyName; image.mediaData = bytes
    context.insert(image); try store.persistChanges()
    try store.removeListCover(copy)
    try check(media.readFile(filename: copyName) == bytes, "Cover removal respects an image block sharing the filename")
    copy.coverFilename = copyName; copy.coverData = bytes; copy.coverMetadataData = metadata
    try store.persistChanges()
    store.removeEditorMedia(filename: copyName)
    try check(media.readFile(filename: copyName) == bytes, "Editor image and attachment cleanup respects active list covers")
    let file = Attachment(blockID: image.id, filename: copyName, displayName: "shared", contentType: "image/png", byteCount: bytes.count, contentData: bytes)
    context.insert(file); try store.persistChanges()
    store.purgeMediaAndAttachments(for: image)
    try check(media.readFile(filename: copyName) == bytes, "Existing subtree media cleanup keeps a list-owned cache")
    context.delete(image); try store.persistChanges()

    let retainedName = template.coverFilename!
    try check(store.trashList(template), "List cover moves into Trash with its list")
    try check(store.trashEntries().first { $0.id == template.id }?.byteCount == bytes.count, "Trash byte total includes list cover")
    store.removeEditorMedia(filename: retainedName)
    try check(media.readFile(filename: retainedName) == bytes, "Editor cleanup protects retained list covers")
    try media.eraseCachedFile(filename: retainedName)
    try check(store.restoreTrash(ids: [template.id]), "List restore recreates cover cache from retained bytes")
    try check(media.readFile(filename: retainedName) == bytes && template.coverPresentation == .hidden, "Restore preserves bytes and hidden preference")
    try check(store.trashList(template) && store.permanentlyEraseTrash(ids: [template.id]), "Explicit permanent list erase succeeds")
    try check(!files().contains(retainedName), "Permanent erase removes unreferenced cover cache")
    try check(media.readFile(filename: copyName) == bytes, "Permanent erase leaves independent copy intact")

    let shared = store.createList(title: "Shared Trash cover")
    shared.coverFilename = copyName; shared.coverData = bytes; shared.coverMetadataData = metadata
    try store.persistChanges()
    try check(store.trashList(shared) && store.permanentlyEraseTrash(ids: [shared.id]), "Shared cover may be permanently erased from one retained owner")
    try check(media.readFile(filename: copyName) == bytes, "Trash purge respects other live cover references")
    // Session Undo owns its own file bytes even while another live model keeps
    // the shared cache alive. Covers can be replaced/removed before that Undo.
    for isAttachment in [false, true] {
        for replaceCover in [false, true] {
            let owner = store.createList(title: "Shared legacy Undo")
            try store.setListCover(owner, from: source)
            let sharedName = owner.coverFilename!
            let legacy = Block(kind: isAttachment ? .task : .image, listID: owner.id)
            let legacyID = legacy.id
            context.insert(legacy)
            if isAttachment {
                context.insert(Attachment(blockID: legacy.id, filename: sharedName,
                    displayName: "Legacy image", contentType: "image/png", byteCount: bytes.count))
            } else {
                legacy.mediaFilename = sharedName
                legacy.mediaData = nil
            }
            try store.persistChanges()
            let undo = UndoManager(); undo.groupsByEvent = false
            undo.beginUndoGrouping()
            store.undoableEditorEdit(in: owner.id, name: "Remove legacy media", undoManager: undo) {
                store.deleteBlock(legacy)
                store.save()
            }
            undo.endUndoGrouping()
            try check(media.fileContents(filename: sharedName) == bytes, "Structural deletion retains a shared cover cache")
            if replaceCover { try store.setListCover(owner, from: replacement) }
            else { try store.removeListCover(owner) }
            try check(media.fileContents(filename: sharedName) == nil, "Later cover mutation removes the now-unreferenced cache")
            undo.undo()
            try check(store.block(id: legacyID) != nil && media.fileContents(filename: sharedName) == bytes,
                "Undo restores legacy image/attachment bytes after shared cover removal or replacement")
            if isAttachment {
                try check(store.attachments(for: legacyID).first?.filename == sharedName,
                    "Undo restores the legacy attachment owner as well as its bytes")
            }
            undo.redo()
            try check(store.block(id: legacyID) == nil && media.fileContents(filename: sharedName) == nil,
                "Redo removes only the restored legacy media")
            undo.undo()
            try check(media.fileContents(filename: sharedName) == bytes, "A later Undo retains its independent media snapshot")
        }
    }

    copy.title = "Cold cover"; copy.coverPresentationRaw = "hidden"
    try store.persistChanges()
    try manager.removeItem(at: source)
    print("\(checks) cover ownership checks passed")
} else if phase == "reopen" {
    let list = store.allLists().first { $0.title == "Cold cover" }!
    let name = list.coverFilename!
    try check(list.coverMetadata?.pixelWidth == 64 && list.coverPresentation == .hidden, "Cold relaunch preserves metadata and hidden preference")
    try media.eraseCachedFile(filename: name)
    try check(media.image(named: name, data: list.coverData) != nil, "Cold image renders from durable bytes without original file or cache")
    _ = try media.materialize(filename: name, data: list.coverData)
    try check(media.readFile(filename: name) == list.coverData, "Cold relaunch can recreate independent cover cache")
    let replacement = root.appendingPathComponent("replacement.png")
    let before = BackupTaskList(list)
    let beforeFiles = try files()
    let failing = Store(context: context, commitContext: { _ in throw CocoaError(.fileWriteOutOfSpace) })
    rejects("Rejected replacement save is reported") { try failing.setListCover(list, from: replacement) }
    try check(BackupTaskList(list) == before && files() == beforeFiles, "Failed replacement restores same live fields and original cache, discarding only staged media")
    rejects("Rejected removal save is reported") { try failing.removeListCover(list) }
    try check(BackupTaskList(list) == before && media.readFile(filename: name) == before.coverData, "Failed removal leaves fields and media untouched")
    try autoreleasepool {
        let readOnly = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, allowsSave: false, cloudKitDatabase: .none)])
        let readonlyStore = Store(context: ModelContext(readOnly))
        let current = readonlyStore.list(id: list.id)!
        rejects("Actual read-only replacement fails") { try readonlyStore.setListCover(current, from: replacement) }
        try check(BackupTaskList(current) == before && files() == beforeFiles, "Actual failed replacement preserves live fields and all prior files")
        rejects("Actual read-only removal fails") { try readonlyStore.removeListCover(current) }
        try check(BackupTaskList(current) == before && media.readFile(filename: name) == before.coverData, "Actual failed removal preserves same view model and original cache")
    }
    print("\(checks) cold cover and failure checks passed")
} else if phase == "verify" {
    let list = store.allLists().first { $0.title == "Cold cover" }!
    try check(list.coverFilename != nil && list.coverPresentation == .hidden && list.coverMetadata?.pixelWidth == 64, "Failed operations leave persisted cover unchanged after another cold process")
    print("\(checks) post-failure persistence check passed")
}
