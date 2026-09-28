//
//  NextLibraryCore.swift
//  openlist
//

import Foundation

/// One render pass's view of the library, built from the shell's queries so
/// every screen reads the same lists, labels and tasks. UI-free, so the
/// phone builds the same view from its own queries.
struct NextLibrary {
    /// Active lists in sidebar order: Inbox, each section's lists, then the
    /// rest, with nested lists straight after their parent.
    var lists: [TaskList] = []
    /// Archived lists, directly or through a parent, nested after their parent.
    private(set) var archived: [TaskList] = []
    var sections: [SidebarSection] = []
    var labels: [TaskLabel] = []
    /// Every non-trashed task in an active list, open and completed.
    private(set) var tasks: [Block] = []
    /// The open subset of `tasks`.
    private(set) var open: [Block] = []
    var hierarchy = ListHierarchy([])
    var inboxIDs: Set<UUID> = []

    /// Active and archived lists.
    private var listsByID: [UUID: TaskList] = [:]
    private var activeListIDs: Set<UUID> = []
    private var labelsByID: [UUID: TaskLabel] = [:]
    /// Non-trashed tasks of active and archived lists.
    private var tasksByList: [UUID: [Block]] = [:]
    private var tasksByID: [UUID: Block] = [:]
    private var openByList: [UUID: Int] = [:]
    private var openByLabel: [UUID: Int] = [:]

    init() {}

    init(lists allLists: [TaskList], sections: [SidebarSection], labels: [TaskLabel], tasks: [Block]) {
        hierarchy = ListHierarchy(allLists)
        self.sections = sections.sorted { $0.sortIndex < $1.sortIndex }
        self.labels = labels.sorted { $0.sortIndex < $1.sortIndex }
        let active = allLists.filter { hierarchy.activeIDs.contains($0.id) }
        let archived = allLists.filter { hierarchy.isArchived($0.id) }
        lists = hierarchy.sidebarOrder(active, sections: self.sections)
        self.archived = hierarchy.nested(archived.sorted { $0.sortIndex < $1.sortIndex })
        listsByID = Dictionary((active + archived).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        activeListIDs = Set(active.map(\.id))
        labelsByID = Dictionary(labels.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for task in tasks where task.trashID == nil {
            guard let listID = task.listID, listsByID[listID] != nil else { continue }
            tasksByList[listID, default: []].append(task)
            tasksByID[task.id] = task
            if !task.isCompleted { openByList[listID, default: 0] += 1 }
            guard activeListIDs.contains(listID) else { continue }
            self.tasks.append(task)
            guard !task.isCompleted else { continue }
            open.append(task)
            for id in Set(task.labelIDs) { openByLabel[id, default: 0] += 1 }
        }
        inboxIDs = hierarchy.inboxIDs
    }

    /// Resolves active and archived lists.
    func list(_ id: UUID?) -> TaskList? { id.flatMap { listsByID[$0] } }
    func label(_ id: UUID) -> TaskLabel? { labelsByID[id] }

    var inbox: TaskList? { lists.first(where: \.isSystemInbox) }
    /// Lists you can file into: everything except Inbox.
    var destinations: [TaskList] { lists.filter { !$0.isSystemInbox } }

    /// Every non-trashed task in a list, active or archived, open and completed.
    func tasks(in listID: UUID) -> [Block] { tasksByList[listID] ?? [] }

    func isInbox(_ task: Block) -> Bool { task.listID.map(inboxIDs.contains) == true }

    func openCount(in listID: UUID) -> Int { openByList[listID] ?? 0 }

    /// Open tasks in active lists with the label.
    func openCount(label id: UUID) -> Int { openByLabel[id] ?? 0 }

    /// Top-level lists in a section; nested lists follow their parent.
    func lists(in section: SidebarSection) -> [TaskList] {
        lists.filter { !$0.isSystemInbox && $0.sectionID == section.id && hierarchy.parent(of: $0.id) == nil }
    }

    /// Lists with no surviving section.
    var unsectioned: [TaskList] {
        let ids = Set(sections.map(\.id))
        return lists.filter { list in
            !list.isSystemInbox && hierarchy.parent(of: list.id) == nil
                && (list.sectionID == nil || !ids.contains(list.sectionID!))
        }
    }

    /// Active nested lists, in order.
    func children(of list: TaskList) -> [TaskList] {
        hierarchy.children(of: list.id).filter { activeListIDs.contains($0.id) }
    }

    /// Each list followed by its active nested lists, depth first.
    func outline(_ roots: [TaskList]) -> [NXOutlineRow] {
        var rows: [NXOutlineRow] = []
        var seen = Set<UUID>()
        func visit(_ list: TaskList, depth: Int) {
            guard seen.insert(list.id).inserted else { return }
            rows.append(NXOutlineRow(list: list, depth: depth))
            for child in children(of: list) { visit(child, depth: depth + 1) }
        }
        for root in roots { visit(root, depth: 0) }
        return rows
    }

    /// The section a list is filed under, through its top-level ancestor.
    func sectionTitle(for list: TaskList) -> String {
        if list.isSystemInbox { return "" }
        let root = hierarchy.ancestors(of: list.id).first ?? list
        return sections.first { $0.id == root.sectionID }?.displayTitle ?? ""
    }
}

/// A list in an outline, with how far below its top-level list it sits.
struct NXOutlineRow: Identifiable {
    let list: TaskList
    let depth: Int
    var id: UUID { list.id }
}

// MARK: - Shared queries

extension NextLibrary {
    /// Whether an open task sits above this one, through its parent tasks.
    func isUnderOpenTask(_ task: Block) -> Bool {
        var seen: Set<UUID> = [task.id]
        var parentID = task.parentID
        while let id = parentID, let parent = tasksByID[id], seen.insert(id).inserted {
            if !parent.isCompleted { return true }
            parentID = parent.parentID
        }
        return false
    }

    /// Inbox tasks waiting for a decision, oldest first: open, not `kept`
    /// for later and not `closing` in their completion dwell. A subtask goes
    /// with the open task above it, whose card carries it; one under done
    /// tasks only is a card of its own, or triage could never reach it.
    func inboxQueue(kept: Set<UUID>, closing: Set<UUID>) -> [Block] {
        tasks.filter { isInbox($0) && !$0.isCompleted && !kept.contains($0.id) && !closing.contains($0.id) }
            .filter { !isUnderOpenTask($0) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Open Inbox tasks set aside for later, oldest first.
    func keptInbox(kept: Set<UUID>) -> [Block] {
        tasks.filter { isInbox($0) && !$0.isCompleted && kept.contains($0.id) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Every task in the order the lists show it: lists in sidebar order,
    /// each in its document's order under the list's Sort, as its page draws
    /// it. `blocks` are the documents' non-trashed blocks, for that order.
    func tasksInOutlineOrder(blocks: [Block]) -> [Block] {
        let blocksByList = Dictionary(grouping: blocks) { $0.listID }
        return lists.flatMap { list -> [Block] in
            let tasks = tasks(in: list.id)
            guard !tasks.isEmpty else { return [] }
            let taskIDs = Set(tasks.lazy.map(\.id))
            let rows = BlockTree.flatten(blocksByList[list.id] ?? [], respectCollapse: false)
            let ordered = BlockTree.sortingTaskRuns(in: rows, by: list.sorting)
                .compactMap { taskIDs.contains($0.id) ? $0.block : nil }
            // Tasks the outline could not reach still belong on the screen.
            let seen = Set(ordered.lazy.map(\.id))
            return ordered + tasks.filter { !seen.contains($0.id) }
        }
    }
}
