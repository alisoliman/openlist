import Foundation
import SwiftData
import CoreData

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
        let originalTask = try context.fetch(FetchDescriptor<Block>()).first { $0.id == UUID(uuidString: "24000000-0000-0000-0000-000000000004")! }!
        let section = SidebarSection(title: "Original grouping", sortIndex: 19, isDefault: true)
        context.insert(section); list.sectionID = section.id
        let label = TaskLabel(name: "Original label", accent: .orange)
        context.insert(label); originalTask.labelIDs = [label.id]
        let image = Block(kind: .image, listID: inbox.id, parentID: originalTask.id)
        image.mediaFilename = "old-image.png"; image.mediaCaption = "Original caption"
        image.mediaData = Data(repeating: 0x42, count: 1_048_601)
        image.mediaWidth = 240; image.mediaHeight = 120
        context.insert(image)
        let bytes = Data(repeating: 0x57, count: 2_097_163)
        let attachment = Attachment(blockID: originalTask.id, filename: "old-file.pdf", displayName: "Original paper", contentType: "application/pdf", byteCount: bytes.count, contentData: bytes)
        context.insert(attachment)
        let time = Date(timeIntervalSinceReferenceDate: 700000000)
        let event = ActivityEvent(kind: .renamed, title: "Earlier original title", blockID: originalTask.id, listID: inbox.id, listTitle: "Inbox")
        event.timestamp = time; context.insert(event)
        let session = WorkSession(task: originalTask, deviceID: "Old fixture", startedAt: time)
        session.endedAt = time.addingTimeInterval(300); context.insert(session)
        context.insert(CompletionRecord(task: originalTask, completedAt: time, estimateMinutes: 25))
        context.insert(SchedulePlacement(task: originalTask, start: time, end: time.addingTimeInterval(1800)))
        try context.save()
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: url)
        let libraryID = UUID(uuidString: metadata[NSStoreUUIDKey] as! String)!
        let suite = "OpenlistInboxLegacy-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let snapshot = try LibraryBackup(context: context, libraryID: libraryID, settings: .init(defaults: defaults), createdAt: time)
        try JSONEncoder().encode(snapshot).write(to: url.appendingPathExtension("json"))
        print("Created actual prior Block schema in a separate process")
    }
}
