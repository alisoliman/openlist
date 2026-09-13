import Foundation
import SwiftData

private struct InboxChange {
    let id: UUID
    let before: Data?
    let after: Data?
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
                guard (InboxPolicy.selection(task) != nil) != included || (!included && task.inboxMembershipData == nil) else { continue }
                let previousOrder = order
                order -= BlockTree.indexStep
                guard !included || (order.isFinite && order < previousOrder) else { throw InboxMembershipError.ordering }
                let data = included ? try InboxMembership.included(order: order, occurrenceID: task.occurrenceID).encoded() : InboxMembership.excludedData
                changes.append(InboxChange(id: id, before: task.inboxMembershipData, after: data))
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
                let data = try InboxMembership.included(order: Double(index) * BlockTree.indexStep, occurrenceID: task.occurrenceID).encoded()
                return data == task.inboxMembershipData ? nil : InboxChange(id: task.id, before: task.inboxMembershipData, after: data)
            }
            return try applyInboxChanges(changes, name: "Reorder Inbox", undoManager: undoManager)
        } catch { inboxError = error.localizedDescription; return false }
    }

    private func applyInboxChanges(_ changes: [InboxChange], name: String, undoManager: UndoManager?) throws -> Bool {
        guard !changes.isEmpty else { inboxError = nil; return true }
        let ids = changes.map(\.id)
        let tasks = try context.fetch(FetchDescriptor<Block>(predicate: #Predicate { ids.contains($0.id) }))
        let byID = Dictionary(tasks.filter { !$0.isDeleted }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard changes.allSatisfy({ change in
            guard let task = byID[change.id] else { return false }
            return task.inboxMembershipData == change.before
        }) else { throw InboxMembershipError.unavailable }
        for change in changes { byID[change.id]?.inboxMembershipData = change.after }
        do { try persistChanges() }
        catch {
            for change in changes { byID[change.id]?.inboxMembershipData = change.before }
            context.processPendingChanges()
            throw error
        }
        inboxError = nil
        if let undoManager {
            undoManager.registerUndo(withTarget: self) { [weak undoManager] store in
                do {
                    let inverse = changes.map { InboxChange(id: $0.id, before: $0.after, after: $0.before) }
                    _ = try store.applyInboxChanges(inverse, name: name, undoManager: undoManager)
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
