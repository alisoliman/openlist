import Foundation
import SwiftData

@main struct LegacyFixture {
    static func main() throws {
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let schema = Schema([TaskList.self, Block.self, SidebarSection.self, TaskLabel.self, Attachment.self, ActivityEvent.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        let context = container.mainContext
        let list = TaskList(title: "Legacy list", icon: "📚", accent: .blue)
        let task = Block(kind: .task, text: "Legacy café 日本語 ✅", listID: list.id)
        task.id = UUID(uuidString: "C0000000-0000-0000-0000-000000000001")!
        task.note = "Preserve rich task payload"
        task.richData = Data(#"{\rtf1\ansi Legacy \b text\b0}"#.utf8)
        task.dueDate = Date(timeIntervalSince1970: 2_100_000_000)
        task.includesTime = true
        task.priorityRaw = 3
        task.recurrenceData = Recurrence.weekly.jsonData
        let second = Block(kind: .task, text: "Second legacy task", listID: list.id)
        context.insert(list)
        context.insert(task)
        context.insert(second)
        try context.save()
        print("Created pre-calendar fixture")
    }
}
