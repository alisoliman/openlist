import Foundation
import SwiftData

/// Scalar ownership is separate from reference links, task indentation and pins.
/// All traversal is bounded even while independent CloudKit records arrive.
struct ListHierarchy {
    private let records: [UUID: TaskList]
    private let displayParents: [UUID: UUID]
    let availableIDs: Set<UUID>
    let activeIDs: Set<UUID>

    init(_ supplied: [TaskList]) {
        var lists = supplied.filter { !$0.isDeleted }
        let ids = Set(lists.map(\.id))
        var expansionFailed = false
        // A filtered query can omit an archived/retained ancestor. Include it in
        // the policy projection without changing the caller's visible results.
        if lists.contains(where: { $0.parentListID.map { !ids.contains($0) } == true }),
           let context = lists.compactMap(\.modelContext).first {
            do { lists = try context.fetch(FetchDescriptor<TaskList>()).filter { !$0.isDeleted } }
            catch { expansionFailed = true }
        }
        let records = Dictionary(lists.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.records = records
        var parents: [UUID: UUID] = [:]
        for list in lists where !list.isSystemInbox {
            if let id = list.parentListID, let parent = records[id], !parent.isSystemInbox,
               parent.mergedIntoID == nil { parents[list.id] = id }
        }
        // Break the lowest UUID edge of each imported cycle for display only.
        for start in parents.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            var path: [UUID] = []
            var positions: [UUID: Int] = [:]
            var next: UUID? = start
            while let id = next {
                if let position = positions[id] {
                    let root = path[position...].min { $0.uuidString < $1.uuidString }!
                    parents[root] = nil
                    break
                }
                positions[id] = path.count
                path.append(id)
                next = parents[id]
            }
        }
        displayParents = parents
        var available = Set<UUID>(), active = Set<UUID>()
        for list in lists where list.mergedIntoID == nil {
            var archived = false, retained = false
            var seen = Set<UUID>()
            var next: UUID? = list.id
            while let id = next, seen.insert(id).inserted, let ancestor = records[id] {
                archived = archived || ancestor.isArchived
                retained = retained || ancestor.isTrashed
                next = ancestor.isSystemInbox ? nil : ancestor.parentListID
            }
            // A failed read is different from a successfully read orphan.
            // Unknown inherited state cannot contribute active work.
            if expansionFailed && next != nil { continue }
            if !retained {
                available.insert(list.id)
                if !archived { active.insert(list.id) }
            }
        }
        availableIDs = available
        activeIDs = active
    }

    func isArchived(_ id: UUID) -> Bool { availableIDs.contains(id) && !activeIDs.contains(id) }
    func isAvailable(_ id: UUID) -> Bool { availableIDs.contains(id) }
    func parent(of id: UUID) -> TaskList? { displayParents[id].flatMap { records[$0] } }

    func ancestors(of id: UUID) -> [TaskList] {
        var result: [TaskList] = []
        var next = displayParents[id]
        while let id = next, let parent = records[id] {
            result.append(parent)
            next = displayParents[id]
        }
        return result.reversed()
    }

    func children(of id: UUID) -> [TaskList] {
        records.values.filter { displayParents[$0.id] == id && availableIDs.contains($0.id) }.sorted(by: Self.ordered)
    }

    /// Includes archived owned documents; excludes independently retained units.
    func subtree(of id: UUID) -> [TaskList] {
        guard let root = records[id] else { return [] }
        var result = [root], offset = 0
        while offset < result.count {
            result.append(contentsOf: children(of: result[offset].id))
            offset += 1
        }
        return result
    }

    func canMove(_ id: UUID, under parentID: UUID?) -> Bool {
        guard let list = records[id], !list.isSystemInbox, availableIDs.contains(id) else { return false }
        guard let parentID else { return true }
        guard let parent = records[parentID], !parent.isSystemInbox, activeIDs.contains(parentID) else { return false }
        // Inspect raw references too, so an imported cycle cannot hide a
        // forbidden descendant behind the presentation-only broken edge.
        var next: UUID? = parentID, seen = Set<UUID>()
        while let current = next {
            if current == id || !seen.insert(current).inserted { return false }
            next = records[current]?.parentListID
        }
        return true
    }

    func retainedGroup(for id: UUID) -> UUID? {
        var next: UUID? = id, seen = Set<UUID>()
        while let current = next, seen.insert(current).inserted, let list = records[current] {
            if let group = list.trashID { return group }
            next = list.parentListID
        }
        return nil
    }

    func path(for id: UUID) -> String {
        (ancestors(of: id).map(\.displayTitle) + (records[id].map { [$0.displayTitle] } ?? [])).joined(separator: " › ")
    }

    func recoveryContext(for id: UUID) -> String? {
        guard let list = records[id], let parentID = list.parentListID else { return nil }
        if records[parentID] == nil { return "Parent list unavailable. Shown at top level until its parent returns." }
        if displayParents[id] == nil { return "This imported parent relationship cannot be displayed. Move this list to choose its location." }
        return nil
    }

    private static func ordered(_ left: TaskList, _ right: TaskList) -> Bool {
        left.sortIndex == right.sortIndex ? left.id.uuidString < right.id.uuidString : left.sortIndex < right.sortIndex
    }
}
