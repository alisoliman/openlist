import Foundation
import SwiftData

// The pre-task-history schema, intentionally without changeData.
@Model final class ActivityEvent {
    var id: UUID = UUID()
    var kindRaw: String = "scheduled"
    var timestamp: Date = Date.now
    var title: String = "Historic task title"
    var detail: String = "Tomorrow"
    var blockID: UUID?
    var listID: UUID?
    var listTitle: String = "Historic list title"
    var listIcon: String = "📚"
    init() { blockID = UUID(uuidString: "31000000-0000-0000-0000-000000000001") }
}

@main struct LegacyFixture {
    static func main() throws {
        let schema = Schema([ActivityEvent.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(
            schema: schema, url: URL(fileURLWithPath: CommandLine.arguments[1]), cloudKitDatabase: .none)])
        container.mainContext.insert(ActivityEvent())
        try container.mainContext.save()
    }
}
