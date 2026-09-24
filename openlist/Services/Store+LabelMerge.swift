import Foundation
import SwiftData

extension Store {
    enum LabelMaintenanceError: LocalizedError {
        case blankName, missingLabel, collision, sameLabel, changedPlan, undoConflict

        var errorDescription: String? {
            switch self {
            case .blankName: "Enter a label name. The original label has been kept."
            case .missingLabel: "A label no longer exists. Close this dialog and choose the labels again."
            case .collision: "A label already uses that name. Confirm a merge to combine them."
            case .sameLabel: "Choose a different label to merge into."
            case .changedPlan: "The labels or their tasks changed. Review the updated details before merging."
            case .undoConflict: "This merge cannot be undone because one of its labels was deleted or replaced."
            }
        }
    }

    /// Retained picker actions carry IDs, not a deleted SwiftData model. Aliases
    /// exist only for this session; persisted references are rewritten together.
    func label(id: UUID) -> TaskLabel? {
        var current = id
        var seen: Set<UUID> = []
        while seen.insert(current).inserted {
            if let value = allLabels().first(where: { $0.id == current }) { return value }
            guard let destination = mergedLabelIDs[current] else { return nil }
            current = destination
        }
        return nil
    }

    /// Older capture/editor-undo snapshots may outlive a merge. Resolve only
    /// identities removed by a merge; keep unrelated or unknown references as
    /// they were, and collapse source/destination overlap without reordering.
    func resolvedLabelIDs(_ ids: [UUID]) -> [UUID] {
        let existing = Set(allLabels().map(\.id))
        let resolved = ids.map { id in
            var current = id
            var seen: Set<UUID> = []
            while !existing.contains(current), seen.insert(current).inserted,
                  let destination = mergedLabelIDs[current] {
                current = destination
            }
            return current
        }
        let destinations = Set(zip(ids, resolved).compactMap { $0 == $1 ? nil : $1 })
        var included: Set<UUID> = []
        return resolved.filter { !destinations.contains($0) || included.insert($0).inserted }
    }

    func matchingLabels(named name: String, excluding sourceID: UUID? = nil) -> [TaskLabel] {
        allLabels().filter { $0.id != sourceID && TaskLabel.namesMatch($0.name, name) }.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    /// Includes every current record regardless of list, archive, completion,
    /// nesting, or visibility. Future retained Trash blocks must remain in this
    /// path (or extend it if Trash introduces a separate reference-bearing model).
    private func allLabelReferenceRecords() throws -> [Block] {
        try context.fetch(FetchDescriptor<Block>())
    }

    func labelMergePlan(sourceID: UUID, destinationID: UUID) throws -> LabelMergePlan {
        guard sourceID != destinationID else { throw LabelMaintenanceError.sameLabel }
        let labels = try context.fetch(FetchDescriptor<TaskLabel>())
        guard let source = labels.first(where: { $0.id == sourceID }),
              let destination = labels.first(where: { $0.id == destinationID }) else {
            throw LabelMaintenanceError.missingLabel
        }
        let references = try allLabelReferenceRecords().filter {
            $0.labelIDs.contains(sourceID) || $0.labelIDs.contains(destinationID)
        }.map { LabelMergePlan.Reference(id: $0.id, isTask: $0.isTask, labels: $0.labelIDs) }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        return LabelMergePlan(source: .init(source), destination: .init(destination), references: references)
    }

    func renameLabel(id: UUID, to rawName: String) throws {
        let name = TaskLabel.normalize(rawName)
        guard !name.isEmpty else { throw LabelMaintenanceError.blankName }
        guard !isSavingSuspended else { throw LabelMaintenanceError.changedPlan }
        if context.hasChanges { try persistChanges() }
        guard let live = try context.fetch(FetchDescriptor<TaskLabel>()).first(where: { $0.id == id }) else {
            throw LabelMaintenanceError.missingLabel
        }
        let writer = ModelContext(context.container)
        writer.autosaveEnabled = false
        let labels = try writer.fetch(FetchDescriptor<TaskLabel>())
        guard let target = labels.first(where: { $0.id == id }) else { throw LabelMaintenanceError.missingLabel }
        guard !labels.contains(where: { $0.id != id && TaskLabel.namesMatch($0.name, name) }) else {
            throw LabelMaintenanceError.collision
        }
        do {
            target.name = name
            try writer.save()
        } catch {
            writer.rollback()
            throw error
        }
        live.name = name
        adoptCommittedLabelChanges()
        labelRevision += 1
        onDidSave?()
    }

    /// Failed SwiftData saves can leave live cached values stale even after
    /// rollback. Write in a sibling context so failure never mutates UI models.
    /// Successful changes are projected into the retained models for Observation,
    /// then their redundant edits are discarded against the committed disk state.
    func mergeLabels(_ reviewed: LabelMergePlan) throws {
        guard !isSavingSuspended else { throw LabelMaintenanceError.changedPlan }
        if context.hasChanges { try persistChanges() }
        let liveBlocks = try allLabelReferenceRecords()
        let liveSource = try context.fetch(FetchDescriptor<TaskLabel>()).first { $0.id == reviewed.source.id }
        let writer = Store(context: ModelContext(context.container))
        writer.context.autosaveEnabled = false
        let current = try writer.labelMergePlan(sourceID: reviewed.source.id, destinationID: reviewed.destination.id)
        guard current == reviewed else { throw LabelMaintenanceError.changedPlan }
        guard let source = writer.label(id: current.source.id) else { throw LabelMaintenanceError.missingLabel }
        var changes: [UUID: [UUID]] = [:]
        do {
            for block in try writer.allLabelReferenceRecords() where block.labelIDs.contains(current.source.id)
                || block.labelIDs.contains(current.destination.id) {
                let merged = current.mergedLabels(block.labelIDs)
                if block.labelIDs != merged {
                    changes[block.id] = merged
                    block.labelIDs = merged
                }
            }
            writer.context.delete(source)
            try writer.context.save()
        } catch {
            writer.context.rollback()
            throw error
        }
        for block in liveBlocks {
            if let labels = changes[block.id] { block.labelIDs = labels }
        }
        if let liveSource { context.delete(liveSource) }
        adoptCommittedLabelChanges()
        mergedLabelIDs[current.source.id] = current.destination.id
        labelMergeUndo = current
        labelRevision += 1
        onLabelsMerged?(current.source.id, current.destination.id)
        onDidSave?()
    }

    /// Takes back `merge`, as the window's Undo does, or with none the latest
    /// merge. Later task content and unrelated labels are left in place.
    @discardableResult
    func undoLabelMerge(_ merge: LabelMergePlan? = nil) -> Bool {
        guard let plan = merge ?? labelMergeUndo else { return false }
        do {
            guard !isSavingSuspended else { throw LabelMaintenanceError.changedPlan }
            if context.hasChanges { try persistChanges() }
            let liveBlocks = try allLabelReferenceRecords()
            let writer = Store(context: ModelContext(context.container))
            writer.context.autosaveEnabled = false
            let labels = try writer.context.fetch(FetchDescriptor<TaskLabel>())
            guard !labels.contains(where: { $0.id == plan.source.id }),
                  labels.contains(where: { $0.id == plan.destination.id }) else {
                throw LabelMaintenanceError.undoConflict
            }
            let byID = Dictionary(uniqueKeysWithValues: try writer.allLabelReferenceRecords().map { ($0.id, $0) })
            let restoredSource = plan.source.restore()
            var changes: [UUID: [UUID]] = [:]
            do {
                writer.context.insert(restoredSource)
                for reference in plan.references {
                    guard let block = byID[reference.id] else { continue } // Never recreate deleted tasks.
                    let merged = plan.mergedLabels(reference.labels)
                    let previous = block.labelIDs
                    if previous == merged {
                        block.labelIDs = reference.labels
                    } else if reference.labels.contains(plan.source.id), previous.contains(plan.destination.id),
                              !previous.contains(plan.source.id) {
                        // Keep label additions/removals since the merge. If the
                        // merged label was removed, leave that deliberate edit.
                        var restored = previous
                        if !reference.labels.contains(plan.destination.id) {
                            restored.removeAll { $0 == plan.destination.id }
                        }
                        let position = min(reference.labels.firstIndex(of: plan.source.id) ?? restored.count, restored.count)
                        restored.insert(plan.source.id, at: position)
                        block.labelIDs = restored
                    }
                    if previous != block.labelIDs { changes[block.id] = block.labelIDs }
                }
                try writer.context.save()
            } catch {
                writer.context.rollback()
                throw error
            }
            for block in liveBlocks {
                if let labels = changes[block.id] { block.labelIDs = labels }
            }
            // Materialize the actual committed identity; inserting a clone here
            // would temporarily create a second model with the same logical ID.
            let restored = context.model(for: restoredSource.persistentModelID) as? TaskLabel
            _ = restored?.id
            adoptCommittedLabelChanges()
            mergedLabelIDs[plan.source.id] = nil
            if labelMergeUndo == plan { labelMergeUndo = nil }
            labelRevision += 1
            onDidSave?()
            return true
        } catch {
            labelMaintenanceError = "The label merge could not be undone. \(error.localizedDescription)"
            return false
        }
    }

    /// The write is already committed. Refresh failures must not claim that the
    /// operation was rolled back, and must retain its successful undo/result.
    private func adoptCommittedLabelChanges() {
        context.rollback()
        context.processPendingChanges()
        labelMaintenanceError = nil
        persistenceError = nil
        do {
            _ = try context.fetch(FetchDescriptor<TaskLabel>())
            _ = try allLabelReferenceRecords()
        } catch {
            labelMaintenanceError = "The label changes were saved, but the view could not refresh. Reopen the window. \(error.localizedDescription)"
        }
    }
}
