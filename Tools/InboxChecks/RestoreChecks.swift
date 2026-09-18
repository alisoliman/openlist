import CoreData
import Foundation
import SwiftData

var checks = 0
func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
    checks += 1
    guard try value() else { fatalError("FAIL: \(message)") }
}
func files(in root: URL) throws -> [String: Data] {
    let manager = FileManager.default
    var result: [String: Data] = [:]
    let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL
    let rootComponents = canonicalRoot.pathComponents
    let enumerator = manager.enumerator(at: canonicalRoot, includingPropertiesForKeys: [.isRegularFileKey])!
    for case let file as URL in enumerator {
        // Core Data may update read marks in SHM, but authoritative database,
        // WAL and external payload files must remain byte-for-byte unchanged.
        let components = file.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        guard components.starts(with: rootComponents) else {
            fatalError("FAIL: Enumerated original file escaped the fixture root")
        }
        let relativeComponents = components.dropFirst(rootComponents.count)
        let relative = relativeComponents.joined(separator: "/")
        if try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true,
           !file.lastPathComponent.hasSuffix("-shm"), relativeComponents.first != "LibraryRecovery" {
            result[relative] = try Data(contentsOf: file)
        }
    }
    return result
}
@main struct RestoreChecks {
    static func main() throws {
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let phase = CommandLine.arguments[2]
let originalDirectory = root.appendingPathComponent("Original")
let originalURL = originalDirectory.appendingPathComponent("Openlist.store")
var expected = try JSONDecoder().decode(LibraryBackup.self, from: Data(contentsOf: originalURL.appendingPathExtension("json")))
try expected.upgradeToCurrentVersion()
let originalFiles = try files(in: originalDirectory)
let reader = try BackupSnapshotReader(schema: AppPersistence.schema)
let storage = LibraryRestoreStorage(originalStoreURL: originalURL, originalMediaURL: originalDirectory.appendingPathComponent("Media"))
let model = NSManagedObjectModel.makeManagedObjectModel(for: AppPersistence.schema)!
let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: originalURL)
try check(!model.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata), "Retained original still has the actual old Block schema before startup")

if phase == "restore" {
    let read = try reader.readClosedStore(at: originalURL, settings: expected.settings, createdAt: expected.createdAt)
    try check(read == expected, "Private migration retains every DTO field, UUID, rich content, history and calendar source record")
    try check(read.blocks.allSatisfy { $0.inboxMembershipData == nil }, "Private migration leaves all old membership fields nil")
    try check(read.attachments.first?.contentData?.count == 2_097_163 && read.blocks.contains { $0.mediaData?.count == 1_048_601 }, "Large external image and attachment bytes survive private migration")
    try check(try files(in: originalDirectory) == originalFiles, "Private migration leaves original database, WAL, payloads and snapshot unchanged")
    let scratch = root.appendingPathComponent("Scratch")
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    do {
        _ = try reader.readClosedStore(at: originalURL, settings: expected.settings, temporaryDirectory: scratch) { _ in
            throw CocoaError(.fileReadNoPermission)
        }
        fatalError("FAIL: Injected copy inspection failure must stop")
    } catch {
        try check(try FileManager.default.contentsOfDirectory(atPath: scratch.path).isEmpty, "Failed private migration preflight removes its temporary copy")
    }
    try check(try files(in: originalDirectory) == originalFiles, "Failed private-copy preflight leaves every original authoritative file intact")
    let futureURL = root.appendingPathComponent("Future.store")
    try autoreleasepool {
        let future = model.copy() as! NSManagedObjectModel
        let field = NSAttributeDescription(); field.name = "unsupportedFutureField"; field.attributeType = .stringAttributeType; field.isOptional = true
        future.entities.first { $0.name == "Block" }!.properties.append(field)
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: future)
        let store = try coordinator.addPersistentStore(type: .sqlite, at: futureURL)
        try coordinator.remove(store)
    }
    let futureBytes = try Data(contentsOf: futureURL)
    do {
        _ = try reader.readClosedStore(at: futureURL, settings: expected.settings)
        fatalError("FAIL: Unknown schema must not be migrated")
    } catch {
        try check(error.localizedDescription.contains("incompatible schema"), "Newer/unrelated schema is rejected with recovery guidance")
    }
    try check(try Data(contentsOf: futureURL) == futureBytes, "Rejected incompatible store remains untouched")
    var incoming = expected
    incoming.libraryID = UUID()
    incoming.settings.parsesNaturalLanguageDates.toggle()
    incoming.blocks[incoming.blocks.firstIndex { $0.id == UUID(uuidString: "24000000-0000-0000-0000-000000000004")! }!].text = "Restored task only"
    let prepared = try storage.prepare(incoming, using: reader)
    try storage.queue(prepared)
    let startup = try storage.activatePending(currentSettings: expected.settings, using: reader)
    try check(startup.isLocalRestore && startup.selection?.libraryID == incoming.libraryID, "Restore selects the validated independent generation")
    let afterRestoreFiles = try files(in: originalDirectory)
    if afterRestoreFiles != originalFiles {
        print("Original file changes:", Set(afterRestoreFiles.keys).union(originalFiles.keys).filter { afterRestoreFiles[$0] != originalFiles[$0] }.sorted())
        fflush(stdout)
    }
    try check(try files(in: originalDirectory) == originalFiles, "Restore startup creates recovery without migrating retained original")
    try autoreleasepool {
        let opened = try AppPersistence.openSelected(startup, storage: storage, iCloudUnavailableReason: "Isolated migration fixture")
        let context = opened.container.mainContext; context.autosaveEnabled = false
        let task = try context.fetch(FetchDescriptor<Block>()).first { $0.text == "Restored task only" }!
        task.text = "Edited restored generation"
        task.inboxMembershipData = try LegacyInboxMembership.included(order: 8192, occurrenceID: task.occurrenceID).encoded()
        try context.save()
    }
    try check(try files(in: originalDirectory) == originalFiles, "Editing new selected-generation schema leaves old original unchanged")
    print("\(checks) old-schema private migration/restore checks passed")
    exit(0)
}

try check(storage.selection()?.generation != nil, "A new process starts with the restored generation selected")
let currentSettings = try storage.selection()!.settings
try storage.queueReturnToOriginal()
let returned = try storage.activatePending(currentSettings: currentSettings, using: reader)
try check(returned.selection?.generation == nil && returned.selection?.libraryID == expected.libraryID, "Cold Return selects retained original UUID across schema upgrade")
try check(returned.selection?.settings == expected.settings, "Return keeps original settings independently of restored changes")
try check(try files(in: originalDirectory) == originalFiles, "Return preflight never migrates or rewrites original authoritative files")
let recovery = try LibraryBackupPackage.read(at: storage.recoveryDirectory.appendingPathComponent(returned.selection!.recoveryName!))
try check(recovery.snapshot.blocks.contains { $0.text == "Edited restored generation" && $0.inboxMembershipData != nil }, "Return recovery includes current restored content and v2 membership")
try autoreleasepool {
    let opened = try AppPersistence.openSelected(returned, storage: storage, iCloudUnavailableReason: "Isolated migration fixture")
    opened.container.mainContext.autosaveEnabled = false
    let actual = try LibraryBackup(context: opened.container.mainContext, libraryID: expected.libraryID, settings: expected.settings, createdAt: expected.createdAt)
    try check(actual == expected, "Actual selected original factory performs supported migration with full old DTO equality")
}
try check(try storage.pending() == nil, "Successful Return completes the pending journal")
print("\(checks) separate-process original Return/migration checks passed")

    }
}
