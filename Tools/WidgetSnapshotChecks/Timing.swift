import Foundation
import SwiftData

/// Times snapshot rebuilds on a library far larger than the fixture: fifty
/// documents with 5,000 tasks among 20,000 prose blocks, and 10,000 retained
/// completions. Saves, work state changes and settings changes all rebuild on
/// the main actor, so these numbers are what a typing pause or a Start costs.
/// The times are printed for a person to read; the checks count what each
/// rebuild reads instead, which a busy machine doesn't change.
@MainActor
func runTimingChecks(directory: URL, now: Date) throws {
    let schema = Schema([TaskList.self, Block.self, SidebarSection.self, TaskLabel.self, Attachment.self, ActivityEvent.self,
                         WorkSession.self, CompletionRecord.self, SchedulePlacement.self])
    let configuration = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("Timing.store"), cloudKitDatabase: .none)
    let container = try ModelContainer(for: schema, configurations: [configuration])
    let store = Store(context: container.mainContext)
    store.bootstrap()
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: now)

    var tasks: [Block] = []
    var lists: [TaskList] = []
    store.isLoggingSuspended = true
    for listIndex in 0..<50 {
        let list = TaskList(title: "List \(listIndex)", icon: "📋", accent: .blue)
        lists.append(list)
        list.sortIndex = Double(listIndex)
        list.sidebarIndex = Double(listIndex)
        store.context.insert(list)
        var index = 0.0
        for section in 0..<20 {
            let heading = Block(kind: .heading2, text: "Section \(section)", listID: list.id, sortIndex: index)
            store.context.insert(heading)
            index += 1
            for paragraph in 0..<19 {
                store.context.insert(Block(kind: .paragraph, text: "Notes \(section).\(paragraph) for the list's document",
                                           listID: list.id, sortIndex: index))
                index += 1
            }
            for row in 0..<5 {
                // Half the tasks sit under their section's heading.
                let parent = row.isMultiple(of: 2) ? heading : nil
                let task = Block(kind: .task, text: "Task \(listIndex).\(section).\(row)", listID: list.id,
                                 parentID: parent?.id, sortIndex: parent == nil ? index : Double(row))
                if parent == nil { index += 1 }
                if row == 1 { task.dueDate = calendar.date(byAdding: .day, value: section - 10, to: today) }
                if row == 3, section < 8 {
                    task.isCompleted = true
                    task.completedAt = calendar.date(byAdding: .hour, value: -section * 30, to: now)
                }
                store.context.insert(task)
                tasks.append(task)
            }
        }
    }
    // A year of completions, recurring so each one counts once.
    for number in 0..<10_000 {
        let task = tasks[number % tasks.count]
        let completedAt = now.addingTimeInterval(-Double(number) * 3_150)
        let event = ActivityEvent(kind: .completed, title: task.text, blockID: task.id, listID: task.listID)
        event.timestamp = completedAt
        event.change = TaskActivityChange(before: nil, after: nil, completionID: UUID(), completedAt: completedAt,
                                          completedOccurrenceID: UUID(), completionWasRecurring: true)
        store.context.insert(event)
    }
    store.save()
    store.isLoggingSuspended = false
    check(store.persistenceError == nil, "the timing library saves")

    let publisher = WidgetSnapshotPublisher(store: store)
    func time(_ body: () -> Void) -> Double {
        let start = ContinuousClock.now
        body()
        let elapsed = ContinuousClock.now - start
        return Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15
    }
    /// What `body`'s rebuilds read, each.
    func reads(of runs: Int = 1, _ body: () -> Void) -> WidgetSnapshotPublisher.Reads {
        let before = publisher.reads
        for _ in 0..<runs { body() }
        let after = publisher.reads
        return .init(blocks: (after.blocks - before.blocks) / runs, documents: (after.documents - before.documents) / runs,
                     histories: (after.histories - before.histories) / runs)
    }
    let everyBlockCount = try store.context.fetchCount(FetchDescriptor<Block>(predicate: #Predicate { $0.trashID == nil }))
    var snapshot = WidgetSnapshot()
    var first = 0.0
    let firstReads = reads { first = time { snapshot = publisher.buildSnapshot(now: now) } }
    check(snapshot.totalOpenCount == 5_000 - 400 && snapshot.lists.count == 51, "the timing library is all in the snapshot")
    check(snapshot.lists[1].openItems.first?.title == "Task 0.0.0", "a list's rows still follow its outline")
    check(firstReads.histories == 1 && firstReads.documents == 0, "the first rebuild reads the history once, and no document")
    let runs = 5
    var unchanged = 0.0
    let unchangedReads = reads(of: runs) { unchanged += time { _ = publisher.buildSnapshot(now: now) } / Double(runs) }
    // What the rebuild used to read every time: every block, and the history.
    check(unchangedReads.histories == 0 && unchangedReads.blocks == firstReads.blocks && unchangedReads.blocks < everyBlockCount,
          "a rebuild that leaves the history alone reads its tasks and what they sit under, not every block or the history")
    // A sorted list's order reads its whole document, prose and all, but
    // only when the order may have changed: not on a rebuild that leaves it.
    for list in lists.prefix(25) { store.setSorting(.dueDate, for: list) }
    var firstSorted = 0.0
    let firstSortedReads = reads { firstSorted = time { _ = publisher.buildSnapshot(now: now) } }
    check(firstSortedReads.documents == 25 && firstSortedReads.histories == 0, "a list newly sorted reads its document once")
    var sortedUnchanged = 0.0
    let sortedUnchangedReads = reads(of: runs) { sortedUnchanged += time { _ = publisher.buildSnapshot(now: now) } / Double(runs) }
    check(sortedUnchangedReads == unchangedReads, "a rebuild that leaves sorted lists alone does not read their documents again")
    store.toggleCompletion(tasks[0], now: now)
    var completed = 0.0
    let completedReads = reads { completed = time { snapshot = publisher.buildSnapshot(now: now) } }
    check(completedReads.histories == 1, "a completion reads the history again")
    check(snapshot.activity.today == WidgetSnapshotPublisher(store: store).buildSnapshot(now: now).activity.today,
          "a completion rebuilds the kept Activity section")

    let everyBlock = time { _ = try? store.context.fetch(FetchDescriptor<Block>(predicate: #Predicate { $0.trashID == nil })) }
    let history = time { _ = try? store.activityHeatmap(now: now, calendar: calendar, weeks: 21) }
    print(String(format: "⏱  snapshot rebuild, 5k tasks, 20k prose blocks, 10k completions: first %.0f ms, "
                 + "then %.0f ms while the history is unchanged, %.0f ms after a completion "
                 + "(reading every block takes %.0f ms, the history %.0f ms); with half the lists sorted, "
                 + "%.0f ms once, then %.0f ms", first, unchanged, completed, everyBlock, history, firstSorted, sortedUnchanged))
}
