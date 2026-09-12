import AppKit
import SwiftData

@main struct LegacyFixture {
    @MainActor static func main() throws {
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let schema = Schema([TaskList.self, Block.self, SidebarSection.self, TaskLabel.self, Attachment.self, ActivityEvent.self])
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        ])
        let context = container.mainContext
        context.autosaveEnabled = false
        let inbox = TaskList()
        inbox.id = UUID(uuidString: "F0000000-0000-0000-0000-000000000001")!
        inbox.title = "Inbox"
        inbox.isSystemInbox = true
        let section = SidebarSection()
        section.id = UUID(uuidString: "F0000000-0000-0000-0000-000000000002")!
        section.title = "My lists"
        section.isDefault = true
        let list = TaskList()
        list.title = "Existing local list"
        list.sectionID = section.id
        list.isPinned = true
        list.summary = "Keep my local data"
        list.sortIndex = 2048
        let label = TaskLabel()
        label.name = "legacy"
        let task = Block()
        task.kindRaw = "task"
        task.text = "Legacy task"
        task.note = "A note written before iCloud"
        task.richData = Data(#"{\rtf1\ansi Legacy \b task\b0}"#.utf8)
        task.listID = list.id
        task.labelIDs = [label.id]
        task.dueDate = Date(timeIntervalSince1970: 2_100_000_000)
        task.reminderAt = task.dueDate!.addingTimeInterval(-600)
        task.includesTime = true
        task.priorityRaw = 3
        task.isStarred = true
        task.recurrenceData = Recurrence.weekly.jsonData
        let image = Block()
        image.kindRaw = "image"
        image.listID = list.id
        image.parentID = task.id
        image.sortIndex = 1024
        image.mediaFilename = "legacy.png"
        image.mediaCaption = "Keep this image"
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        let red = NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1)
        for x in 0..<2 { for y in 0..<2 { bitmap.setColor(red, atX: x, y: y) } }
        let imageBytes = bitmap.representation(using: .png, properties: [:])!
        try MediaStore.shared.restoreFile(imageBytes, filename: "legacy.png")
        let attachment = Attachment()
        attachment.blockID = task.id
        attachment.filename = "legacy.bin"
        attachment.displayName = "Original document.bin"
        attachment.contentType = "application/octet-stream"
        let bytes = Data(repeating: 0xA5, count: 2 * 1024 * 1024)
        attachment.byteCount = bytes.count
        try MediaStore.shared.restoreFile(bytes, filename: attachment.filename)
        let event = ActivityEvent()
        event.title = task.text
        event.blockID = task.id
        event.listID = list.id
        event.listTitle = list.title
        context.insert(inbox)
        context.insert(section)
        context.insert(list)
        context.insert(label)
        context.insert(task)
        context.insert(image)
        context.insert(attachment)
        context.insert(event)
        try context.save()
        print("Created pre-iCloud SQLite fixture")
    }
}
