import AppKit
import Foundation
import SwiftData

var checks = 0
func check(_ value: @autoclosure () throws -> Bool, _ message: String) rethrows {
    checks += 1
    guard try value() else { fatalError(message) }
}

struct CopiedLinks: Codable {
    var libraryID: UUID
    var taskID: UUID
    var listID: UUID
    var task: URL
    var list: URL
}

let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let phase = CommandLine.arguments[2]
let manager = FileManager.default
try manager.createDirectory(at: root, withIntermediateDirectories: true)
let storage = LibraryRestoreStorage(originalStoreURL: root.appendingPathComponent("Original/Openlist.store"),
    originalMediaURL: root.appendingPathComponent("Original/Media"))
let package = root.appendingPathComponent("Library.openlistbackup")
let copiedURL = root.appendingPathComponent("copied-links.json")
let defaultsName = "openlist.link-restore-check.\(UUID())"
let defaults = UserDefaults(suiteName: defaultsName)!
defer { defaults.removePersistentDomain(forName: defaultsName) }
let settings = LibraryBackupSettings(defaults: defaults)
let reader = try BackupSnapshotReader(schema: AppPersistence.schema)

func navigation(context: ModelContext, storeURL: URL) throws -> (Navigator, LocalLinkNavigation) {
    let navigator = Navigator()
    let links = LocalLinkNavigation(libraryID: try LibraryIdentity.read(at: storeURL), navigator: navigator)
    links.storeReady { target in
        try LocalLinkNavigation.resolve(target, blocks: context.fetch(FetchDescriptor<Block>()),
            lists: context.fetch(FetchDescriptor<TaskList>()))
    }
    links.windowReady(true)
    return (navigator, links)
}

if phase == "prepare" {
    try manager.createDirectory(at: storage.originalMediaURL, withIntermediateDirectories: true)
    let loaded = try AppPersistence.open(at: storage.originalStoreURL, iCloudUnavailableReason: "Isolated link fixture")
    let context = loaded.container.mainContext
    context.autosaveEnabled = false
    let list = TaskList(title: "Original document")
    let task = Block(kind: .task, text: "Original task", listID: list.id)
    context.insert(list)
    context.insert(task)
    try context.save()
    let (_, links) = try navigation(context: context, storeURL: storage.originalStoreURL)
    let copied = try CopiedLinks(libraryID: LibraryIdentity.read(at: storage.originalStoreURL),
        taskID: task.id, listID: list.id, task: links.link(to: .task(task.id)), list: links.link(to: .list(list.id)))
    try JSONEncoder().encode(copied).write(to: copiedURL)
    let snapshot = try reader.read(at: storage.originalStoreURL, settings: settings)
    try LibraryBackupPackage.write(snapshot, to: package) { _ in throw CocoaError(.fileReadNoSuchFile) }
    try check(LocalLink.parse(copied.task).libraryID == snapshot.libraryID, "Copied task URL records the backed-up library identity")
    try check(LocalLink.parse(copied.list).target == .list(list.id), "Copied list URL records the original stable list identity")
} else {
    let copied = try JSONDecoder().decode(CopiedLinks.self, from: Data(contentsOf: copiedURL))
    var snapshot = try LibraryBackupPackage.read(at: package).snapshot
    if phase == "return" {
        try storage.queueReturnToOriginal()
    } else {
        if phase == "different" { snapshot.libraryID = UUID() }
        let prepared = try storage.prepare(snapshot, using: reader)
        try storage.queue(prepared)
    }
    let startup = try storage.activatePending(currentSettings: settings, using: reader)
    let loaded = try AppPersistence.openSelected(startup, storage: storage, iCloudUnavailableReason: "Isolated link fixture")
    let context = loaded.container.mainContext
    context.autosaveEnabled = false
    let (navigator, links) = try navigation(context: context, storeURL: startup.storeURL)
    let task = try context.fetch(FetchDescriptor<Block>()).first { $0.id == copied.taskID }!
    let expectedIdentity = phase == "different" ? snapshot.libraryID : copied.libraryID
    try check(LibraryIdentity.read(at: startup.storeURL) == expectedIdentity, "Selected store metadata preserves the selected library identity")
    check(startup.isLocalRestore == (phase != "return"), "Restore and Return select their intended storage generation")
    if phase == "different" {
        try check(LibraryIdentity.read(at: storage.originalStoreURL) == copied.libraryID, "Restoring another library leaves original identity unchanged")
        links.receive(copied.task)
        check(links.error == .wrongLibrary && navigator.contentReveal == nil, "Old task URL rejects another selected library despite identical item UUIDs")
        links.receive(copied.list)
        check(links.error == .wrongLibrary && navigator.contentReveal == nil, "Old list URL rejects another selected library despite identical item UUIDs")
        let selectedTaskLink = try links.link(to: .task(copied.taskID))
        try check(LocalLink.parse(selectedTaskLink).libraryID == snapshot.libraryID && selectedTaskLink != copied.task,
            "Copy uses the active restored library identity rather than the original store")
        links.receive(selectedTaskLink)
        check(links.error == nil && navigator.openTaskID == copied.taskID, "A link copied in the other restored library resolves there")
    } else {
        try check(links.link(to: .task(copied.taskID)) == copied.task && links.link(to: .list(copied.listID)) == copied.list,
            "Copied task and list URLs remain identical across restore and return")
        links.receive(copied.task)
        check(links.error == nil && navigator.openTaskID == copied.taskID, "Previously copied task URL resolves in the selected store")
        links.receive(copied.list)
        check(links.error == nil && navigator.contentReveal?.destination == .list(copied.listID), "Previously copied list URL resolves in the selected store")
        check(task.text == "Original task", "Selected task content comes from the intended saved library")
        if phase == "restore" {
            check(startup.storeURL != storage.originalStoreURL, "Restored link target uses a separate store location")
            task.text = "Edited only in the restored generation"
            try context.save()
        } else {
            check(startup.storeURL == storage.originalStoreURL, "Return resolves links against the untouched original store")
        }
    }
}
print("Passed \(checks) separate-process selected-library link checks (\(phase))")
