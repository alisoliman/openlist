//
//  Store.swift
//  openlist
//

import Foundation
import SwiftData
import SwiftUI

/// Identifies the document currently being edited: either a list, or a task's
/// detail page, which behaves like a miniature list rooted at that task.
struct DocumentContext: Hashable {
    var listID: UUID
    /// `nil` when editing the list itself; a task id when editing its details.
    var rootBlockID: UUID?

    init(listID: UUID, rootBlockID: UUID? = nil) {
        self.listID = listID
        self.rootBlockID = rootBlockID
    }
}

/// Every mutation in the app funnels through here.
///
/// Views own presentation; `Store` owns the rules — how completing a repeating
/// task rolls it forward, what indenting does to a subtree, which changes are
/// worth recording in the Updates feed.
@Observable
@MainActor
final class Store {
    let context: ModelContext

    /// Suppresses activity logging during bulk work such as seeding samples.
    private var isLoggingSuspended = false

    /// Set by ``batch(_:)`` so a run of mutations commits once.
    var isSavingSuspended = false

    private var pendingSave: Task<Void, Never>?

    /// Called after every successful save, so downstream caches — currently the
    /// widget snapshot — can refresh themselves.
    var onDidSave: (() -> Void)?

    /// Called when a task is ticked off, wherever that happened — a checkbox,
    /// ⌘D, or the menu bar. Keeps the completion sound on one path instead of
    /// asking every view to remember it.
    var onDidCompleteTask: ((Block) -> Void)?

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Fetching

    func list(id: UUID?) -> TaskList? {
        guard let id else { return nil }
        let descriptor = FetchDescriptor<TaskList>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    func block(id: UUID?) -> Block? {
        guard let id else { return nil }
        let descriptor = FetchDescriptor<Block>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    func allLists(includeArchived: Bool = false) -> [TaskList] {
        var descriptor = FetchDescriptor<TaskList>(sortBy: [SortDescriptor(\.sortIndex)])
        if !includeArchived {
            descriptor.predicate = #Predicate { !$0.isArchived }
        }
        return (try? context.fetch(descriptor)) ?? []
    }

    func blocks(inList listID: UUID) -> [Block] {
        let descriptor = FetchDescriptor<Block>(
            predicate: #Predicate { $0.listID == listID },
            sortBy: [SortDescriptor(\.sortIndex)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func children(of parentID: UUID?, listID: UUID) -> [Block] {
        BlockTree.children(of: parentID, in: blocks(inList: listID))
    }

    func allLabels() -> [TaskLabel] {
        let descriptor = FetchDescriptor<TaskLabel>(sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.name)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func labels(for block: Block) -> [TaskLabel] {
        guard !block.labelIDs.isEmpty else { return [] }
        let wanted = Set(block.labelIDs)
        return allLabels().filter { wanted.contains($0.id) }
    }

    func attachments(for blockID: UUID) -> [Attachment] {
        let descriptor = FetchDescriptor<Attachment>(
            predicate: #Predicate { $0.blockID == blockID },
            sortBy: [SortDescriptor(\.sortIndex)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Bootstrap

    /// Creates the Inbox and the default sidebar section on first launch.
    func bootstrap() {
        if inboxList() == nil {
            let inbox = TaskList(title: "Inbox", icon: "📥", accent: .blue, isSystemInbox: true)
            inbox.sortIndex = -1_000_000
            context.insert(inbox)
        }

        let sections = allSections()
        if sections.isEmpty {
            let section = SidebarSection(title: "My lists", sortIndex: 0, isDefault: true)
            context.insert(section)
        }
        save()
    }

    func inboxList() -> TaskList? {
        let descriptor = FetchDescriptor<TaskList>(predicate: #Predicate { $0.isSystemInbox })
        return try? context.fetch(descriptor).first
    }

    func allSections() -> [SidebarSection] {
        let descriptor = FetchDescriptor<SidebarSection>(sortBy: [SortDescriptor(\.sortIndex)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func defaultSection() -> SidebarSection? {
        allSections().first { $0.isDefault } ?? allSections().first
    }

    // MARK: - Lists

    @discardableResult
    func createList(
        title: String = "",
        icon: String = "📋",
        accent: ListAccent = .graphite,
        in section: SidebarSection? = nil
    ) -> TaskList {
        let list = TaskList(title: title, icon: icon, accent: accent)
        let existing = allLists(includeArchived: true)
        list.sortIndex = (existing.map(\.sortIndex).max() ?? 0) + BlockTree.indexStep

        let target = section ?? defaultSection()
        list.sectionID = target?.id
        list.isPinned = target != nil
        let peers = existing.filter { $0.sectionID == target?.id }
        list.sidebarIndex = (peers.map(\.sidebarIndex).max() ?? 0) + BlockTree.indexStep

        context.insert(list)
        log(.listCreated, title: list.displayTitle, list: list)
        save()
        return list
    }

    func deleteList(_ list: TaskList) {
        guard !list.isSystemInbox else { return }
        let listID = list.id

        // Blocks are keyed by list rather than related, so remove them here.
        for block in blocks(inList: listID) {
            purgeMediaAndAttachments(for: block)
            NotificationService.shared.cancelReminder(for: block.id)
            context.delete(block)
        }
        log(.listDeleted, title: list.displayTitle, list: list)
        context.delete(list)
        save()
    }

    func duplicateList(_ list: TaskList) -> TaskList {
        let copy = TaskList(title: "\(list.displayTitle) copy", icon: list.icon, accent: list.accent)
        copy.summary = list.summary
        copy.sectionID = list.sectionID
        copy.isPinned = list.isPinned
        copy.sortingRaw = list.sortingRaw
        copy.sortIndex = list.sortIndex + 1
        copy.sidebarIndex = list.sidebarIndex + 1
        context.insert(copy)

        // Re-key the tree so parent pointers land on the new blocks.
        let originals = blocks(inList: list.id)
        var idMap: [UUID: UUID] = [:]
        for original in originals { idMap[original.id] = UUID() }

        for original in originals {
            let clone = Block(kind: original.kind, listID: copy.id)
            clone.id = idMap[original.id] ?? UUID()
            clone.parentID = original.parentID.flatMap { idMap[$0] }
            clone.sortIndex = original.sortIndex
            clone.copyPayload(from: original)

            // Give the copy its own file, or deleting either list would take
            // the shared asset out from under the other.
            if let filename = original.mediaFilename {
                clone.mediaFilename = MediaStore.shared.duplicate(filename: filename) ?? filename
            }
            context.insert(clone)

            for attachment in attachments(for: original.id) {
                guard let copiedName = MediaStore.shared.duplicate(filename: attachment.filename) else { continue }
                context.insert(
                    Attachment(
                        blockID: clone.id,
                        filename: copiedName,
                        displayName: attachment.displayName,
                        contentType: attachment.contentType,
                        byteCount: attachment.byteCount,
                        sortIndex: attachment.sortIndex
                    )
                )
            }
        }

        save()
        return copy
    }

    func setPinned(_ pinned: Bool, for list: TaskList, section: SidebarSection? = nil) {
        list.isPinned = pinned
        if pinned {
            let target = section ?? defaultSection()
            list.sectionID = target?.id
            let peers = allLists().filter { $0.sectionID == target?.id && $0.id != list.id }
            list.sidebarIndex = (peers.map(\.sidebarIndex).max() ?? 0) + BlockTree.indexStep
        } else {
            list.sectionID = nil
        }
        list.touch()
        save()
    }

    func move(list: TaskList, toSection sectionID: UUID?, above target: TaskList?) {
        list.sectionID = sectionID
        list.isPinned = sectionID != nil

        let peers = allLists()
            .filter { $0.sectionID == sectionID && $0.id != list.id }
            .sorted { $0.sidebarIndex < $1.sidebarIndex }

        if let target, let index = peers.firstIndex(where: { $0.id == target.id }) {
            let previous = index > 0 ? peers[index - 1].sidebarIndex : nil
            list.sidebarIndex = BlockTree.index(after: previous, before: peers[index].sidebarIndex)
        } else {
            list.sidebarIndex = (peers.map(\.sidebarIndex).max() ?? 0) + BlockTree.indexStep
        }

        // Repeated midpoint inserts converge, so respace when they do — the
        // same repair the block outline gets.
        let ordered = (peers + [list]).sorted { $0.sidebarIndex < $1.sidebarIndex }.map(SidebarOrdered.init)
        if BlockTree.needsRenormalisation(ordered) {
            BlockTree.renormalise(ordered)
        }

        list.touch()
        save()
    }

    // MARK: - Sections

    @discardableResult
    func createSection(title: String = "New section") -> SidebarSection {
        let sections = allSections()
        let section = SidebarSection(
            title: title,
            sortIndex: (sections.map(\.sortIndex).max() ?? 0) + BlockTree.indexStep
        )
        context.insert(section)
        save()
        return section
    }

    /// Removing a section leaves its lists intact and still in the sidebar,
    /// gathered under "Other lists" until they are filed again.
    func deleteSection(_ section: SidebarSection) {
        // The default section is the fallback every new list is filed into, so
        // it has to survive.
        guard !section.isDefault else { return }
        for list in allLists(includeArchived: true) where list.sectionID == section.id {
            list.sectionID = nil
            // Deliberately still pinned: the user removed a grouping, not the
            // lists inside it.
        }
        context.delete(section)
        save()
    }

    // MARK: - Persistence

    func save() {
        guard !isSavingSuspended else { return }
        pendingSave?.cancel()
        pendingSave = nil

        // `onDidSave` fires even when SwiftData's autosave already flushed the
        // change, because downstream caches still need to know it happened.
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                assertionFailure("Failed to save: \(error)")
                return
            }
        }
        onDidSave?()
    }

    /// Saves once the user pauses.
    ///
    /// Called from the editor on every keystroke, where saving synchronously
    /// each time would be wasteful.
    func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    // MARK: - Activity log

    func withoutLogging<T>(_ body: () throws -> T) rethrows -> T {
        isLoggingSuspended = true
        defer { isLoggingSuspended = false }
        return try body()
    }

    func log(_ kind: ActivityKind, title: String, detail: String = "", block: Block? = nil, list: TaskList? = nil) {
        guard !isLoggingSuspended else { return }
        let owningList = list ?? self.list(id: block?.listID)
        let event = ActivityEvent(
            kind: kind,
            title: title,
            detail: detail,
            blockID: block?.id,
            listID: owningList?.id,
            listTitle: owningList?.displayTitle ?? "",
            listIcon: owningList?.icon ?? ""
        )
        context.insert(event)
    }

    func recentActivity(limit: Int = 300) -> [ActivityEvent] {
        var descriptor = FetchDescriptor<ActivityEvent>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    func clearActivity() {
        for event in recentActivity(limit: 10_000) {
            context.delete(event)
        }
        save()
    }

    // MARK: - List properties

    func rename(_ list: TaskList, to title: String) {
        guard list.title != title else { return }
        list.title = title
        list.touch()
        save()
    }

    func setAppearance(icon: String? = nil, accent: ListAccent? = nil, for list: TaskList) {
        if let icon { list.icon = icon }
        if let accent { list.accent = accent }
        list.touch()
        save()
    }

    func setSummary(_ summary: String, for list: TaskList) {
        guard list.summary != summary else { return }
        list.summary = summary
        list.touch()
        save()
    }

    func setSorting(_ sorting: ListSorting, for list: TaskList) {
        list.sorting = sorting
        list.touch()
        save()
    }

    func setShowsCompleted(_ shows: Bool, for list: TaskList) {
        list.showsCompleted = shows
        list.touch()
        save()
    }

    func setArchived(_ archived: Bool, for list: TaskList) {
        list.isArchived = archived
        list.touch()
        save()
    }

    func markOpened(_ list: TaskList) {
        list.lastOpenedAt = .now
        save()
    }

    // MARK: - Section properties

    func rename(_ section: SidebarSection, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, section.title != trimmed else { return }
        section.title = trimmed
        save()
    }

    func setCollapsed(_ collapsed: Bool, for section: SidebarSection) {
        guard section.isCollapsed != collapsed else { return }
        section.isCollapsed = collapsed
        save()
    }

    // MARK: - Task note

    func setNote(_ note: String, for block: Block) {
        guard block.note != note else { return }
        let wasEmpty = block.note.isEmpty
        block.note = note
        block.touch()
        if wasEmpty, !note.isEmpty {
            log(.noteAdded, title: block.displayTitle, block: block)
        }
        save()
    }

    // MARK: - Label appearance

    func setAccent(_ accent: ListAccent, for label: TaskLabel) {
        label.accent = accent
        save()
    }
}
