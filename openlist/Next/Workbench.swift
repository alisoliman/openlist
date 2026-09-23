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

    var focusID: UUID?
    var selection: Set<UUID> = []
    /// Row order on screen, published by the visible screen for J/K and ⌘A.
    @ObservationIgnored var visibleIDs: [UUID] = []

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
    /// Bumped whenever the undo stack may have changed so labels re-read it.
    private(set) var undoRevision = 0

    // MARK: Inbox triage

    var kept: Set<UUID> = []
    var reviewed = 0
    var triageExit: TriageExit?
    var triageFlip = false

    // MARK: Screens

    var screenFlip = false
    var collapsedGroups: Set<String> = []
    var calendarDays = 7
    var calendarAnchor = Calendar.current.startOfDay(for: .now)
    var tasksStatus: TasksStatusFilter = .open
    var tasksGrouping: TasksGroupingMode = .list
    var tasksQuery = ""
    var tasksPills = TasksPillFilter()
    /// Sentence mode: the lists picked in "in [all lists▾]" and the title filter.
    var tasksListFilter: Set<UUID> = []
    var tasksTitleFilter = ""
    /// Whether the query field on Tasks has keyboard focus (drives its popover).
    var tasksQueryFocused = false
    var captureOpen = false
    var captureText = ""
    var captureListID: UUID?
    var captureForToday = false
    var paletteQuery = ""
    var paletteIndex = 0
    var searchQuery = ""
    var searchIndex = 0
    var searchIncludesCompleted = false
    var activityDay: Date?

    var workStartedAt: Date?
    var workPausedTaskID: UUID?
    var workCarrySeconds: Double = 0
    /// Lists shown as their editable document instead of Next's task view.
    var documentListIDs: Set<UUID> = []

    @ObservationIgnored var gPressedAt: Date?
    /// Names the Store's completion Undo after the design action that caused it.
    @ObservationIgnored var completionLabel: String?
    /// Set while replaying design Undo so the Store doesn't register a second entry.
    @ObservationIgnored var suppressesStoreUndo = false
    @ObservationIgnored weak var undoManager: UndoManager? {
        didSet { if oldValue !== undoManager { observeUndo() } }
    }
    @ObservationIgnored private var batchCounter = 0
    @ObservationIgnored private var closingBatches: [(batch: Int, label: String, ids: [UUID])] = []
    @ObservationIgnored private var settleTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var flashTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var trayTask: Task<Void, Never>?
    @ObservationIgnored private var undoObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var isApplyingOwnUndo = false

    init(store: Store, navigator: Navigator, settings: AppSettings, calendar: CalendarCoordinator) {
        self.store = store
        self.navigator = navigator
        self.settings = settings
        self.calendar = calendar
    }

    // MARK: Style

    var style: NextStyle {
        let reduced = settings.reducesMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        return NextStyle(
            accent: settings.accent.color,
            motion: reduced ? 0.4 : settings.motion.scale,
            lively: !reduced && settings.motion != .restrained,
            dwell: Double(settings.undoDwellSeconds),
            compact: settings.density == .compact,
            serifTitles: settings.serifTitles
        )
    }

    func ms(_ base: Double) -> Double { style.ms(base) }

    /// Minutes planned for a task without its own estimate.
    var defaultEstimate: Int { max(5, Int(calendar.preferences.defaultEstimateMinutes)) }

    // MARK: Targets

    /// Selection, else keyboard focus, else the inspected task.
    var targetIDs: [UUID] {
        if !selection.isEmpty {
            let ordered = visibleIDs.filter(selection.contains)
            return ordered.isEmpty ? Array(selection) : ordered + selection.subtracting(ordered)
        }
        if let focusID { return [focusID] }
        if let openID = navigator.openTaskID { return [openID] }
        return []
    }

    var targetTasks: [Block] { targetIDs.compactMap { store.block(id: $0) }.filter(\.isTask) }

    func tasks(_ ids: [UUID]) -> [Block] { ids.compactMap { store.block(id: $0) }.filter(\.isTask) }

    // MARK: Navigation

    func go(_ route: AppRoute) {
        focusID = nil
        selection = []
        navigator.isCommandPaletteOpen = false
        navigator.isSearchOpen = false
        guard navigator.route != route else { return }
        withAnimation(style.ease(260)) { screenFlip.toggle() }
        navigator.go(to: route)
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
        let next = current.map { min(max($0 + delta, 0), visibleIDs.count - 1) } ?? (delta > 0 ? 0 : visibleIDs.count - 1)
        let id = visibleIDs[next]
        if extending {
            if let focusID { selection.insert(focusID) }
            selection.insert(id)
        }
        focusID = id
        if navigator.openTaskID != nil { navigator.openTask(id) }
    }

    func toggleSelection(_ id: UUID) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        focusID = id
    }

    func selectAllVisible() {
        selection = Set(visibleIDs)
    }

    /// A plain click: focus, and follow along if the inspector is open.
    func click(_ id: UUID, command: Bool, shift: Bool) {
        if closing[id] != nil { cancelClosing([id]); return }
        if command || shift {
            toggleSelection(id)
            return
        }
        selection = []
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

    /// Records a change in the log and announces it in the tray.
    func snap(_ label: String, icon: String, tone: TrayTone, ids: [UUID], undoable: Bool = true,
              destination: TrayDestination? = nil) {
        batchCounter += 1
        let now = Date.now
        let entries = (ids.isEmpty ? [nil] : ids.map(Optional.some)).map {
            ChangeEntry(taskID: $0, label: label, icon: icon, tone: tone, at: now, batch: batchCounter)
        }
        log.insert(contentsOf: entries, at: 0)
        if log.count > 400 { log.removeLast(log.count - 400) }
        showTray(label, icon: icon, tone: tone, undoable: undoable, destination: destination)
        undoRevision += 1
    }

    var latestBatch: Int? { log.first?.batch }

    func entries(for taskID: UUID) -> [ChangeEntry] { log.filter { $0.taskID == taskID } }

    // MARK: Undo

    /// The label the toolbar's Undo button shows, or nil when nothing can be undone.
    var undoLabel: String? {
        _ = undoRevision
        if let pending = closingBatches.last { return pending.label }
        guard let undoManager, undoManager.canUndo else { return nil }
        let name = undoManager.undoActionName
        return name.isEmpty ? "Undo" : name
    }

    var canUndo: Bool { undoLabel != nil }

    /// Toolbar, tray and ⌘Z: cancel a pending completion first, else step the undo stack.
    func undoLast() {
        let stackIsNewer = closingBatches.last.map { pending in
            (log.first?.batch ?? pending.batch) > pending.batch && undoManager?.canUndo == true
        } ?? true
        if !stackIsNewer, let pending = closingBatches.popLast() {
            for id in pending.ids { settleTasks.removeValue(forKey: id)?.cancel() }
            withAnimation(style.ease(260)) {
                for id in pending.ids { closing[id] = nil }
            }
            markRestored(pending.ids)
            log.removeAll { $0.batch == pending.batch }
            showTray("Undid — \(pending.label)", icon: "arrow.uturn.backward", tone: .neutral)
            undoRevision += 1
            return
        }
        guard let undoManager, undoManager.canUndo else { return }
        undoManager.undo()
    }

    func registerUndo(_ label: String, undo: @escaping @MainActor (Workbench) -> Void,
                      redo: @escaping @MainActor (Workbench) -> Void) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { workbench in
            MainActor.assumeIsolated {
                undo(workbench)
                workbench.registerUndo(label, undo: redo, redo: undo)
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
        let names: [Notification.Name] = [.NSUndoManagerDidCloseUndoGroup, .NSUndoManagerDidRedoChange,
                                          .NSUndoManagerCheckpoint]
        for name in names {
            undoObservers.append(center.addObserver(forName: name, object: undoManager, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.undoRevision += 1 }
            })
        }
        undoObservers.append(center.addObserver(forName: .NSUndoManagerDidUndoChange, object: undoManager,
                                                queue: .main) { [weak self, weak undoManager] _ in
            MainActor.assumeIsolated {
                guard let self, let undoManager else { return }
                self.didUndo(named: undoManager.redoActionName)
            }
        })
    }

    private func didUndo(named name: String) {
        undoRevision += 1
        guard let first = log.first else { return }
        // Only design actions have log entries; text-editing undo leaves the log alone.
        let matches = first.label == name || name.hasPrefix("Complete") || name == "Move to Trash"
        guard matches else { return }
        let ids = log.filter { $0.batch == first.batch }.compactMap(\.taskID)
        log.removeAll { $0.batch == first.batch }
        markRestored(ids)
        showTray("Undid — \(first.label)", icon: "arrow.uturn.backward", tone: .neutral)
    }

    // MARK: Flashes

    func flash(_ keyPath: ReferenceWritableKeyPath<Workbench, Set<UUID>>, _ ids: [UUID], for milliseconds: Double) {
        guard !ids.isEmpty else { return }
        let key = "\(keyPath.hashValue)"
        self[keyPath: keyPath].formUnion(ids)
        flashTasks[key]?.cancel()
        flashTasks[key] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(milliseconds)))
            guard !Task.isCancelled, let self else { return }
            withAnimation(self.style.ease(400)) { self[keyPath: keyPath].subtract(ids) }
        }
    }

    func markRestored(_ ids: [UUID]) { flash(\.restored, ids, for: 900) }

    func pulse(list listID: UUID?) {
        guard let listID else { return }
        pulseListID = listID
        pulseRevision += 1
        let revision = pulseRevision
        flashTasks["pulseList"]?.cancel()
        flashTasks["pulseList"] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1100))
            guard !Task.isCancelled, let self, self.pulseRevision == revision else { return }
            self.pulseListID = nil
        }
    }

    func pulseCheck(_ id: UUID) {
        guard style.lively else { return }
        pulseTaskID = id
        flashTasks["pulseTask"]?.cancel()
        flashTasks["pulseTask"] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, let self else { return }
            self.pulseTaskID = nil
        }
    }

    func flashBlock(_ taskID: UUID) {
        freshBlockTaskID = taskID
        flashTasks["freshBlock"]?.cancel()
        flashTasks["freshBlock"] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1400))
            guard !Task.isCancelled, let self else { return }
            withAnimation(self.style.ease(400)) { self.freshBlockTaskID = nil }
        }
    }

    // MARK: Completion dwell

    /// Starts the visible completion: pop, strike, then settle after the dwell.
    func beginClosing(_ tasks: [Block], label: String, batch: Int) {
        let ids = tasks.map(\.id)
        closingBatches.append((batch, label, ids))
        undoRevision += 1
        for (index, task) in tasks.enumerated() {
            let id = task.id
            let stagger = Double(index) * ms(75)
            settleTasks[id]?.cancel()
            settleTasks[id] = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(Int(stagger)))
                guard !Task.isCancelled, let self else { return }
                withAnimation(self.style.spring(260)) { self.closing[id] = false }
                if index == 0 { self.pulseCheck(id) }
                try? await Task.sleep(for: .milliseconds(Int(self.ms(130))))
                guard !Task.isCancelled else { return }
                withAnimation(self.style.ease(340)) { self.closing[id] = true }
                try? await Task.sleep(for: .milliseconds(Int(self.style.dwell * 1000 + 300)))
                guard !Task.isCancelled else { return }
                self.settle(id)
            }
        }
    }

    func cancelClosing(_ ids: [UUID]) {
        for id in ids { settleTasks.removeValue(forKey: id)?.cancel() }
        withAnimation(style.ease(240)) { for id in ids { closing[id] = nil } }
        for index in closingBatches.indices.reversed() {
            closingBatches[index].ids.removeAll(where: ids.contains)
            if closingBatches[index].ids.isEmpty {
                log.removeAll { $0.batch == closingBatches[index].batch }
                closingBatches.remove(at: index)
            }
        }
        undoRevision += 1
    }

    private func settle(_ id: UUID) {
        settleTasks[id] = nil
        let label = closingBatches.first(where: { $0.ids.contains(id) })?.label
        for index in closingBatches.indices.reversed() {
            closingBatches[index].ids.removeAll { $0 == id }
            if closingBatches[index].ids.isEmpty { closingBatches.remove(at: index) }
        }
        if let task = store.block(id: id), !task.isCompleted {
            if calendar.activeSession?.taskID == id { calendar.complete(task: task) }
            else { store.toggleCompletion(task) }
            if let label { undoManager?.setActionName(label) }
        }
        withAnimation(style.ease(320)) { closing[id] = nil }
        undoRevision += 1
    }

    /// Settles every pending completion immediately — used before quitting.
    func flushClosings() {
        for id in Array(settleTasks.keys) {
            settleTasks[id]?.cancel()
            settle(id)
        }
    }

    func bumpUndo() { undoRevision += 1 }

    func nextBatch() -> Int {
        batchCounter += 1
        return batchCounter
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

struct TasksPillFilter: Equatable {
    var when: String?
    var listID: UUID?
    var labelID: UUID?
    var only: String?

    var isEmpty: Bool { when == nil && listID == nil && labelID == nil && only == nil }
}
