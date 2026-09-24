//
//  Workbench.swift
//  openlist
//

import AppKit
import Foundation
import SwiftUI

/// The tint a tray message and change-log entry use.
enum TrayTone: Equatable {
    case neutral, accent, green, red, amber
}

/// A route the tray's secondary button jumps to.
struct TrayDestination: Equatable {
    var label: String
    var route: AppRoute
}

/// The single feedback surface: one line, optional Undo, optional jump.
struct TrayMessage: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var icon: String
    var tone: TrayTone
    var undoable: Bool
    var destination: TrayDestination?
}

/// One row of the session's change log shown under Activity › Changes.
struct ChangeEntry: Identifiable, Equatable {
    let id = UUID()
    var taskID: UUID?
    var label: String
    var icon: String
    var tone: TrayTone
    var at: Date
    /// Entries created by one action share a batch; Undo removes the batch.
    var batch: Int
}

/// Where a triaged card leaves the stack.
enum TriageExit: Equatable {
    case left, up, right, done, down
}

/// Interaction state for the Next interface.
///
/// Models live in SwiftData; this holds only what the design animates or
/// remembers for a session: keyboard focus, the selection, rows mid-completion,
/// flashes after an edit, the tray and the change log.
@Observable @MainActor
final class Workbench {
    @ObservationIgnored let store: Store
    @ObservationIgnored let navigator: Navigator
    @ObservationIgnored let settings: AppSettings
    @ObservationIgnored let calendar: CalendarCoordinator

    // MARK: Focus & selection

    var focusID: UUID? {
        // A row taking the focus ends what Escape left in the list document.
        didSet { if focusID != nil { document?.forgetEscape() } }
    }
    var selection: Set<UUID> = []
    /// Row order on screen, published by the visible screen for J/K and ⌘A.
    @ObservationIgnored var visibleIDs: [UUID] = [] {
        didSet {
            visibleRoute = navigator.route
            // A row that leaves the screen leaves the selection, so the
            // selection bar never counts rows its buttons can't reach.
            if !selection.isEmpty, !selection.isSubset(of: visibleIDs) { selection.formIntersection(visibleIDs) }
        }
    }

    // MARK: Row feedback

    /// Rows that were just ticked: `false` while the check pops, `true` once struck.
    var closing: [UUID: Bool] = [:]
    var flying: Set<UUID> = []
    var fresh: Set<UUID> = []
    var restored: Set<UUID> = []
    var freshChip: Set<UUID> = []
    var pulseTaskID: UUID?
    var pulseListID: UUID?
    var pulseRevision = 0
    var freshBlockTaskID: UUID?

    // MARK: Tray & log

    var tray: TrayMessage?
    private(set) var log: [ChangeEntry] = []
    /// When this session began. Changes counts saved history from then on as
    /// this session's.
    let startedAt = Date.now
    /// Each moment the log's changes were written, undone or redone, in time
    /// order, with the tasks and lists they covered.
    @ObservationIgnored private var logWrites: [(at: Date, ids: Set<UUID>)] = []
    /// Bumped whenever the undo stack may have changed so labels re-read it.
    private(set) var undoRevision = 0

    // MARK: Inbox triage

    var kept: Set<UUID> = []
    var reviewed = 0
    var triageExit: TriageExit?

    // MARK: Screens

    var collapsedGroups: Set<String> = []
    var calendarDays = 7
    /// A day the Calendar shows its range from instead of today: stepped to,
    /// or where Plan put a task. Nil follows today.
    var calendarAnchor: Date?
    var tasksStatus: TasksStatusFilter = .open
    var tasksGrouping: TasksGroupingMode = .list
    var tasksQuery = ""
    /// Sentence mode: the lists picked in "in [all lists▾]" and the title filter.
    var tasksListFilter: Set<UUID> = []
    var tasksTitleFilter = ""
    /// Whether the query field on Tasks has keyboard focus (drives its popover).
    var tasksQueryFocused = false
    /// The sentence-bar menu open on Tasks, if any; Esc closes it first.
    var tasksMenu: NXTasksMenu?
    var captureOpen = false
    var captureText = ""
    var captureListID: UUID?
    var captureForToday = false
    /// The label screen capture opened on; the new task gets that label.
    var captureLabelID: UUID?
    var paletteQuery = ""
    var paletteIndex = 0
    var searchQuery = ""
    var searchIndex = 0
    var searchIncludesCompleted = false
    var activityDay: Date?

    // MARK: List document

    /// The list document on show, for the keys and Undo that reach it from
    /// outside its rows.
    @ObservationIgnored weak var document: OutlineEditor?
    /// The lists in sidebar order as the window last drew them, for Task ▸
    /// Move to, which would otherwise fetch them on every menu update.
    @ObservationIgnored var drawnLists: [TaskList] = []
    /// Tasks whose note shows under them in the list document, remembered on
    /// this Mac.
    var openNotes: Set<UUID> = [] {
        didSet { if openNotes != oldValue { defaults?.set(openNotes.map(\.uuidString), forKey: Self.openNotesKey) } }
    }
    /// The task whose note is being written in place.
    var editingNoteID: UUID? {
        didSet { if editingNoteID != nil, editingNoteID != oldValue { noteEditRequestedAt = .now } }
    }
    /// When a note was last asked to take the keyboard, which it does a
    /// moment later, for the keys typed in between.
    @ObservationIgnored private(set) var noteEditRequestedAt: Date?
    /// The task the inspector's Add subtask is for, until its list's document
    /// is on show to write the new line.
    @ObservationIgnored var pendingSubtaskParentID: UUID? {
        didSet { if pendingSubtaskParentID != nil { subtaskRequestedAt = .now } }
    }
    /// When Add subtask last went to open the task's list, for the keys
    /// typed before the new line shows.
    @ObservationIgnored private(set) var subtaskRequestedAt: Date?
    /// A list just made, whose title takes the keyboard once its page shows.
    @ObservationIgnored var namingListID: UUID?
    @ObservationIgnored private let defaults: UserDefaults?
    private static let openNotesKey = "nextOpenNotes"

    /// The inspector's Add subtask, as the design's: goes to the task's list
    /// document, opening it if needed, where the task unfolds and a new
    /// subtask line at the end of its subtasks takes the caret.
    func addSubtask(to id: UUID) {
        guard let task = store.block(id: id), task.isTask, let list = store.list(id: task.listID) else { return }
        document?.commitLine()
        if let document, document.document.listID == list.id {
            document.appendSubtask(to: id)
            return
        }
        pendingSubtaskParentID = id
        go(route(for: list))
    }

    /// Space, or a task's note button: shows or hides its note under it. A
    /// task with no note starts one instead.
    func toggleNote(_ id: UUID) {
        guard let task = store.block(id: id), task.isTask else { return }
        if !openNotes.contains(id), task.note.isEmpty {
            editNote(id)
            return
        }
        withAnimation(style.ease(180)) {
            if openNotes.contains(id) { openNotes.remove(id) } else { openNotes.insert(id) }
        }
    }

    /// Opens a task's note for writing in place, as ⇧↩ does from its title.
    func editNote(_ id: UUID) {
        openNotes.insert(id)
        editingNoteID = id
        focusID = id
        clearSelection()
    }

    /// View ▸ Hide Sidebar. The shell also folds the sidebar away while a
    /// narrow window shows the inspector; either one hides it.
    var isSidebarHidden = false
    var isSidebarFoldedForRoom = false
    var showsSidebar: Bool { !isSidebarHidden && !isSidebarFoldedForRoom }

    func toggleSidebar() {
        withAnimation(style.ease(280)) {
            if showsSidebar {
                isSidebarHidden = true
            } else {
                isSidebarHidden = false
                isSidebarFoldedForRoom = false
            }
        }
    }

    /// The running task, calendar notice, extension, conflict and reschedule the work watch last saw.
    @ObservationIgnored var workWatch: (taskID: UUID?, notice: String?, grant: CalendarWorkExtension?,
                                        conflict: CalendarWorkConflict?, moved: UUID?) = (nil, nil, nil, nil, nil)
    /// Undo entries about the running work, which the work watch takes off the
    /// stack once they no longer apply.
    @ObservationIgnored var workUndos: [WorkUndo] = []
    /// Why the calendar paused work by itself, told again when you come back to
    /// the Mac. `returnedAt` is the first return it was shown for.
    @ObservationIgnored var awayPause: (taskID: UUID, text: String, returnedAt: Date?)?
    /// Until the calendar's first notice: work paused when Openlist last quit
    /// comes back with one.
    @ObservationIgnored var awaitsLaunchNotice = true

    @ObservationIgnored var gPressedAt: Date?
    /// Names the Store's completion Undo after the design action that caused it.
    @ObservationIgnored var completionLabel: String?
    /// Where the Store's completion Undo goes while a completion batch writes;
    /// nil sends it to the window.
    @ObservationIgnored private(set) var completionUndoTarget: UndoManager?
    @ObservationIgnored weak var undoManager: UndoManager? {
        didSet { if oldValue !== undoManager { observeUndo() } }
    }
    @ObservationIgnored private var batchCounter = 0
    /// The newest batch Clear all activity history took out of the log.
    @ObservationIgnored private var clearedBatch = 0
    /// Completions still in their dwell, oldest first.
    @ObservationIgnored private var completions: [CompletionBatch] = []
    /// Trashes whose rows are still flying out.
    @ObservationIgnored private var trashes: [TrashBatch] = []
    /// Every change whose window entry only moves tasks into or out of Trash,
    /// by its log mark; each entry keeps its mark alive.
    @ObservationIgnored private let trashUndos = NSHashTable<LogMark>.weakObjects()
    /// The pop and strike of each row in the dwell.
    @ObservationIgnored private var closingTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var flashTasks: [String: Task<Void, Never>] = [:]
    /// Ids each flash key still has to clear when its timer fires.
    @ObservationIgnored private var flashPending: [String: Set<UUID>] = [:]
    @ObservationIgnored private var trayTask: Task<Void, Never>?
    @ObservationIgnored private var undoObservers: [NSObjectProtocol] = []
    /// The route the last navigation reset ran for.
    @ObservationIgnored private var shownRoute: AppRoute?
    /// The route `visibleIDs` was published on.
    @ObservationIgnored private var visibleRoute: AppRoute?

    init(store: Store, navigator: Navigator, settings: AppSettings, calendar: CalendarCoordinator,
         defaults: UserDefaults? = nil) {
        self.store = store
        self.navigator = navigator
        self.settings = settings
        self.calendar = calendar
        self.defaults = defaults
        openNotes = Set((defaults?.stringArray(forKey: Self.openNotesKey) ?? []).compactMap(UUID.init(uuidString:)))
        watchWork()
        calendar.onMacReturn = { [weak self] in self?.macDidReturn() }
    }

    // MARK: Style

    var style: NextStyle {
        let reduced = settings.reducesMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        return NextStyle(
            accent: settings.accent.color,
            motion: reduced ? 0.4 : settings.motion.scale,
            lively: !reduced && settings.motion != .restrained,
            slides: !reduced,
            dwell: Double(settings.undoDwellSeconds),
            compact: settings.density == .compact,
            serifTitles: settings.serifTitles
        )
    }

    func ms(_ base: Double) -> Double { style.ms(base) }

    /// Minutes planned for a task without its own estimate.
    var defaultEstimate: Int { max(5, Int(calendar.preferences.defaultEstimateMinutes)) }

    // MARK: Targets

    /// The selected rows the current screen shows, in screen order: what the
    /// selection bar counts and acts on.
    var selectedVisibleIDs: [UUID] { visibleIDs.filter(selection.contains) }

    /// Selection, else keyboard focus, else the inspected task. Selected rows
    /// the current screen doesn't show are never targets, and while anything
    /// is selected nothing else is either.
    var targetIDs: [UUID] {
        if !selection.isEmpty { return selectedVisibleIDs }
        if let focusID { return [focusID] }
        if let openID = navigator.openTaskID { return [openID] }
        return []
    }

    var targetTasks: [Block] { targetIDs.compactMap { store.block(id: $0) }.filter(\.isTask) }

    func tasks(_ ids: [UUID]) -> [Block] { ids.compactMap { store.block(id: $0) }.filter(\.isTask) }

    // MARK: Navigation

    func go(_ route: AppRoute) {
        navigator.isCommandPaletteOpen = false
        navigator.isSearchOpen = false
        guard navigator.route != route else {
            focusID = nil
            clearSelection()
            return
        }
        navigator.go(to: route)
        routeDidChange()
    }

    /// Resets what belongs to the screen being left. Runs for every route
    /// change — Back/Forward, reveals and deletions as well as `go` — once per route.
    /// The inspector belongs to the window, so it stays open on the new screen
    /// as long as its task is still there.
    func routeDidChange() {
        guard shownRoute != navigator.route else { return }
        shownRoute = navigator.route
        focusID = nil
        selection = []
        // The new screen may already have published its rows.
        if visibleRoute != navigator.route { visibleIDs = [] }
        tasksQueryFocused = false
        gPressedAt = nil
        navigator.isCommandPaletteOpen = false
        navigator.isSearchOpen = false
        if let openID = navigator.openTaskID,
           !(store.block(id: openID).map { $0.isTask && $0.trashID == nil } ?? false) {
            navigator.closeTask()
        }
    }

    func inspect(_ id: UUID?) {
        guard let id else { navigator.closeTask(); return }
        focusID = id
        navigator.openTask(id)
    }

    // MARK: Focus movement

    func moveFocus(by delta: Int, extending: Bool) {
        guard !visibleIDs.isEmpty else { return }
        let current = focusID.flatMap { visibleIDs.firstIndex(of: $0) }
        var next = current.map { min(max($0 + delta, 0), visibleIDs.count - 1) } ?? (delta > 0 ? 0 : visibleIDs.count - 1)
        // From a list document line left with Escape that isn't a task, J
        // and K go to the task beside it, or below the document to the rows
        // after it.
        if current == nil, focusID == nil, let document, let line = document.escapedBlockID, document.shows(line) {
            if let id = document.task(beside: line, forward: delta > 0), let index = visibleIDs.firstIndex(of: id) {
                next = index
            } else if delta > 0, let index = visibleIDs.firstIndex(where: { !document.shows($0) }) {
                next = index
            } else {
                return
            }
        }
        let id = visibleIDs[next]
        if extending {
            withAnimation(style.ease(180)) {
                if let focusID { selection.insert(focusID) }
                selection.insert(id)
            }
        }
        focusID = id
        if navigator.openTaskID != nil { navigator.openTask(id) }
    }

    /// As the design's toggleSel, the focus stays where it is: a ⌘-clicked
    /// row takes the selected tint, not the focused card, and one clicked
    /// off again leaves the keys nothing of its own to act on.
    func toggleSelection(_ id: UUID) {
        withAnimation(style.ease(180)) {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        }
    }

    func selectAllVisible() {
        withAnimation(style.ease(180)) { selection = Set(visibleIDs) }
    }

    /// Like every selection change here, clearing animates, so the rows'
    /// marks and tint ease out rather than snap.
    func clearSelection() {
        guard !selection.isEmpty else { return }
        withAnimation(style.ease(180)) { selection = [] }
    }

    /// A plain click: focus, and follow along if the inspector is open.
    func click(_ id: UUID, command: Bool, shift: Bool) {
        if closing[id] != nil { cancelClosing([id]); return }
        if command || shift {
            toggleSelection(id)
            return
        }
        clearSelection()
        focusID = id
        if navigator.openTaskID != nil { navigator.openTask(id) }
    }

    // MARK: Tray

    func showTray(_ text: String, icon: String, tone: TrayTone = .neutral, undoable: Bool = false,
                  destination: TrayDestination? = nil) {
        let message = TrayMessage(text: text, icon: icon, tone: tone, undoable: undoable, destination: destination)
        withAnimation(style.spring(320)) { tray = message }
        trayTask?.cancel()
        let delay = style.dwell + 0.3
        trayTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, self.tray?.id == message.id else { return }
            withAnimation(self.style.ease(220)) { self.tray = nil }
        }
    }

    func dismissTray() {
        trayTask?.cancel()
        withAnimation(style.ease(200)) { tray = nil }
    }

    // MARK: Change log

    /// Records a change in the log and announces it in the tray. An undoable
    /// change ties its log batch to the Undo entry the caller just registered.
    /// An `owner` shares the Undo entry's target, so the whole entry leaves the
    /// stack with `removeAllActions(withTarget:)`.
    func snap(_ label: String, icon: String, tone: TrayTone, ids: [UUID], undoable: Bool = true,
              destination: TrayDestination? = nil, owner: AnyObject? = nil) {
        let mark = record(label, icon: icon, tone: tone, ids: ids)
        mark.owner = owner
        if undoable { attach(mark, restores: false) }
        showTray(label, icon: icon, tone: tone, undoable: undoable, destination: destination)
    }

    /// Logs an edit the list document has just put on the undo stack, in the
    /// same step, so it shows in Changes and names the toolbar's Undo. As in
    /// the design, an edit shows no tray.
    func logEdit(_ label: String, ids: [UUID]) {
        attach(record(label, icon: "pencil", tone: .neutral, ids: ids), restores: false)
    }

    var latestBatch: Int? { log.first?.batch }

    func entries(for taskID: UUID) -> [ChangeEntry] { log.filter { $0.taskID == taskID } }

    /// Settings' Clear all activity history: the saved history, then, once it's
    /// gone, the log, so Changes and each task's Activity start over. The undo
    /// stack keeps its steps; redoing one from before the clear logs it anew.
    func clearActivityHistory() {
        store.clearActivity()
        guard store.persistenceError == nil else { return }
        log.removeAll()
        clearedBatch = batchCounter
        undoRevision += 1
    }

    private func record(_ label: String, icon: String, tone: TrayTone, ids: [UUID]) -> LogMark {
        batchCounter += 1
        let now = Date.now
        let entries = (ids.isEmpty ? [nil] : ids.map(Optional.some)).map {
            ChangeEntry(taskID: $0, label: label, icon: icon, tone: tone, at: now, batch: batchCounter)
        }
        insert(entries)
        let mark = LogMark(batch: batchCounter, label: label, entries: entries, covers: covered(ids))
        noteLogWrite(mark)
        undoRevision += 1
        return mark
    }

    /// `ids` with everything their change writes history for too: each task's
    /// subtasks and child blocks, and each list's nested lists.
    private func covered(_ ids: [UUID]) -> Set<UUID> {
        var covered = Set(ids)
        let blocks = ids.compactMap { store.block(id: $0) }
        for listID in Set(blocks.compactMap(\.listID)) {
            let index = BlockTree.childIndex(of: store.blocks(inList: listID))
            for block in blocks where block.listID == listID {
                covered.formUnion(BlockTree.descendants(of: block.id, using: index).map(\.id))
            }
        }
        let listIDs = Set(ids).subtracting(blocks.map(\.id))
        if !listIDs.isEmpty {
            let hierarchy = store.listHierarchy()
            for id in listIDs { covered.formUnion(hierarchy.subtree(of: id).map(\.id)) }
        }
        return covered
    }

    private func noteLogWrite(_ mark: LogMark) {
        logWrites.append((.now, mark.covers))
        if logWrites.count > 1000 { logWrites.removeFirst(logWrites.count - 1000) }
    }

    /// Whether saved history from `date` about a task or list came from one of
    /// the log's own writes — a change, its Undo or Redo — so it's already in
    /// the log or was taken back. A write accounts for what it covered, saved
    /// from 2 s before it to 3 s after; one that covered nothing, for all of it.
    func logWrote(at date: Date, about ids: [UUID?]) -> Bool {
        let from = date.addingTimeInterval(-3), to = date.addingTimeInterval(2)
        // Writes are in time order; start at the first one late enough.
        var low = 0, high = logWrites.count
        while low < high {
            let mid = (low + high) / 2
            if logWrites[mid].at < from { low = mid + 1 } else { high = mid }
        }
        return logWrites[low...].prefix { $0.at <= to }.contains { write in
            write.ids.isEmpty || ids.contains { $0.map(write.ids.contains) == true }
        }
    }

    /// Puts entries back in batch order, so Redo returns a batch to where it was.
    private func insert(_ entries: [ChangeEntry]) {
        guard let batch = entries.first?.batch else { return }
        log.insert(contentsOf: entries, at: log.firstIndex { $0.batch < batch } ?? log.endIndex)
        if log.count > 400 { log.removeLast(log.count - 400) }
    }

    /// Registers the log half of an Undo entry, in the same group as the change
    /// itself. However that entry is undone — ⌘Z, the tray, Edit › Undo — this
    /// takes exactly its batch out of the log, and Redo puts it back.
    private func attach(_ mark: LogMark, restores: Bool) {
        guard let undoManager else { return }
        // The manager holds its target weakly; the handler keeps the mark alive.
        undoManager.registerUndo(withTarget: mark.owner ?? mark) { [weak self, mark] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if restores { self.relog(mark) } else { self.unlog(mark) }
                self.attach(mark, restores: !restores)
            }
        }
        undoManager.setActionName(mark.label)
    }

    private func unlog(_ mark: LogMark) {
        log.removeAll { $0.batch == mark.batch }
        noteLogWrite(mark)
        markRestored(mark.entries.compactMap(\.taskID))
        showTray("Undid — \(mark.label)", icon: "arrow.uturn.backward", tone: .neutral)
        undoRevision += 1
    }

    private func relog(_ mark: LogMark) {
        // A batch the clear took out doesn't come back with its old time: the
        // Redo writes it now, so it's logged now, as the newest batch.
        if mark.batch <= clearedBatch {
            batchCounter += 1
            mark.batch = batchCounter
            let now = Date.now
            for index in mark.entries.indices {
                mark.entries[index].batch = batchCounter
                mark.entries[index].at = now
            }
        }
        insert(mark.entries)
        noteLogWrite(mark)
        undoRevision += 1
    }

    // MARK: Undo

    /// The label the toolbar's Undo button shows, or nil when nothing can be undone.
    /// It names the entry on top of the stack, which is what Undo will take back.
    var undoLabel: String? {
        _ = undoRevision
        guard let undoManager, undoManager.canUndo else { return nil }
        let name = undoManager.undoActionName
        return name.isEmpty ? "Undo" : name
    }

    /// Whether Undo would take back the newest logged change, so the tray and
    /// Changes only offer Undo for the change they describe.
    var canUndo: Bool {
        _ = undoRevision
        guard let undoManager, undoManager.canUndo, let first = log.first else { return false }
        return undoManager.undoActionName == first.label
    }

    /// Toolbar, tray and ⌘Z: step the window's undo stack. A completion still in
    /// its dwell is an entry there like any other; undoing it cancels the dwell.
    func undoLast() {
        // A line still being written is one step of its own, so finish it.
        document?.commitLine()
        guard let undoManager, undoManager.canUndo else { return }
        undoManager.undo()
    }

    /// An `owner` becomes the entry's target in place of the workbench, as in `snap`.
    func registerUndo(_ label: String, owner: AnyObject? = nil, undo: @escaping @MainActor (Workbench) -> Void,
                      redo: @escaping @MainActor (Workbench) -> Void) {
        guard let undoManager else { return }
        // The manager holds its target weakly; the handler keeps the owner alive.
        undoManager.registerUndo(withTarget: owner ?? self) { [weak self, owner] _ in
            MainActor.assumeIsolated {
                guard let workbench = self else { return }
                undo(workbench)
                workbench.registerUndo(label, owner: owner, undo: redo, redo: undo)
            }
        }
        undoManager.setActionName(label)
        undoRevision += 1
    }

    private func observeUndo() {
        for observer in undoObservers { NotificationCenter.default.removeObserver(observer) }
        undoObservers = []
        guard let undoManager else { return }
        let center = NotificationCenter.default
        let names: [Notification.Name] = [.NSUndoManagerDidCloseUndoGroup, .NSUndoManagerDidUndoChange,
                                          .NSUndoManagerDidRedoChange, .NSUndoManagerCheckpoint]
        for name in names {
            undoObservers.append(center.addObserver(forName: name, object: undoManager, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.undoRevision += 1 }
            })
        }
    }

    // MARK: Flashes

    /// Runs `clear` after `milliseconds`, replacing the timer pending under `key`.
    func after(_ milliseconds: Double, key: String, _ clear: @escaping (Workbench) -> Void) {
        flashTasks[key]?.cancel()
        flashTasks[key] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(milliseconds)))
            guard !Task.isCancelled, let self else { return }
            self.flashTasks[key] = nil
            clear(self)
        }
    }

    func flash(_ keyPath: ReferenceWritableKeyPath<Workbench, Set<UUID>>, _ ids: [UUID], for milliseconds: Double) {
        guard !ids.isEmpty else { return }
        let key = "\(keyPath.hashValue)"
        self[keyPath: keyPath].formUnion(ids)
        // A later flash restarts the timer, so it clears the earlier ids too.
        flashPending[key, default: []].formUnion(ids)
        after(milliseconds, key: key) { workbench in
            let ids = workbench.flashPending.removeValue(forKey: key) ?? []
            withAnimation(workbench.style.ease(400)) { workbench[keyPath: keyPath].subtract(ids) }
        }
    }

    func markRestored(_ ids: [UUID]) { flash(\.restored, ids, for: 900) }

    func pulse(list listID: UUID?) {
        guard let listID else { return }
        pulseListID = listID
        pulseRevision += 1
        let revision = pulseRevision
        after(1100, key: "pulseList") { workbench in
            guard workbench.pulseRevision == revision else { return }
            workbench.pulseListID = nil
        }
    }

    func pulseCheck(_ id: UUID) {
        guard style.lively else { return }
        pulseTaskID = id
        after(700, key: "pulseTask") { $0.pulseTaskID = nil }
    }

    func flashBlock(_ taskID: UUID) {
        freshBlockTaskID = taskID
        after(1400, key: "freshBlock") { workbench in
            withAnimation(workbench.style.ease(400)) { workbench.freshBlockTaskID = nil }
        }
    }

    // MARK: Completion dwell

    /// Completes `tasks` as one change: repeats roll forward now, the rest pop,
    /// strike and settle together once the dwell ends. The window's undo stack
    /// gets a single entry for all of it straight away. Undone during the dwell
    /// it cancels what's pending; undone later it restores what was written.
    /// `resume` is paused work the completion took off the notch, which Undo
    /// offers again. `makeLabel` runs after rolling, with the repeats that
    /// rolled and the tasks that close, so a lone repeat can name its next
    /// date; those are the tasks the log records. `settleNow` writes every row
    /// at once, with no dwell, and `date` is when the completion happened, for
    /// ticks made outside the window.
    func beginClosing(_ tasks: [Block], resuming resume: WorkTaskReference? = nil, settleNow: Bool = false,
                      at date: Date? = nil, label makeLabel: (_ rolls: [Block], _ closes: [Block]) -> String) {
        // A parent covers the subtasks ticked with it: a repeat resets them for
        // its next date, and the rest complete with their parent as it settles.
        let rolls = uncovered(tasks.filter { $0.recurrence != nil }, by: Set(tasks.map(\.id)))
        let rolled = Set(rolls.map(\.id))
        let closes = uncovered(tasks.filter { !rolled.contains($0.id) }, by: rolled)
        let plain = closes.map(\.id)
        let changes = UndoManager()
        changes.groupsByEvent = false
        write(rolls, on: changes, at: date)
        let label = makeLabel(rolls, closes)
        let icon = !rolls.isEmpty && plain.isEmpty ? "repeat" : "checkmark.circle.fill"
        let completion = CompletionBatch(mark: record(label, icon: icon, tone: .green, ids: rolls.map(\.id) + plain),
                                         changes: changes, pending: plain, resume: resume, date: date)
        attach(completion: completion, restores: false)
        showTray(label, icon: icon, tone: .green, undoable: true)
        guard !plain.isEmpty else {
            if let first = rolls.first { pulseCheck(first.id) }
            return
        }
        completions.append(completion)
        if settleNow {
            settle(completion)
            return
        }
        let strike = Int(ms(130))
        for (index, id) in plain.enumerated() {
            let stagger = Int(Double(index) * ms(75))
            closingTasks[id]?.cancel()
            // The first row pops in this turn, so a screen that drops closing
            // rows, like the Inbox triage card, never shows it open again.
            if index == 0 {
                withAnimation(style.spring(260)) { closing[id] = false }
                pulseCheck(id)
            }
            closingTasks[id] = Task { [weak self] in
                if index > 0 {
                    try? await Task.sleep(for: .milliseconds(stagger))
                    guard !Task.isCancelled, let self else { return }
                    withAnimation(self.style.spring(260)) { self.closing[id] = false }
                }
                try? await Task.sleep(for: .milliseconds(strike))
                guard !Task.isCancelled, let self else { return }
                withAnimation(self.style.ease(340)) { self.closing[id] = true }
                self.closingTasks[id] = nil
            }
        }
        // The batch settles as a unit once its last row has struck and dwelt.
        let delay = Double(plain.count - 1) * ms(75) + ms(130) + style.dwell * 1000 + 300
        completion.settleTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(delay)))
            guard !Task.isCancelled, let self else { return }
            self.settle(completion)
        }
    }

    /// Takes rows out of the dwell before they're written. A batch left with
    /// nothing pending or written leaves the log and the undo stack. Paused
    /// work the completion took off the notch comes back unless `restoresWork`
    /// is false, as when the rows go to Trash instead.
    func cancelClosing(_ ids: [UUID], restoresWork: Bool = true) {
        for id in ids { closingTasks.removeValue(forKey: id)?.cancel() }
        withAnimation(style.ease(240)) { for id in ids { closing[id] = nil } }
        for completion in completions where completion.pending.contains(where: ids.contains) {
            let dropped = completion.pending.filter(ids.contains)
            completion.pending.removeAll(where: dropped.contains)
            completion.mark.entries.removeAll { $0.taskID.map(dropped.contains) ?? false }
            log.removeAll { $0.batch == completion.mark.batch && ($0.taskID.map(dropped.contains) ?? false) }
            if restoresWork, let resume = completion.resume, dropped.contains(resume.taskID) {
                calendar.restoreResume(resume)
            }
            guard completion.pending.isEmpty else { continue }
            completion.settleTask?.cancel()
            completion.settleTask = nil
            completions.removeAll { $0 === completion }
            if !completion.changes.canUndo {
                log.removeAll { $0.batch == completion.mark.batch }
                undoManager?.removeAllActions(withTarget: completion.mark)
            }
        }
        undoRevision += 1
    }

    /// Writes every row still pending in the batch in one turn.
    private func settle(_ completion: CompletionBatch) {
        completion.settleTask?.cancel()
        completion.settleTask = nil
        completions.removeAll { $0 === completion }
        let ids = completion.pending
        completion.pending = []
        for id in ids { closingTasks.removeValue(forKey: id)?.cancel() }
        write(ids.compactMap { store.block(id: $0) }, on: completion.changes, at: completion.date)
        noteLogWrite(completion.mark)
        withAnimation(style.ease(320)) { for id in ids { closing[id] = nil } }
        undoRevision += 1
    }

    /// Completes tasks through the Store as one group on the batch's own undo
    /// stack, so the window never gets a second entry for them.
    private func write(_ tasks: [Block], on changes: UndoManager, at date: Date? = nil) {
        let open = tasks.filter { !$0.isCompleted }
        // A parent completes the subtasks written with it, and toggling one of
        // them afterwards would reopen it.
        let roots = uncovered(open, by: Set(open.map(\.id)))
        guard !roots.isEmpty else { return }
        changes.beginUndoGrouping()
        completionUndoTarget = changes
        for task in roots where !task.isCompleted {
            let now = date ?? .now
            if calendar.activeSession?.taskID == task.id { calendar.complete(task: task, now: now) }
            else { store.toggleCompletion(task, now: now) }
        }
        completionUndoTarget = nil
        changes.endUndoGrouping()
    }

    /// The tasks with no parent, at any depth, among `ids`.
    private func uncovered(_ tasks: [Block], by ids: Set<UUID>) -> [Block] {
        tasks.filter { task in
            var parentID = task.parentID
            var visited: Set<UUID> = [task.id]
            while let id = parentID, visited.insert(id).inserted {
                if ids.contains(id) { return false }
                parentID = store.block(id: id)?.parentID
            }
            return true
        }
    }

    /// The batch's one window entry. Undo cancels and restores the whole batch;
    /// Redo writes it again, rows that never settled included.
    private func attach(completion: CompletionBatch, restores: Bool) {
        guard let undoManager else { return }
        // The manager holds its target weakly; the handler keeps the batch alive.
        undoManager.registerUndo(withTarget: completion.mark) { [weak self, completion] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if restores { self.reapply(completion) } else { self.revert(completion) }
                self.attach(completion: completion, restores: !restores)
            }
        }
        undoManager.setActionName(completion.mark.label)
    }

    private func revert(_ completion: CompletionBatch) {
        completion.settleTask?.cancel()
        completion.settleTask = nil
        completions.removeAll { $0 === completion }
        let pending = completion.pending
        completion.cancelled = pending
        completion.pending = []
        for id in pending { closingTasks.removeValue(forKey: id)?.cancel() }
        withAnimation(style.ease(260)) { for id in pending { closing[id] = nil } }
        while completion.changes.canUndo { completion.changes.undo() }
        if let resume = completion.resume { calendar.restoreResume(resume) }
        unlog(completion.mark)
    }

    private func reapply(_ completion: CompletionBatch) {
        while completion.changes.canRedo { completion.changes.redo() }
        if !completion.cancelled.isEmpty {
            write(completion.cancelled.compactMap { store.block(id: $0) }, on: completion.changes)
            completion.cancelled = []
            // The batch is written now, so it's logged now: the Store dates its
            // completion from this write.
            let now = Date.now
            for index in completion.mark.entries.indices { completion.mark.entries[index].at = now }
        }
        if let resume = completion.resume, calendar.resumeTaskID == resume.taskID { calendar.dismissResume() }
        relog(completion.mark)
    }

    /// Settles every pending completion and trash now. Runs before quitting,
    /// so a row that showed as done or deleted is saved that way.
    func flushClosings() {
        for completion in completions { settle(completion) }
        for trash in trashes { land(trash) }
    }

    // MARK: Trash

    /// Moves tasks to Trash as one change. The window's undo stack and the log
    /// get the entry now; the rows fly out and are written once they've gone.
    /// Undone in flight, nothing is written.
    func beginTrash(_ ids: [UUID], label: String) {
        guard !ids.isEmpty else { return }
        let changes = UndoManager()
        changes.groupsByEvent = false
        let trash = TrashBatch(mark: record(label, icon: "trash", tone: .red, ids: ids), ids: ids, changes: changes)
        attach(trash: trash, restores: false)
        trashUndos.add(trash.mark)
        showTray(label, icon: "trash", tone: .red, undoable: true,
                 destination: TrayDestination(label: "Open Trash", route: .trash))
        trashes.append(trash)
        withAnimation(style.ease(320)) { flying.formUnion(ids) }
        let delay = ms(320)
        trash.task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(delay)))
            guard !Task.isCancelled, let self else { return }
            self.land(trash)
        }
    }

    /// Writes a trash whose rows have flown out.
    private func land(_ trash: TrashBatch) {
        trash.task?.cancel()
        trash.task = nil
        trashes.removeAll { $0 === trash }
        let wrote = writeTrash(trash)
        flying.subtract(trash.ids)
        guard !wrote else { return }
        // Nothing moved: the change leaves the log and the undo stack, and the
        // shell's Trash notice says why in place of the tray.
        log.removeAll { $0.batch == trash.mark.batch }
        undoManager?.removeAllActions(withTarget: trash.mark)
        if tray?.text == trash.mark.label { dismissTray() }
        undoRevision += 1
    }

    /// Moves the batch's tasks still present to Trash, on its own undo stack.
    private func writeTrash(_ trash: TrashBatch) -> Bool {
        let blocks = trash.ids.compactMap { store.block(id: $0) }
        guard !blocks.isEmpty else { return false }
        trash.changes.beginUndoGrouping()
        let wrote = store.trashBlocks(blocks, undoManager: trash.changes)
        trash.changes.endUndoGrouping()
        return wrote
    }

    /// The trash's one window entry. Undo puts the rows back, or stops a trash
    /// still in flight; Redo moves them to Trash again.
    private func attach(trash: TrashBatch, restores: Bool) {
        guard let undoManager else { return }
        // The manager holds its target weakly; the handler keeps the batch alive.
        undoManager.registerUndo(withTarget: trash.mark) { [weak self, trash] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if restores {
                    if trash.changes.canRedo { trash.changes.redo() } else { _ = self.writeTrash(trash) }
                    self.relog(trash.mark)
                } else {
                    if let task = trash.task {
                        task.cancel()
                        trash.task = nil
                        self.trashes.removeAll { $0 === trash }
                        withAnimation(self.style.ease(260)) { self.flying.subtract(trash.ids) }
                    }
                    while trash.changes.canUndo { trash.changes.undo() }
                    self.unlog(trash.mark)
                }
                self.attach(trash: trash, restores: !restores)
            }
        }
        undoManager.setActionName(trash.mark.label)
    }

    /// Logs a task's restore from Trash with its one window entry: Undo moves
    /// it back to Trash, Redo restores it again. Erased from Trash meanwhile,
    /// it leaves the stack instead; see `forgetErasedTrashes`.
    func snapRestore(_ label: String, id: UUID, icon: String, tone: TrayTone, destination: TrayDestination?) {
        let mark = record(label, icon: icon, tone: tone, ids: [id])
        attach(restore: mark, id: id, restores: false)
        trashUndos.add(mark)
        showTray(label, icon: icon, tone: tone, undoable: true, destination: destination)
    }

    private func attach(restore mark: LogMark, id: UUID, restores: Bool) {
        guard let undoManager else { return }
        // The manager holds its target weakly; the handler keeps the mark alive.
        undoManager.registerUndo(withTarget: mark) { [weak self, mark] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if restores {
                    self.store.restoreTrash(ids: [id])
                    self.relog(mark)
                } else {
                    // The handler keeps the id, never the model, which Trash may erase.
                    if let block = self.store.block(id: id) { self.store.trashBlocks([block]) }
                    self.unlog(mark)
                }
                self.attach(restore: mark, id: id, restores: !restores)
            }
        }
        undoManager.setActionName(mark.label)
    }

    /// Takes Undo off every trash or restore whose tasks have all been erased
    /// since: they're gone for good, so it has nothing left to do. A trash
    /// with some of its tasks left still undoes those.
    func forgetErasedTrashes() {
        let erased = store.permanentlyErasedBlockIDs
        for mark in trashUndos.allObjects {
            let ids = mark.entries.compactMap(\.taskID)
            guard !ids.isEmpty, ids.allSatisfy(erased.contains) else { continue }
            undoManager?.removeAllActions(withTarget: mark)
            trashUndos.remove(mark)
        }
        undoRevision += 1
    }

    func bumpUndo() { undoRevision += 1 }
}

// MARK: - Undo records

/// Ties a log batch to the undo entry that made it, so undoing that entry
/// removes exactly this batch, whatever the entry is called.
private final class LogMark {
    /// Renumbered when a Redo logs it again after Clear all activity history.
    var batch: Int
    let label: String
    /// What Redo puts back in the log; rows cancelled mid-dwell drop out.
    var entries: [ChangeEntry]
    /// The target the log's half of the entry shares with the change, if any.
    var owner: AnyObject?
    /// The tasks and lists whose saved history the change, its Undo and Redo write.
    let covers: Set<UUID>

    init(batch: Int, label: String, entries: [ChangeEntry], covers: Set<UUID>) {
        self.batch = batch
        self.label = label
        self.entries = entries
        self.covers = covers
    }
}

/// Tasks completed together, undone and redone as one window entry.
///
/// The Store's writes, repeats rolling at once and the rest when the dwell
/// ends, register their exact restores on `changes`. The window entry
/// unwinds and replays that stack as a unit.
private final class CompletionBatch {
    let mark: LogMark
    let changes: UndoManager
    /// Rows still in the dwell, in tick order.
    var pending: [UUID]
    /// Rows Undo cancelled before they were written; Redo writes them.
    var cancelled: [UUID] = []
    var settleTask: Task<Void, Never>?
    /// Paused work the completion took off the notch; Undo offers it again.
    let resume: WorkTaskReference?
    /// When the completion happened, if not when it's written.
    let date: Date?

    init(mark: LogMark, changes: UndoManager, pending: [UUID], resume: WorkTaskReference?, date: Date? = nil) {
        self.mark = mark
        self.changes = changes
        self.pending = pending
        self.resume = resume
        self.date = date
    }
}

/// Tasks moved to Trash together. The rows fly out first; the Store's write
/// then registers its exact restore on `changes`.
private final class TrashBatch {
    let mark: LogMark
    let ids: [UUID]
    let changes: UndoManager
    /// Lands the trash once the rows have flown out; nil once written.
    var task: Task<Void, Never>?

    init(mark: LogMark, ids: [UUID], changes: UndoManager) {
        self.mark = mark
        self.ids = ids
        self.changes = changes
    }
}

// MARK: - Screen filters

enum TasksStatusFilter: String, CaseIterable, Identifiable {
    case open, done, all
    var id: String { rawValue }
    var title: String {
        switch self {
        case .open: "Open"
        case .done: "Completed"
        case .all: "All"
        }
    }
    var word: String {
        switch self {
        case .open: "open"
        case .done: "completed"
        case .all: "all"
        }
    }
}

enum TasksGroupingMode: String, CaseIterable, Identifiable {
    case list, due, none
    var id: String { rawValue }
    var title: String {
        switch self {
        case .list: "By list"
        case .due: "By date"
        case .none: "Flat"
        }
    }
    var word: String {
        switch self {
        case .list: "list"
        case .due: "due date"
        case .none: "nothing"
        }
    }
    var next: TasksGroupingMode {
        switch self {
        case .list: .due
        case .due: .none
        case .none: .list
        }
    }
}
