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
    /// On the Calendar, the day its range moves to show; nil shows today's,
    /// as the design's Calendar always does.
    var day: Date? = nil
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
    /// Every task row takes the restored tint, as the design's Undo marks
    /// every task it puts back restored, not only those the step changed.
    var restoredAll = false
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
    /// When the log's changes, and the list document's lines, were written.
    @ObservationIgnored private var logWrites = NXLogWrites()
    /// Bumped whenever the undo stack may have changed so labels re-read it.
    private(set) var undoRevision = 0

    // MARK: Inbox triage

    var kept: Set<UUID> = []
    var reviewed = 0
    var triageExit: TriageExit?

    // MARK: Screens

    var collapsedGroups: Set<String> = []
    /// The Completed groups' shared fold; nil until the user folds one.
    var completedFold: NXCompletedFold?
    var calendarDays = 7
    /// A day the Calendar shows its range from instead of today: stepped to,
    /// or where Plan put a task. Nil follows today, as does one set on an
    /// earlier day (`calendarStart(now:)`).
    var calendarAnchor: Date? {
        didSet { calendarAnchorSetAt = .now }
    }
    /// When `calendarAnchor` was last set.
    @ObservationIgnored private(set) var calendarAnchorSetAt = Date.now
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
    /// Why Return couldn't add the capture, on its card until the text changes.
    var captureNotice: NXCaptureNotice?
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
        didSet {
            guard editingNoteID != nil, editingNoteID != oldValue else { return }
            noteEditRequestedAt = .now
            noteEdit &+= 1
        }
    }
    /// Counts the notes started, so a note left and started again in one
    /// update, as the note button does to an empty one, gets an editor of
    /// its own, which takes the keyboard.
    private(set) var noteEdit = 0
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
    /// A section just made, whose name field the sidebar opens.
    var namingSectionID: UUID?
    @ObservationIgnored private let defaults: UserDefaults?
    private static let openNotesKey = "nextOpenNotes"

    /// The inspector's Add subtask, as the design's: goes to the task's list
    /// document, opening it if needed, where the task unfolds and a new
    /// subtask line at the end of its subtasks takes the caret. The Inbox
    /// shows as its document from then on, the one place it has to write it.
    func addSubtask(to id: UUID) {
        guard let task = store.block(id: id), task.isTask, let list = store.list(id: task.listID) else { return }
        document?.commitLine()
        if let document, document.document.listID == list.id {
            document.appendSubtask(to: id)
            return
        }
        if list.id == navigator.inboxListID, navigator.listViewMode(for: list.id) != .document {
            navigator.setListViewMode(.document, for: list.id)
        }
        pendingSubtaskParentID = id
        go(route(for: list))
        // Only that list's document takes it up; kept for a later one, it
        // would write a line nobody asked for then.
        if navigator.documentListID != list.id { pendingSubtaskParentID = nil }
    }

    /// Space, or a task's note button: shows or hides its note under it. A
    /// task with no note starts one instead. As the design's, only the note
    /// fades in as it shows; the lines below move at once.
    func toggleNote(_ id: UUID) {
        guard let task = store.block(id: id), task.isTask else { return }
        if !openNotes.contains(id), task.note.isEmpty {
            editNote(id)
            return
        }
        if openNotes.contains(id) { openNotes.remove(id) } else { openNotes.insert(id) }
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
    /// The log batches that report completions made outside Next's rows,
    /// which never stand for one of Next's own saved late.
    @ObservationIgnored var outsideCompletionBatches: Set<Int> = []
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
    /// Restores whose rows are still flying out of Trash.
    @ObservationIgnored private var restoring: [RestoreBatch] = []
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
        // A refusal, like a drop the document's rules don't allow, passes in
        // the tray as the design's "No free slot" does.
        store.onRefusal = { [weak self] message in
            self?.showTray(message, icon: "exclamationmark.circle", tone: .neutral)
        }
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

    /// Going to the screen already on show only closes the palette and
    /// search, as the design's go returns: the focus and selection stay.
    func go(_ route: AppRoute) {
        navigator.isCommandPaletteOpen = false
        navigator.isSearchOpen = false
        guard navigator.route != route else { return }
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
        navigator.releaseRevealSelection()
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
        navigator.releaseRevealSelection()
        if extending {
            if let focusID { selection.insert(focusID) }
            selection.insert(id)
        }
        focusID = id
        if navigator.openTaskID != nil { navigator.openTask(id) }
    }

    /// As the design's toggleSel, the focus stays where it is: a ⌘-clicked
    /// row takes the selected tint, not the focused card, and one clicked
    /// off again leaves the keys nothing of its own to act on.
    func toggleSelection(_ id: UUID) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    func selectAllVisible() {
        selection = Set(visibleIDs)
    }

    /// Like every selection change here, a plain change, as the design's: the
    /// rows' checks go at once and their chips move back, while each row's
    /// tint and ring ease out through their own animations.
    func clearSelection() {
        guard !selection.isEmpty else { return }
        selection = []
    }

    /// A plain click: focus, and follow along if the inspector is open.
    func click(_ id: UUID, command: Bool, shift: Bool) {
        if closing[id] != nil { cancelClosing([id]); return }
        if command || shift {
            toggleSelection(id)
            return
        }
        clearSelection()
        navigator.releaseRevealSelection()
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

    /// The tray's jump: to its route, and on the Calendar to a range that
    /// shows its day, whichever range the Calendar was stepped or moved to.
    func follow(_ destination: TrayDestination) {
        guard destination.route == .calendar else { go(destination.route); return }
        showOnCalendar(destination.day ?? .now)
    }

    /// Whether the tray offers its jump: away from its route, and on the
    /// Calendar while the range, stepped or moved away, doesn't show its day.
    func offers(_ destination: TrayDestination) -> Bool {
        destination.route != navigator.route || destination.route == .calendar && !calendarShows(destination.day ?? .now)
    }

    // MARK: Change log

    /// Records a change in the log and announces it in the tray, unless
    /// `showsTray` is off. An undoable change ties its log batch to the Undo
    /// entry the caller just registered. An `owner` shares the Undo entry's
    /// target, so the whole entry leaves the stack with `removeAllActions(withTarget:)`.
    func snap(_ label: String, icon: String, tone: TrayTone, ids: [UUID], undoable: Bool = true,
              destination: TrayDestination? = nil, owner: AnyObject? = nil, showsTray: Bool = true) {
        let mark = record(label, icon: icon, tone: tone, ids: ids)
        mark.owner = owner
        if undoable { attach(mark, restores: false) }
        if showsTray {
            showTray(label, icon: icon, tone: tone, undoable: undoable, destination: destination)
        } else if undoable, tray?.undoable == true {
            // The tray still up would take this back, not its own change.
            withAnimation(style.ease(200)) { tray?.undoable = false }
        }
    }

    /// Records and announces a change whose Undo or Redo can fail, like a
    /// label's, with the change and its log half in one window entry. `undo`
    /// and `redo` say whether they did what they were to; see the `attach`
    /// that takes them.
    func snap(_ label: String, icon: String, tone: TrayTone, ids: [UUID], destination: TrayDestination? = nil,
              undo: @escaping @MainActor (Workbench) -> Bool, redo: @escaping @MainActor (Workbench) -> Bool) {
        attach(record(label, icon: icon, tone: tone, ids: ids), restores: false, undo: undo, redo: redo)
        showTray(label, icon: icon, tone: tone, undoable: true, destination: destination)
    }

    /// Logs an edit the list document has just put on the undo stack, in the
    /// same step, so it shows in Changes and names the toolbar's Undo. As in
    /// the design, an edit shows no tray; one still showing an earlier change,
    /// like the new section whose name this is, loses its Undo, which would
    /// now take back the edit instead.
    func logEdit(_ label: String, ids: [UUID]) {
        attach(record(label, icon: "pencil", tone: .neutral, ids: ids), restores: false)
        if tray?.undoable == true { withAnimation(style.ease(200)) { tray?.undoable = false } }
    }

    var latestBatch: Int? { log.first?.batch }

    func entries(for taskID: UUID) -> [ChangeEntry] { log.filter { $0.taskID == taskID } }

    /// Settings' Clear all activity history: the saved history, then, once it's
    /// gone, the log, so Changes and each task's Activity start over, said in
    /// the tray as Settings' other Data actions are. The undo stack keeps its
    /// steps; redoing one from before the clear logs it anew.
    func clearActivityHistory() {
        store.clearActivity()
        guard store.persistenceError == nil else { return }
        log.removeAll()
        clearedBatch = batchCounter
        showTray("Cleared all activity history", icon: "clock.arrow.circlepath")
        undoRevision += 1
    }

    /// Settings' Delete everything. Once the Store has erased the library,
    /// the session's changes go with it: every step on the window's undo
    /// stack, which has nothing left to act on, the log, rows mid-change and
    /// the tray, as the saved history already has. False, and nothing of the
    /// session touched, when the Store couldn't finish.
    @discardableResult
    func resetLibrary() -> Bool {
        document?.commitLine()
        guard store.permanentlyResetLibrary() else { return false }
        for completion in completions { completion.settleTask?.cancel() }
        completions = []
        for trash in trashes { trash.task?.cancel() }
        trashes = []
        for restore in restoring { restore.task?.cancel() }
        restoring = []
        for task in closingTasks.values { task.cancel() }
        closingTasks = [:]
        closing = [:]
        flying = []
        undoManager?.removeAllActions()
        trashUndos.removeAllObjects()
        workUndos = []
        outsideCompletionBatches = []
        log.removeAll()
        clearedBatch = batchCounter
        kept = []
        reviewed = 0
        selection = []
        focusID = nil
        showTray("Deleted everything for good", icon: "trash.slash", tone: .red)
        undoRevision += 1
        return true
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
        logWrites.note(mark.covers)
    }

    /// A list document line's edit ended, and the one entry saved history
    /// takes for what it saved to `ids`, if any, is the log's, which records
    /// the line once, with the design's name, or not at all when a new line
    /// left empty goes, as in the design.
    func noteLineWrites(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        logWrites.note(ids)
        // Changes reads the log's writes as it draws, so it draws again.
        undoRevision += 1
    }

    /// Whether saved history from `date` about a task or list came from one of
    /// the log's own writes — a change, its Undo or Redo, or a list document
    /// line — so it's already in the log, was taken back or never counted.
    func logWrote(at date: Date, about ids: [UUID?]) -> Bool {
        logWrites.wrote(at: date, about: ids)
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

    /// The window entry of a change whose Undo or Redo can fail. A step that
    /// did its part moves the batch in or out of the log as `attach` does. One
    /// that failed changed nothing, so the log stays as it was and the tray
    /// says so in place of "Undid", while the Store's notice says why. It
    /// registers nothing, so the entry leaves the stack rather than stay on
    /// top of everything under it.
    private func attach(_ mark: LogMark, restores: Bool, undo: @escaping @MainActor (Workbench) -> Bool,
                        redo: @escaping @MainActor (Workbench) -> Bool) {
        guard let undoManager else { return }
        // The manager holds its target weakly; the handler keeps the mark alive.
        undoManager.registerUndo(withTarget: mark) { [weak self, mark] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard restores ? redo(self) : undo(self) else {
                    self.showTray("Could not \(restores ? "redo" : "undo") — \(mark.label)",
                                  icon: "exclamationmark.triangle", tone: .red)
                    self.undoRevision += 1
                    return
                }
                if restores { self.relog(mark) } else { self.unlog(mark) }
                self.attach(mark, restores: !restores, undo: undo, redo: redo)
            }
        }
        undoManager.setActionName(mark.label)
    }

    private func unlog(_ mark: LogMark) {
        log.removeAll { $0.batch == mark.batch }
        noteLogWrite(mark)
        markAllRestored()
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
    /// It names what Undo will take back: the entry on top of the stack, or,
    /// while a list document line has typing there, the step the line
    /// commits as, since Undo finishes the line first, or the step under its
    /// typing when finishing it registers none. The text system's name for
    /// that typing would read "Typing" whenever a line is written.
    var undoLabel: String? {
        _ = undoRevision
        guard let undoManager, undoManager.canUndo else { return nil }
        let name = undoManager.undoActionName
        if Self.textActionNames.contains(name), let document, document.isWritingLine {
            return document.lineStepName ?? document.stepUnderLine
        }
        return name.isEmpty ? "Undo" : name
    }

    /// The names AppKit's text system files its own undo entries under
    /// (typing, paste, drag…), in the app's language.
    private static let textActionNames: Set<String> = {
        let bundle = Bundle(for: NSTextView.self)
        return Set(["Typing", "Paste", "Cut", "Drag", "Suggestion", "Change Attributes", "Set Font", "Set Color"]
            .map { bundle.localizedString(forKey: $0, value: $0, table: "Undo") })
    }()

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

    /// Closes the window's undo group, which holds everything registered in
    /// this event, so the change about to be made is a step of its own rather
    /// than undone with, say, a draft just saved for it. Only right before a
    /// change that is sure to register: a group left empty stays on the stack.
    func separateUndoStep() {
        guard let undoManager, undoManager.groupingLevel > 0,
              !undoManager.isUndoing, !undoManager.isRedoing else { return }
        undoManager.endUndoGrouping()
        undoManager.beginUndoGrouping()
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

    /// The design's Undo: every task row on show takes the restored tint for
    /// 900ms, done ones too, and none keeps the fresh one over it.
    func markAllRestored() {
        fresh = []
        restoredAll = true
        after(900, key: "restoredAll") { workbench in
            withAnimation(workbench.style.ease(400)) { workbench.restoredAll = false }
        }
    }

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
        let activity = UUID()
        write(rolls, on: changes, at: date, activity: activity)
        let label = makeLabel(rolls, closes)
        let icon = !rolls.isEmpty && plain.isEmpty ? "repeat" : "checkmark.circle"
        let completion = CompletionBatch(mark: record(label, icon: icon, tone: .green, ids: rolls.map(\.id) + plain),
                                         changes: changes, pending: plain, resume: resume, date: date, activity: activity)
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
            // A plain change, as the design's: a row eases its pop, dim, fill
            // and tick through its own animations, while what drops a closing
            // task, like the Calendar's Planned now banner, goes at once.
            if index == 0 {
                closing[id] = false
                pulseCheck(id)
            }
            closingTasks[id] = Task { [weak self] in
                if index > 0 {
                    try? await Task.sleep(for: .milliseconds(stagger))
                    guard !Task.isCancelled, let self else { return }
                    self.closing[id] = false
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
        write(ids.compactMap { store.block(id: $0) }, on: completion.changes, at: completion.date, activity: completion.activity)
        noteLogWrite(completion.mark)
        // A plain change, as the design's settle: the row leaves its group at
        // once, the page closes up under it and the counts change without
        // rolling. What stays on screen, like a done subtask in the document,
        // eases through its own animations, and the header's bar through its 560ms.
        for id in ids { closing[id] = nil }
        undoRevision += 1
    }

    /// Completes tasks through the Store as one group on the batch's own undo
    /// stack, so the window never gets a second entry for them, and their
    /// saved history is one change, the `activity` batch, as the log's is.
    private func write(_ tasks: [Block], on changes: UndoManager, at date: Date? = nil, activity: UUID = UUID()) {
        let open = tasks.filter { !$0.isCompleted }
        // A parent completes the subtasks written with it, and toggling one of
        // them afterwards would reopen it.
        let roots = uncovered(open, by: Set(open.map(\.id)))
        guard !roots.isEmpty else { return }
        changes.beginUndoGrouping()
        completionUndoTarget = changes
        store.withActivityBatch(activity) {
            for task in roots where !task.isCompleted {
                let now = date ?? .now
                if calendar.activeSession?.taskID == task.id { calendar.complete(task: task, now: now) }
                else { store.toggleCompletion(task, now: now) }
            }
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
        // Its saved history is one change, as the batch's Redo's is.
        store.withActivityBatch(UUID()) {
            while completion.changes.canUndo { completion.changes.undo() }
        }
        if let resume = completion.resume { calendar.restoreResume(resume) }
        unlog(completion.mark)
    }

    private func reapply(_ completion: CompletionBatch) {
        // What it writes again, rows that never settled too, saves as one
        // change: a batch of its own, as the Undo before it was, so it never
        // reads as more tasks with the history first written.
        let activity = UUID()
        store.withActivityBatch(activity) {
            while completion.changes.canRedo { completion.changes.redo() }
        }
        if !completion.cancelled.isEmpty {
            write(completion.cancelled.compactMap { store.block(id: $0) }, on: completion.changes, activity: activity)
            completion.cancelled = []
            // The batch is written now, so it's logged now: the Store dates its
            // completion from this write.
            let now = Date.now
            for index in completion.mark.entries.indices { completion.mark.entries[index].at = now }
        }
        if let resume = completion.resume, calendar.resumeTaskID == resume.taskID { calendar.dismissResume() }
        relog(completion.mark)
    }

    /// Settles every pending completion, trash and restore now. Runs before
    /// quitting, so a row that showed as done, deleted or restored is saved that way.
    func flushClosings() {
        for completion in completions { settle(completion) }
        for trash in trashes { land(trash) }
        for restore in restoring { land(restore) }
    }

    // MARK: Trash

    /// Moves tasks to Trash as one change. The window's undo stack and the log
    /// get the entry now; the rows fly out and are written once they've gone.
    /// Undone in flight, nothing is written.
    func beginTrash(_ ids: [UUID], label: String) {
        guard !ids.isEmpty else { return }
        // As a restore does: a failure saying the same appears, and is heard, anew.
        store.trashError = nil
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

    /// Moves a list, with its nested lists and everything in them, to Trash
    /// as one change, as the design's trash does for tasks: the tray offers
    /// Undo and Open Trash. Steps off the list first if it's on screen.
    @discardableResult
    func trashList(_ list: TaskList) -> Bool {
        document?.commitLine()
        let id = list.id
        let label = "Moved \(NXFormat.quoted(list.displayTitle)) to Trash"
        guard moveToTrash(list) else { return false }
        let mark = record(label, icon: "trash", tone: .red, ids: [id])
        mark.trashedListID = id
        // The handlers keep the id, never the model.
        attach(mark, restores: false, undo: { workbench in
            // Restored from Trash by hand meanwhile, it's back already.
            !workbench.store.isInTrash(id) || workbench.store.restoreTrash(ids: [id])
        }, redo: { workbench in
            // Out of the library, it's in Trash already or erased.
            guard let list = workbench.store.list(id: id) else { return true }
            return workbench.moveToTrash(list)
        })
        trashUndos.add(mark)
        showTray(label, icon: "trash", tone: .red, undoable: true,
                 destination: TrayDestination(label: "Open Trash", route: .trash))
        return true
    }

    /// Trashes the list through the Store, leaving its page, or a nested
    /// list's, for Today as it goes. As the design's trash does, its tasks
    /// leave the inspector, the focus and the selection with it.
    private func moveToTrash(_ list: TaskList) -> Bool {
        let owned = store.listHierarchy().subtree(of: list.id).map(\.id)
        let wasOpen = navigator.route.listID.map(Set(owned).contains) == true
        let blockIDs = Set(owned.flatMap { store.blocks(inList: $0).map(\.id) })
        guard store.trashList(list) else { return false }
        if wasOpen { navigator.replace(with: .today) }
        if let open = navigator.openTaskID, blockIDs.contains(open) { navigator.closeTask() }
        if let focusID, blockIDs.contains(focusID) { self.focusID = nil }
        selection.subtract(blockIDs)
        return true
    }

    /// Restores a Trash entry as one change, as the design's restore does:
    /// the log, the window's Undo and the tray, saying where it goes back
    /// to, get it now; the row flies out and is written once it has gone.
    /// Undone in flight, nothing is written; undone later, it goes back to
    /// Trash. Erased from Trash meanwhile, it leaves the stack instead; see
    /// `forgetErasedTrashes`.
    func beginRestore(_ entry: TrashEntry, label: String, destination: TrayDestination?) {
        guard !flying.contains(entry.id) else { return }
        // The notice is the last attempt's, which this one replaces, as its
        // write would: so a failure saying the same appears, and is heard, anew.
        store.trashError = nil
        let restore = RestoreBatch(mark: record(label, icon: "arrow.up.bin", tone: .accent, ids: [entry.id]),
                                   id: entry.id, isList: entry.isList)
        if entry.isList { restore.mark.trashedListID = entry.id }
        attach(restore: restore, restores: false)
        trashUndos.add(restore.mark)
        showTray(label, icon: "arrow.up.bin", tone: .accent, undoable: true, destination: destination)
        restoring.append(restore)
        // The row flies out on its own fixed animation, and the restore is
        // written after the design's fixed 300 ms, whatever the Motion setting.
        flying.insert(entry.id)
        restore.task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            self.land(restore)
        }
    }

    /// Writes a restore whose row has flown out. Written first, as a trash
    /// lands: the row leaves Trash as it stops flying, and one that stays
    /// comes back. One the Store couldn't write leaves the log and the undo
    /// stack, and the shell's Trash notice says why, as for a trash.
    private func land(_ restore: RestoreBatch) {
        restore.task?.cancel()
        restore.task = nil
        restoring.removeAll { $0 === restore }
        let recoveries = store.restoreTrashRecoveries(ids: [restore.id])
        flying.remove(restore.id)
        guard let recoveries else {
            log.removeAll { $0.batch == restore.mark.batch }
            undoManager?.removeAllActions(withTarget: restore.mark)
            trashUndos.remove(restore.mark)
            // The notice says why; the tray does only when the Store gave no
            // reason, and one still saying it's restored goes, as for a trash.
            if store.trashError == nil {
                showTray("This item could not be restored.", icon: "exclamationmark.triangle", tone: .red)
            } else if tray?.text == restore.mark.label {
                dismissTray()
            }
            undoRevision += 1
            return
        }
        restore.recoveries = recoveries
        // What came back with it, a task's subtasks or a list's contents, is
        // in the library again, and its saved history is the log's too.
        restore.mark.covers = covered([restore.id])
        noteLogWrite(restore.mark)
        // A task going to Recovered items, whose list the tray couldn't open
        // before it was made, can be opened now.
        if !restore.isList, tray?.text == restore.mark.label, tray?.destination == nil,
           let list = store.block(id: restore.id).flatMap({ store.list(id: $0.listID) }) {
            tray?.destination = TrayDestination(label: "Open \(list.displayTitle)", route: route(for: list))
        }
        markRestored([restore.id])
    }

    /// The restore's one window entry. Undo stops a restore still in flight,
    /// or moves what it restored back to Trash; Redo restores it again. One
    /// the Store couldn't write changed nothing: as a label's does, the log
    /// stays as it was, the tray says so and the entry leaves the stack.
    private func attach(restore: RestoreBatch, restores: Bool) {
        guard let undoManager else { return }
        // The manager holds its target weakly; the handler keeps the batch alive.
        undoManager.registerUndo(withTarget: restore.mark) { [weak self, restore] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let id = restore.id
                if restores {
                    // Restored from Trash by hand meanwhile, it's back already.
                    if self.store.isInTrash(id) {
                        guard let recoveries = self.store.restoreTrashRecoveries(ids: [id]) else {
                            self.restoreStepFailed(restore, redo: true)
                            return
                        }
                        restore.recoveries = recoveries
                    }
                    restore.mark.covers = self.covered([id])
                    self.relog(restore.mark)
                } else {
                    if let task = restore.task {
                        task.cancel()
                        restore.task = nil
                        self.restoring.removeAll { $0 === restore }
                        // The row flies back on its own animation.
                        self.flying.remove(id)
                    } else if restore.isList {
                        // The handler keeps the id, never the model, which Trash may erase.
                        // Out of the library, it's in Trash already or erased.
                        if let list = self.store.list(id: id), !self.moveToTrash(list) {
                            self.restoreStepFailed(restore, redo: false)
                            return
                        }
                    } else if let block = self.store.block(id: id) {
                        // Back to Trash as it was, taking a Recovered items list made for it.
                        let made = Set(restore.recoveries.filter(\.madeList).map(\.listID))
                        guard self.store.trashBlocks([block], puttingBack: restore.recoveries) else {
                            self.restoreStepFailed(restore, redo: false)
                            return
                        }
                        restore.recoveries = []
                        if let open = self.navigator.route.listID, made.contains(open), self.store.list(id: open) == nil {
                            self.navigator.replace(with: .today)
                        }
                    }
                    self.unlog(restore.mark)
                }
                self.attach(restore: restore, restores: !restores)
            }
        }
        undoManager.setActionName(restore.mark.label)
    }

    /// An Undo or Redo of a restore the Store refused, whose notice says why.
    private func restoreStepFailed(_ restore: RestoreBatch, redo: Bool) {
        trashUndos.remove(restore.mark)
        showTray("Could not \(redo ? "redo" : "undo") — \(restore.mark.label)", icon: "exclamationmark.triangle", tone: .red)
        undoRevision += 1
    }

    /// Takes Undo off every trash or restore whose tasks have all been erased
    /// since: they're gone for good, so it has nothing left to do. A trash
    /// with some of its tasks left still undoes those. A trashed list is gone
    /// once it's neither in Trash nor in the library.
    func forgetErasedTrashes() {
        let erased = store.permanentlyErasedBlockIDs
        for mark in trashUndos.allObjects {
            let ids = mark.entries.compactMap(\.taskID)
            if let listID = mark.trashedListID {
                guard !store.isInTrash(listID), store.list(id: listID) == nil else { continue }
            } else {
                guard !ids.isEmpty, ids.allSatisfy(erased.contains) else { continue }
            }
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
    /// The list a list trash moved to Trash, which Undo restores.
    var trashedListID: UUID?
    /// The tasks and lists whose saved history the change, its Undo and Redo
    /// write. A restore learns what came back with it once it's written.
    var covers: Set<UUID>

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
    /// The saved history's batch, shared by the repeats rolled and the rows settled.
    let activity: UUID

    init(mark: LogMark, changes: UndoManager, pending: [UUID], resume: WorkTaskReference?, date: Date? = nil,
         activity: UUID = UUID()) {
        self.mark = mark
        self.changes = changes
        self.pending = pending
        self.resume = resume
        self.date = date
        self.activity = activity
    }
}

/// A Trash entry restored, whose row flies out before the Store writes it.
private final class RestoreBatch {
    let mark: LogMark
    let id: UUID
    let isList: Bool
    /// Where the restore last written put a task whose place was gone, which its Undo puts back.
    var recoveries: [TrashRecovery] = []
    /// Writes the restore once the row has flown out; nil once written or stopped.
    var task: Task<Void, Never>?

    init(mark: LogMark, id: UUID, isList: Bool) {
        self.mark = mark
        self.id = id
        self.isList = isList
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
