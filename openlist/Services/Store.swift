//
//  Store.swift
//  openlist
//

import Foundation
import SwiftData
import SwiftUI

/// Identifies a document: a list, or the subtree under one of its tasks,
/// which behaves like a miniature list rooted at that task. The list
/// document edits a whole list; the store appends under a task too, as MCP
/// adds subtasks.
struct DocumentContext: Hashable {
    var listID: UUID
    /// `nil` for the list itself; a task id for the subtree under it.
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
/// worth recording in Activity's Changes.
@Observable
@MainActor
final class Store {
    let context: ModelContext
    @ObservationIgnored private let commitContext: (ModelContext) throws -> Void

    /// Suppresses activity logging during bulk work such as seeding samples.
    var isLoggingSuspended = false
    @ObservationIgnored var pendingActivity: [ActivityDraft] = []
    @ObservationIgnored var activitySuppressedTaskIDs: Set<UUID> = []
    @ObservationIgnored var pendingRestoredTaskIDs: Set<UUID> = []
    @ObservationIgnored var pendingCompletionCycleIDs: [UUID: UUID] = [:]
    @ObservationIgnored var pendingReopenedCycleIDs: [UUID: UUID] = [:]
    /// Failed SwiftData saves can leave inserted models in the live fetch
    /// cache even after deletion. Never publish those attempt identities, and
    /// explicitly delete them again before any subsequent commit.
    private(set) var uncommittedActivityIDs: Set<UUID> = []
    /// List document lines' own saves to their tasks, which reach saved
    /// history as one entry each once the line ends.
    @ObservationIgnored var lineHistory = EditorLineHistory()
    /// The batch of a change written in several saves; see `withActivityBatch`.
    @ObservationIgnored var activityBatch: UUID?

    /// Set by ``batch(_:)`` so a run of mutations commits once.
    var isSavingSuspended = false

    private var pendingSave: Task<Void, Never>?

    // Structural editor edits retain media deleted during the operation so
    // Undo can restore the original attachment and image contents as well.
    var isRecordingEditorEdit = false
    var editorMediaBackups: [String: Data] = [:]
    /// Structural Undo may remove the task currently open in an inspector.
    @ObservationIgnored var onEditorBlocksRemoved: ((Set<UUID>) -> Void)?
    var persistenceError: String?
    var editorNotice: String?
    /// Why the last export, Copy as Markdown, cover change, image or file
    /// failed, where a system alert said so before, or a Duplicate, move,
    /// Copy Content and Subtasks or paste. It stays, red, under the toolbar
    /// until dismissed; VoiceOver hears it as it appears.
    var actionError: String?
    /// Takes what ``refuse(_:)`` reports; the window shows it in its tray.
    @ObservationIgnored var onRefusal: ((String) -> Void)?
    /// Why the last Trash change failed. Successes report in the tray.
    var trashError: String?
    @ObservationIgnored var permanentlyErasedBlockIDs: Set<UUID> = []
    @ObservationIgnored var trashMediaRollbacks: [() -> Void] = []
    /// The latest merge, which ``undoLabelMerge(_:)`` takes back when given
    /// no plan. The window's Undo holds its own merge's plan instead.
    var labelMergeUndo: LabelMergePlan?
    var labelMaintenanceError: String?
    var labelRevision = 0
    @ObservationIgnored var mergedLabelIDs: [UUID: UUID] = [:]
    var onLabelsMerged: ((UUID, UUID) -> Void)?
    var syncPreparationError: String?
    /// Set by the calendar coordinator from this Mac's preferences.
    var calendarDefaultEstimateMinutes: Int = 30
    /// Identifies this Mac when closing imported open sessions conservatively.
    var calendarDeviceID: String?
    /// The live coordinator applies the same approved and fixed-time boundary
    /// when a checkbox, parent completion, deferral, or deletion closes work.
    @ObservationIgnored var calendarRecordingEndpoint: ((WorkSession, Date) -> Date)?
    /// The displayed generated plan is captured before a completion removes it.
    @ObservationIgnored var calendarPlannedBlocks: [PlannedBlock] = []
    var completionUndo: CompletionUndoAction?
    @ObservationIgnored var completionUndoChanges: [UUID: CompletionUndoChange] = [:]
    @ObservationIgnored var pendingCompletionUndoChanges: [CompletionUndoChange] = []
    @ObservationIgnored var completionUndoRegistrations: [UUID: CompletionUndoRegistration] = [:]
    var onCompletionUndoAvailable: ((CompletionUndoAction) -> Void)?
    /// Smart rows commit local title drafts on blur. External writes must not
    /// overwrite those drafts or be overwritten by their later commit.
    @ObservationIgnored var activeTitleDrafts: [UUID: UUID] = [:]

    /// Called after every successful save, so downstream caches — currently the
    /// widget snapshot — can refresh themselves.
    var onDidSave: (() -> Void)?

    init(context: ModelContext, commitContext: @escaping (ModelContext) throws -> Void = { try $0.save() }) {
        self.context = context
        self.commitContext = commitContext
        // Task changes and their activity must commit together. Independent
        // autosave could otherwise write the task before its history exists.
        context.autosaveEnabled = false
    }

    // MARK: - Fetching

    func list(id: UUID?) -> TaskList? {
        var nextID = id
        var visited: Set<UUID> = []
        while let id = nextID {
            guard visited.insert(id).inserted else {
                persistenceError = "An Inbox sync reference could not be resolved."
                return nil
            }
            let descriptor = FetchDescriptor<TaskList>(predicate: #Predicate { $0.id == id })
            guard let list = try? context.fetch(descriptor).first else { return nil }
            guard !list.isTrashed else { return nil }
            guard let mergedIntoID = list.mergedIntoID else { return list.isEffectivelyTrashed ? nil : list }
            nextID = mergedIntoID
        }
        return nil
    }

    func block(id: UUID?) -> Block? {
        guard let id else { return nil }
        let descriptor = FetchDescriptor<Block>(predicate: #Predicate { $0.id == id && $0.trashID == nil })
        guard let block = try? context.fetch(descriptor).first else { return nil }
        if let listID = block.listID, list(id: listID) == nil { return nil }
        return block
    }

    func allLists(includeArchived: Bool = false) -> [TaskList] {
        let descriptor = FetchDescriptor<TaskList>(sortBy: [SortDescriptor(\.sortIndex)])
        let lists = (try? context.fetch(descriptor)) ?? []
        let hierarchy = ListHierarchy(lists)
        return lists.filter { includeArchived ? hierarchy.availableIDs.contains($0.id) : hierarchy.activeIDs.contains($0.id) }
    }

    func listHierarchy() -> ListHierarchy {
        ListHierarchy((try? context.fetch(FetchDescriptor<TaskList>())) ?? [])
    }

    @discardableResult
    func createChildList(in parent: TaskList) -> TaskList? {
        guard listHierarchy().activeIDs.contains(parent.id), !parent.isSystemInbox else { return nil }
        do { try persistChanges() } catch { persistenceError = error.localizedDescription; return nil }
        let child = TaskList()
        child.parentListID = parent.id
        child.sortIndex = (allLists(includeArchived: true).map(\.sortIndex).max() ?? 0) + BlockTree.indexStep
        context.insert(child)
        log(.listCreated, title: child.displayTitle, list: child)
        do { try persistChanges(); return child }
        catch {
            context.rollback()
            pendingActivity.removeAll()
            if child.modelContext != nil { context.delete(child) }
            context.processPendingChanges()
            persistenceError = "The child list could not be created. \(error.localizedDescription)"
            return nil
        }
    }

    @discardableResult
    func moveList(_ list: TaskList, under parentID: UUID?) -> Bool {
        guard listHierarchy().canMove(list.id, under: parentID) else {
            editorNotice = "Choose an available parent outside this list's own descendants."
            return false
        }
        do { try persistChanges() } catch { persistenceError = error.localizedDescription; return false }
        let previous = list.parentListID, updated = list.updatedAt
        list.parentListID = parentID
        list.touch()
        do {
            try persistChanges()
            refreshAllReminders()
            return true
        } catch {
            context.rollback()
            list.parentListID = previous
            list.updatedAt = updated
            persistenceError = "The list could not be moved. \(error.localizedDescription)"
            return false
        }
    }

    func blocks(inList listID: UUID) -> [Block] {
        guard list(id: listID) != nil else { return [] }
        let listID = resolvedListID(listID) ?? listID
        let descriptor = FetchDescriptor<Block>(
            predicate: #Predicate { $0.trashID == nil && $0.listID == listID },
            sortBy: [SortDescriptor(\.sortIndex)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func children(of parentID: UUID?, listID: UUID) -> [Block] {
        BlockTree.children(of: parentID, in: blocks(inList: listID))
    }

    func allLabels() -> [TaskLabel] {
        _ = labelRevision // Refresh open pickers when a label identity disappears.
        let descriptor = FetchDescriptor<TaskLabel>(sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.name)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func labels(for block: Block) -> [TaskLabel] {
        guard block.modelContext != nil, !block.isDeleted else { return [] }
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

    /// Takes a file off its task as one Undo step on `undoManager`, named
    /// `name`: Undo puts the file back, its bytes and all, and Redo takes it
    /// off again. `didRegister` runs once the step is on the stack. With no
    /// undo manager, or no live task to hold it, the file just goes.
    func removeAttachment(_ attachment: Attachment, name: String, undoManager: UndoManager?,
                          didRegister: (() -> Void)? = nil) {
        guard attachment.modelContext != nil, !attachment.isDeleted else { return }
        let remove = {
            // Inside the edit, the file's bytes are kept for Undo before the cache lets it go.
            self.removeEditorMedia(filename: attachment.filename)
            self.context.delete(attachment)
            self.save()
        }
        guard let owner = block(id: attachment.blockID), let listID = owner.listID else { return remove() }
        undoableEditorEdit(in: listID, name: name, undoManager: undoManager, didRegister: didRegister, remove)
    }

    // MARK: - Bootstrap

    /// Creates the Inbox and the default sidebar section on first launch.
    func bootstrap() {
        do {
            let inboxes = try context.fetch(FetchDescriptor<TaskList>(predicate: #Predicate { $0.isSystemInbox }))
            if inboxes.isEmpty {
                let inbox = TaskList(title: "Inbox", icon: "📥", accent: .blue, isSystemInbox: true)
                inbox.sortIndex = -1_000_000
                context.insert(inbox)
            }
            let defaults = try context.fetch(FetchDescriptor<SidebarSection>(predicate: #Predicate { $0.isDefault }))
            if defaults.isEmpty {
                context.insert(SidebarSection(title: "My lists", sortIndex: 0, isDefault: true))
            }
            try reconcileSystemRecords()
            guard reconcileRetainedListDescendants() else { throw TrashError.invalidRetention }
            rewordRecoveredItemsSummaries()
            save()
        } catch {
            persistenceError = "The Inbox could not be opened. \(error.localizedDescription)"
        }
    }

    func inboxList() -> TaskList? {
        let descriptor = FetchDescriptor<TaskList>(predicate: #Predicate { $0.isSystemInbox && $0.mergedIntoID == nil })
        return try? context.fetch(descriptor).first
    }

    func allSections() -> [SidebarSection] {
        let descriptor = FetchDescriptor<SidebarSection>(
            predicate: #Predicate { $0.mergedIntoID == nil },
            sortBy: [SortDescriptor(\.sortIndex)]
        )
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
        list.sectionID = resolvedSectionID(target?.id)
        list.isPinned = target != nil
        let peers = existing.filter { $0.sectionID == list.sectionID }
        list.sidebarIndex = (peers.map(\.sidebarIndex).max() ?? 0) + BlockTree.indexStep

        context.insert(list)
        log(.listCreated, title: list.displayTitle, list: list)
        save()
        return list
    }

    func duplicateList(_ list: TaskList) -> TaskList {
        do {
            let id = try copyList(list, mode: .duplicate)
            return self.list(id: id) ?? list
        } catch {
            actionError = "The list was not duplicated because its content or a file could not be copied. \(error.localizedDescription)"
            return list
        }
    }

    func setPinned(_ pinned: Bool, for list: TaskList, section: SidebarSection? = nil) {
        let list = self.list(id: list.id) ?? list
        list.isPinned = pinned
        if pinned {
            let target = section ?? defaultSection()
            list.sectionID = resolvedSectionID(target?.id)
            let peers = allLists().filter { $0.sectionID == list.sectionID && $0.id != list.id }
            list.sidebarIndex = (peers.map(\.sidebarIndex).max() ?? 0) + BlockTree.indexStep
        } else {
            list.sectionID = nil
        }
        list.touch()
        save()
    }

    func move(list: TaskList, toSection sectionID: UUID?, above target: TaskList?) {
        let list = self.list(id: list.id) ?? list
        let sectionID = resolvedSectionID(sectionID)
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

    /// A one-off refusal that changed nothing, like a drop the list's rules
    /// don't allow: it passes, as the design's tray does, rather than staying
    /// pinned like an error. With no window to show it, it waits in `editorNotice`.
    func refuse(_ message: String) {
        if let onRefusal { onRefusal(message) } else { editorNotice = message }
    }

    // MARK: - Persistence

    func save() {
        guard !isSavingSuspended else { return }
        do {
            try persistChanges()
        } catch {
            persistenceError = "Your latest changes could not be saved. \(error.localizedDescription)"
        }
    }

    /// External callers must acknowledge a write only after it reaches disk.
    /// Unlike `save()`, this propagates failures so an MCP mutation can roll back.
    func persistChanges() throws {
        pendingSave?.cancel()
        pendingSave = nil

        if !uncommittedActivityIDs.isEmpty {
            let ids = Array(uncommittedActivityIDs)
            for event in try context.fetch(FetchDescriptor<ActivityEvent>(predicate: #Predicate { ids.contains($0.id) })) {
                context.delete(event)
            }
        }
        if context.hasChanges || !pendingActivity.isEmpty || lineHistory.hasEnded {
            context.processPendingChanges()
            let staged = try stagedTaskActivity() + stagedLegacyActivity()
            // One save is one change, a task each: Changes shows its history
            // as the one row the log gives it.
            let batch = activityBatch ?? UUID()
            for event in staged { event.batchID = batch }
            // After staging, which holds what the lines saved last.
            let events = staged + endedLineActivity()
            for event in events { context.insert(event) }
            do {
                try commitContext(context)
            } catch {
                // Keep the user's edits retryable. A failed attempt is never
                // a published fact, even if SwiftData returns its stale model.
                uncommittedActivityIDs.formUnion(events.map(\.id))
                for event in events { context.delete(event) }
                context.processPendingChanges()
                throw error
            }
        }
        // Successful cleanup usually removes the failed insertion from the
        // cache as well. Keep only IDs SwiftData still returns; a refresh
        // failure must not turn an already committed write into a save error.
        if !uncommittedActivityIDs.isEmpty {
            let ids = Array(uncommittedActivityIDs)
            if let remaining = try? context.fetch(FetchDescriptor<ActivityEvent>(predicate: #Predicate { ids.contains($0.id) })) {
                uncommittedActivityIDs.formIntersection(remaining.map(\.id))
            }
        }
        pendingActivity.removeAll()
        lineHistory.didSave()
        activitySuppressedTaskIDs.removeAll()
        pendingRestoredTaskIDs.removeAll()
        pendingCompletionCycleIDs.removeAll()
        pendingReopenedCycleIDs.removeAll()
        persistenceError = nil
        refreshAllReminders()
        onDidSave?()
        publishPendingCompletionUndo()
    }

    /// Saves once the user pauses.
    ///
    /// Called from the editor on every keystroke, where saving synchronously
    /// each time would be wasteful.
    func scheduleSave(after delay: Duration = .milliseconds(400)) {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    // MARK: - Activity log

    func withoutLogging<T>(_ body: () throws -> T) rethrows -> T {
        let previous = isLoggingSuspended
        isLoggingSuspended = true
        defer {
            activitySuppressedTaskIDs.formUnion((context.insertedModelsArray + context.changedModelsArray)
                .compactMap { $0 as? Block }.map(\.id))
            isLoggingSuspended = previous
        }
        return try body()
    }

    func log(_ kind: ActivityKind, title: String, detail: String = "", block: Block? = nil, list: TaskList? = nil) {
        guard !isLoggingSuspended else { return }
        // Tracked task changes are derived from the actual committed before
        // and after states, including callers that write several fields.
        if block?.isTask == true, [.created, .completed, .reopened, .scheduled, .unscheduled, .moved, .deleted].contains(kind) {
            return
        }
        let owningList = list ?? self.list(id: block?.listID)
        pendingActivity.append(ActivityDraft(
            kind: kind,
            title: title,
            detail: detail,
            blockID: block?.id,
            listID: owningList?.id,
            listTitle: owningList?.displayTitle ?? "",
            listIcon: owningList?.icon ?? ""
        ))
    }

    /// The newest saved history, optionally only from `start` on or from
    /// before `end`, and past the first `offset` of it.
    func recentActivity(limit: Int = 300, since start: Date = .distantPast, before end: Date = .distantFuture,
                        offset: Int = 0) -> [ActivityEvent] {
        let excluded = Array(uncommittedActivityIDs)
        var descriptor = FetchDescriptor<ActivityEvent>(predicate: #Predicate {
            $0.timestamp >= start && $0.timestamp < end && !excluded.contains($0.id)
        }, sortBy: [SortDescriptor(\.timestamp, order: .reverse), SortDescriptor(\.id)])
        descriptor.fetchLimit = limit
        descriptor.fetchOffset = offset
        return (try? context.fetch(descriptor)) ?? []
    }

    func clearActivity() {
        do {
            try persistChanges()
            let events = try context.fetch(FetchDescriptor<ActivityEvent>())
            let writer = ModelContext(context.container)
            writer.autosaveEnabled = false
            for event in try writer.fetch(FetchDescriptor<ActivityEvent>()) { writer.delete(event) }
            try writer.save()
            // Publish the committed deletion to existing queries. Failure in
            // the writer never changes the live event collection.
            for event in events { context.delete(event) }
            context.rollback()
            context.processPendingChanges()
            _ = try? context.fetch(FetchDescriptor<ActivityEvent>())
            persistenceError = nil
            onDidSave?()
        } catch {
            persistenceError = "Activity history could not be cleared. \(error.localizedDescription)"
        }
    }

    // MARK: - List properties

    func rename(_ list: TaskList, to title: String) {
        let list = self.list(id: list.id) ?? list
        guard list.title != title else { return }
        list.title = title
        list.touch()
        save()
    }

    func setAppearance(icon: String? = nil, accent: ListAccent? = nil, for list: TaskList) {
        let list = self.list(id: list.id) ?? list
        if let icon { list.icon = icon }
        if let accent { list.accent = accent }
        list.touch()
        save()
    }

    func setSummary(_ summary: String, for list: TaskList) {
        let list = self.list(id: list.id) ?? list
        guard list.summary != summary else { return }
        list.summary = summary
        list.touch()
        save()
    }

    func setSorting(_ sorting: ListSorting, for list: TaskList) {
        let list = self.list(id: list.id) ?? list
        list.sorting = sorting
        list.touch()
        save()
    }

    func setCompletedVisibility(_ visibility: TaskList.CompletedVisibility, for list: TaskList) {
        let list = self.list(id: list.id) ?? list
        list.completedVisibility = visibility
        list.touch()
        save()
    }

    func setArchived(_ archived: Bool, for list: TaskList) {
        let list = self.list(id: list.id) ?? list
        guard !list.isSystemInbox else { return }
        list.isArchived = archived
        list.touch()
        refreshAllReminders()
        save()
    }

    func markOpened(_ list: TaskList) {
        let list = self.list(id: list.id) ?? list
        list.lastOpenedAt = .now
        save()
    }

    // MARK: - Section properties

    func rename(_ section: SidebarSection, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, section.title != trimmed else { return }
        let section = resolvedSection(section)
        section.title = trimmed
        save()
    }

    func setCollapsed(_ collapsed: Bool, for section: SidebarSection) {
        let section = resolvedSection(section)
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
