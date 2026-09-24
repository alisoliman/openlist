import Foundation
import SwiftData

extension TaskActivityState {
    init(_ task: Block, list: TaskList?) {
        title = task.text
        dueDate = task.dueDate
        includesTime = task.includesTime
        isCompleted = task.isCompleted
        listID = task.listID
        listTitle = list?.displayTitle ?? ""
        listIcon = list?.icon ?? ""
        occurrenceID = task.occurrenceID
    }
}

extension Store {
    /// A fresh reader publishes only committed completion actions, and the
    /// Undo and reopen actions that took one back, including after a failed
    /// write leaves retryable models in the live context.
    func activityHeatmap(now: Date = .now, calendar: Calendar = .current, weeks: Int = 12) throws -> ActivityHeatmap {
        let reader = ModelContext(context.container)
        reader.autosaveEnabled = false
        let saved = try reader.fetch(FetchDescriptor<ActivityEvent>(predicate: #Predicate {
            $0.kindRaw == "completed" || $0.kindRaw == "completionUndone" || $0.kindRaw == "reopened"
        }))
        let events = saved.filter { $0.kindRaw == "completed" }
        let needed = Array(Set(events.filter { $0.change?.completionWasRecurring == nil || $0.change?.completedOccurrenceID == nil }
            .compactMap { $0.change?.completionID }))
        let records = needed.isEmpty ? [] : try reader.fetch(FetchDescriptor<CompletionRecord>(predicate: #Predicate { needed.contains($0.id) }))
        let byID = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ActivityHeatmap(completions: events.map {
            ActivityCompletion(event: $0, matchingRecord: $0.change?.completionID.flatMap { byID[$0] })
        }, reversals: saved.compactMap(ActivityReversal.init(event:)), now: now, calendar: calendar, weeks: weeks)
    }

    /// Existing one-way note/star entries must still describe a committed
    /// change after a failed save. Reversing the unsaved edit cancels the
    /// queued entry; this does not add note or priority diff history.
    func stagedLegacyActivity() throws -> [ActivityEvent] {
        let checkedKinds: Set<ActivityKind> = [.noteAdded, .starred]
        let ids = Array(Set(pendingActivity.filter { checkedKinds.contains($0.kind) }.compactMap(\.blockID)))
        guard !ids.isEmpty else { return pendingActivity.map { $0.model() } }
        let reader = ModelContext(context.container)
        reader.autosaveEnabled = false
        let originals = try reader.fetch(FetchDescriptor<Block>(predicate: #Predicate { ids.contains($0.id) }))
        let originalByID = Dictionary(originals.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen: Set<String> = []
        return pendingActivity.compactMap { draft in
            guard checkedKinds.contains(draft.kind), let id = draft.blockID else { return draft.model() }
            guard let current = block(id: id), !current.isDeleted else { return nil }
            // MCP uses the existing noteAdded kind for a paragraph/heading's
            // creation too; that content is in text, not the task note field.
            if draft.kind == .noteAdded && !current.isTask { return draft.model() }
            let before = originalByID[id]
            let applies = draft.kind == .noteAdded
                ? !current.note.isEmpty && before?.note.isEmpty != false
                : current.isStarred && before?.isStarred != true
            guard applies, seen.insert("\(draft.kind.rawValue):\(id)").inserted else { return nil }
            let event = draft.model()
            let owningList = list(id: current.listID)
            event.title = current.displayTitle
            event.listID = current.listID
            event.listTitle = owningList?.displayTitle ?? ""
            event.listIcon = owningList?.icon ?? ""
            return event
        }
    }

    /// Read only the changed task IDs from committed storage. A separate
    /// context keeps the before values independent of live unsaved models.
    func stagedTaskActivity() throws -> [ActivityEvent] {
        guard !isLoggingSuspended else { return [] }
        let candidates = context.insertedModelsArray + context.changedModelsArray + context.deletedModelsArray
        let tasks = candidates.compactMap { $0 as? Block }.filter(\.isTask)
        let ids = Array(Set(tasks.map(\.id)).subtracting(activitySuppressedTaskIDs))
        guard !ids.isEmpty else { return [] }
        let reader = ModelContext(context.container)
        reader.autosaveEnabled = false
        let originals = try reader.fetch(FetchDescriptor<Block>(predicate: #Predicate { ids.contains($0.id) }))
        let originalByID = Dictionary(originals.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let oldListIDs = Array(Set(originals.compactMap(\.listID)))
        let oldLists = try reader.fetch(FetchDescriptor<TaskList>(predicate: #Predicate { oldListIDs.contains($0.id) }))
        let oldListByID = Dictionary(oldLists.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let inserted = context.insertedModelsArray.compactMap { $0 as? CompletionRecord }
        let removed = context.deletedModelsArray.compactMap { $0 as? CompletionRecord }
        // Bulk Reopen Undo restores an already recorded completion without
        // inserting another calendar record. Reuse only its exact task and
        // occurrence match so this action cannot inflate the heatmap.
        let savedCompletions = try reader.fetch(FetchDescriptor<CompletionRecord>(predicate: #Predicate { ids.contains($0.taskID) }))
        var result: [ActivityEvent] = []
        var seen: Set<UUID> = []
        let included = Set(ids)
        for task in tasks where included.contains(task.id) && seen.insert(task.id).inserted {
            let original = originalByID[task.id]
            let previousList = original?.listID.flatMap { oldListByID[$0] }
            let before = original.flatMap { $0.isTrashed ? nil : TaskActivityState($0, list: previousList) }
            let after = task.isDeleted || task.isTrashed ? nil : TaskActivityState(task, list: list(id: task.listID))
            func append(_ kind: ActivityKind, completion: CompletionRecord? = nil, undone: CompletionRecord? = nil) {
                guard let subject = after ?? before else { return }
                // What a list document line saves to its own task as it's
                // written is the line's one entry, recorded as it ends.
                if let line = line(saving: kind, to: task) {
                    line.hold(kind, of: task.id, from: before, to: after)
                    return
                }
                let event = ActivityEvent(kind: kind, title: subject.title.isEmpty ? "Untitled task" : subject.title,
                    blockID: task.id, listID: subject.listID, listTitle: subject.listTitle, listIcon: subject.listIcon)
                let record = completion ?? undone ?? (kind == .completed ? savedCompletions.first {
                    $0.taskID == task.id && $0.occurrenceID == after?.occurrenceID
                } : nil)
                event.change = TaskActivityChange(before: before, after: after, completionID: record?.id,
                    completedAt: record?.completedAt, completedDueDate: record?.dueDate,
                    advancesOccurrence: completion.map { $0.occurrenceID != after?.occurrenceID } ?? false,
                    completedOccurrenceID: record?.occurrenceID, completionWasRecurring: record?.wasRecurring,
                    completionCycleID: record.flatMap { pendingCompletionCycleIDs[$0.id] }
                        ?? (kind == .reopened ? after.flatMap { pendingReopenedCycleIDs[$0.occurrenceID] } : nil))
                result.append(event)
            }
            guard let after else {
                if before != nil { append(.deleted) }
                continue
            }
            guard let before else {
                // Editor Undo knows a restoration even if the user cleared
                // history after deletion. Never reconstruct those old entries.
                if pendingRestoredTaskIDs.contains(task.id) {
                    append(.restored)
                } else {
                    let id = task.id
                    var prior = FetchDescriptor<ActivityEvent>(predicate: #Predicate { $0.blockID == id })
                    prior.fetchLimit = 1
                    append(try reader.fetch(prior).isEmpty ? .created : .restored)
                }
                for completion in inserted where completion.taskID == task.id { append(.completed, completion: completion) }
                continue
            }
            if before.title != after.title { append(.renamed) }
            let completions = inserted.filter { $0.taskID == task.id }
            let reversals = removed.filter { $0.taskID == task.id }
            for completion in completions { append(.completed, completion: completion) }
            for reversal in reversals { append(.completionUndone, undone: reversal) }
            if completions.isEmpty, reversals.isEmpty, before.isCompleted != after.isCompleted {
                append(after.isCompleted ? .completed : .reopened)
            }
            // The occurrence event already explains its resulting date.
            if completions.isEmpty, reversals.isEmpty,
               before.dueDate != after.dueDate || before.includesTime != after.includesTime {
                append(after.dueDate == nil ? .unscheduled : .scheduled)
            }
            if before.listID != after.listID { append(.moved) }
        }
        return result
    }

    /// Runs a change that saves more than once, like tasks completed
    /// together, so its history is one batch, as a single save's is.
    func withActivityBatch<T>(_ batch: UUID, _ body: () throws -> T) rethrows -> T {
        let previous = activityBatch
        activityBatch = batch
        defer { activityBatch = previous }
        return try body()
    }

    /// Task history is independent of `recentActivity`, which Changes reads.
    func taskActivity(for taskID: UUID, limit: Int = 50, offset: Int = 0) throws -> [ActivityEvent] {
        let excluded = Array(uncommittedActivityIDs)
        var descriptor = FetchDescriptor<ActivityEvent>(predicate: #Predicate { $0.blockID == taskID && !excluded.contains($0.id) },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse), SortDescriptor(\.id)])
        descriptor.fetchLimit = max(1, limit)
        descriptor.fetchOffset = max(0, offset)
        return try context.fetch(descriptor)
    }
}
