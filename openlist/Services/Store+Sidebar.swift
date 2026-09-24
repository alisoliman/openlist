import Foundation
import SwiftData

/// Where a list sits in the sidebar, which Undo of a sidebar change puts back.
struct SidebarPlacement: Equatable {
    var sectionID: UUID?
    var isPinned: Bool
    var sidebarIndex: Double
}

/// A sidebar section as it was deleted, with the lists it held, for the Undo
/// that brings it back.
struct DeletedSidebarSection: Equatable {
    var id: UUID
    var title: String
    var sortIndex: Double
    var isCollapsed: Bool
    var createdAt: Date
    /// Its lists as they sat in it.
    var lists: [UUID: SidebarPlacement]
}

extension Store {
    /// Every list's place in the sidebar, archived ones included.
    func sidebarPlacements() -> [UUID: SidebarPlacement] {
        Dictionary(allLists(includeArchived: true).map {
            ($0.id, SidebarPlacement(sectionID: $0.sectionID, isPinned: $0.isPinned, sidebarIndex: $0.sidebarIndex))
        }, uniquingKeysWith: { first, _ in first })
    }

    /// Puts lists back where `placements` has them, in one save: only those
    /// still where `expected` left them, so a list filed elsewhere since
    /// stays there. A section gone since leaves its lists under "Other lists".
    func applySidebarPlacements(_ placements: [UUID: SidebarPlacement], expecting expected: [UUID: SidebarPlacement]) {
        let sections = Set(allSections().map(\.id))
        var changed = false
        for list in allLists(includeArchived: true) {
            guard var placement = placements[list.id], let wanted = expected[list.id],
                  SidebarPlacement(sectionID: list.sectionID, isPinned: list.isPinned, sidebarIndex: list.sidebarIndex) == wanted
            else { continue }
            if let sectionID = placement.sectionID, !sections.contains(sectionID) { placement.sectionID = nil }
            guard placement != wanted else { continue }
            list.sectionID = placement.sectionID
            list.isPinned = placement.isPinned
            list.sidebarIndex = placement.sidebarIndex
            list.touch()
            changed = true
        }
        if changed { save() }
    }

    /// ``deleteSection(_:)``, keeping what Undo needs to bring the section
    /// back with its lists. Nil, and nothing deleted, for the default one.
    func removeSection(_ section: SidebarSection) -> DeletedSidebarSection? {
        let section = resolvedSection(section)
        guard !section.isDefault, section.modelContext != nil, !section.isDeleted else { return nil }
        let placements = sidebarPlacements().filter { $0.value.sectionID == section.id }
        let deleted = DeletedSidebarSection(id: section.id, title: section.title, sortIndex: section.sortIndex,
                                            isCollapsed: section.isCollapsed, createdAt: section.createdAt, lists: placements)
        deleteSection(section)
        return deleted
    }

    /// Undo of ``removeSection(_:)``: the section back under its own id, and
    /// its lists back in it where they sat, unless filed elsewhere since.
    @discardableResult
    func restoreSection(_ deleted: DeletedSidebarSection) -> Bool {
        let id = deleted.id
        guard (try? context.fetchCount(FetchDescriptor<SidebarSection>(predicate: #Predicate { $0.id == id }))) == 0 else {
            return true
        }
        let section = SidebarSection(title: deleted.title, sortIndex: deleted.sortIndex)
        section.id = id
        section.isCollapsed = deleted.isCollapsed
        section.createdAt = deleted.createdAt
        context.insert(section)
        do {
            try persistChanges()
        } catch {
            context.rollback()
            if section.modelContext != nil { context.delete(section) }
            context.processPendingChanges()
            persistenceError = "The section could not be restored. \(error.localizedDescription)"
            return false
        }
        // Deleting it left each of them unfiled, still pinned where it was.
        let unfiled = deleted.lists.mapValues { SidebarPlacement(sectionID: nil, isPinned: $0.isPinned, sidebarIndex: $0.sidebarIndex) }
        applySidebarPlacements(deleted.lists, expecting: unfiled)
        return true
    }
}
