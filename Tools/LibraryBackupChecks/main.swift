import AppKit
import CoreData
import CryptoKit
import Foundation
import SwiftData

var checks = 0
func check(_ value: @autoclosure () throws -> Bool, _ message: String) rethrows {
    checks += 1
    guard try value() else { fatalError("FAIL: \(message)") }
}
func rejects(_ message: String, _ operation: () throws -> Void) {
    do { try operation(); fatalError("FAIL: \(message)") }
    catch { check(!error.localizedDescription.isEmpty, message) }
}
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let phase = CommandLine.arguments[2]
let manager = FileManager.default
try manager.createDirectory(at: root, withIntermediateDirectories: true)
let package = root.appendingPathComponent("Library.openlistbackup")
let settingsSuite = "openlist.backup-check.\(UUID())"
let defaults = UserDefaults(suiteName: settingsSuite)!
defer { defaults.removePersistentDomain(forName: settingsSuite) }
let fixedDate = Date(timeIntervalSinceReferenceDate: 700_000_000.125)

if phase == "read-closed" {
    let source = root.appendingPathComponent("Source.store")
    let expected = try JSONDecoder().decode(LibraryBackup.self, from: Data(contentsOf: root.appendingPathComponent("expected-closed.json")))
    let reader = try BackupSnapshotReader(schema: AppPersistence.schema)
    let scratch = root.appendingPathComponent("Scratch", isDirectory: true)
    try manager.createDirectory(at: scratch, withIntermediateDirectories: true)
    func sourceBytes() throws -> [String: String] {
        var result: [String: String] = [:]
        for case let url as URL in manager.enumerator(at: root, includingPropertiesForKeys: nil)! {
            let relative = String(url.path.dropFirst(root.path.count + 1))
            guard relative == "Source.store" || relative == "Source.store-wal" || relative.hasPrefix(".Source_SUPPORT/") else { continue }
            guard (try manager.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) == .typeRegular else { continue }
            result[relative] = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
        }
        return result
    }
    let before = try sourceBytes()
    let actual = try reader.readClosedStore(at: source, settings: expected.settings, createdAt: expected.createdAt,
                                            temporaryDirectory: scratch) { directory in
        let files = FileManager.default
        guard (try files.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber)?.intValue == 0o700 else { throw CocoaError(.fileReadNoPermission) }
        for case let url as URL in files.enumerator(at: directory, includingPropertiesForKeys: nil)! {
            let attributes = try files.attributesOfItem(atPath: url.path)
            let required = attributes[.type] as? FileAttributeType == .typeDirectory ? 0o700 : 0o600
            guard (attributes[.posixPermissions] as? NSNumber)?.intValue == required else { throw CocoaError(.fileReadNoPermission) }
        }
    }
    check(actual == expected, "Closed actual SwiftData source preserves all nine DTO types, identity and payloads exactly")
    check(actual.blocks.contains { $0.mediaData?.count == 1_048_593 }, "Closed source hydrates external image bytes")
    check(actual.attachments.contains { $0.contentData?.count == 3_000_000 }, "Closed source hydrates external attachment bytes")
    try check(sourceBytes() == before, "Closed read leaves original DB, WAL and external payload bytes unchanged; SHM read marks are excluded")
    try check(manager.contentsOfDirectory(atPath: scratch.path).isEmpty, "Successful read removes its private scratch files")
    rejects("Injected failure after copying aborts the read") {
        _ = try reader.readClosedStore(at: source, settings: expected.settings, temporaryDirectory: scratch,
                                      afterCopy: { _ in throw CocoaError(.userCancelled) })
    }
    try check(manager.contentsOfDirectory(atPath: scratch.path).isEmpty, "Injected failure removes its private scratch files")
    rejects("Missing expected external bytes in scratch cannot become successful legacy media") {
        _ = try reader.readClosedStore(at: source, settings: expected.settings, temporaryDirectory: scratch) { directory in
            let files = FileManager.default
            for case let url as URL in files.enumerator(at: directory, includingPropertiesForKeys: nil)! {
                if url.path.contains("_EXTERNAL_DATA/"), (try files.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) == .typeRegular {
                    try files.removeItem(at: url)
                }
            }
        }
    }
    try check(manager.contentsOfDirectory(atPath: scratch.path).isEmpty, "Failed materialization removes its private scratch files")
    try check(sourceBytes() == before, "All failure paths preserve original DB, WAL and payload bytes")
    print("\(checks) closed SwiftData snapshot checks passed")
    exit(0)
}

if phase.hasPrefix("crash-") || phase == "resume-journal" {
    let fixture = try LibraryBackupPackage.read(at: package)
    let reader = try BackupSnapshotReader(schema: AppPersistence.schema)
    let storage = LibraryRestoreStorage(originalStoreURL: root.appendingPathComponent("Original/Openlist.store"),
        originalMediaURL: root.appendingPathComponent("Original/Media"))
    if phase == "resume-journal" {
        let startup = try storage.activatePending(currentSettings: fixture.snapshot.settings, using: reader)
        let opened = try AppPersistence.openSelected(startup, storage: storage, iCloudUnavailableReason: "Isolated fixture")
        let expected = try JSONDecoder().decode(UUID.self, from: Data(contentsOf: root.appendingPathComponent("expected-id.json")))
        let actual = try reader.read(at: startup.storeURL, settings: fixture.snapshot.settings)
        check(startup.isLocalRestore && actual.libraryID == expected, "Actual fresh process activates the intended restored identity")
        try check(opened.container.mainContext.fetchCount(FetchDescriptor<Block>()) == fixture.snapshot.blocks.count, "Actual fresh process opens the complete activated store")
        check(manager.fileExists(atPath: storage.originalStoreURL.path), "Actual process replay retains original storage")
        check(storage.needsDerivedReset(startup, defaults: defaults), "Actual fresh process must reset derived state before an absent marker is published")
        if root.lastPathComponent == "crash-after-journal-cleanup" {
            check(!startup.changed, "Journal-cleanup interruption reopens with changed false and still needs reset")
        }
        print("\(checks) process-interruption reopen checks passed")
        exit(0)
    }
    var incoming = fixture.snapshot
    incoming.libraryID = UUID()
    try JSONEncoder().encode(incoming.libraryID).write(to: root.appendingPathComponent("expected-id.json"))
    let prepared = try storage.prepare(incoming, using: reader)
    try storage.queue(prepared)
    _ = try storage.activatePending(currentSettings: fixture.snapshot.settings, using: reader) { point in
        switch (phase, point) {
        case ("crash-before-selection", .beforeSelection), ("crash-after-selection", .afterSelection):
            kill(getpid(), SIGKILL)
        default: break
        }
    }
    if phase == "crash-after-journal-cleanup" { kill(getpid(), SIGKILL) }
    fatalError("Crash checkpoint was not reached")
}

if phase == "mutate-scalars" || phase == "mutate-media" || phase == "mutate-cover" {
    let schema = AppPersistence.schema
    let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema,
        url: root.appendingPathComponent("Source.store"), cloudKitDatabase: .none)])
    let context = container.mainContext
    context.autosaveEnabled = false
    if phase == "mutate-scalars" {
        let list = try context.fetch(FetchDescriptor<TaskList>()).first { $0.title == "Archived rich document" }!
        let block = try context.fetch(FetchDescriptor<Block>()).first { $0.text == "Completed repeating task" }!
        list.title = "List committed after snapshot"
        block.text = "Task committed after snapshot"
    } else if phase == "mutate-cover" {
        let list = try context.fetch(FetchDescriptor<TaskList>()).first { $0.coverFilename == "cover-original.png" }!
        list.coverData = Data("new cover after snapshot".utf8)
        var metadata = list.coverMetadata!
        metadata.byteCount = list.coverData!.count
        list.coverMetadataData = try JSONEncoder().encode(metadata)
    } else {
        let image = try context.fetch(FetchDescriptor<Block>()).first { $0.mediaFilename == "image-original.png" }!
        image.mediaData = Data("new blob after snapshot".utf8)
    }
    try context.save()
    exit(0)
}

if phase == "reopen" {
    let validated = try LibraryBackupPackage.read(at: package)
    let restored = try BackupStagedStore.read(at: root.appendingPathComponent("Restored/Openlist.store"),
        settings: validated.snapshot.settings, createdAt: validated.snapshot.createdAt)
    check(restored == validated.snapshot, "Every record, UUID, rich payload and media byte survives a separate process")
    check(restored.libraryID == validated.manifest.libraryID, "Full restore retains library link identity across processes")
    check(restored.activity.count == 2 && restored.activity.contains { $0.blockID != nil && !restored.blocks.map(\.id).contains($0.blockID!) }, "Deleted-subject historical events survive relaunch")
    check(restored.completions.count == 1 && restored.workSessions.count == 1 && restored.placements.count == 1, "Calendar source records survive relaunch")
    print("\(checks) backup reopen checks passed")
    exit(0)
}

let schema = AppPersistence.schema
let container = try AppPersistence.open(at: root.appendingPathComponent("Source.store"),
                                        iCloudUnavailableReason: "Isolated backup fixture").container
let context = container.mainContext
context.autosaveEnabled = false
let section = SidebarSection(title: "Pinned personal", sortIndex: 8.5, isDefault: true)
section.isCollapsed = true
let aliasSection = SidebarSection(title: "Old default", sortIndex: -2, isDefault: true)
aliasSection.mergedIntoID = section.id
let inbox = TaskList(title: "Inbox", icon: "📥", accent: .blue, isSystemInbox: true)
let list = TaskList(title: "Archived rich document", icon: "🪴", accent: .green)
list.summary = "Long description with unicode → αβ"
list.sectionID = section.id; list.isPinned = true; list.isArchived = true
list.sortIndex = 8.125; list.sidebarIndex = 4.125; list.sorting = .priority
list.completedVisibility = .hide; list.availabilityCategoryRaw = "personal"
list.lastOpenedAt = fixedDate
list.coverFilename = "cover-original.png"
list.coverData = Data(repeating: 0x42, count: 1_048_611)
list.coverMetadataData = try JSONEncoder().encode(ListCoverMetadata(displayName: "Garden.png", contentType: "image/png", byteCount: 1_048_611, pixelWidth: 800, pixelHeight: 600))
list.coverPresentationRaw = ListCoverPresentation.hidden.rawValue
let aliasList = TaskList(title: "Old Inbox", isSystemInbox: true)
aliasList.mergedIntoID = inbox.id
let label = TaskLabel(name: "#Long label", accent: .orange, sortIndex: 2.5)
let task = Block(kind: .task, text: "Completed repeating task", listID: list.id, sortIndex: 6.25)
task.richData = Data([1, 2, 3, 4])
task.isCollapsed = true; task.isCompleted = true; task.completedAt = fixedDate
task.dueDate = fixedDate.addingTimeInterval(3600); task.includesTime = true
task.reminderAt = fixedDate.addingTimeInterval(1800)
task.isStarred = true; task.priority = .high; task.labelIDs = [label.id]
task.recurrenceData = Data("{\"frequency\":\"weekly\"}".utf8)
task.note = "**Rich task note**\nWith details"
task.schedulingEstimateMinutes = 67; task.selectedForDay = fixedDate
task.deferredUntil = fixedDate.addingTimeInterval(9000)
task.keepsSessionsTogether = true; task.tracksAwayFromMac = true
task.calendarOccurrenceID = UUID()
task.inboxMembershipData = try InboxMembership.included(order: 19.25, occurrenceID: task.occurrenceID).encoded()
let child = Block(kind: .task, text: "Nested child", listID: list.id, parentID: task.id, sortIndex: 0.125)
let heading = Block(kind: .heading2, text: "Nested section", listID: list.id, parentID: child.id)
let image = Block(kind: .image, text: "", listID: list.id, parentID: heading.id)
image.mediaFilename = "image-original.png"; image.mediaData = Data(repeating: 0x5A, count: 1_048_593)
image.mediaWidth = 140.5; image.mediaHeight = 70.25; image.mediaCaption = "Caption"
let legacyImage = Block(kind: .image, text: "", listID: inbox.id)
legacyImage.mediaFilename = "legacy-file.png"
let attachmentBytes = phase == "prepare-closed" ? Data(repeating: 0x51, count: 3_000_000) : Data("pdf bytes".utf8)
let attachment = Attachment(blockID: task.id, filename: "source-file.pdf", displayName: "Original 📎 file.pdf",
    contentType: "application/pdf", byteCount: attachmentBytes.count, sortIndex: 9.5, contentData: attachmentBytes)
let event = ActivityEvent(kind: .renamed, title: "Old title", detail: "Available facts", blockID: task.id,
    listID: list.id, listTitle: "Historical list", listIcon: "🧾")
event.timestamp = fixedDate; event.change = TaskActivityChange(before: TaskActivityState(title: task.text, dueDate: task.dueDate, includesTime: true, isCompleted: true, listID: list.id, listTitle: list.title, listIcon: list.icon, occurrenceID: task.occurrenceID), after: TaskActivityState(title: task.text, dueDate: task.dueDate, includesTime: true, isCompleted: true, listID: list.id, listTitle: list.title, listIcon: list.icon, occurrenceID: task.occurrenceID))
let legacyEvent = ActivityEvent(kind: .deleted, title: "Gone subject", detail: "No old facts invented", blockID: UUID(), listID: UUID())
legacyEvent.changeData = Data([255, 0, 128])
let work = WorkSession(task: task, deviceID: "historical-device", startedAt: fixedDate)
work.endedAt = fixedDate.addingTimeInterval(500); work.lastHeartbeatAt = fixedDate.addingTimeInterval(480)
work.correctedMinutes = 12.75; work.pauseReason = "Closed"; work.plannedIntervals = [.init(start: fixedDate, end: fixedDate.addingTimeInterval(200))]
let completion = CompletionRecord(task: task, completedAt: fixedDate, estimateMinutes: 70)
completion.wasRecurring = true; completion.plannedIntervals = [.init(start: fixedDate, end: fixedDate.addingTimeInterval(200))]
let placement = SchedulePlacement(task: child, start: fixedDate, end: fixedDate.addingTimeInterval(800), isPinned: true)
[section, aliasSection].forEach { context.insert($0) }
let ownerDocument = TaskList(title: "Parent document")
list.parentListID = ownerDocument.id
[inbox, list, aliasList, ownerDocument].forEach { context.insert($0) }
[task, child, heading, image, legacyImage].forEach { context.insert($0) }
context.insert(label); context.insert(attachment); context.insert(event); context.insert(legacyEvent)
context.insert(work); context.insert(completion); context.insert(placement)
try context.save()
defaults.set(false, forKey: "settings.showsCompleted")
defaults.set(false, forKey: "settings.naturalLanguage")
defaults.set("today", forKey: "settings.defaultDestination")
defaults.set(2, forKey: "settings.firstWeekday")
defaults.set("priority", forKey: TodaySorting.preferenceKey)
defaults.set("alphabetical", forKey: ListGallerySorting.preferenceKey)
defaults.set(false, forKey: ListGallerySorting.ascendingPreferenceKey)
defaults.set("SECRET", forKey: "settings.mcpToken")
defaults.set(true, forKey: "settings.mcpEnabled")
defaults.set(true, forKey: "calendar.connected")
let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: root.appendingPathComponent("Source.store"))
let libraryID = UUID(uuidString: metadata[NSStoreUUIDKey] as! String)!
let snapshot = try LibraryBackup(context: context, libraryID: libraryID, settings: .init(defaults: defaults), createdAt: fixedDate)
let reader = try BackupSnapshotReader(schema: schema)
if phase == "prepare-closed" {
    try JSONEncoder().encode(snapshot).write(to: root.appendingPathComponent("expected-closed.json"))
    print("Prepared closed actual AppPersistence source without an earlier backup read")
    exit(0)
}
let pinned = try reader.read(at: root.appendingPathComponent("Source.store"), settings: snapshot.settings, createdAt: fixedDate)
check(pinned == snapshot, "Public pinned reader matches every actual-schema value including external media")
try snapshot.validate()
let legacyBytes = Data("Legacy bytes read from local cache".utf8)
try LibraryBackupPackage.write(snapshot, to: package) { filename in
    check(filename == legacyImage.mediaFilename, "Inline media bytes take precedence over local cache")
    return legacyBytes
}
let validated = try LibraryBackupPackage.read(at: package)
var hydrated = snapshot
hydrated.blocks[hydrated.blocks.firstIndex { $0.id == legacyImage.id }!].mediaData = legacyBytes
check(validated.snapshot == hydrated, "Logical package preserves every field and loads legacy media bytes")
check(validated.manifest.version == LibraryBackup.currentVersion, "New backup format prevents older apps silently dropping Inbox curation")
check(validated.snapshot.blocks.first { $0.id == task.id }?.inboxMembershipData == task.inboxMembershipData,
    "Archive, completed and nested record backup retains exact Inbox order and occurrence payload")
let oldPackage = root.appendingPathComponent("Version1.openlistbackup")
try manager.copyItem(at: package, to: oldPackage)
var oldSnapshot = validated.snapshot
oldSnapshot.version = 1
for index in oldSnapshot.lists.indices {
    oldSnapshot.lists[index].parentListID = nil
    oldSnapshot.lists[index].coverFilename = nil
    oldSnapshot.lists[index].coverData = nil
    oldSnapshot.lists[index].coverMetadataData = nil
    oldSnapshot.lists[index].coverPresentationRaw = nil
}
for index in oldSnapshot.blocks.indices {
    oldSnapshot.blocks[index].inboxMembershipData = nil
    oldSnapshot.blocks[index].mediaData = nil
}
for index in oldSnapshot.attachments.indices { oldSnapshot.attachments[index].contentData = nil }
let oldBytes = try JSONEncoder().encode(oldSnapshot)
var oldManifest = validated.manifest
oldManifest.version = 1
oldManifest.assets.removeAll { $0.filename == "cover-original.png" }
oldManifest.libraryDigest = LibraryBackupPackage.digest(oldBytes)
try oldBytes.write(to: oldPackage.appendingPathComponent("library.json"))
try JSONEncoder().encode(oldManifest).write(to: oldPackage.appendingPathComponent("manifest.json"))
let upgraded = try LibraryBackupPackage.read(at: oldPackage)
check(upgraded.manifest.version == 1 && upgraded.snapshot.version == LibraryBackup.currentVersion, "Version 1 package gets an explicit in-memory upgrade")
check(upgraded.snapshot.blocks.allSatisfy { $0.inboxMembershipData == nil }, "Version 1 preserves legacy nil for ownership-aware migration")
for version in [2, 3, 4] {
    let olderPackage = root.appendingPathComponent("Version\(version).openlistbackup")
    try manager.copyItem(at: oldPackage, to: olderPackage)
    var older = oldSnapshot; older.version = version
    let encoded = try JSONEncoder().encode(older)
    var manifest = oldManifest; manifest.version = version; manifest.libraryDigest = LibraryBackupPackage.digest(encoded)
    try encoded.write(to: olderPackage.appendingPathComponent("library.json"))
    try JSONEncoder().encode(manifest).write(to: olderPackage.appendingPathComponent("manifest.json"))
    let loaded = try LibraryBackupPackage.read(at: olderPackage)
    check(loaded.snapshot == upgraded.snapshot && loaded.manifest.version == version,
        "Version \(version) package upgrades without invented cover fields")
}
var disguisedCover = validated.snapshot; disguisedCover.version = 3
rejects("Older backup version cannot silently carry unsupported cover data") { try disguisedCover.upgradeToCurrentVersion() }

let upgradedURL = try BackupStagedStore.create(from: upgraded.snapshot, in: root.appendingPathComponent("UpgradedV1"), using: reader)
let upgradedRead = try reader.read(at: upgradedURL, settings: upgraded.snapshot.settings, createdAt: upgraded.snapshot.createdAt)
check(upgradedRead == upgraded.snapshot, "Version 1 upgrade stages and reopens every field without guessed membership")
var futureSelection = validated.snapshot
futureSelection.blocks[0].inboxMembershipData = Data(#"{"version":90,"included":true}"#.utf8)
let futureURL = try BackupStagedStore.create(from: futureSelection, in: root.appendingPathComponent("FutureSelection"), using: reader)
try check(try reader.read(at: futureURL, settings: futureSelection.settings, createdAt: futureSelection.createdAt) == futureSelection,
    "Unknown membership payload remains lossless in recovery backups")
check(validated.manifest.assets.count == 4, "Cover, inline image, legacy image and attachment all have checked assets")
check(validated.snapshot.lists.contains { $0.isArchived } && validated.snapshot.lists.contains { $0.mergedIntoID != nil }, "Archive and retained aliases are included")
check(validated.snapshot.activity.first { $0.id == legacyEvent.id }?.changeData == legacyEvent.changeData, "Undecodable legacy activity details are preserved as recorded")
let restoredURL = try BackupStagedStore.create(from: validated.snapshot, in: root.appendingPathComponent("Restored"))
let restored = try BackupStagedStore.read(at: restoredURL, settings: snapshot.settings, createdAt: fixedDate)
check(restored == validated.snapshot, "Reopened staged store has exact records and original UUID identity")
check(!context.hasChanges && task.text == "Completed repeating task", "Package and staging do not mutate source models")
try validated.snapshot.settings.apply(to: defaults)
check(defaults.string(forKey: "settings.mcpToken") == "SECRET" && defaults.bool(forKey: "settings.mcpEnabled") && defaults.bool(forKey: "calendar.connected"), "Restore leaves machine credentials and connections unchanged")
let encodedSettings = try JSONEncoder().encode(snapshot.settings)
check(!String(decoding: encodedSettings, as: UTF8.self).contains("SECRET"), "Machine secrets never enter the backup")

let priorManifest = try Data(contentsOf: package.appendingPathComponent("manifest.json"))
rejects("Existing backup is never overwritten") { try LibraryBackupPackage.write(snapshot, to: package) { _ in legacyBytes } }
try check(try Data(contentsOf: package.appendingPathComponent("manifest.json")) == priorManifest, "Existing backup remains byte-identical")
let cancelled = root.appendingPathComponent("Cancelled.openlistbackup")
rejects("Interrupted write is not published") {
    try LibraryBackupPackage.write(snapshot, to: cancelled, readMedia: { _ in legacyBytes }, beforePublish: { throw CocoaError(.userCancelled) })
}
check(!manager.fileExists(atPath: cancelled.path), "Cancelled package has no published destination")
let raced = root.appendingPathComponent("Raced.openlistbackup")
let racedBytes = Data("Destination created while backup was being validated".utf8)
rejects("A destination created before publication is never replaced") {
    try LibraryBackupPackage.write(snapshot, to: raced, readMedia: { _ in legacyBytes }, beforePublish: {
        try racedBytes.write(to: raced)
    })
}
try check(try Data(contentsOf: raced) == racedBytes, "Concurrent destination remains byte-identical")
let failedStage = root.appendingPathComponent("FailedStage")
rejects("Failed staged save leaves original store untouched") {
    _ = try BackupStagedStore.create(from: validated.snapshot, in: failedStage, beforeSave: { throw CocoaError(.fileWriteNoPermission) })
}
check(!manager.fileExists(atPath: failedStage.path), "Failed stage cleans up its incomplete store")
try check(try LibraryBackup(context: context, libraryID: libraryID, settings: snapshot.settings, createdAt: fixedDate) == snapshot, "Live source remains exact after staging failure")
rejects("Missing legacy source media stops the whole backup") { try LibraryBackupPackage.write(snapshot, to: cancelled) { _ in throw CocoaError(.fileReadNoSuchFile) } }
check(!manager.fileExists(atPath: cancelled.path), "Missing media creates no partial package")

func altered(_ name: String, _ operation: (URL) throws -> Void) throws {
    let target = root.appendingPathComponent(name + ".openlistbackup")
    try manager.copyItem(at: package, to: target)
    try operation(target)
    rejects(name) { _ = try LibraryBackupPackage.read(at: target) }
}
try altered("unsupported version") { url in
    var manifest = validated.manifest; manifest.version = 99
    try JSONEncoder().encode(manifest).write(to: url.appendingPathComponent("manifest.json"))
}
try altered("damaged library checksum") { url in
    try Data("{}".utf8).write(to: url.appendingPathComponent("library.json"))
}
try altered("missing media") { url in
    try manager.removeItem(at: url.appendingPathComponent("Media").appendingPathComponent(validated.manifest.assets[0].digest))
}
try altered("media checksum mismatch") { url in
    try Data("different bytes".utf8).write(to: url.appendingPathComponent("Media").appendingPathComponent(validated.manifest.assets[0].digest))
}
try altered("media symlink") { url in
    let asset = url.appendingPathComponent("Media").appendingPathComponent(validated.manifest.assets[0].digest)
    try manager.removeItem(at: asset)
    try manager.createSymbolicLink(at: asset, withDestinationURL: package.appendingPathComponent("library.json"))
}
try altered("media directory symlink") { url in
    let assets = url.appendingPathComponent("Media")
    try manager.removeItem(at: assets)
    try manager.createSymbolicLink(at: assets, withDestinationURL: package.appendingPathComponent("Media"))
}
try altered("traversal in asset digest") { url in
    var manifest = validated.manifest; manifest.assets[0].digest = "../library.json"
    try JSONEncoder().encode(manifest).write(to: url.appendingPathComponent("manifest.json"))
}
try altered("duplicate media manifest") { url in
    var manifest = validated.manifest; manifest.assets.append(manifest.assets[0])
    try JSONEncoder().encode(manifest).write(to: url.appendingPathComponent("manifest.json"))
}
for invalid in ["../outside", "/absolute", "a/b", "a\\b", ".", "..", "a\0b"] {
    rejects("Invalid media filename \(invalid)") { try LibraryBackupPackage.validateFilename(invalid) }
}
func invalidSnapshot(_ description: String, _ change: (inout LibraryBackup) -> Void) {
    var copy = snapshot; change(&copy)
    rejects(description) { try copy.validate() }
}
invalidSnapshot("Missing list reference") { $0.blocks[0].listID = UUID() }
invalidSnapshot("Missing parent") { $0.blocks[0].parentID = UUID() }
invalidSnapshot("Cyclic parent") { $0.blocks[0].parentID = $0.blocks[0].id }
invalidSnapshot("Missing label") { $0.blocks[0].labelIDs = [UUID()] }
invalidSnapshot("Invalid attachment owner") { $0.attachments[0].blockID = UUID() }
invalidSnapshot("Duplicate block UUID") { $0.blocks.append($0.blocks[0]) }
invalidSnapshot("Missing alias destination") { $0.lists[0].mergedIntoID = UUID() }
invalidSnapshot("Alias cycle") { $0.lists[0].mergedIntoID = $0.lists[0].id }
invalidSnapshot("Nonfinite order") { $0.blocks[0].sortIndex = .nan }
invalidSnapshot("Unsupported future block kind") { $0.blocks[0].kindRaw = "future" }
invalidSnapshot("Unsupported preferences") { $0.settings.defaultDestination = "other" }
invalidSnapshot("Invalid calendar horizon") { $0.settings.calendarPreferences.horizonDays = 0 }

// Restart selection is tested without ever opening the app or touching its paths.
let legacyMedia = root.appendingPathComponent("OriginalMedia")
try manager.createDirectory(at: legacyMedia, withIntermediateDirectories: true)
try legacyBytes.write(to: legacyMedia.appendingPathComponent(legacyImage.mediaFilename!))
let storage = LibraryRestoreStorage(originalStoreURL: root.appendingPathComponent("Source.store"), originalMediaURL: legacyMedia)
let originalStartup = try storage.activatePending(currentSettings: snapshot.settings, using: reader)
check(!storage.needsDerivedReset(originalStartup, defaults: defaults), "An ordinary original-library launch needs no explicit restore reset")
var incoming = validated.snapshot
incoming.libraryID = UUID()
incoming.settings.firstWeekday = 7
incoming.blocks[incoming.blocks.firstIndex { $0.id == task.id }!].text = "Restored task title"
incoming.createdAt = fixedDate.addingTimeInterval(1_000)
incoming.workSessions[0].endedAt = nil
let prepared = try storage.prepare(incoming, using: reader)
let staged = try reader.read(at: storage.storeURL(for: prepared.generation), settings: incoming.settings, createdAt: incoming.createdAt)
check(staged.workSessions[0].endedAt == work.lastHeartbeatAt, "Restored open work pauses at its last recorded heartbeat, never at relaunch time")
check(incoming.workSessions[0].endedAt == nil, "Pausing a restored session leaves the backup record unchanged")
try storage.queue(prepared)
try check(storage.selection() == nil && storage.pending() != nil, "Selecting and confirming staging does not activate it in the live process")
try check(storage.canCancelPending(), "Prepared restore offers cancellation before selection commits")
rejects("Interruption before pointer commit preserves original selection") {
    _ = try storage.activatePending(currentSettings: snapshot.settings, using: reader) { point in
        if case .beforeSelection = point { throw CocoaError(.userCancelled) }
    }
}
try check(storage.selection() == nil, "Pre-commit failure leaves the original generation selected")
check(defaults.integer(forKey: "settings.firstWeekday") == 2, "Pre-commit failure leaves original preferences unchanged")
let recoveryNames = try manager.contentsOfDirectory(atPath: storage.recoveryDirectory.path)
check(recoveryNames.count == 1, "A recoverable logical backup exists before activation")
let recoverySource = try LibraryBackupPackage.read(at: storage.recoveryDirectory.appendingPathComponent(recoveryNames[0])).snapshot
check(recoverySource.libraryID == libraryID && recoverySource.blocks.first { $0.id == task.id }?.text == task.text, "Recovery contains the original library identity and task values")
rejects("Interruption after pointer commit retains validated new and old storage") {
    _ = try storage.activatePending(currentSettings: snapshot.settings, using: reader) { point in
        if case .afterSelection = point { throw CocoaError(.userCancelled) }
    }
}
let selectedAfterCommit = try storage.selection()!
try check(!storage.canCancelPending(), "Post-commit recovery offers return instead of misleading cancellation")
check(selectedAfterCommit.generation == prepared.generation && manager.fileExists(atPath: storage.originalStoreURL.path), "Post-commit interruption leaves original store intact and points to complete staging")
check(defaults.integer(forKey: "settings.firstWeekday") == 2, "Settings are not applied to the old running environment")
let replay = try storage.activatePending(currentSettings: snapshot.settings, using: reader)
check(replay.isLocalRestore && replay.storeURL != storage.originalStoreURL && replay.mediaURL != storage.originalMediaURL, "New process resolves a separate local-only store and media generation")
try check(storage.pending() == nil, "Post-commit replay consumes the journal without repeating activation")
check(storage.needsDerivedReset(replay, defaults: defaults), "A newly selected library requires derived notification reset")
let afterJournalCleanup = try storage.activatePending(currentSettings: snapshot.settings, using: reader)
check(!afterJournalCleanup.changed && storage.needsDerivedReset(afterJournalCleanup, defaults: defaults), "Interruption after journal cleanup still replays the missing derived reset")
storage.finishDerivedReset(afterJournalCleanup, defaults: defaults, succeeded: false)
check(storage.needsDerivedReset(afterJournalCleanup, defaults: defaults), "Failed saved-state reconciliation leaves the derived reset replayable")
storage.finishDerivedReset(afterJournalCleanup, defaults: defaults, succeeded: true)
let afterDerivedRecovery = try storage.activatePending(currentSettings: snapshot.settings, using: reader)
check(!storage.needsDerivedReset(afterDerivedRecovery, defaults: defaults), "Completed reconciliation records the selection and skips repeated reset")
try check(manager.contentsOfDirectory(atPath: storage.recoveryDirectory.path).count == 1, "Replay does not duplicate recovery backups")
try storage.applySettings(replay, to: defaults)
check(defaults.integer(forKey: "settings.firstWeekday") == 7, "New selection applies restored library preferences")
defaults.set(4, forKey: "settings.firstWeekday")
try storage.applySettings(replay, to: defaults)
check(defaults.integer(forKey: "settings.firstWeekday") == 4, "Ordinary relaunch never overwrites later preference edits")
try storage.queueReturnToOriginal()
let returned = try storage.activatePending(currentSettings: .init(defaults: defaults), using: reader)
check(storage.needsDerivedReset(returned, defaults: defaults), "Returning to original uses a new selection and resets departing-library notifications")
storage.finishDerivedReset(returned, defaults: defaults, succeeded: true)
check(!storage.needsDerivedReset(returned, defaults: defaults), "Returned-original recovery is also idempotent")
try storage.applySettings(returned, to: defaults)
check(!returned.isLocalRestore && returned.storeURL == storage.originalStoreURL && returned.mediaURL == storage.originalMediaURL, "Return selects the untouched original store and its original media")
check(defaults.integer(forKey: "settings.firstWeekday") == 2, "Return restores original library preferences")
check(manager.fileExists(atPath: storage.storeURL(for: prepared.generation).path), "Return retains the restored generation for recovery")
try check(reader.read(at: returned.storeURL, settings: snapshot.settings, createdAt: fixedDate) == snapshot, "Original records survive activation and return unchanged")
try storage.queue(prepared)
try storage.cancelPending()
let cancelledStartup = try storage.activatePending(currentSettings: snapshot.settings, using: reader)
check(cancelledStartup.storeURL == storage.originalStoreURL, "Cancelling pending restore keeps the original library")

// Recovery remains usable even when the selected restored database is unreadable.
try storage.queue(prepared)
let secondRestore = try storage.activatePending(currentSettings: snapshot.settings, using: reader)
try storage.applySettings(secondRestore, to: defaults)
let damagedURL = storage.storeURL(for: prepared.generation)
let damagedEvidence = Data("unreadable restored database preserved for recovery".utf8)
try damagedEvidence.write(to: damagedURL, options: .atomic)
try storage.queueReturnToOriginal()
let recoveredOriginal = try storage.activatePending(currentSettings: incoming.settings, using: reader)
try storage.applySettings(recoveredOriginal, to: defaults)
check(recoveredOriginal.storeURL == storage.originalStoreURL && recoveredOriginal.selection?.recoveryWarning != nil, "Explicit return can recover a verified original despite unreadable restored source")
try check(Data(contentsOf: damagedURL) == damagedEvidence, "Recovery preserves corrupt-generation evidence untouched")
try check(reader.read(at: recoveredOriginal.storeURL, settings: snapshot.settings, createdAt: fixedDate).libraryID == libraryID, "Recovered original keeps its library identity")
check(defaults.integer(forKey: "settings.firstWeekday") == 2, "Corrupt-generation recovery also restores original settings")

// Both resolver replay and the actual container factory fail closed when a
// selected generation goes missing. A fresh original first launch remains valid.
let missingPrepared = try storage.prepare(incoming, using: reader)
try storage.queue(missingPrepared)
rejects("Stop after publishing selection for replay fixture") {
    _ = try storage.activatePending(currentSettings: snapshot.settings, using: reader) { point in
        if case .afterSelection = point { throw CocoaError(.userCancelled) }
    }
}
let missingSelection = try storage.selection()!
let missingURL = storage.storeURL(for: missingPrepared.generation)
let evidenceURL = missingURL.appendingPathExtension("retained-evidence")
try manager.moveItem(at: missingURL, to: evidenceURL)
rejects("Post-commit replay rejects a missing selected store") {
    _ = try storage.activatePending(currentSettings: snapshot.settings, using: reader)
}
try storage.cancelPending()
rejects("Ordinary startup rejects a missing selected store") {
    _ = try storage.activatePending(currentSettings: snapshot.settings, using: reader)
}
let missingStartup = LibraryRestoreStorage.Startup(selection: missingSelection, storeURL: missingURL,
    mediaURL: storage.mediaURL(for: missingPrepared.generation), changed: false)
rejects("Actual container factory cannot create an empty selected generation") {
    _ = try AppPersistence.openSelected(missingStartup, storage: storage, iCloudUnavailableReason: "Isolated fixture")
}
check(!manager.fileExists(atPath: missingURL.path) && manager.fileExists(atPath: evidenceURL.path), "All startup rejection paths preserve absence and retained evidence")
try storage.queueReturnToOriginal()
let missingRecovered = try storage.activatePending(currentSettings: incoming.settings, using: reader)
check(missingRecovered.storeURL == storage.originalStoreURL, "A missing generation can still return to its verified original")
// Give the fresh-install fixture its own recovery root, outside existing selection.
let freshRoot = root.appendingPathComponent("FreshInstall")
try manager.createDirectory(at: freshRoot, withIntermediateDirectories: true)
let freshStorage = LibraryRestoreStorage(originalStoreURL: freshRoot.appendingPathComponent("Openlist.store"), originalMediaURL: freshRoot.appendingPathComponent("Media"))
let freshStartup = try freshStorage.activatePending(currentSettings: snapshot.settings, using: reader)
let freshContainer = try AppPersistence.openSelected(freshStartup, storage: freshStorage, iCloudUnavailableReason: "Isolated fixture")
try check(freshContainer.container.mainContext.fetchCount(FetchDescriptor<Block>()) == 0, "An original first install can create its new store")

// A restore queued by the format-1 app predates the schema and fingerprint
// version marker. Reject that pending transition before opening either store;
// the user can cancel it and choose its valid v1 logical package again.
let oldPendingRoot = root.appendingPathComponent("PendingV1")
let oldOriginalURL = try BackupStagedStore.create(from: validated.snapshot, in: oldPendingRoot.appendingPathComponent("Original"), using: reader)
let oldStorage = LibraryRestoreStorage(originalStoreURL: oldOriginalURL, originalMediaURL: oldPendingRoot.appendingPathComponent("Original/Media"))
let oldPrepared = try oldStorage.prepare(upgraded.snapshot, using: reader)
try oldStorage.queue(oldPrepared)
struct LegacyGeneration: Codable { var createdAt: Date; var fingerprint: String }
let oldVerification = oldStorage.generationDirectory(oldPrepared.generation).appendingPathComponent("verification.json")
let originalGeneration = try JSONDecoder().decode(LegacyGeneration.self, from: Data(contentsOf: oldVerification))
try JSONEncoder().encode(originalGeneration).write(to: oldVerification)
let oldOriginalBytes = try Data(contentsOf: oldOriginalURL)
let oldStagedURL = oldStorage.storeURL(for: oldPrepared.generation)
let oldStagedBytes = try Data(contentsOf: oldStagedURL)
do {
    _ = try oldStorage.activatePending(currentSettings: validated.snapshot.settings, using: reader)
    fatalError("FAIL: Old pending restore must be rejected safely")
} catch {
    check(error.localizedDescription.contains("Cancel the pending restore") && error.localizedDescription.contains("version 1"),
        "Old prepared restore has actionable cancellation and supported package-upgrade guidance")
}
try check(oldStorage.selection() == nil && oldStorage.pending() != nil && oldStorage.canCancelPending(),
    "Version 1 pending rejection retains original selection and a cancellable journal")
try check(Data(contentsOf: oldOriginalURL) == oldOriginalBytes && Data(contentsOf: oldStagedURL) == oldStagedBytes,
    "Rejected old pending restore leaves original and staged database bytes untouched")
try oldStorage.cancelPending()
let originalAfterOldCancellation = try oldStorage.activatePending(currentSettings: validated.snapshot.settings, using: reader)
check(originalAfterOldCancellation.storeURL == oldOriginalURL && !originalAfterOldCancellation.isLocalRestore,
    "Cancelling old pending restore returns to original startup without an empty fallback")
// Compile-time DTOs plus actual SwiftData schema coverage keep newly persisted
// fields from silently falling out of this versioned reconstruction contract.
let covered: [String: Set<String>] = [
    "TaskList": Set(Mirror(reflecting: BackupTaskList(list)).children.compactMap(\.label)),
    "Block": Set(Mirror(reflecting: BackupBlock(task)).children.compactMap(\.label)),
    "SidebarSection": Set(Mirror(reflecting: BackupSidebarSection(section)).children.compactMap(\.label)),
    "TaskLabel": Set(Mirror(reflecting: BackupTaskLabel(label)).children.compactMap(\.label)),
    "Attachment": Set(Mirror(reflecting: BackupAttachment(attachment)).children.compactMap(\.label)),
    "ActivityEvent": Set(Mirror(reflecting: BackupActivityEvent(event)).children.compactMap(\.label)),
    "WorkSession": Set(Mirror(reflecting: BackupWorkSession(work)).children.compactMap(\.label)),
    "CompletionRecord": Set(Mirror(reflecting: BackupCompletionRecord(completion)).children.compactMap(\.label)),
    "SchedulePlacement": Set(Mirror(reflecting: BackupSchedulePlacement(placement)).children.compactMap(\.label))
]
check(Set(schema.entities.map(\.name)) == Set(covered.keys), "Every authoritative model is in the format contract")
for entity in schema.entities {
    check(Set(entity.properties.map(\.name)) == covered[entity.name], "Every persisted \(entity.name) field is covered")
}
// Abrupt process termination bypasses cleanup/defer. A new executable process
// resumes the durable journal on both sides of the selection publication.
for crashPhase in ["crash-before-selection", "crash-after-selection", "crash-after-journal-cleanup"] {
    let processRoot = root.appendingPathComponent(crashPhase)
    try manager.createDirectory(at: processRoot, withIntermediateDirectories: true)
    try manager.copyItem(at: package, to: processRoot.appendingPathComponent("Library.openlistbackup"))
    _ = try BackupStagedStore.create(from: validated.snapshot, in: processRoot.appendingPathComponent("Original"), using: reader)
    let process = Process(); process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    process.arguments = [processRoot.path, crashPhase]
    try process.run(); process.waitUntilExit()
    check(process.terminationReason == .uncaughtSignal && process.terminationStatus == SIGKILL, "Fixture actually stops abruptly at \(crashPhase)")
    let processStorage = LibraryRestoreStorage(originalStoreURL: processRoot.appendingPathComponent("Original/Openlist.store"), originalMediaURL: processRoot.appendingPathComponent("Original/Media"))
    if crashPhase == "crash-before-selection" {
        try check(processStorage.selection() == nil, "Abrupt pre-commit stop keeps original selection")
    } else {
        try check(processStorage.selection()?.generation != nil, "Abrupt post-commit stop retains the complete new selection")
    }
    let resumed = Process(); resumed.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    resumed.arguments = [processRoot.path, "resume-journal"]
    try resumed.run(); resumed.waitUntilExit()
    check(resumed.terminationReason == .exit && resumed.terminationStatus == 0, "New process resumes \(crashPhase) into a verified complete library")
}

// A real separate SwiftData writer commits between entity reads in the public
// pinned reader. Scalar changes stay outside the snapshot; lost external bytes
// abort the whole export instead of becoming legacy-file fallbacks.
let executable = CommandLine.arguments[0]
let oldGeneration = try reader.read(at: storage.originalStoreURL, settings: snapshot.settings, createdAt: fixedDate,
    afterFirstFetch: { [root, executable] in
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = [root.path, "mutate-scalars"]
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
    })
check(oldGeneration == snapshot, "Cross-type snapshot remains exact across a separate-process SwiftData scalar commit")
let latestGeneration = try reader.read(at: storage.originalStoreURL, settings: snapshot.settings, createdAt: fixedDate)
check(latestGeneration.blocks.contains { $0.text == "Task committed after snapshot" } && latestGeneration.lists.contains { $0.title == "List committed after snapshot" }, "A new snapshot observes both later committed entity changes")
rejects("Replacing an external blob during pinned export cannot publish missing bytes") {
    _ = try reader.read(at: storage.originalStoreURL, settings: snapshot.settings, createdAt: fixedDate,
        afterFirstFetch: { [root, executable] in
            let process = Process(); process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = [root.path, "mutate-media"]
            try process.run(); process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
        })
}

rejects("Replacing a list cover external blob during pinned export cannot publish missing bytes") {
    _ = try reader.read(at: storage.originalStoreURL, settings: snapshot.settings, createdAt: fixedDate,
        afterFirstFetch: { [root, executable] in
            let process = Process(); process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = [root.path, "mutate-cover"]
            try process.run(); process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
        })
}

print("\(checks) library backup checks passed")
