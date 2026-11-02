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
    /// for later, not snoozed past `now`'s day and not `closing` in their
    /// completion dwell. A subtask goes with the open task above it, whose
    /// card carries it; one under done tasks only is a card of its own, or
    /// triage could never reach it.
    func inboxQueue(kept: Set<UUID>, closing: Set<UUID>, now: Date = .now) -> [Block] {
        tasks.filter { isInbox($0) && !$0.isCompleted && !kept.contains($0.id) && !closing.contains($0.id) }
            .filter { !isUnderOpenTask($0) && !InboxPolicy.isSnoozed($0, now: now) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Open Inbox tasks set aside for later, oldest first; snoozed ones are
    /// `snoozedInbox`'s.
    func keptInbox(kept: Set<UUID>, now: Date = .now) -> [Block] {
        tasks.filter { isInbox($0) && !$0.isCompleted && kept.contains($0.id) && !InboxPolicy.isSnoozed($0, now: now) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Inbox tasks snoozed past `now`'s day, the soonest back first. A
    /// subtask goes with the open task above it, as in the queue.
    func snoozedInbox(now: Date = .now) -> [Block] {
        tasks.filter { isInbox($0) && !$0.isCompleted && !isUnderOpenTask($0) && InboxPolicy.isSnoozed($0, now: now) }
            .sorted { ($0.deferredUntil ?? .distantFuture, $0.createdAt) < ($1.deferredUntil ?? .distantFuture, $1.createdAt) }
    }

    /// Tasks in the lists still waiting for a day, in the order the lists
    /// show them: open, with no due date, not planned for a day or deferred
    /// to one, not `kept` for later and not `closing` in their completion
    /// dwell. The Inbox's tasks are its own queue's, and a subtask goes with
    /// the open task above it, as there. `blocks` are the documents'
    /// non-trashed blocks, for that order.
    func undatedQueue(blocks: [Block], kept: Set<UUID>, closing: Set<UUID>, now: Date = .now) -> [Block] {
        tasksInOutlineOrder(blocks: blocks).filter {
            waitsForADay($0, now: now) && !kept.contains($0.id) && !closing.contains($0.id)
        }
    }

    /// How many tasks `undatedQueue` deals, without putting them in order.
    func undatedCount(kept: Set<UUID>, closing: Set<UUID>, now: Date = .now) -> Int {
        open.count { waitsForADay($0, now: now) && !kept.contains($0.id) && !closing.contains($0.id) }
    }

    /// An open task in the lists with no day, not snoozed to one, and no
    /// open task above it.
    private func waitsForADay(_ task: Block, now: Date) -> Bool {
        !task.isCompleted && task.dueDate == nil && task.selectedForDay == nil && !isInbox(task) && !isUnderOpenTask(task)
            && !InboxPolicy.isSnoozed(task, now: now)
    }

    /// Every task in the order the lists show it: lists in sidebar order,
    /// each in its document's order under the list's Sort, as its page draws
    /// it. `blocks` are the documents' non-trashed blocks, for that order.
    func tasksInOutlineOrder(blocks: [Block]) -> [Block] {
        taskRowsInOutlineOrder(blocks: blocks).map(\.block)
    }

    /// The same order with task nesting preserved, including tasks reached
    /// through headings or prose. Folded branches remain available to Today.
    func taskRowsInOutlineOrder(blocks: [Block]) -> [BlockRow] {
        let blocksByList = Dictionary(grouping: blocks) { $0.listID }
        return lists.flatMap { list -> [BlockRow] in
            let tasks = tasks(in: list.id)
            guard !tasks.isEmpty else { return [] }
            let taskIDs = Set(tasks.lazy.map(\.id))
            let rows = BlockTree.flatten(blocksByList[list.id] ?? [], respectCollapse: false)
            let ordered = BlockTree.taskOutline(BlockTree.sortingTaskRuns(in: rows, by: list.sorting))
                .filter { taskIDs.contains($0.id) }
            // Tasks the outline could not reach still belong on the screen.
            let seen = Set(ordered.lazy.map(\.id))
            return ordered + tasks.filter { !seen.contains($0.id) }.map {
                BlockRow(block: $0, depth: 0, ordinal: 0, hasChildren: false, isCollapsed: false)
            }
        }
    }
}

// MARK: - Filing suggestions

extension NextLibrary {
    /// The list `task` most likely belongs in, which triage offers first: the
    /// one whose name its title says, else the one whose tasks share most of
    /// its words, a word few lists use counting for more than a common one.
    /// Nil when no list stands out, or the title says too little to tell.
    func suggestedDestination(for task: Block) -> TaskList? {
        let words = Set(Self.filingWords(in: task.displayTitle))
        let candidates = destinations.filter { $0.id != task.listID }
        guard !words.isEmpty, candidates.count > 1 else { return nil }
        var shared: [UUID: [String: Int]] = [:]
        var named: [UUID: Int] = [:]
        var listsUsing: [String: Int] = [:]
        for list in candidates {
            var counts: [String: Int] = [:]
            // The newest few hundred say enough about a long list.
            for other in tasks(in: list.id).suffix(400) where other.id != task.id {
                for word in Set(Self.filingWords(in: other.displayTitle)) where words.contains(word) { counts[word, default: 0] += 1 }
            }
            shared[list.id] = counts
            named[list.id] = Set(Self.filingWords(in: list.displayTitle)).intersection(words).count
            for word in counts.keys { listsUsing[word, default: 0] += 1 }
        }
        let scores = candidates.map { list -> (list: TaskList, score: Double) in
            let content = (shared[list.id] ?? [:]).reduce(0.0) { sum, entry in
                sum + Double(min(3, entry.value)) / Double(max(1, listsUsing[entry.key] ?? 1))
            }
            return (list, Double(named[list.id] ?? 0) * 2 + content)
        }
        .filter { $0.score > 0 }
        .sorted { $0.score > $1.score }
        // Two words in common, a word two of its tasks use, or its name: one
        // word once, like a person's name, says too little.
        guard let best = scores.first, best.score >= 2, scores.count == 1 || best.score > scores[1].score * 1.25 else { return nil }
        return best.list
    }

    /// The words of `text` that say what it's about: folded, singular, and
    /// without the little words every title has.
    static func filingWords(in text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 3 && !$0.allSatisfy(\.isNumber) && !filingStopWords.contains($0) }
            .map(singular)
    }

    /// An English plural's singular, near enough to match the two:
    /// "berries" "berry", "tomatoes" "tomato", "boxes" "box", "seeds" "seed".
    private static func singular(_ word: String) -> String {
        guard word.count > 3, word.hasSuffix("s") else { return word }
        if word.hasSuffix("ies"), word.count > 4 { return String(word.dropLast(3)) + "y" }
        if ["oes", "ches", "shes", "xes", "zes", "sses"].contains(where: word.hasSuffix) { return String(word.dropLast(2)) }
        if ["ss", "us", "is"].contains(where: word.hasSuffix) { return word }
        return String(word.dropLast())
    }

    private static let filingStopWords: Set<String> = [
        "the", "and", "for", "with", "from", "about", "into", "onto", "this", "that", "these", "those", "your", "our",
        "their", "his", "her", "its", "are", "was", "were", "been", "have", "has", "had", "will", "can", "could",
        "should", "would", "out", "off", "over", "under", "then", "than", "too", "very", "just", "not", "all", "any",
        "some", "more", "most", "new", "get", "got", "make", "made", "take", "put", "set", "use", "via", "per",
        "next", "week", "today", "tomorrow", "tonight", "day", "days", "back", "again", "also", "need", "needs", "todo",
    ]
}
