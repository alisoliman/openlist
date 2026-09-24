//
//  NextLibrary.swift
//  openlist
//

import SwiftUI

/// One render pass's view of the library, built from the shell's queries so
/// every screen reads the same lists, labels and tasks.
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

extension TaskList {
    @MainActor var nxColor: Color { isSystemInbox ? NX.inbox : accent.color }
}

extension TaskLabel {
    @MainActor var nxColor: Color { accent.color }
}

private struct NextLibraryKey: EnvironmentKey {
    static let defaultValue = NextLibrary()
}

extension EnvironmentValues {
    var nextLibrary: NextLibrary {
        get { self[NextLibraryKey.self] }
        set { self[NextLibraryKey.self] = newValue }
    }
}

/// Glyph for list icons that may be an emoji or an SF Symbol name.
struct NXListGlyph: View {
    let list: TaskList
    var size: CGFloat = 14

    /// Whether a list icon names an SF Symbol rather than being an emoji,
    /// by the rule the widgets share (`ListIcon`).
    static func isSymbolName(_ icon: String) -> Bool { ListIcon.isSymbolName(icon) }

    var body: some View {
        let icon = list.glyph
        if Self.isSymbolName(icon) {
            Image(systemName: icon)
                .font(.system(size: size * 0.9, weight: .medium))
                .foregroundStyle(list.nxColor)
        } else {
            Text(icon).font(.system(size: Self.emojiPointSize(size)))
        }
    }

    /// The emoji's size for a design size, which the widget shares (`EmojiSize`).
    static func emojiPointSize(_ size: CGFloat) -> CGFloat { EmojiSize.points(forDesign: size) }

    /// A list icon to run inline with text at `size`, as the design's
    /// `emoji + " " + name` strings: the emoji at the design's size rather
    /// than Core Text's larger one, or the SF Symbol, in `color` if given.
    static func text(_ icon: String, size: CGFloat, color: Color? = nil) -> Text {
        guard isSymbolName(icon) else { return Text(verbatim: icon).font(.system(size: emojiPointSize(size))) }
        let symbol = Text(Image(systemName: icon)).font(.system(size: size * 0.9, weight: .medium))
        return color.map { symbol.foregroundStyle($0) } ?? symbol
    }

    /// A list's glyph inline with text at `size`, a symbol in the list's colour.
    static func text(_ list: TaskList, size: CGFloat) -> Text {
        text(list.glyph, size: size, color: list.nxColor)
    }
}

/// A list as a menu item, as in Move to: its emoji before its name, or its
/// symbol as the item's image rather than the symbol's name as text.
struct NXListMenuButton: View {
    let list: TaskList
    let action: () -> Void

    var body: some View {
        let icon = list.glyph
        if NXListGlyph.isSymbolName(icon) {
            Button(list.displayTitle, systemImage: icon, action: action)
        } else {
            Button("\(icon) \(list.displayTitle)", action: action)
        }
    }
}

// MARK: - Shared queries

extension NextLibrary {
    /// Whether a task sits under another task rather than at a list's top level.
    func isSubtask(_ task: Block) -> Bool {
        guard let parentID = task.parentID else { return false }
        return tasksByID[parentID] != nil
    }

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

    /// Inbox tasks waiting for a decision, oldest first. A subtask goes with
    /// the open task above it, whose card carries it; one under done tasks
    /// only is a card of its own, or triage could never reach it.
    @MainActor
    func inboxQueue(_ workbench: Workbench) -> [Block] {
        tasks.filter { isInbox($0) && !$0.isCompleted && !workbench.kept.contains($0.id) && workbench.closing[$0.id] == nil }
            .filter { !isUnderOpenTask($0) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    @MainActor
    func keptInbox(_ workbench: Workbench) -> [Block] {
        tasks.filter { isInbox($0) && !$0.isCompleted && workbench.kept.contains($0.id) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Open work that belongs on Today: due or overdue, planned, or starred.
    @MainActor
    func isToday(_ task: Block, _ workbench: Workbench) -> Bool {
        guard !task.isCompleted || workbench.closing[task.id] != nil else { return false }
        if task.isDueOnOrBeforeToday { return true }
        return workbench.isPlanned(task) || task.isStarred
    }

    @MainActor
    func todayCount(_ workbench: Workbench) -> Int {
        open.filter { isToday($0, workbench) }.count
    }
}
