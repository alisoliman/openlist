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
        var result: [ActivityEvent] = []
        var seen: Set<UUID> = []
        let included = Set(ids)
        for task in tasks where included.contains(task.id) && seen.insert(task.id).inserted {
            let original = originalByID[task.id]
            let previousList = original?.listID.flatMap { oldListByID[$0] }
            let before = original.map { TaskActivityState($0, list: previousList) }
            let after = task.isDeleted ? nil : TaskActivityState(task, list: list(id: task.listID))
            func append(_ kind: ActivityKind, completion: CompletionRecord? = nil, undone: CompletionRecord? = nil) {
                guard let subject = after ?? before else { return }
                let event = ActivityEvent(kind: kind, title: subject.title.isEmpty ? "Untitled task" : subject.title,
                    blockID: task.id, listID: subject.listID, listTitle: subject.listTitle, listIcon: subject.listIcon)
                let record = completion ?? undone
                event.change = TaskActivityChange(before: before, after: after, completionID: record?.id,
                    completedAt: record?.completedAt, completedDueDate: record?.dueDate,
                    advancesOccurrence: completion.map { $0.occurrenceID != after?.occurrenceID } ?? false)
                result.append(event)
            }
            guard let after else {
                if before != nil { append(.deleted) }
                continue
            }
            guard let before else {
                // Restoring a deleted task keeps its UUID and existing history.
                let id = task.id
                var prior = FetchDescriptor<ActivityEvent>(predicate: #Predicate { $0.blockID == id })
                prior.fetchLimit = 1
                append(try reader.fetch(prior).isEmpty ? .created : .restored)
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

    /// Task history is independent of the Updates feed's latest-300 helper.
    func taskActivity(for taskID: UUID, limit: Int = 50, offset: Int = 0) throws -> [ActivityEvent] {
        let excluded = Array(uncommittedActivityIDs)
        var descriptor = FetchDescriptor<ActivityEvent>(predicate: #Predicate { $0.blockID == taskID && !excluded.contains($0.id) },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse), SortDescriptor(\.id)])
        descriptor.fetchLimit = max(1, limit)
        descriptor.fetchOffset = max(0, offset)
        return try context.fetch(descriptor)
    }
}
