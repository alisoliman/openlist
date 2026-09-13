import Foundation
import SwiftData

enum BulkActionError: LocalizedError {
    case unavailable, invalidHierarchy, invalidDestination, busy, changed

    var errorDescription: String? {
        switch self {
        case .unavailable: "Some selected items are no longer available. Select them again."
        case .invalidHierarchy: "The selected content has an incomplete or conflicting hierarchy. No items were changed."
        case .invalidDestination: "Choose a destination outside the selected content in an available list."
        case .busy: "Finish the current editor operation before changing the selection."
        case .changed: "These items have moved or changed since this action. The move could not be restored."
        }
    }
}

/// The complete selection is resolved before any mutation. Repeated appearances
/// keep the first visible position, and an ancestor covers its entire subtree.
private struct BulkSelectionSnapshot {
    let blocks: [UUID: Block]
    let lists: [UUID: TaskList]
    let ordered: [Block]

    init(ids: [UUID], context: ModelContext) throws {
        let all = try context.fetch(FetchDescriptor<Block>()).filter { !$0.isDeleted }
        let allLists = try context.fetch(FetchDescriptor<TaskList>()).filter { !$0.isDeleted }
        guard Set(all.map(\.id)).count == all.count,
              Set(allLists.map(\.id)).count == allLists.count else { throw BulkActionError.invalidHierarchy }
        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        blocks = byID
        lists = Dictionary(uniqueKeysWithValues: allLists.map { ($0.id, $0) })
        var seen = Set<UUID>()
        ordered = try ids.filter { seen.insert($0).inserted }.map { id in
            guard let block = byID[id] else { throw BulkActionError.unavailable }
            return block
        }
        for block in ordered { try validate(block) }
    }

    func validate(_ block: Block) throws {
        guard let listID = block.listID, lists[listID] != nil else { throw BulkActionError.invalidHierarchy }
        var current = block
        var visited: Set<UUID> = [block.id]
        while let parentID = current.parentID {
            guard visited.insert(parentID).inserted, let parent = blocks[parentID],
                  parent.listID == listID, parent.kind.acceptsChildren else { throw BulkActionError.invalidHierarchy }
            current = parent
        }
    }

    func roots(of candidates: [Block]) -> [Block] {
        let ids = Set(candidates.map(\.id))
        return candidates.filter { block in
            var parentID = block.parentID
            while let id = parentID {
                if ids.contains(id) { return false }
                parentID = blocks[id]?.parentID
            }
            return true
        }
    }

    func subtree(_ roots: [Block]) throws -> [Block] {
        let children = Dictionary(grouping: blocks.values.filter { $0.parentID != nil }, by: { $0.parentID! })
        var result: [Block] = []
        var seen = Set<UUID>()
        var queue = roots
        while let block = queue.popLast() {
            guard seen.insert(block.id).inserted else { continue }
            try validate(block)
            result.append(block)
            queue.append(contentsOf: children[block.id] ?? [])
        }
        return result
    }
}

private struct BulkBlockPosition: Equatable {
    let listID: UUID?
    let parentID: UUID?
    let sortIndex: Double

    init(_ block: Block) {
        listID = block.listID
        parentID = block.parentID
        sortIndex = block.sortIndex
    }

    func apply(to block: Block) {
        block.listID = listID
        block.parentID = parentID
        block.sortIndex = sortIndex
        block.touch()
    }
}

extension Store {
    /// Explicit Complete/Reopen never toggles mixed-state selections. Completing
    /// a selected parent covers selected children once; reopening does not cascade.
    @discardableResult
    func setBulkCompletion(_ completed: Bool, ids: [UUID], now: Date = .now) throws -> Int {
        let snapshot = try BulkSelectionSnapshot(ids: ids, context: context)
        let candidates = snapshot.ordered.filter { $0.isTask && $0.isCompleted != completed }
        let roots = completed ? snapshot.roots(of: candidates) : candidates
        guard !roots.isEmpty else { return 0 }
        let affected = completed ? try snapshot.subtree(roots).filter(\.isTask) : roots
        let affectedIDs = Set(affected.map(\.id))
        // Fetch calendar inputs explicitly before applying the first task. The
        // single-task semantics below can then use the same loaded models.
        let placements = try context.fetch(FetchDescriptor<SchedulePlacement>())
        let records = try context.fetch(FetchDescriptor<CompletionRecord>())
        let sessions = try context.fetch(FetchDescriptor<WorkSession>()).filter { affectedIDs.contains($0.taskID) }
        let sessionStates = sessions.map { ($0, $0.endedAt, $0.lastHeartbeatAt, $0.pauseReason) }
        let updatedAt = Dictionary(uniqueKeysWithValues: affected.map { ($0.id, $0.updatedAt) })
        let before = CompletionUndoSnapshot(
            tasks: Dictionary(uniqueKeysWithValues: affected.map { ($0.id, CompletionTaskState($0)) }),
            placements: placements.filter { affectedIDs.contains($0.taskID) }.map(CompletionPlacementState.init),
            existingRecordIDs: Set(records.map(\.id)))
        var attemptedRecordIDs = Set<UUID>()
        try commitBulkMutation({
            for task in roots {
                if completed { complete(task, now: now) } else { reopen(task) }
            }
            attemptedRecordIDs = Set(context.insertedModelsArray.compactMap { ($0 as? CompletionRecord)?.id })
            stageCompletionUndo(for: roots, title: "\(candidates.count) tasks", before: before,
                                now: now, isReopening: !completed)
        }, restoring: {
            // SwiftData rollback can leave retained Block instances showing
            // attempted values. Restore those live fields as well as disk state.
            for task in affected {
                before.tasks[task.id]?.apply(to: task, replacing: CompletionTaskState(task))
                if let date = updatedAt[task.id] { task.updatedAt = date }
            }
            for (session, endedAt, heartbeat, reason) in sessionStates {
                session.endedAt = endedAt
                session.lastHeartbeatAt = heartbeat
                session.pauseReason = reason
            }
            // A failed real SwiftData save may retain newly inserted history
            // in the fetch cache after rollback. Remove only this attempt's
            // identities so calendar readers cannot display a failed action.
            for record in completionRecords() where attemptedRecordIDs.contains(record.id) {
                context.delete(record)
            }
        })
        return candidates.count
    }

    /// Moves canonical roots in their displayed selection order. All children
    /// follow with their original IDs, content, files and task metadata.
    @discardableResult
    func moveSelection(_ ids: [UUID], to listID: UUID, parentID: UUID? = nil,
                       above targetID: UUID? = nil, undoManager: UndoManager? = nil) throws -> [UUID] {
        let snapshot = try BulkSelectionSnapshot(ids: ids, context: context)
        guard let destination = snapshot.lists[listID], destination.mergedIntoID == nil,
              !destination.isArchived else { throw BulkActionError.invalidDestination }
        let roots = snapshot.roots(of: snapshot.ordered)
        guard !roots.isEmpty else { return [] }
        let subtree = try snapshot.subtree(roots)
        let movingIDs = Set(subtree.map(\.id))
        if let parentID {
            guard let parent = snapshot.blocks[parentID], parent.listID == listID,
                  parent.kind.acceptsChildren, !movingIDs.contains(parentID) else { throw BulkActionError.invalidDestination }
            try snapshot.validate(parent)
        }
        if let targetID {
            guard let target = snapshot.blocks[targetID], target.listID == listID,
                  target.parentID == parentID, !movingIDs.contains(targetID) else { throw BulkActionError.invalidDestination }
        }
        let rootIDs = Set(roots.map(\.id))
        var peers = BlockTree.children(of: parentID, in: Array(snapshot.blocks.values).filter { $0.listID == listID })
            .filter { !rootIDs.contains($0.id) }
        let insertion = targetID.flatMap { id in peers.firstIndex { $0.id == id } } ?? peers.count
        peers.insert(contentsOf: roots, at: insertion)
        let touched = Dictionary(uniqueKeysWithValues: (subtree + peers).map { ($0.id, $0) }.uniquedByID())
        let before = touched.mapValues(BulkBlockPosition.init)
        let updatedAt = touched.mapValues(\.updatedAt)
        try commitBulkMutation({
            for block in subtree where block.listID != listID { block.listID = listID; block.touch() }
            for root in roots { root.parentID = parentID; root.touch() }
            // One deterministic spacing pass keeps the whole selected run
            // together even where old floating-point gaps have converged.
            for (index, block) in peers.enumerated() {
                block.sortIndex = Double(index + 1) * BlockTree.indexStep
                block.touch()
            }
        }, restoring: {
            for (id, model) in touched {
                before[id]?.apply(to: model)
                if let date = updatedAt[id] { model.updatedAt = date }
            }
        })
        let after = touched.mapValues(BulkBlockPosition.init)
        let changed = before.filter { after[$0.key] != $0.value }
        if let undoManager, !changed.isEmpty {
            registerBulkMove(source: after.filter { changed[$0.key] != nil }, desired: changed, with: undoManager)
        }
        return roots.map(\.id)
    }

    /// Pending typing is saved before the atomic operation starts. A failed
    /// initial save leaves drafts retryable; rollback is limited to this action.
    private func commitBulkMutation(_ body: () throws -> Void, restoring: () -> Void = {}) throws {
        guard !isSavingSuspended, !isRecordingEditorEdit else { throw BulkActionError.busy }
        try persistChanges()
        isSavingSuspended = true
        do {
            try body()
            isSavingSuspended = false
            try persistChanges()
        } catch {
            isSavingSuspended = false
            context.rollback()
            restoring()
            context.processPendingChanges()
            pendingActivity.removeAll()
            pendingCompletionUndoChanges.removeAll()
            activitySuppressedTaskIDs.removeAll()
            pendingRestoredTaskIDs.removeAll()
            refreshAllReminders()
            persistenceError = "The selected items could not be changed. \(error.localizedDescription)"
            throw error
        }
    }

    private func registerBulkMove(source: [UUID: BulkBlockPosition], desired: [UUID: BulkBlockPosition],
                                  with manager: UndoManager) {
        manager.registerUndo(withTarget: self) { store in
            do {
                let snapshot = try BulkSelectionSnapshot(ids: Array(source.keys), context: store.context)
                guard source.allSatisfy({ id, expected in snapshot.blocks[id].map(BulkBlockPosition.init) == expected })
                else { throw BulkActionError.changed }
                // Validate the proposed restored graph, including parents that
                // were not themselves moved, before changing any positions.
                for (id, position) in desired {
                    guard let listID = position.listID, snapshot.lists[listID] != nil else { throw BulkActionError.changed }
                    var visited: Set<UUID> = [id]
                    var parentID = position.parentID
                    while let parent = parentID {
                        guard visited.insert(parent).inserted, let model = snapshot.blocks[parent], model.kind.acceptsChildren else {
                            throw BulkActionError.changed
                        }
                        let parentPosition = desired[parent] ?? BulkBlockPosition(model)
                        guard parentPosition.listID == listID else { throw BulkActionError.changed }
                        parentID = parentPosition.parentID
                    }
                }
                // A child added or indented after the move is not in the old
                // position snapshot. Returning its parent to another list
                // would orphan it unless the proposed edge is checked too.
                for model in snapshot.blocks.values {
                    let position = desired[model.id] ?? BulkBlockPosition(model)
                    guard let parentID = position.parentID,
                          desired[model.id] != nil || desired[parentID] != nil else { continue }
                    guard let parent = snapshot.blocks[parentID], parent.kind.acceptsChildren,
                          (desired[parentID] ?? BulkBlockPosition(parent)).listID == position.listID else {
                        throw BulkActionError.changed
                    }
                }
                let updatedAt = snapshot.blocks.mapValues(\.updatedAt)
                try store.commitBulkMutation({
                    for (id, position) in desired { position.apply(to: snapshot.blocks[id]!) }
                }, restoring: {
                    for (id, position) in source {
                        if let model = snapshot.blocks[id] {
                            position.apply(to: model)
                            if let date = updatedAt[id] { model.updatedAt = date }
                        }
                    }
                })
                store.registerBulkMove(source: desired, desired: source, with: manager)
            } catch { store.editorNotice = error.localizedDescription }
        }
        manager.setActionName("Move selected items")
    }
}

private extension Array where Element == (UUID, Block) {
    func uniquedByID() -> Self {
        var seen = Set<UUID>()
        return filter { seen.insert($0.0).inserted }
    }
}
