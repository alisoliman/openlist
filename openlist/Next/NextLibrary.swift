//
//  NextLibrary.swift
//  openlist
//

import SwiftUI

/// One render pass's view of the library, built from the shell's queries so
/// every screen reads the same lists, labels and tasks.
struct NextLibrary {
    /// Active lists in sidebar order, Inbox first.
    var lists: [TaskList] = []
    var sections: [SidebarSection] = []
    var labels: [TaskLabel] = []
    /// Every non-trashed task in an active list, open and completed.
    var tasks: [Block] = []
    var hierarchy = ListHierarchy([])
    var inboxIDs: Set<UUID> = []

    private var listsByID: [UUID: TaskList] = [:]
    private var labelsByID: [UUID: TaskLabel] = [:]

    init() {}

    init(lists allLists: [TaskList], sections: [SidebarSection], labels: [TaskLabel], tasks: [Block]) {
        hierarchy = ListHierarchy(allLists)
        let active = allLists.filter { hierarchy.activeIDs.contains($0.id) }
            .sorted { ($0.isSystemInbox ? 0 : 1, $0.sidebarIndex) < ($1.isSystemInbox ? 0 : 1, $1.sidebarIndex) }
        lists = active
        self.sections = sections.sorted { $0.sortIndex < $1.sortIndex }
        self.labels = labels.sorted { $0.sortIndex < $1.sortIndex }
        listsByID = Dictionary(active.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        labelsByID = Dictionary(labels.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let activeIDs = Set(active.map(\.id))
        self.tasks = tasks.filter { $0.trashID == nil && $0.listID.map(activeIDs.contains) == true }
        inboxIDs = hierarchy.inboxIDs
    }

    func list(_ id: UUID?) -> TaskList? { id.flatMap { listsByID[$0] } }
    func label(_ id: UUID) -> TaskLabel? { labelsByID[id] }

    var inbox: TaskList? { lists.first(where: \.isSystemInbox) }
    /// Lists you can file into: everything except Inbox.
    var destinations: [TaskList] { lists.filter { !$0.isSystemInbox } }

    var open: [Block] { tasks.filter { !$0.isCompleted } }

    func isInbox(_ task: Block) -> Bool { task.listID.map(inboxIDs.contains) == true }

    func openCount(in listID: UUID) -> Int { tasks.filter { $0.listID == listID && !$0.isCompleted }.count }

    func openCount(label id: UUID) -> Int { tasks.filter { !$0.isCompleted && $0.labelIDs.contains(id) }.count }

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

    func children(of list: TaskList) -> [TaskList] {
        hierarchy.children(of: list.id).filter { listsByID[$0.id] != nil }
    }

    func sectionTitle(for list: TaskList) -> String {
        if list.isSystemInbox { return "" }
        let root = hierarchy.ancestors(of: list.id).last ?? list
        return sections.first { $0.id == root.sectionID }?.displayTitle ?? ""
    }
}

extension TaskList {
    /// The emoji shown for a list; Inbox has a fixed one.
    var glyph: String {
        if isSystemInbox { return "📥" }
        return icon.isEmpty ? "📋" : icon
    }

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

    var body: some View {
        let icon = list.glyph
        if icon.allSatisfy({ $0.isASCII }), icon.contains(".") || icon.count > 2, NSImage(systemSymbolName: icon, accessibilityDescription: nil) != nil {
            Image(systemName: icon)
                .font(.system(size: size * 0.9, weight: .medium))
                .foregroundStyle(list.nxColor)
        } else {
            Text(icon).font(.system(size: size))
        }
    }
}

// MARK: - Shared queries

extension NextLibrary {
    /// Whether a task sits under another task rather than at a list's top level.
    func isSubtask(_ task: Block) -> Bool {
        guard let parentID = task.parentID else { return false }
        return tasks.contains { $0.id == parentID }
    }

    /// Inbox tasks waiting for a decision, oldest first.
    @MainActor
    func inboxQueue(_ workbench: Workbench) -> [Block] {
        tasks.filter { isInbox($0) && !$0.isCompleted && !workbench.kept.contains($0.id) && workbench.closing[$0.id] == nil }
            .filter { !isSubtask($0) }
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
        if let due = task.dueDate, NXFormat.dayOffset(due) <= 0 { return true }
        return workbench.isPlanned(task) || task.isStarred
    }

    @MainActor
    func todayCount(_ workbench: Workbench) -> Int {
        open.filter { isToday($0, workbench) }.count
    }
}
