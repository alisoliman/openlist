import AppKit
import CloudKit
import CoreData
import Security
import SwiftData

private nonisolated struct CheckFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private nonisolated struct Fixture: Codable {
    let listID: UUID
    let blockID: UUID
    let attachmentID: UUID

    func expectedID(for type: String) -> UUID? {
        switch type {
        case "CD_TaskList": listID
        case "CD_Block": blockID
        case "CD_Attachment": attachmentID
        default: nil
        }
    }
}

@MainActor private final class Transfers {
    var lastError: String?
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event, event.endDate != nil else { return }
            let error = event.succeeded ? nil : (event.error.map { ICloudError.message(for: $0) } ?? "CloudKit transfer failed")
            MainActor.assumeIsolated {
                guard let self else { return }
                if let error {
                    self.lastError = error
                    print("CloudKit operation error: \(error)")
                }
            }
        }
    }

    isolated deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}

@MainActor private final class CheckApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            let result = await CloudSyncChecks.runChecks()
            exit(result)
        }
    }
}

@main struct CloudSyncChecks {
    @MainActor private static let verificationTimeout: TimeInterval = 600

    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = CheckApplicationDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.prohibited)
        withExtendedLifetime(delegate) { application.run() }
    }

    @MainActor static func runChecks() async -> Int32 {
        do {
            guard let mode = CommandLine.arguments.dropFirst().first,
                  ["--account-only", "--connection", "--initialize-schema", "--seed", "--upload",
                   "--download-edit", "--verify-edit-delete", "--verify-deletion", "--cleanup"].contains(mode) else {
                throw CheckFailure(message: "Use run-cloud-sync-checks.sh with an explicit verification mode.")
            }
            if let reason = ICloudConfiguration.unavailableReason { throw CheckFailure(message: reason) }
            guard let task = SecTaskCreateFromSelf(nil),
                  SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-container-environment" as CFString, nil) as? String == "Development" else {
                throw CheckFailure(message: "Live checks refuse Production. Supply a development-signed app.")
            }
            if mode == "--seed" {
                let root = try verificationDirectory().appendingPathComponent("OpenlistCloudCheck-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                try seedOfflineFixture(in: root)
                print("SEEDED_ROOT: \(root.path)")
                print("RESULT: success")
                return 0
            }
            let account = try await CKContainer(identifier: ICloudConfiguration.containerIdentifier).accountStatus()
            guard account == .available else {
                throw CheckFailure(message: "iCloud account unavailable (status \(account.rawValue)). No test records were created.")
            }
            print("Development iCloud account is available")
            guard mode != "--account-only" else {
                print("RESULT: success")
                return 0
            }
            if mode == "--connection" {
                let zones = try await CKContainer(identifier: ICloudConfiguration.containerIdentifier).privateCloudDatabase.allRecordZones()
                print("PASS: authenticated CloudKit service request completed (\(zones.count) zone(s)); no records changed.")
                print("RESULT: success")
                return 0
            }
            if mode == "--cleanup" {
                guard CommandLine.arguments.count == 3 else {
                    throw CheckFailure(message: "--cleanup requires the retained diagnostic directory.")
                }
                try await cleanupRetainedFixture(at: URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true))
                print("RESULT: success")
                return 0
            }
            NSApplication.shared.registerForRemoteNotifications()
            let root: URL
            if ["--upload", "--download-edit", "--verify-edit-delete", "--verify-deletion"].contains(mode) {
                guard CommandLine.arguments.count == 3 else {
                    throw CheckFailure(message: "The round-trip requires an offline fixture directory.")
                }
                root = try validatedRoot(URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true))
            } else {
                root = try verificationDirectory().appendingPathComponent("OpenlistCloudCheck-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            }
            do {
                if mode == "--initialize-schema" {
                    try await initializeSchema(at: root.appendingPathComponent("Schema.store"))
                    print("Initialized the complete DEVELOPMENT schema. Production deployment remains a separate release step.")
                } else {
                    try await runPhase(mode, in: root)
                }
                if mode == "--initialize-schema" || mode == "--verify-deletion" {
                    try FileManager.default.removeItem(at: root)
                }
                print("RESULT: success")
            } catch {
                // No personal store is opened. Keep the isolated diagnostic DBs
                // when cloud cleanup cannot be proved, rather than losing retry data.
                print("Isolated diagnostic stores retained at \(root.path)")
                throw error
            }
        } catch {
            print("FAIL: \(diagnostic(error))")
            print("RESULT: failure")
            return 1
        }
        return 0
    }

    nonisolated private static func diagnostic(_ error: Error) -> String {
        if let failure = error as? CheckFailure { return failure.message }
        let error = error as NSError
        var messages = ["\(error.domain) \(error.code): \(error.localizedDescription)"]
        for key in ["reason", "message"] {
            if let reason = error.userInfo[key] as? String { messages.append(reason) }
        }
        if let reason = error.localizedFailureReason, !error.localizedDescription.contains(reason) { messages.append(reason) }
        if let reason = error.userInfo[NSLocalizedRecoverySuggestionErrorKey] as? String { messages.append(reason) }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? Error { messages.append(diagnostic(underlying)) }
        if let url = error.userInfo[NSURLErrorFailingURLErrorKey] as? URL, let host = url.host {
            messages.append("Service host: \(host)")
        }
        for key in [NSDetailedErrorsKey, "encounteredErrors"] {
            if let details = error.userInfo[key] as? [Error] {
                messages.append(contentsOf: details.map(diagnostic))
            }
        }
        messages.append("Diagnostic keys: \(error.userInfo.keys.sorted().joined(separator: ", "))")
        return messages.joined(separator: "\n")
    }

    @MainActor static func initializeSchema(at url: URL) async throws {
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: AppPersistence.modelTypes) else {
            throw CheckFailure(message: "Could not create the SwiftData managed object model.")
        }
        let container = NSPersistentCloudKitContainer(name: "OpenlistSchema", managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: url)
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: ICloudConfiguration.containerIdentifier)
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            container.loadPersistentStores { _, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
        do {
            try container.initializeCloudKitSchema()
        } catch {
            for store in container.persistentStoreCoordinator.persistentStores {
                try container.persistentStoreCoordinator.remove(store)
            }
            throw error
        }
        for store in container.persistentStoreCoordinator.persistentStores {
            try container.persistentStoreCoordinator.remove(store)
        }
    }

    @MainActor static func seedOfflineFixture(in root: URL) throws {
        let listID = UUID(), blockID = UUID(), attachmentID = UUID()
        let fixture = Fixture(listID: listID, blockID: blockID, attachmentID: attachmentID)
        try JSONEncoder().encode(fixture).write(to: root.appendingPathComponent("Fixture.json"), options: .atomic)
        let initialBytes = Data(repeating: 0x63, count: 2 * 1024 * 1024)
        let writerURL = root.appendingPathComponent("Writer.store")
        // The process exits before the cloud-enabled stack opens this file.
        // SwiftData may retain a container beyond an autoreleasepool's lifetime.
        try autoreleasepool {
            let offline = try AppPersistence.open(at: writerURL, iCloudUnavailableReason: "Offline fixture")
            let context = offline.container.mainContext
            context.autosaveEnabled = false
            let list = TaskList(title: "iCloud verification \(listID.uuidString)")
            list.id = listID
            list.isArchived = true
            let block = Block(kind: .task, text: "Offline capture", listID: listID)
            block.id = blockID
            block.note = "Synthetic sync verification; no personal data"
            block.richData = Data(#"{\rtf1\ansi Offline \b capture\b0}"#.utf8)
            block.labelIDs = [UUID()]
            block.mediaFilename = "\(blockID).bin"
            block.mediaData = initialBytes
            let attachment = Attachment(
                blockID: blockID, filename: "\(attachmentID).bin",
                displayName: "Synthetic test asset", contentType: "application/octet-stream",
                byteCount: initialBytes.count, contentData: initialBytes
            )
            attachment.id = attachmentID
            context.insert(list)
            context.insert(block)
            context.insert(attachment)
            try context.save()
        }
    }

    @MainActor static func runPhase(_ phase: String, in root: URL) async throws {
        let checkpointURL = root.appendingPathComponent("CompletedPhases.json")
        let checkpoints = try CloudSyncCheckpoints(at: checkpointURL)
        if checkpoints.contains(phase) {
            print("PASS: previously verified phase \(phase)")
            return
        }
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: root.appendingPathComponent("Fixture.json")))
        let listID = fixture.listID, blockID = fixture.blockID, attachmentID = fixture.attachmentID
        let bytes = Data(repeating: 0x63, count: 2 * 1024 * 1024)
        let transfers = Transfers()
        let isReader = phase == "--download-edit" || phase == "--verify-deletion"
        let storeURL = root.appendingPathComponent(isReader ? "Reader.store" : "Writer.store")
        let container = try openCloudStore(at: storeURL)
        let database = CKContainer(identifier: ICloudConfiguration.containerIdentifier).privateCloudDatabase
        switch phase {
        case "--upload":
            try await waitForCloudFixture(fixture)
            print("PASS: existing offline records and asset references reached the private iCloud database")

        case "--download-edit":
            // Each replica runs in a separate app process. This avoids assuming
            // that CloudKit delivers a device's own pushes to another local stack.
            try await wait("records and exact assets reaching an independent store", transfers: transfers) {
                let context = ModelContext(container)
                guard let block = try context.fetch(FetchDescriptor<Block>(predicate: #Predicate { $0.id == blockID })).first,
                      let attachment = try context.fetch(FetchDescriptor<Attachment>(predicate: #Predicate { $0.id == attachmentID })).first else { return false }
                let listCount = try context.fetchCount(FetchDescriptor<TaskList>(predicate: #Predicate { $0.id == listID }))
                return ["Offline capture", "Edited on the second store"].contains(block.text) && block.mediaData == bytes
                    && attachment.contentData == bytes && listCount == 1
            }
            print("PASS: an independent store downloaded records and both exact 2 MiB assets")
            let editingContext = container.mainContext
            let edited = try editingContext.fetch(FetchDescriptor<Block>(predicate: #Predicate { $0.id == blockID })).first!
            edited.text = "Edited on the second store"
            edited.isCompleted = true
            edited.completedAt = .now
            try editingContext.save()
            try await waitForCloudEdit(fixture, in: database)
            print("PASS: the second replica's edit and completion reached iCloud")

        case "--verify-edit-delete":
            // A retry after local deletion must not wait for that deleted task.
            try await checkpoints.perform("\(phase):imported") {
                try await wait("remote edit and completion reaching the first store", transfers: transfers) {
                    let context = ModelContext(container)
                    let block = try context.fetch(FetchDescriptor<Block>(predicate: #Predicate { $0.id == blockID })).first
                    return block?.text == "Edited on the second store" && block?.isCompleted == true
                }
            }
            print("PASS: the original persistent store imported the other replica's edit and completion")
            let cleanup = container.mainContext
            for value in try cleanup.fetch(FetchDescriptor<Attachment>(predicate: #Predicate { $0.id == attachmentID })) { cleanup.delete(value) }
            for value in try cleanup.fetch(FetchDescriptor<Block>(predicate: #Predicate { $0.id == blockID })) { cleanup.delete(value) }
            for value in try cleanup.fetch(FetchDescriptor<TaskList>(predicate: #Predicate { $0.id == listID })) { cleanup.delete(value) }
            try cleanup.save()
            let deadline = Date.now.addingTimeInterval(verificationTimeout)
            while !(try await matchingRecords(fixture, in: database).isEmpty) {
                guard Date.now < deadline else { throw CheckFailure(message: "Cloud fixture deletion did not finish within the verification deadline.") }
                try await Task.sleep(for: .seconds(10))
            }
            print("PASS: native deletion removed all synthetic records from iCloud")

        case "--verify-deletion":
            try await wait("deletion reaching the persistent store that previously held the fixture", transfers: transfers) {
                let context = ModelContext(container)
                return try context.fetchCount(FetchDescriptor<TaskList>(predicate: #Predicate { $0.id == listID })) == 0
                    && context.fetchCount(FetchDescriptor<Block>(predicate: #Predicate { $0.id == blockID })) == 0
                    && context.fetchCount(FetchDescriptor<Attachment>(predicate: #Predicate { $0.id == attachmentID })) == 0
            }
            print("PASS: the second persistent replica imported deletion; cloud fixture cleanup is verified")

        default:
            throw CheckFailure(message: "Unknown verification phase.")
        }
        try checkpoints.record(phase)
    }

    @MainActor private static func validatedRoot(_ root: URL) throws -> URL {
        let root = root.resolvingSymlinksInPath().standardizedFileURL
        let temp = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        let group = try verificationDirectory().resolvingSymlinksInPath().standardizedFileURL
        let prefix = "OpenlistCloudCheck-"
        guard [temp, group].contains(root.deletingLastPathComponent()),
              root.lastPathComponent.hasPrefix(prefix),
              UUID(uuidString: String(root.lastPathComponent.dropFirst(prefix.count))) != nil else {
            throw CheckFailure(message: "Refusing access outside an isolated OpenlistCloudCheck directory.")
        }
        return root
    }

    @MainActor private static func cleanupRetainedFixture(at root: URL) async throws {
        let root = try validatedRoot(root)
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: root.appendingPathComponent("Fixture.json")))
        let database = CKContainer(identifier: ICloudConfiguration.containerIdentifier).privateCloudDatabase
        let matches = try await matchingRecords(fixture, in: database)
        for id in matches { _ = try await database.deleteRecord(withID: id) }
        guard try await matchingRecords(fixture, in: database).isEmpty else {
            throw CheckFailure(message: "Synthetic records are still present; the diagnostic stores were kept.")
        }
        // No model container is opened in this recovery path. Pending local
        // fixture transactions cannot upload again after deleting this directory.
        try FileManager.default.removeItem(at: root)
        print("PASS: removed \(matches.count) synthetic cloud record(s), confirmed their absence, and removed the isolated local stores.")
    }

    @MainActor private static func matchingRecords(_ fixture: Fixture, in database: CKDatabase, recordType: String? = nil) async throws -> [CKRecord.ID] {
        var matches: [CKRecord.ID] = []
        for zone in try await database.allRecordZones() {
            guard zone.zoneID.zoneName != CKRecordZone.default().zoneID.zoneName else { continue }
            var token: CKServerChangeToken?
            var more = true
            while more {
                // Read identifiers only, never personal task text or asset bytes.
                let changes = try await database.recordZoneChanges(
                    inZoneWith: zone.zoneID, since: token, desiredKeys: ["CD_id"], resultsLimit: 200
                )
                for result in changes.modificationResultsByID.values {
                    let record = try result.get().record
                    if let recordType, record.recordType != recordType { continue }
                    guard let expected = fixture.expectedID(for: record.recordType) else { continue }
                    let id: UUID?
                    if let string = record["CD_id"] as? String {
                        id = UUID(uuidString: string)
                    } else if let data = record["CD_id"] as? Data, data.count == 16 {
                        id = data.withUnsafeBytes { UUID(uuid: $0.loadUnaligned(as: uuid_t.self)) }
                    } else {
                        throw CheckFailure(message: "A synced \(record.recordType) record has an unrecognized ID representation; refusing to guess during cleanup.")
                    }
                    if id == expected { matches.append(record.recordID) }
                }
                token = changes.changeToken
                more = changes.moreComing
            }
        }
        return matches
    }

    @MainActor private static func waitForCloudFixture(_ fixture: Fixture) async throws {
        let database = CKContainer(identifier: ICloudConfiguration.containerIdentifier).privateCloudDatabase
        let deadline = Date.now.addingTimeInterval(verificationTimeout)
        while Date.now < deadline {
            if try await matchingRecords(fixture, in: database).count == 3 { return }
            try await Task.sleep(for: .seconds(10))
        }
        throw CheckFailure(message: "Existing offline records did not reach the private iCloud database within the verification deadline.")
    }

    @MainActor private static func waitForCloudEdit(_ fixture: Fixture, in database: CKDatabase) async throws {
        let deadline = Date.now.addingTimeInterval(verificationTimeout)
        while Date.now < deadline {
            let ids = try await matchingRecords(fixture, in: database, recordType: "CD_Block")
            let results = try await database.records(for: ids, desiredKeys: ["CD_text", "CD_isCompleted"])
            for result in results.values {
                let record = try result.get()
                if record["CD_text"] as? String == "Edited on the second store",
                   (record["CD_isCompleted"] as? NSNumber)?.boolValue == true { return }
            }
            try await Task.sleep(for: .seconds(10))
        }
        throw CheckFailure(message: "The second replica's edit did not reach iCloud within the verification deadline.")
    }

    @MainActor static func openCloudStore(at url: URL) throws -> ModelContainer {
        let loaded = try AppPersistence.open(at: url, iCloudUnavailableReason: nil)
        if let reason = loaded.iCloudUnavailableReason { throw CheckFailure(message: reason) }
        // Match app startup: opening a lazy container alone does not exercise
        // the store. Register and fetch through its main context before waiting.
        let context = loaded.container.mainContext
        context.autosaveEnabled = true
        _ = try context.fetchCount(FetchDescriptor<TaskList>())
        return loaded.container
    }

    @MainActor private static func verificationDirectory() throws -> URL {
        guard let group = AppGroup.containerURL else {
            throw CheckFailure(message: "The signed app cannot access its App Group container.")
        }
        return group.appendingPathComponent("CloudSyncChecks", isDirectory: true)
    }

    @MainActor private static func wait(_ description: String, transfers: Transfers, until condition: () throws -> Bool) async throws {
        let deadline = Date.now.addingTimeInterval(verificationTimeout)
        while Date.now < deadline {
            if try condition() { return }
            try await Task.sleep(for: .seconds(2))
        }
        throw CheckFailure(message: "Timed out waiting for \(description). \(transfers.lastError ?? "CloudKit did not complete the operation within the verification deadline.")")
    }
}
