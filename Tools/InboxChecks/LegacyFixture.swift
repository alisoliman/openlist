import Foundation
import SwiftData

// This executable is built with the exact pre-BRI24 Block definition. Its
// SQLite store is closed before the new executable performs real migration.
@main struct LegacyFixture {
    static func main() throws {
        let schema = Schema([TaskList.self, Block.self, SidebarSection.self, TaskLabel.self, Attachment.self,
                             ActivityEvent.self, WorkSession.self, CompletionRecord.self, SchedulePlacement.self])
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        let context = container.mainContext
        context.autosaveEnabled = false
        let inbox = TaskList(title: "Inbox", isSystemInbox: true)
        inbox.id = UUID(uuidString: "24000000-0000-0000-0000-000000000001")!
        inbox.summary = "Original rich capture document"
        context.insert(inbox)
        let list = TaskList(title: "Project")
        list.id = UUID(uuidString: "24000000-0000-0000-0000-000000000002")!
        context.insert(list)
        let note = Block(kind: .paragraph, text: "Rich Inbox note", listID: inbox.id, sortIndex: 100)
        note.id = UUID(uuidString: "24000000-0000-0000-0000-000000000003")!
        note.richData = Data("retained rich bytes".utf8)
        context.insert(note)
        for index in 4...6 {
            let task = Block(kind: .task, text: "Legacy task \(index)", listID: inbox.id,
                parentID: index == 5 ? note.id : nil, sortIndex: Double(index * 100))
            task.id = UUID(uuidString: String(format: "24000000-0000-0000-0000-%012d", index))!
            task.note = "Task details preserved"
            task.isCompleted = index == 6
            if task.isCompleted { task.completedAt = Date(timeIntervalSinceReferenceDate: 700000000) }
            context.insert(task)
        }
        let project = Block(kind: .task, text: "Existing project task", listID: list.id)
        project.id = UUID(uuidString: "24000000-0000-0000-0000-000000000007")!
        context.insert(project)
        try context.save()
        print("Created actual prior Block schema in a separate process")
    }
}
