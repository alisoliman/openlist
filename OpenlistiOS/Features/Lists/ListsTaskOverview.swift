import Foundation

/// A single task queue across active lists, including Inbox and nested lists.
/// Due tasks lead; ties and undated tasks retain each list's document order.
enum ListsTaskOverview {
    static func tasks(in library: NextLibrary, blocks: [Block], selectedLists: Set<UUID> = []) -> [Block] {
        let selection = selectedLists.intersection(library.lists.map(\.id))
        let pool = library.tasksInOutlineOrder(blocks: blocks)
            .filter { !$0.isCompleted && (selection.isEmpty || $0.listID.map(selection.contains) == true) }
        let position = Dictionary(pool.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        return pool.sorted { lhs, rhs in
            switch (lhs.dueDate, rhs.dueDate) {
            case let (left?, right?) where left != right: left < right
            case (_?, nil): true
            case (nil, _?): false
            default: (position[lhs.id] ?? 0) < (position[rhs.id] ?? 0)
            }
        }
    }

    /// The full path distinguishes equally named nested lists.
    static func source(of task: Block, in library: NextLibrary) -> String? {
        guard let list = library.list(task.listID) else { return nil }
        return (library.hierarchy.ancestors(of: list.id) + [list]).map(\.displayTitle).joined(separator: " › ")
    }
}
