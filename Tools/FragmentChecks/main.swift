import AppKit
import SwiftData

var checks = 0
func check(_ condition: Bool, _ message: String) { precondition(condition, message); checks += 1 }
func rejects(_ message: String, _ body: () throws -> Void) {
    do { try body(); preconditionFailure(message) } catch { checks += 1 }
}
let schema = Schema([TaskList.self, Block.self, SidebarSection.self, TaskLabel.self, Attachment.self,
    ActivityEvent.self, WorkSession.self, CompletionRecord.self, SchedulePlacement.self])
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
let store = Store(context: container.mainContext)
let media = MediaStore.shared
let blob = Data("Self-contained clipboard attachment".utf8)
let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a1ZkAAAAASUVORK5CYII=")!
let fragmentURL = url.appendingPathExtension("fragment")
let manifestURL = url.appendingPathExtension("manifest")
let clipboard = NSPasteboard(name: .init(ProcessInfo.processInfo.environment["OPENLIST_COPY_CHECK_ID"]!))
struct Manifest: Codable { var listID: UUID; var rootID: UUID; var count: Int }
func files() throws -> Set<String> {
    _ = media.fileContents(filename: "drain")
    return Set(try FileManager.default.contentsOfDirectory(atPath: media.url(for: "drain").deletingLastPathComponent().path))
}
func events(_ context: ModelContext) throws -> Set<UUID> { Set(try context.fetch(FetchDescriptor<ActivityEvent>()).map(\.id)) }

if CommandLine.arguments[2] == "reopen" {
    let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
    let fragment = try FragmentClipboard.read(from: clipboard)
    check(try fragment.encoded() == Data(contentsOf: fragmentURL) || fragment == DocumentFragment.decode(Data(contentsOf: fragmentURL)), "Actual private clipboard payload survives source-process exit")
    check(store.block(id: fragment.roots[0]) == nil, "Deleted clipboard source remains absent across processes")
    let ids = try store.pasteFragment(fragment, in: .init(listID: manifest.listID), after: nil)
    let root = store.block(id: ids[0])!
    check(root.text == fragment.blocks[0].text, "Self-contained serialized clipboard pastes after restart and source deletion")
    let children = BlockTree.descendants(of: root.id, in: store.blocks(inList: manifest.listID))
    check(children.count + 1 == manifest.count, "Restart paste retains complete mixed hierarchy")
    check(store.attachments(for: root.id).first?.contentData == blob, "Restart paste owns embedded attachment bytes")
    check(store.block(id: manifest.rootID) != nil, "Undo/Redo inserted identity survives restart")
    print("✅ \(checks) fragment restart checks passed")
    exit(0)
}

let sourceList = store.createList(title: "Fragment source")
let target = store.createList(title: "Destination")
let root = store.appendBlock(kind: .task, text: "Bold linked 🧭 procedure", to: .init(listID: sourceList.id))
let sourceID = root.id
root.note = "Two lines\n[explicit](https://example.com)"
root.isCompleted = true
root.completedAt = .now.addingTimeInterval(-50)
root.dueDate = .now.addingTimeInterval(86_400)
root.reminderAt = .now.addingTimeInterval(80_000)
root.includesTime = true
root.recurrence = Recurrence(frequency: .weekly, weekdays: [2], completedOccurrences: 7)
root.selectedForDay = .now
root.deferredUntil = .now.addingTimeInterval(600)
root.calendarOccurrenceID = UUID()
root.inboxMembershipData = try LegacyInboxMembership.included(order: 0, occurrenceID: root.occurrenceID).encoded()
root.isStarred = true
root.priority = .high
root.isCollapsed = true
root.schedulingEstimateMinutes = 45
root.keepsSessionsTogether = true
root.tracksAwayFromMac = true
let attributed = NSMutableAttributedString(string: root.text, attributes: RichTextCodec.baseAttributes(for: .paragraph))
RichTextCodec.toggleTrait(.boldFontMask, in: attributed, range: NSRange(location: 0, length: 4), kind: .paragraph)
RichTextCodec.toggleTrait(.italicFontMask, in: attributed, range: NSRange(location: 5, length: 6), kind: .paragraph)
RichTextCodec.setLink(URL(string: "https://example.com/a?q=1"), in: attributed, range: NSRange(location: 5, length: 6))
RichTextCodec.toggleStrikethrough(in: attributed, range: NSRange(location: 15, length: 9))
RichTextCodec.toggleInlineCode(in: attributed, range: NSRange(location: 15, length: 9), kind: .paragraph)
root.richData = RichTextCodec.encode(attributed)
let label = store.findOrCreateLabel(named: "Travel")!
label.accent = .orange
root.labelIDs = [label.id]
var previous = root
for index in 0..<24 {
    previous = store.insertChild(kind: index.isMultiple(of: 3) ? .task : .paragraph, text: "Level \(index)", of: previous, at: .last)
}
let image = store.insertChild(kind: .image, of: root, at: .last)
image.mediaFilename = "source-image.png"
image.mediaData = png
image.mediaWidth = 320
image.mediaHeight = 200
image.mediaCaption = "Image caption"
try media.restoreFile(png, filename: image.mediaFilename!)
let attachment = Attachment(blockID: root.id, filename: "source-attachment.txt", displayName: "Proof.txt", contentType: "text/plain", byteCount: blob.count, contentData: blob)
store.context.insert(attachment)
try media.restoreFile(blob, filename: attachment.filename)
let sibling = store.appendBlock(kind: .heading1, text: "Outside subtree", to: .init(listID: sourceList.id))
try store.persistChanges()
let fragment = try FragmentContent.capture([root.id, previous.id, root.id], store: store)
let pendingDestination = TaskList(title: "Unsaved destination")
store.context.insert(pendingDestination)
rejects("An unsaved list cannot receive durable children") { _ = try store.pasteFragment(fragment, in: .init(listID: pendingDestination.id), after: nil) }
let pendingParent = Block(kind: .task, text: "Unsaved parent", listID: target.id)
store.context.insert(pendingParent)
rejects("An unsaved parent cannot receive durable children") { _ = try store.pasteFragment(fragment, in: .init(listID: target.id, rootBlockID: pendingParent.id), after: nil) }
let orphanReader = ModelContext(container)
check(try orphanReader.fetch(FetchDescriptor<Block>()).allSatisfy { $0.listID != pendingDestination.id && $0.parentID != pendingParent.id }, "Fresh disk reader sees no orphan from rejected draft destinations")
check(store.context.hasChanges && pendingDestination.title == "Unsaved destination" && pendingParent.text == "Unsaved parent", "Rejected destination preserves pending list and task instances")
store.context.delete(pendingParent)
store.context.delete(pendingDestination)
try store.persistChanges()
try FragmentClipboard.copy([root.id], store: store, to: clipboard)
check(try FragmentClipboard.read(from: clipboard) == fragment && clipboard.string(forType: .string) != nil && clipboard.string(forType: FragmentClipboard.markdownType) != nil, "Private clipboard publishes self-contained data and both public fallback flavors")
check(fragment.roots == [root.id] && fragment.blocks.count == 26, "Ancestor+descendant selection canonicalizes once at arbitrary mixed depth")
let multiple = try FragmentContent.capture([sibling.id, root.id, previous.id], store: store)
check(multiple.roots == [root.id, sibling.id], "Disjoint roots preserve document order independent of input order")
let payload = try fragment.encoded()
check(try DocumentFragment.decode(payload) == fragment, "Versioned JSON round-trip retains every value")
check(fragment.blocks[0].recurrence?.completedOccurrences == 0, "Transport carries repeat rules without historical progress")
let restoredStyle = FragmentContent.styles(from: FragmentContent.attributedText(fragment.blocks[0]))
check(restoredStyle == fragment.blocks[0].styles, "Supported bold, italic, strike and explicit links round-trip")
let placeholderRich = NSMutableAttributedString(attributedString: attributed)
placeholderRich.insert(NSAttributedString(string: "\u{fffc}"), at: 4)
root.richData = RichTextCodec.encode(placeholderRich)
check(try FragmentContent.capture([root.id], store: store).blocks[0].styles == fragment.blocks[0].styles, "Legacy attachment placeholders do not shift later formatting ranges")
root.richData = RichTextCodec.encode(attributed)
let markdown = FragmentMarkdown.render(fragment)
check(markdown.contains("https://example.com/a?q=1") && markdown.contains("Proof") && !markdown.contains("Outside subtree") && !markdown.contains("file://"), "Markdown fallback is subtree-only, rich, readable, and has no private cache links")

var malformed = fragment
malformed.version = 999
rejects("Unknown version rejected") { _ = try malformed.encoded() }
malformed = fragment; malformed.blocks.append(fragment.blocks[0])
rejects("Duplicate identities rejected") { try malformed.validate() }
malformed = fragment; malformed.blocks[1].parentID = UUID()
rejects("Orphan rejected") { try malformed.validate() }
malformed = fragment; malformed.blocks[1].parentID = malformed.blocks[2].id
rejects("Cycle rejected") { try malformed.validate() }
malformed = fragment; malformed.blocks[0].styles[0].length = Int.max
rejects("Overflow formatting range rejected") { try malformed.validate() }
malformed = fragment; malformed.blocks[0].attachments[0].media.fileExtension = "../../escape"
rejects("Media paths rejected") { try malformed.validate() }
malformed = fragment; malformed.blocks[0].labelIDs = [UUID()]
rejects("Dangling labels rejected") { try malformed.validate() }
malformed = fragment; malformed.blocks[25].image?.data = Data("broken image".utf8)
rejects("Corrupt image bytes rejected") { try malformed.validate() }
rejects("Malformed JSON rejected") { _ = try DocumentFragment.decode(Data("{oops".utf8)) }
malformed = fragment; malformed.blocks[0].attachments[0].media.data = Data(count: DocumentFragment.maximumAssetBytes + 1)
rejects("Oversized media rejected before staging") { try malformed.validate() }

let undo = UndoManager()
undo.groupsByEvent = false
var pasted: [UUID] = []
undo.beginUndoGrouping()
store.undoableEditorEdit(in: target.id, name: "Paste content", undoManager: undo, includingNewLabels: true) {
    pasted = try! store.pasteFragment(fragment, in: .init(listID: target.id), after: nil)
}
undo.endUndoGrouping()
let copyID = pasted[0]
let copy = store.block(id: copyID)!
check(copy.id != root.id && copy.occurrenceID == copy.id, "Paste creates independent identities and a fresh occurrence")
check(copy.isCompleted && copy.completedAt == root.completedAt && copy.isStarred && copy.priority == .high, "Content copy preserves completion, stars and priority")
check(copy.dueDate == nil && copy.reminderAt == nil && copy.recurrence == nil && copy.selectedForDay == nil && copy.deferredUntil == nil, "Default paste clears all scheduling payload")
check(copy.inboxMembershipData == nil && root.inboxMembershipData != nil, "Content paste does not copy legacy queue metadata or change the source")
check(copy.note == root.note && copy.isCollapsed && copy.schedulingEstimateMinutes == 45, "Content, collapse and estimate retained")
check(copy.labelIDs == [label.id] && store.allLabels().count == 1 && label.accent == .orange, "Same-name destination label identity/color reused")
let copiedFile = store.attachments(for: copy.id)[0]
let copiedFilename = copiedFile.filename
check(copiedFile.id != attachment.id && copiedFile.filename != attachment.filename && media.fileContents(filename: copiedFile.filename) == blob, "Attachment gets independent identity, filename and bytes")
check(try store.taskActivity(for: copy.id).map(\.kind) == [.created], "Pasted completed task has only fresh Created history")
undo.undo()
check(store.block(id: copyID) == nil && store.allLabels().count == 1, "One Undo removes whole insertion without existing labels")
undo.redo()
check(BlockTree.descendants(of: copyID, in: store.blocks(inList: target.id)).count == 25, "One Redo restores complete hierarchy")
check(store.block(id: copyID)?.inboxMembershipData == nil, "Paste Redo retains clean metadata")
check(try store.taskActivity(for: copyID).map(\.kind).contains(.restored), "Redo records Restored under pasted UUID")
var active = fragment
active.blocks[0].isCompleted = false
active.blocks[0].completedAt = nil
let activeID = try store.pasteFragment(active, in: .init(listID: target.id), after: nil)[0]
check(store.block(id: activeID)?.reminderAt == nil && !NotificationService.shared.scheduled.contains(activeID),
      "An open task's pasted copy leaves its future reminder behind")
var converted = fragment
converted.blocks[0].kind = "paragraph"
let convertedID = try store.pasteFragment(converted, in: .init(listID: target.id), after: nil)[0]
check(store.attachments(for: convertedID).first?.contentData == blob, "Converted task retains hidden attachment bytes on a non-task block")
check(try FragmentContent.capture([convertedID], store: store).blocks[0].attachments[0].media.data == blob, "Copying converted task retains its full hidden file payload")

var foreign = fragment
foreign.labels[0].name = "New destination label"
foreign.labels[0].accent = ListAccent.teal.rawValue
var foreignID: UUID!
let labelUndo = UndoManager(); labelUndo.groupsByEvent = false
labelUndo.beginUndoGrouping()
store.undoableEditorEdit(in: target.id, name: "Paste content", undoManager: labelUndo, includingNewLabels: true) {
    foreignID = try! store.pasteFragment(foreign, in: .init(listID: target.id), after: nil)[0]
}
labelUndo.endUndoGrouping()
let newLabelID = store.block(id: foreignID)!.labelIDs[0]
check(newLabelID != label.id && store.allLabels().count == 2, "Cross-library labels are mapped by name to fresh destination identities")
labelUndo.undo()
check(store.allLabels().count == 1, "Unused label introduced by paste is removed by same Undo")
labelUndo.redo()
check(store.block(id: foreignID)?.labelIDs == [newLabelID] && store.allLabels().count == 2, "Redo restores introduced label before task references")
sibling.labelIDs = [newLabelID]; try store.persistChanges()
labelUndo.undo()
check(store.allLabels().contains { $0.id == newLabelID }, "Undo retains introduced label now used by another task")
labelUndo.redo()
check(store.allLabels().count == 2 && store.block(id: foreignID)?.labelIDs == [newLabelID], "Redo reuses retained label without duplicate")

let oldNote = root.note
root.note = "Unsaved live source note"
target.summary = "Unsaved destination summary"
let pending = try FragmentContent.capture([root.id], store: store)
let pendingCopyID = try store.pasteFragment(pending, in: .init(listID: target.id), after: nil)[0]
check(store.block(id: pendingCopyID)?.note == root.note && store.context.hasChanges, "Successful paste snapshots live source text without flushing its draft")
let pendingReader = ModelContext(container)
check(try pendingReader.fetch(FetchDescriptor<Block>(predicate: #Predicate { $0.id == sourceID })).first?.note == oldNote, "Sibling insertion leaves committed source note unchanged")
root.note = oldNote
target.summary = ""
try store.persistChanges()

let readonly = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, allowsSave: false, cloudKitDatabase: .none)])
let failing = Store(context: readonly.mainContext)
let retained = failing.block(id: root.id)!, retainedList = failing.list(id: target.id)!
retained.note = "Pending source edit"; retainedList.summary = "Pending destination edit"
let beforeFiles = try files(), beforeIDs = Set(failing.blocks(inList: target.id).map(\.id)), beforeHistory = try events(failing.context)
let beforeLabels = Set(failing.allLabels().map(\.id))
foreign.labels[0].name = "Must not leak"
rejects("Real read-only writer rejects complete insertion") { _ = try failing.pasteFragment(foreign, in: .init(listID: target.id), after: nil) }
check(retained.note == "Pending source edit" && retainedList.summary == "Pending destination edit" && failing.context.hasChanges, "Failure preserves retained instances and unsaved editor state")
check(Set(failing.blocks(inList: target.id).map(\.id)) == beforeIDs && Set(failing.allLabels().map(\.id)) == beforeLabels, "First live fetch has no partial blocks or labels")
check(try files() == beforeFiles && events(failing.context) == beforeHistory, "Failed writer rolls back all media and history")
let fresh = ModelContext(container)
check(try events(fresh) == beforeHistory, "Fresh disk reader sees no failed paste history")

let missingFilename = attachment.filename
attachment.filename = "not-present-on-disk.txt"
attachment.contentData = nil
rejects("Missing source file rejects clipboard copy before replacing clipboard") { try FragmentClipboard.copy([root.id], store: store, to: clipboard) }
check(try FragmentClipboard.read(from: clipboard) == fragment, "Failed copy keeps the prior clipboard payload intact")
attachment.filename = missingFilename
attachment.contentData = blob
try store.persistChanges()

let mediaFolder = media.url(for: "drain").deletingLastPathComponent()
let attributes = try FileManager.default.attributesOfItem(atPath: mediaFolder.path)
try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: mediaFolder.path)
rejects("A real media staging write failure aborts insertion") { _ = try store.pasteFragment(fragment, in: .init(listID: target.id), after: nil) }
try FileManager.default.setAttributes([.posixPermissions: attributes[.posixPermissions]!], ofItemAtPath: mediaFolder.path)
check(try Set(store.blocks(inList: target.id).map(\.id)) == beforeIDs && events(store.context) == beforeHistory, "Media failure leaves no staged tree or Created history")

let cross = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url.appendingPathExtension("other"), cloudKitDatabase: .none)])
let other = Store(context: cross.mainContext)
let otherList = other.createList(title: "Other library")
let collision = TaskLabel(name: "Unrelated identity collision", accent: .red)
collision.id = label.id
let match = TaskLabel(name: "travel", accent: .blue)
other.context.insert(collision); other.context.insert(match)
try other.persistChanges()
let crossID = try other.pasteFragment(fragment, in: .init(listID: otherList.id), after: nil)[0]
check(other.block(id: crossID)?.labelIDs == [match.id] && match.accent == .blue && collision.name == "Unrelated identity collision", "Cross-library matching ignores source UUID collisions and preserves destination color")
check(other.allLabels().count == 2 && other.block(id: crossID)?.listID == otherList.id, "Cross-library insertion creates no dangling label or source list reference")
check(other.block(id: crossID)?.inboxMembershipData == nil, "Cross-library paste has no source Inbox membership")

// External text as a paste reads it: what doesn't read as Markdown keeps its words, a
// trimmed text line for each non-blank line and a fenced block as one code line.
let fenced = MarkdownInputRules.pasteLines("```swift\n# not a heading\n\n- not a bullet\n```")
check(fenced.map(\.kind) == [.code] && fenced.map(\.text) == ["# not a heading\n\n- not a bullet"], "An external fenced block pastes as one code line, its content literal")
for (source, lines) in [("first\n\nlast", ["first", "last"]), ("first  \nsecond", ["first", "second"]), ("  indented\nnext", ["indented", "next"]),
                        (" one space\nnext", ["one space", "next"]), ("\u{00a0}nonbreaking indent\nnext", ["nonbreaking indent", "next"]),
                        ("[title](https://example.com)\n<script>data</script>", ["[title](https://example.com)", "<script>data</script>"])] {
    let parsed = MarkdownInputRules.pasteLines(source)
    check(parsed.allSatisfy { $0.kind == .paragraph && $0.depth == 0 } && parsed.map(\.text) == lines, "Unsupported external Markdown pastes as trimmed text lines, keeping its words")
}
check(MarkdownInputRules.pasteLines("- [ ] Parent\n  - [x] Child").map(\.depth) == [0, 1], "Supported external task Markdown keeps nesting")
// The fallback takes the whole paste: one blank line anywhere keeps every line's markers as text.
let spaced = MarkdownInputRules.pasteLines("## Groceries\n\n- [ ] Milk\n- [ ] Eggs")
check(spaced.allSatisfy { $0.kind == .paragraph && $0.depth == 0 } && spaced.map(\.text) == ["## Groceries", "- [ ] Milk", "- [ ] Eggs"], "A blank line anywhere pastes every line as text, markers included")
try payload.write(to: fragmentURL)
store.deleteBlock(root); try store.persistChanges()
check(store.block(id: sourceID) == nil && media.fileContents(filename: copiedFilename) == blob, "Source deletion leaves pasted files independent")
try JSONEncoder().encode(Manifest(listID: target.id, rootID: copyID, count: fragment.blocks.count)).write(to: manifestURL)
print("✅ \(checks) fragment validation, copy, paste, failure and Undo/Redo checks passed")
