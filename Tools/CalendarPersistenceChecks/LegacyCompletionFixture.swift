import Foundation
import SwiftData

/// Frozen completion schema before calendar interval snapshots were introduced.
@Model final class CompletionRecord {
    var id: UUID = UUID()
    var taskID: UUID = UUID()
    var occurrenceID: UUID = UUID()
    var listID: UUID?
    var title: String = ""
    var completedAt: Date = Date.now
    var dueDate: Date?
    var estimateMinutes: Int = 30
    var wasRecurring: Bool = false

    init() {}
}

@Model final class WorkSession {
    var id: UUID = UUID()
    var taskID: UUID = UUID()
    var occurrenceID: UUID = UUID()
    var listID: UUID?
    var title: String = ""
    var startedAt: Date = Date.now
    var endedAt: Date?
    var lastHeartbeatAt: Date = Date.now
    var deviceID: String = ""
    var correctedMinutes: Double?
    var pauseReason: String?
    init() {}
}

@main struct LegacyCompletionFixture {
    static func main() throws {
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let schema = Schema([CompletionRecord.self, WorkSession.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        let record = CompletionRecord()
        record.title = "Pre-snapshot recurring completion"
        record.completedAt = Date(timeIntervalSince1970: 1_750_000_000)
        record.dueDate = Date(timeIntervalSince1970: 1_749_999_000)
        record.estimateMinutes = 45
        record.wasRecurring = true
        container.mainContext.insert(record)
        let session = WorkSession()
        session.title = "Pre-snapshot work session"
        session.startedAt = record.completedAt.addingTimeInterval(-1_800)
        session.endedAt = record.completedAt
        session.lastHeartbeatAt = record.completedAt
        session.correctedMinutes = 20
        session.deviceID = "legacy-mac"
        container.mainContext.insert(session)
        try container.mainContext.save()
        print("Created pre-snapshot completion fixture")
    }
}
