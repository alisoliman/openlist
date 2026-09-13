import Foundation
import SwiftData

private struct InboxChange {
    let id: UUID
    let before: Data?
    let after: Data?
    let occurrenceID: UUID
}

extension Store {
    /// Classify only legacy nil task records. An explicit exclusion is final,
    /// and unknown payloads remain intact for a compatible app to interpret.
    /// Missing CloudKit owners wait for a later import rather than guessing.
    func migrateInboxMembership() throws {
        let lists = try context.fetch(FetchDescriptor<TaskList>())
        let blocks = try context.fetch(FetchDescriptor<Block>())
        let byID = Dictionary(lists.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let legacy = blocks.filter { $0.isTask && $0.inboxMembershipData == nil }
        guard !legacy.isEmpty else { return }
        let outline = BlockTree.flatten(blocks, respectCollapse: false).map(\.block)
        var order = blocks.compactMap { InboxPolicy.selection($0)?.order }.max() ?? -BlockTree.indexStep
        for task in outline where task.isTask && task.inboxMembershipData == nil {
            guard let ownerID = task.listID, let owner = byID[ownerID], owner.mergedIntoID == nil else { continue }
            if owner.isSystemInbox {
                order += BlockTree.indexStep
                task.inboxMembershipData = try InboxMembership.included(order: order, occurrenceID: task.occurrenceID).encoded()
            } else {
                task.inboxMembershipData = InboxMembership.excludedData
            }
        }
    }

    /// Called only for genuinely new tasks/conversion, never for copies or
    /// moves. New unfiled captures join at the front of the manual queue.
    func includeNewUnfiledTask(_ task: Block) {
        guard task.isTask, let owner = list(id: task.listID), owner.isSystemInbox else { return }
        // Conversion can revisit a retained future payload. Never turn an
        // unknown task -> text -> task roundtrip into a destructive downgrade.
        if let data = task.inboxMembershipData {
            do { _ = try InboxMembership.decode(data) }
            catch { inboxError = error.localizedDescription; return }
        }
        do {
            let tasks = try context.fetch(FetchDescriptor<Block>(predicate: #Predicate { $0.kindRaw == "task" }))
            let first = tasks.compactMap { InboxPolicy.selection($0)?.order }.min()
            let order = BlockTree.index(after: nil, before: first)
            guard order.isFinite, first.map({ order < $0 }) ?? true else { throw InboxMembershipError.ordering }
            task.inboxMembershipData = try InboxMembership.included(order: order, occurrenceID: task.occurrenceID).encoded()
        } catch {
            // A new capture must remain eligible for retrying classification if
            // the ordering read fails. The capture itself stays in unfiled.
            task.inboxMembershipData = nil
            inboxError = "The capture is in Unfiled content. Its Inbox selection could not be prepared. \(error.localizedDescription)"
        }
    }

    @discardableResult
    func setInboxMembership(_ included: Bool, taskIDs: [UUID], undoManager: UndoManager? = nil) -> Bool {
        do {
            let ids = Set(taskIDs)
            let tasks = try context.fetch(FetchDescriptor<Block>(predicate: #Predicate { $0.kindRaw == "task" }))
                .filter { !$0.isDeleted }
            let lists = try context.fetch(FetchDescriptor<TaskList>())
            let byID = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let policy = InboxPolicy(lists: lists)
            var order = tasks.compactMap { InboxPolicy.selection($0)?.order }.min() ?? BlockTree.indexStep
            var changes: [InboxChange] = []
            for id in ids.sorted(by: { $0.uuidString < $1.uuidString }) {
                guard let task = byID[id], let listID = task.listID,
                      policy.activeListIDs.contains(listID) else { throw InboxMembershipError.unavailable }
                if let data = task.inboxMembershipData { _ = try InboxMembership.decode(data) }
                if included, InboxPolicy.selection(task) != nil { continue }
                let previousOrder = order
                order -= BlockTree.indexStep
                guard !included || (order.isFinite && order < previousOrder) else { throw InboxMembershipError.ordering }
                var value = included ? InboxMembership.included(order: order, occurrenceID: task.occurrenceID) : InboxMembership(included: false)
                value.decisionID = UUID()
                let data = try value.encoded()
                changes.append(InboxChange(id: id, before: task.inboxMembershipData, after: data, occurrenceID: task.occurrenceID))
            }
            return try applyInboxChanges(changes, name: included ? "Add to Inbox" : "Remove from Inbox", undoManager: undoManager)
        } catch {
            inboxError = error.localizedDescription
            return false
        }
    }

    /// Reorders only the visible queue's selected IDs; archived entries keep
    /// their old position and reappear there. Renormalization touches payloads
    /// only, never Block.sortIndex or document parentage.
    @discardableResult
    func moveInboxTask(_ id: UUID, before targetID: UUID?, undoManager: UndoManager? = nil) -> Bool {
        do {
            let tasks = try context.fetch(FetchDescriptor<Block>())
            let lists = try context.fetch(FetchDescriptor<TaskList>())
            var ordered = InboxPolicy(lists: lists).ordered(tasks)
            guard let source = ordered.firstIndex(where: { $0.id == id }) else { throw InboxMembershipError.unavailable }
            let task = ordered.remove(at: source)
            let destination: Int
            if let targetID {
                guard let index = ordered.firstIndex(where: { $0.id == targetID }) else { throw InboxMembershipError.unavailable }
                destination = index
            } else { destination = ordered.count }
            ordered.insert(task, at: destination)
            let changes = try ordered.enumerated().compactMap { index, task -> InboxChange? in
                var value = try InboxMembership.decode(task.inboxMembershipData!)
                value.order = Double(index) * BlockTree.indexStep
                let data = try value.encoded()
                return data == task.inboxMembershipData ? nil : InboxChange(id: task.id, before: task.inboxMembershipData, after: data, occurrenceID: task.occurrenceID)
            }
            return try applyInboxChanges(changes, name: "Reorder Inbox", undoManager: undoManager)
        } catch { inboxError = error.localizedDescription; return false }
    }

    private func applyInboxChanges(_ changes: [InboxChange], name: String, undoManager: UndoManager?, rebindingOccurrence: Bool = false) throws -> Bool {
        guard !changes.isEmpty else { inboxError = nil; return true }
        let ids = changes.map(\.id)
        let tasks = try context.fetch(FetchDescriptor<Block>(predicate: #Predicate { ids.contains($0.id) }))
        let byID = Dictionary(tasks.filter { !$0.isDeleted }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let applied = try changes.map { change -> InboxChange in
            guard let task = byID[change.id] else { throw InboxMembershipError.unavailable }
            var matches = task.inboxMembershipData == change.before
            if !matches, rebindingOccurrence,
               let liveData = task.inboxMembershipData, let expectedData = change.before,
               let live = try? InboxMembership.decode(liveData),
               var expected = try? InboxMembership.decode(expectedData),
               live.included, expected.included, live.occurrenceID == task.occurrenceID,
               expected.occurrenceID == change.occurrenceID {
                // Completion Undo/reopen may rebind this same decision. A new
                // decision UUID, order, or included state still conflicts.
                expected.occurrenceID = live.occurrenceID
                matches = live == expected
            }
            guard matches else { throw InboxMembershipError.unavailable }
            var desired = change.after
            if rebindingOccurrence, let data = desired,
               var selection = try? InboxMembership.decode(data), selection.included,
               selection.occurrenceID == change.occurrenceID {
                // Only carry a state that was selected when captured. A stale
                // old-client payload must retain its prior excluded effect.
                selection.occurrenceID = task.occurrenceID
                desired = try selection.encoded()
            }
            return InboxChange(id: change.id, before: task.inboxMembershipData, after: desired, occurrenceID: task.occurrenceID)
        }
        for change in applied { byID[change.id]?.inboxMembershipData = change.after }
        do { try persistChanges() }
        catch {
            for change in applied { byID[change.id]?.inboxMembershipData = change.before }
            context.processPendingChanges()
            throw error
        }
        inboxError = nil
        if let undoManager {
            undoManager.registerUndo(withTarget: self) { [weak undoManager] store in
                do {
                    let inverse = applied.map { InboxChange(id: $0.id, before: $0.after, after: $0.before, occurrenceID: $0.occurrenceID) }
                    _ = try store.applyInboxChanges(inverse, name: name, undoManager: undoManager, rebindingOccurrence: true)
                } catch { store.inboxError = "Inbox Undo could not be applied. \(error.localizedDescription)" }
            }
            undoManager.setActionName(name)
        }
        return true
    }

    /// An ordinary reopen retains curation even though calendar identity
    /// changes. Recurrence advancement deliberately does not call this.
    func carryInboxSelection(_ task: Block, from oldOccurrenceID: UUID) {
        guard let data = task.inboxMembershipData,
              var selection = try? InboxMembership.decode(data), selection.included,
              selection.occurrenceID == oldOccurrenceID else { return }
        selection.occurrenceID = task.occurrenceID
        task.inboxMembershipData = try? selection.encoded()
    }

    func clearInboxForNextOccurrence(_ task: Block) {
        // Unknown future versions are retained, not overwritten. Their own
        // occurrence guard is left to the compatible app that understands it.
        guard let data = task.inboxMembershipData, (try? InboxMembership.decode(data)) != nil else { return }
        task.inboxMembershipData = InboxMembership.excludedData
    }
}
