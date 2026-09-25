//
//  SidebarOrder.swift
//  openlist
//

import Foundation

extension ListHierarchy {
    /// The sidebar's order, which the List widget's picker follows too: Inbox
    /// first, then top-level lists by section and position, each followed by
    /// its nested lists. `sections` come in their own order.
    func sidebarOrder(_ active: [TaskList], sections: [SidebarSection]) -> [TaskList] {
        let sectionRank = Dictionary(sections.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Lists with no surviving section sit under "Other lists", pinned ones
        // first; unpinned ones are only in the gallery.
        func rank(_ list: TaskList) -> Int {
            if list.isSystemInbox { return -1 }
            if let index = list.sectionID.flatMap({ sectionRank[$0] }) { return index }
            return sections.count + (list.isPinned ? 0 : 1)
        }
        let roots = active.filter { parent(of: $0.id) == nil }
            .sorted { (rank($0), $0.sidebarIndex) < (rank($1), $1.sidebarIndex) }
        return nested(roots, among: active)
    }

    /// Each list followed by its nested lists, depth first. Lists whose parent
    /// is in `lists` come after it rather than at the top level.
    func nested(_ lists: [TaskList]) -> [TaskList] {
        let ids = Set(lists.map(\.id))
        let roots = lists.filter { parent(of: $0.id).map { ids.contains($0.id) } != true }
        return nested(roots, among: lists)
    }

    private func nested(_ roots: [TaskList], among lists: [TaskList]) -> [TaskList] {
        let ids = Set(lists.map(\.id))
        var ordered: [TaskList] = []
        var seen = Set<UUID>()
        func visit(_ list: TaskList) {
            guard seen.insert(list.id).inserted else { return }
            ordered.append(list)
            for child in children(of: list.id) where ids.contains(child.id) { visit(child) }
        }
        for root in roots { visit(root) }
        // A list the walk can't reach still belongs in the library.
        return ordered + lists.filter { !seen.contains($0.id) }
    }
}
