import Foundation
import SwiftData

struct CompletionUndoAction: Identifiable {
    var id: UUID = UUID()
    var title: String
    var createdAt: Date
    var isReopening = false
    var commandTitle: String { "\(isReopening ? "Reopen" : "Complete") \(title)" }
}

/// Only completion-owned fields are captured. Titles, notes, estimates, labels,
/// list moves and other edits made after completion are never rolled back.
struct CompletionTaskState: Equatable {
    var id: UUID
    var occurrenceID: UUID
    var isCompleted: Bool
    var completedAt: Date?
    var dueDate: Date?
    var recurrenceData: Data?
    var reminderAt: Date?
    var selectedForDay: Date?
    var deferredUntil: Date?

    init(_ task: Block) {
        id = task.id
        occurrenceID = task.occurrenceID
        isCompleted = task.isCompleted
        completedAt = task.completedAt
        dueDate = task.dueDate
        recurrenceData = task.recurrenceData
        reminderAt = task.reminderAt
        selectedForDay = task.selectedForDay
        deferredUntil = task.deferredUntil
    }

    func apply(to task: Block, replacing source: Self) {
        if occurrenceID != source.occurrenceID, task.occurrenceID == source.occurrenceID { task.occurrenceID = occurrenceID }
        if isCompleted != source.isCompleted, task.isCompleted == source.isCompleted { task.isCompleted = isCompleted }
        if completedAt != source.completedAt, task.completedAt == source.completedAt { task.completedAt = completedAt }
        if dueDate != source.dueDate, task.dueDate == source.dueDate { task.dueDate = dueDate }
        if recurrenceData != source.recurrenceData, task.recurrenceData == source.recurrenceData { task.recurrenceData = recurrenceData }
        if reminderAt != source.reminderAt, task.reminderAt == source.reminderAt { task.reminderAt = reminderAt }
        if selectedForDay != source.selectedForDay, task.selectedForDay == source.selectedForDay { task.selectedForDay = selectedForDay }
        if deferredUntil != source.deferredUntil, task.deferredUntil == source.deferredUntil { task.deferredUntil = deferredUntil }
        task.touch()
    }
}

struct CompletionPlacementState: Equatable {
    var id: UUID
    var taskID: UUID
    var occurrenceID: UUID
    var start: Date
    var end: Date
    var isPinned: Bool

    init(_ placement: SchedulePlacement) {
        id = placement.id
        taskID = placement.taskID
        occurrenceID = placement.occurrenceID
        start = placement.start
        end = placement.end
        isPinned = placement.isPinned
    }

    func insert(in store: Store) {
        guard let task = store.block(id: taskID) else { return }
        let placement = SchedulePlacement(task: task, start: start, end: end, isPinned: isPinned)
        placement.id = id
        placement.occurrenceID = occurrenceID
        store.context.insert(placement)
    }
}

struct CompletionRecordState {
    var id: UUID
    var taskID: UUID
    var occurrenceID: UUID
    var listID: UUID?
    var title: String
    var completedAt: Date
    var dueDate: Date?
    var estimateMinutes: Int
    var wasRecurring: Bool
    var plannedIntervalsData: Data?
    var activityCycleID: UUID?

    init(_ record: CompletionRecord) {
        id = record.id
        taskID = record.taskID
        occurrenceID = record.occurrenceID
        listID = record.listID
        title = record.title
        completedAt = record.completedAt
        dueDate = record.dueDate
        estimateMinutes = record.estimateMinutes
        wasRecurring = record.wasRecurring
        plannedIntervalsData = record.plannedIntervalsData
    }

    func insert(in store: Store) {
        guard let task = store.block(id: taskID) else { return }
        let record = CompletionRecord(task: task, completedAt: completedAt, estimateMinutes: estimateMinutes)
        record.id = id
        record.occurrenceID = occurrenceID
        record.listID = listID
        record.title = title
        record.dueDate = dueDate
        record.wasRecurring = wasRecurring
        record.plannedIntervalsData = plannedIntervalsData
        store.context.insert(record)
        store.pendingCompletionCycleIDs[id] = activityCycleID
    }
}

struct CompletionUndoSnapshot {
    var tasks: [UUID: CompletionTaskState]
    var placements: [CompletionPlacementState]
    var existingRecordIDs: Set<UUID>
}

struct CompletionUndoChange {
    var action: CompletionUndoAction
    var rootTaskID: UUID
    var additionalRootTaskIDs: [UUID] = []
    var before: [UUID: CompletionTaskState]
    var after: [UUID: CompletionTaskState]
    var placements: [CompletionPlacementState]
    var records: [CompletionRecordState]
    var reopenedCycleIDs: [UUID: UUID] = [:]
    var isApplied = true
}

/// An independent native Undo target lets the snackbar consume just this action
/// without removing or swallowing unrelated editor Undo entries.
final class CompletionUndoRegistration {
    weak var store: Store?
    weak var manager: UndoManager?
    init(store: Store, manager: UndoManager) {
        self.store = store
        self.manager = manager
    }
}

extension Store {
    func captureCompletionUndo(for task: Block) -> CompletionUndoSnapshot {
        let descendants = task.listID.map { BlockTree.descendants(of: task.id, in: blocks(inList: $0)).filter(\.isTask) } ?? []
        let tasks = [task] + descendants
        let ids = Set(tasks.map(\.id))
        return CompletionUndoSnapshot(tasks: Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, CompletionTaskState($0)) }),
                                      placements: placements().filter { ids.contains($0.taskID) }.map(CompletionPlacementState.init),
                                      existingRecordIDs: Set(completionRecords().map(\.id)))
    }

    func stageCompletionUndo(for task: Block, before snapshot: CompletionUndoSnapshot, now: Date) {
        stageCompletionUndo(for: [task], title: task.displayTitle, before: snapshot, now: now)
    }

    func stageCompletionUndo(for roots: [Block], title: String, before snapshot: CompletionUndoSnapshot,
                             now: Date, isReopening: Bool = false) {
        guard let first = roots.first else { return }
        let after = Dictionary(uniqueKeysWithValues: snapshot.tasks.keys.compactMap { id -> (UUID, CompletionTaskState)? in
            guard let task = block(id: id) else { return nil }
            return (id, CompletionTaskState(task))
        })
        let changed = snapshot.tasks.filter { after[$0.key] != $0.value }
        let records = completionRecords().filter { !snapshot.existingRecordIDs.contains($0.id) }.map { record in
            var state = CompletionRecordState(record)
            state.activityCycleID = pendingCompletionCycleIDs[record.id]
            return state
        }
        guard !changed.isEmpty, isReopening || !records.isEmpty else { return }
        pendingCompletionUndoChanges.append(CompletionUndoChange(
            action: CompletionUndoAction(title: title, createdAt: now, isReopening: isReopening),
            rootTaskID: first.id, additionalRootTaskIDs: roots.dropFirst().map(\.id),
            before: changed, after: after.filter { changed[$0.key] != nil },
            placements: snapshot.placements.filter { changed[$0.taskID] != nil }, records: records,
            reopenedCycleIDs: Dictionary(uniqueKeysWithValues: after.values.compactMap { state in
                pendingReopenedCycleIDs[state.occurrenceID].map { (state.occurrenceID, $0) }
            })
        ))
    }

    /// Called only after a successful save. Batched MCP mutations may roll back;
    /// verify their records still exist before presenting an Undo action.
    func publishPendingCompletionUndo() {
        let pending = pendingCompletionUndoChanges
        pendingCompletionUndoChanges.removeAll()
        guard !pending.isEmpty else { return }
        let savedIDs = Set(completionRecords().map(\.id))
        for change in pending where change.records.allSatisfy({ savedIDs.contains($0.id) }) {
            completionUndoChanges[change.action.id] = change
            completionUndo = change.action
            onCompletionUndoAvailable?(change.action)
        }
    }

    func registerCompletionUndo(_ action: CompletionUndoAction, with undoManager: UndoManager) {
        guard completionUndoChanges[action.id]?.isApplied == true else { return }
        guard completionUndoRegistrations[action.id] == nil else { return }
        let registration = CompletionUndoRegistration(store: self, manager: undoManager)
        completionUndoRegistrations[action.id] = registration
        undoManager.registerUndo(withTarget: registration) { target in
            guard let store = target.store, let manager = target.manager else { return }
            store.restoreCompletion(action.id, undoing: true, undoManager: manager)
        }
        undoManager.setActionName(action.commandTitle)
    }

    @discardableResult
    func undoCompletion(_ id: UUID) -> Bool {
        guard restoreCompletion(id, undoing: true, undoManager: nil) else { return false }
        if let registration = completionUndoRegistrations.removeValue(forKey: id) {
            registration.manager?.removeAllActions(withTarget: registration)
        }
        return true
    }

    @discardableResult
    private func restoreCompletion(_ id: UUID, undoing: Bool, undoManager: UndoManager?) -> Bool {
        guard var change = completionUndoChanges[id], change.isApplied == undoing else { return false }
        if undoing {
            let recordIDs = Set(completionRecords().map(\.id))
            guard change.records.allSatisfy({ recordIDs.contains($0.id) }) else { return false }
        }
        let source = undoing ? change.after : change.before
        let desired = undoing ? change.before : change.after
        let rootIDs = [change.rootTaskID] + change.additionalRootTaskIDs
        guard rootIDs.allSatisfy({ id in
            guard !permanentlyErasedBlockIDs.contains(id), let root = block(id: id),
                  !root.isDeleted, root.isTask, list(id: root.listID) != nil,
                  let expected = source[id] else { return false }
            return root.occurrenceID == expected.occurrenceID && root.isCompleted == expected.isCompleted
        }) else {
            editorNotice = "This change cannot be undone because a task has changed or was deleted."
            return false
        }
        let matching = source.compactMap { taskID, expected -> Block? in
            guard !permanentlyErasedBlockIDs.contains(taskID), let task = block(id: taskID),
                  !task.isDeleted, list(id: task.listID) != nil, task.occurrenceID == expected.occurrenceID,
                  task.isCompleted == expected.isCompleted else { return nil }
            return task
        }
        let matchingIDs = Set(matching.map(\.id))
        let previousCompletionCycles = pendingCompletionCycleIDs
        let previousReopenedCycles = pendingReopenedCycleIDs
        let previousTasks = Dictionary(uniqueKeysWithValues: matching.map { ($0.id, CompletionTaskState($0)) })
        let originalPlacements = placements()
        let originalRecords = completionRecords()
        let originalSessionStates = workSessions().filter { matchingIDs.contains($0.taskID) && $0.endedAt == nil }
            .map { ($0, $0.endedAt, $0.lastHeartbeatAt, $0.pauseReason) }
        var insertedPlacements: [UUID] = []
        var deletedPlacements: [CompletionPlacementState] = []
        var insertedRecords: [UUID] = []
        var deletedRecords: [CompletionRecordState] = []
        for task in matching {
            // Undo may restore an earlier occurrence; current work stays recorded
            // and paused instead of silently becoming an active older session.
            pauseWorkSessions(for: task, reason: undoing ? "Completion undone" : "Completion restored")
            desired[task.id]?.apply(to: task, replacing: source[task.id]!)
            if !undoing, let cycle = change.reopenedCycleIDs[task.occurrenceID] {
                pendingReopenedCycleIDs[task.occurrenceID] = cycle
            }
        }
        for placement in change.placements where matchingIDs.contains(placement.taskID) {
            if undoing {
                if !originalPlacements.contains(where: { $0.id == placement.id }) {
                    placement.insert(in: self)
                    insertedPlacements.append(placement.id)
                }
            } else if let model = originalPlacements.first(where: { $0.id == placement.id }), CompletionPlacementState(model) == placement {
                deletedPlacements.append(CompletionPlacementState(model))
                context.delete(model)
            }
        }
        for record in change.records where matchingIDs.contains(record.taskID) {
            if undoing {
                if let model = originalRecords.first(where: { $0.id == record.id }) {
                    deletedRecords.append(CompletionRecordState(model))
                    context.delete(model)
                }
            } else if !originalRecords.contains(where: { $0.id == record.id }) {
                record.insert(in: self)
                insertedRecords.append(record.id)
            }
        }
        do {
            try persistChanges()
        } catch {
            for task in matching {
                if let previous = previousTasks[task.id] { previous.apply(to: task, replacing: CompletionTaskState(task)) }
            }
            for placement in placements() where insertedPlacements.contains(placement.id) { context.delete(placement) }
            for record in completionRecords() where insertedRecords.contains(record.id) { context.delete(record) }
            for placement in deletedPlacements { placement.insert(in: self) }
            for record in deletedRecords { record.insert(in: self) }
            for (session, endedAt, heartbeat, reason) in originalSessionStates {
                session.endedAt = endedAt
                session.lastHeartbeatAt = heartbeat
                session.pauseReason = reason
            }
            context.processPendingChanges()
            pendingCompletionCycleIDs = previousCompletionCycles
            pendingReopenedCycleIDs = previousReopenedCycles
            persistenceError = "The completion could not be restored. \(error.localizedDescription)"
            return false
        }
        change.isApplied = !undoing
        completionUndoChanges[id] = change
        if completionUndo?.id == id { completionUndo = nil }
        refreshAllReminders()
        if let undoManager, let registration = completionUndoRegistrations[id] {
            undoManager.registerUndo(withTarget: registration) { target in
                guard let store = target.store, let manager = target.manager else { return }
                store.restoreCompletion(id, undoing: !undoing, undoManager: manager)
            }
            undoManager.setActionName(change.action.commandTitle)
        }
        return true
    }
}
