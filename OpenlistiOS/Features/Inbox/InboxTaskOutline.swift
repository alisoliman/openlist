import Foundation

/// Inbox parents keep their place in the capture or snoozed group. Revealed
/// children are display rows and do not become additional triage entries.
struct InboxTaskOutline {
    struct Row: Identifiable {
        let task: Block
        let depth: Int
        let progress: (done: Int, total: Int)?
        let isExpanded: Bool

        var id: UUID { task.id }
    }

    private var children: [UUID: [Block]] = [:]

    init(library: NextLibrary) {
        for listID in library.inboxIDs {
            for (parent, children) in BlockTree.childIndex(of: library.tasks(in: listID)) {
                if let parent { self.children[parent] = children }
            }
        }
    }

    func rows(for roots: [Block], rootIDs: Set<UUID>, expanded: Set<UUID>, closing: Set<UUID>,
              now: Date, includesSnoozed: Bool = false) -> [Row] {
        var rows: [Row] = []
        func visit(_ task: Block, depth: Int) {
            // During completion dwell the open children can become captures
            // of their own. Render each once, and let Undo restore the fold.
            let subtasks = (children[task.id] ?? []).filter {
                !rootIDs.contains($0.id) && (includesSnoozed || !InboxPolicy.isSnoozed($0, now: now))
            }
            let progress = subtasks.isEmpty || closing.contains(task.id) ? nil
                : (done: subtasks.count { $0.isCompleted || closing.contains($0.id) }, total: subtasks.count)
            let isExpanded = progress != nil && expanded.contains(task.id)
            rows.append(Row(task: task, depth: depth, progress: progress, isExpanded: isExpanded))
            if isExpanded {
                for child in subtasks { visit(child, depth: depth + 1) }
            }
        }
        for root in roots { visit(root, depth: 0) }
        return rows
    }
}
