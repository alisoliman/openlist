import Foundation
import SwiftData

enum IdentityV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [Entry.self] }
    @Model final class Entry {
        var id: UUID = UUID()
        var title: String = ""
        init(title: String) { self.title = title }
    }
}
enum IdentityV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] { [Entry.self] }
    @Model final class Entry {
        var id: UUID = UUID()
        var title: String = ""
        var additionalDetail: String?
        init(title: String) { self.title = title }
    }
}
enum IdentityMigration: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [IdentityV1.self, IdentityV2.self] }
    static var stages: [MigrationStage] { [.lightweight(fromVersion: IdentityV1.self, toVersion: IdentityV2.self)] }
}

@main struct IdentityChecks {
    static func main() throws {
        let phase = CommandLine.arguments[1]
        let directory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("fixture.store")
        let expectedURL = directory.appendingPathComponent("expected.json")
        if phase == "prepare" {
            let schema = Schema(versionedSchema: IdentityV1.self)
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
            let entry = IdentityV1.Entry(title: "Persistent target")
            container.mainContext.insert(entry)
            try container.mainContext.save()
            try JSONEncoder().encode([LibraryIdentity.read(at: url), entry.id]).write(to: expectedURL)
            print("Prepared independent-process library identity fixture")
        } else {
            let expected = try JSONDecoder().decode([UUID].self, from: Data(contentsOf: expectedURL))
            let beforeOpen = try LibraryIdentity.read(at: url)
            precondition(beforeOpen == expected[0], "File-copy/full-restore metadata preserves identity")
            let schema = Schema(versionedSchema: IdentityV2.self)
            let container = try ModelContainer(for: schema, migrationPlan: IdentityMigration.self,
                configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
            let item = try container.mainContext.fetch(FetchDescriptor<IdentityV2.Entry>()).first!
            precondition(item.id == expected[1], "Migration/restoration preserves target identity")
            let afterMigration = try LibraryIdentity.read(at: url)
            precondition(afterMigration == expected[0], "Lightweight migration preserves library identity")
            item.additionalDetail = "Edited after migration"
            try container.mainContext.save()
            let afterSave = try LibraryIdentity.read(at: url)
            precondition(afterSave == expected[0], "Save after migration preserves identity")
            print("Passed 4 independent-process \(phase) metadata/target checks")
        }
    }
}
