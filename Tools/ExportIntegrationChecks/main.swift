import AppKit
import SwiftData

var checks = 0, failures = 0
func check(_ condition: Bool, _ message: String) {
    checks += 1
    if !condition { failures += 1; print("FAIL  \(message)") }
}
let schema = Schema([TaskList.self, Block.self, SidebarSection.self, TaskLabel.self, Attachment.self, ActivityEvent.self, WorkSession.self, CompletionRecord.self, SchedulePlacement.self])
let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
let store = Store(context: container.mainContext)
store.context.autosaveEnabled = false
store.bootstrap()
let media = MediaStore.shared
let mediaFolder = media.url(for: "sentinel").deletingLastPathComponent()
let exportFolder = FileManager.default.temporaryDirectory.appendingPathComponent("openlist-export-integration-\(UUID().uuidString)", isDirectory: true)
try FileManager.default.createDirectory(at: exportFolder, withIntermediateDirectories: true)
defer {
    try? FileManager.default.removeItem(at: mediaFolder.deletingLastPathComponent().deletingLastPathComponent())
    try? FileManager.default.removeItem(at: exportFolder)
}
let list = store.createList(title: "Export café 日本語 [fixture]")
list.summary = "Summary with *literal asterisks*"
let task = store.appendBlock(kind: .task, text: "Review café 日本語 ✅", to: .init(listID: list.id))
let link = URL(string: "https://example.com/review(1)?a=1&b=2#details")!
let rich = NSMutableAttributedString(string: task.text, attributes: [.font: NSFont.boldSystemFont(ofSize: 13), .link: link])
store.setContent(task, attributed: rich)
task.note = "Note with [literal brackets] and café\nSecond line."
task.isStarred = true
task.priority = .high
let label = store.findOrCreateLabel(named: "export-fixture")!
task.labelIDs = [label.id]
let imageBlock = store.insertChild(kind: .image, of: task)
imageBlock.mediaFilename = "inline-image.png"
imageBlock.mediaCaption = "Image [original] 日本語"
let imageBytes = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX1cAAAAASUVORK5CYII=")!
try media.restoreFile(imageBytes, filename: "inline-image.png")
let attachmentBytes = Data([0, 17, 42, 128, 254, 255])
try media.restoreFile(attachmentBytes, filename: "attachment-source.bin")
let attachment = Attachment(blockID: task.id, filename: "attachment-source.bin", displayName: "résumé [final].bin", contentType: "application/octet-stream", byteCount: attachmentBytes.count)
store.context.insert(attachment)
store.save()
check(task.richData != nil, "Real store persists attributed task content before export")
let destination = exportFolder.appendingPathComponent("Portable Export 日本語.md")
try MarkdownExporter.write(list: list, store: store, to: destination)
let markdown = try String(contentsOf: destination, encoding: .utf8)
let parsed = try AttributedString(markdown: markdown)
let visible = String(parsed.characters)
check(visible.contains(list.title) && visible.contains(list.summary), "Rendered Markdown preserves Unicode list title and literal summary")
let linkedRuns = parsed.runs.filter { $0.link == link }
check(linkedRuns.count == 1 && linkedRuns.allSatisfy { String(parsed[$0.range].characters) == task.text }, "Full exporter preserves Unicode task title and exact hyperlink destination")
// Foundation drops inlinePresentationIntent inside links, even for the
// minimal [**bold**](https://example.com). Parse the exported link label
// independently to verify its emphasis, and verify its URL in the full parse.
let taskLine = markdown.components(separatedBy: .newlines).first { $0.hasPrefix("- [ ] ") }!
let linkMarkup = String(taskLine.dropFirst(6))
let labelEnd = linkMarkup.range(of: "](<")!.lowerBound
let labelMarkup = String(linkMarkup[linkMarkup.index(after: linkMarkup.startIndex)..<labelEnd])
let parsedLabel = try AttributedString(markdown: labelMarkup)
check(String(parsedLabel.characters) == task.text && parsedLabel.runs.allSatisfy { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true }, "Independent Markdown parser confirms exported task link label remains bold")
check(visible.contains("Note with [literal brackets] and café") && visible.contains("Second line."), "Full exporter preserves note content with Markdown metacharacters")
check(visible.contains("Priority: High") && visible.contains("#export-fixture") && visible.contains("⭐️"), "Full exporter includes task priority, labels and star")

// Resolve destinations from the actual document, independently of the package
// writer's internal asset map. Every media reference must work after sharing.
let regex = try NSRegularExpression(pattern: #"\]\(<([^>]+)>\)"#)
let ns = markdown as NSString
let destinations = regex.matches(in: markdown, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
let relative = destinations.filter { !$0.hasPrefix("https://") }
check(relative.count == 2, "Export renders both inline image and task attachment references")
let relativePaths = relative.compactMap { $0.removingPercentEncoding }
check(relativePaths.count == 2 && relativePaths.allSatisfy { !$0.hasPrefix("/") && !$0.contains("../") && $0.contains(".assets/") }, "Media destinations are portable relative sibling-asset paths")
let assetURLs = relativePaths.map { exportFolder.appendingPathComponent($0) }
check(assetURLs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) }, "Every exported media reference resolves to an existing file")
let exportedImage = assetURLs.first { $0.pathExtension == "png" }!
let exportedAttachment = assetURLs.first { $0.pathExtension == "bin" }!
check(try Data(contentsOf: exportedImage) == imageBytes, "Full exporter copies original PNG bytes exactly")
check(try Data(contentsOf: exportedAttachment) == attachmentBytes, "Full exporter copies binary attachment bytes exactly")
check(exportedAttachment.lastPathComponent == attachment.displayName, "Portable attachment retains its Unicode display filename")
check(markdown.contains("résumé") && !markdown.contains(mediaFolder.path), "Markdown displays attachment name without leaking internal storage path")

// Copy the document and assets elsewhere, then resolve the same references.
let sharedFolder = exportFolder.appendingPathComponent("Shared", isDirectory: true)
try FileManager.default.createDirectory(at: sharedFolder, withIntermediateDirectories: false)
try FileManager.default.copyItem(at: destination, to: sharedFolder.appendingPathComponent(destination.lastPathComponent))
let assetsFolder = exportedImage.deletingLastPathComponent()
try FileManager.default.copyItem(at: assetsFolder, to: sharedFolder.appendingPathComponent(assetsFolder.lastPathComponent))
let relocated = try relativePaths.map { try Data(contentsOf: sharedFolder.appendingPathComponent($0)) }
check(relocated.contains(imageBytes) && relocated.contains(attachmentBytes), "Exported document and assets remain usable after relocation")
check(media.fileContents(filename: "inline-image.png") == imageBytes && media.fileContents(filename: "attachment-source.bin") == attachmentBytes && store.block(id: task.id)?.text == task.text, "Export preserves source media and model data")

// Missing original media must fail the integrated write, preserving the prior
// document and complete package instead of silently dropping its image.
imageBlock.mediaFilename = "missing-image.png"
let beforeNames = try FileManager.default.contentsOfDirectory(atPath: exportFolder.path).sorted()
do {
    try MarkdownExporter.write(list: list, store: store, to: destination)
    check(false, "Missing model media must throw an export error")
} catch { check(true, "Missing model media surfaces a write error") }
check(try String(contentsOf: destination, encoding: .utf8) == markdown, "Failed integrated export preserves existing Markdown")
check(try FileManager.default.contentsOfDirectory(atPath: exportFolder.path).sorted() == beforeNames, "Failed integrated export leaves no partial package")

// The H1 carries the glyph the app draws: an emoji, the placeholder for none,
// and never the name of an SF Symbol from synced or older data.
func heading(icon: String) throws -> String? {
    let titled = store.createList(title: "Glyph fixture", icon: icon)
    return try MarkdownExporter.markdown(for: titled, store: store).components(separatedBy: .newlines).first
}
check(try heading(icon: "🪴") == "# 🪴 Glyph fixture", "Export's heading keeps a list's emoji")
check(try heading(icon: "") == "# 📋 Glyph fixture", "Export's heading draws a list with no icon as the app does")
check(try heading(icon: "folder.fill") == "# Glyph fixture", "Export's heading leaves out an SF Symbol's name")
print(failures == 0 ? "✅ \(checks) full export integration checks passed" : "❌ \(failures)/\(checks) full export integration checks failed")
exit(failures == 0 ? 0 : 1)
