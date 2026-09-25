//
//  AppEnvironment.swift
//  openlist
//

import AppKit
import Foundation
import Observation
import SwiftData
import SwiftUI

/// A picker inside the task detail panel that a keyboard shortcut can summon.
enum DetailPicker: String, Identifiable {
    case due, repeatRule, reminder, labels
    var id: String { rawValue }
}

/// One-shot instructions sent from menus and shortcuts down into whichever
/// document view is on screen.
enum EditorCommand: Equatable {
    case newTask
    case toggleCompletion
    case openDetails
    case setDueToday
    case pickDueDate
    case clearDueDate
    case pickLabel
    case clearLabels
    case toggleStar
    case indent
    case outdent
    case moveUp
    case moveDown
    case deleteSelection
    case expandAll
    case collapseAll
}

/// The objects every view needs, created once and injected into all scenes.
@Observable
@MainActor
final class AppEnvironment {
    let store: Store
    let navigator: Navigator
    let reminderNavigation: ReminderNavigation
    let localLinks: LocalLinkNavigation
    let settings: AppSettings
    let sync: ICloudSyncMonitor
    let calendar: CalendarCoordinator
    let mcp: MCPIntegration
    let workbench: Workbench
    let libraryMaintenance: LibraryMaintenance?
    /// Takes widget clicks to their screen once the library and window are ready.
    let widgetLinks: WidgetLinkRouter
    /// Keeps the widget's shared snapshot up to date.
    private let widgetPublisher: WidgetSnapshotPublisher
    /// Applies widget buttons: ticking tasks off and the work timer.
    private let widgetCommands: WidgetCommandProcessor
    /// Retained so the notification centre keeps a live delegate.
    private let notificationDelegate = NotificationDelegate()
    private let calendarNotifications: CalendarNotificationBridge
    private var hasBootstrapped = false
    @ObservationIgnored private var notificationActivityObserver: NSObjectProtocol?
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?
    @ObservationIgnored private var derivedRecoveryTask: Task<Void, Never>?

    var templateCopyRequest: TemplateCopyRequest?

    /// What the Quick Add window captures into. A widget's "Add to …" sets it
    /// just before opening the window, and the window puts back a plain
    /// capture when it closes, so the menu and the shortcut never inherit it.
    var quickAddRequest = TaskCaptureRequest()
    /// Opens the Quick Add window. Installed by the main window: widget links
    /// arrive through its scene, and only a view can open windows. So a
    /// widget's Quick Add brings the main window forward as well; see
    /// `WidgetLinkRouter`.
    @ObservationIgnored var openQuickAdd: (() -> Void)?

    /// A command awaiting pickup by the focused document view.
    var pendingCommand: EditorCommand?
    /// Bumped to make the focused document re-read `pendingCommand` even when
    /// the same command is issued twice in a row.
    private(set) var commandToken: Int = 0

    /// A list awaiting the user's confirmation before deletion. Every delete
    /// affordance routes through ``requestDeleteList(_:)`` so the preference is
    /// honoured everywhere rather than only in the sidebar.
    var listPendingDeletion: TaskList?
    var listPendingMove: TaskList?

    /// Which picker the task detail panel should pop open, set by ⌃D / ⌃L.
    var requestedPicker: DetailPicker?

    /// The document menu commands apply to. Several `DocumentView`s can be on
    /// screen at once — a list plus an open task's detail page — so exactly one
    /// of them claims each command.
    var activeDocument: DocumentContext?

    /// Whether the main window is key. The Task menu acts on that window's
    /// rows, so it stays off while Quick Add or Settings has the keyboard.
    var isMainWindowKey = false

    /// Only captures created by the empty-title flow can be removed on cancel.
    /// Keeping their inherited defaults distinguishes them from existing blank
    /// tasks and from a new task the user has already given meaningful details.
    @ObservationIgnored private var pendingTitleCaptures: [UUID: PendingTitleCapture] = [:]

    init(context: ModelContext, sync: ICloudSyncMonitor,
         libraryID: UUID? = nil, libraryStorage: LibraryRestoreStorage? = nil, libraryStartup: LibraryRestoreStorage.Startup? = nil) {
        let store = Store(context: context)
        let settings = AppSettings()
        self.store = store
        self.settings = settings
        self.sync = sync
        if let libraryStorage, let libraryStartup {
            libraryMaintenance = LibraryMaintenance(store: store, storage: libraryStorage, startup: libraryStartup)
        } else {
            libraryMaintenance = nil
        }
        calendar = CalendarCoordinator(store: store)
        mcp = MCPIntegration(store: store, settings: settings)
        navigator = Navigator(defaults: ReviewSession.defaults)
        reminderNavigation = ReminderNavigation(navigator: navigator)
        localLinks = LocalLinkNavigation(libraryID: libraryID, navigator: navigator)
        widgetPublisher = WidgetSnapshotPublisher(store: store,
            sources: .live(calendar: calendar, settings: settings, libraryID: libraryID))
        calendarNotifications = CalendarNotificationBridge(store: store, calendar: calendar, navigator: navigator)
        workbench = Workbench(store: store, navigator: navigator, settings: settings, calendar: calendar)
        widgetLinks = WidgetLinkRouter(store: store, navigator: navigator, screens: workbench)
        widgetCommands = WidgetCommandProcessor(store: store, calendar: calendar, publisher: widgetPublisher)

        calendar.onNudgesChanged = { [weak calendarNotifications] in calendarNotifications?.update() }
        // The plan and the running session change without a save. Debounced,
        // because one Start or Pause reports several times on its way through.
        calendar.onWidgetStateChange = { [weak widgetPublisher] in widgetPublisher?.scheduleRefresh() }

        store.onLabelsMerged = { [weak navigator] sourceID, destinationID in
            navigator?.retargetLabel(from: sourceID, to: destinationID)
        }
        store.onEditorBlocksRemoved = { [weak self] ids in
            guard let self else { return }
            navigator.selection.subtract(ids)
            if let taskID = navigator.openTaskID, ids.contains(taskID) {
                requestedPicker = nil
                navigator.closeTask()
            }
            if let rootID = activeDocument?.rootBlockID, ids.contains(rootID) {
                activeDocument = nil
            }
        }
        store.onDidSave = { [weak widgetPublisher, weak calendar] in
            widgetPublisher?.scheduleRefresh()
            calendar?.storeDidChange()
        }
        sync.onRemoteChange = { [weak self] in self?.refreshAfterRemoteChange() }
        installNotificationDelegate()
        installWidgetActions()
        notificationActivityObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.store.refreshAllReminders()
                    NotificationService.shared.reminders.refresh()
                    if self?.hasBootstrapped == true { self?.widgetCommands.drainQueue() }
                }
            }
        watchWidgetSettings()
    }

    /// Lets widget buttons and links reach the app. The command handler goes
    /// in first thing, because an intent can be what launched the app; it
    /// bootstraps before applying anything.
    private func installWidgetActions() {
        widgetCommands.prepare = { [weak self] in self?.bootstrap() }
        widgetCommands.settleWindowCompletion = { [weak workbench] id in
            if workbench?.closing[id] != nil { workbench?.flushClosings() }
        }
        WidgetCommandRouter.handler = { [weak widgetCommands] command in widgetCommands?.handle(command) }
        widgetLinks.capture = { [weak self] request in self?.presentQuickAdd(request) }
    }

    /// Refreshes the widgets when a setting they mirror changes: the accent,
    /// serif titles, and the first weekday their weeks start on. Settings are
    /// not saved through the Store, so no save announces them. Runs from init,
    /// then again after each change it sees.
    private func watchWidgetSettings() {
        withObservationTracking {
            _ = (settings.accent, settings.serifTitles, settings.firstWeekday)
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.widgetPublisher.scheduleRefresh()
                self?.watchWidgetSettings()
            }
        }
    }

    /// Wires notification handling once the environment is fully built.
    private func installNotificationDelegate() {
        notificationDelegate.onCalendarAction = { [weak calendarNotifications] action, identifier, taskID, occurrenceID in
            calendarNotifications?.handle(action: action, identifier: identifier, taskID: taskID, occurrenceID: occurrenceID)
        }
        notificationDelegate.onOpenTask = { [weak self] id in
            self?.reminderNavigation.receive(id)
            NSApp.activate(ignoringOtherApps: true)
        }
        NotificationService.shared.install(delegate: notificationDelegate)
    }

    func send(_ command: EditorCommand) {
        if command == .newTask {
            presentTaskCapture()
            return
        }
        pendingCommand = command
        commandToken &+= 1
    }

    /// ⌘N and the screens' Add buttons. The capture lives on the workbench, so
    /// a main window opened for it shows the capture as soon as it appears.
    /// On Calendar the workbench plans the task for today by itself.
    func presentTaskCapture(text: String = "") {
        workbench.openCapture(text: text)
    }

    /// Opens the Quick Add window for `request`. A window already open keeps
    /// what has been typed and moves to the request's list.
    func presentQuickAdd(_ request: TaskCaptureRequest) {
        quickAddRequest = request
        openQuickAdd?()
    }

    /// Opens an Openlist link, whether a widget sent it or someone put it in
    /// their own text, such as a task note. A widget's link goes where the
    /// widget would take you. Anything else, including a widget link this
    /// build cannot open, is read as an item link, whose notice says what is
    /// wrong with it: a link that silently does nothing explains nothing.
    func openLink(_ url: URL) {
        if !widgetLinks.receive(url) { localLinks.receive(url) }
    }

    func showCopiedTask(id: UUID, listID: UUID) {
        navigator.go(to: .list(listID))
        navigator.selection = [id]
        navigator.openTask(id)
    }

    func consumeCommand() -> EditorCommand? {
        defer { pendingCommand = nil }
        return pendingCommand
    }

    /// Process-wide setup, including menu-bar-only launches. Samples are limited
    /// to isolated review fixtures so another Mac cannot duplicate demo content.
    func bootstrap() {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        store.bootstrap()
        if sync.state.isEnabled {
            store.prepareForSync()
        } else if libraryMaintenance?.isLocalRestore != true,
                  ReviewSession.identifier != nil, !settings.hasSeededSampleData,
                  store.allLists(includeArchived: true).allSatisfy(\.isSystemInbox),
                  (try? store.context.fetchCount(FetchDescriptor<Block>())) == 0 {
            SampleData.seed(into: store)
            if store.persistenceError == nil { settings.hasSeededSampleData = true }
        }
        store.refreshAllReminders()
        navigator.inboxListID = store.inboxList()?.id
        navigator.replace(with: .today)
        reminderNavigation.storeReady { [weak store] id in
            guard let store, let task = store.block(id: id), task.isTask,
                  let list = store.list(id: task.listID) else { throw ContentReveal.Unavailable.deleted }
            return try ContentReveal.resolve(.block(id), blocks: store.blocks(inList: list.id), lists: store.allLists(includeArchived: true))
        }
        sync.checkAccount()
        if sync.state.isEnabled { NSApplication.shared.registerForRemoteNotifications() }
        calendar.bootstrap()
        // After the calendar, so the first snapshot has the day's plan and the
        // work the last run left paused.
        widgetPublisher.refreshNow()
        // Registered after the calendar's own observer, which pauses running
        // work as the app quits, so the widgets are left showing that pause.
        // The publisher writes running work as paused if it gets there first.
        terminationObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.widgetPublisher.prepareForTermination() }
            }
        calendarNotifications.update()
        mcp.start(storageAvailable: store.persistenceError == nil)
        if let library = libraryMaintenance,
           library.storage.needsDerivedReset(library.startup, defaults: ReviewSession.defaults) {
            derivedRecoveryTask = Task { [weak self] in
                let recovery = NotificationService.shared.reminders
                await recovery.waitUntilIdle()
                guard let self, !Task.isCancelled else { return }
                library.storage.finishDerivedReset(library.startup, defaults: ReviewSession.defaults,
                    succeeded: store.persistenceError == nil && recovery.libraryReadError == nil
                        && recovery.recoveryError == nil)
            }
        }
        localLinks.storeReady { [weak store] target in
            guard let store else { throw LocalLinkError.targetUnavailable }
            return try LocalLinkNavigation.resolve(target,
                blocks: store.context.fetch(FetchDescriptor<Block>()),
                lists: store.context.fetch(FetchDescriptor<TaskList>()))
        }
        widgetLinks.storeReady()
        // Taps the extension queued while the app was not running.
        widgetCommands.listenForSignals()
        widgetCommands.drainQueue()
    }

    private func refreshAfterRemoteChange() {
        guard hasBootstrapped else { return }
        store.context.processPendingChanges()
        store.prepareForSync()
        // A synced Inbox from another Mac can win the merge and take over.
        navigator.inboxListID = store.inboxList()?.id
        store.refreshAllReminders()
        calendar.storeDidChange()
        widgetPublisher.refreshNow()
        if let taskID = navigator.openTaskID, store.block(id: taskID) == nil {
            navigator.closeTask()
        }
        if case let .list(id) = navigator.route {
            if let list = store.list(id: id) {
                if list.id != id { navigator.replace(with: .list(list.id)) }
            } else {
                navigator.replace(with: .today)
            }
        }
    }
}

// MARK: - Convenience

extension AppEnvironment {
    func copyLink(to target: LocalLink.Target) {
        do {
            let url = try localLinks.link(to: target)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([url as NSURL])
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
        } catch {
            localLinks.error = error as? LocalLinkError ?? .targetUnavailable
        }
    }

    /// Sugar so views can write `app.route` instead of reaching through the navigator.
    var route: AppRoute { navigator.route }

    /// Deletes a list, asking first when the user has asked to be asked.
    func requestDeleteList(_ list: TaskList) {
        guard !list.isSystemInbox else { return }
        if settings.confirmsBeforeDeletingLists {
            listPendingDeletion = list
        } else {
            performDeleteList(list)
        }
    }

    /// Deletes for real, and steps off the list if it is the one on screen.
    func performDeleteList(_ list: TaskList) {
        let ownedIDs = Set(store.listHierarchy().subtree(of: list.id).map(\.id))
        let wasOpen = navigator.route.listID.map(ownedIDs.contains) == true
        guard store.deleteList(list) else { return }
        if wasOpen { navigator.replace(with: .today) }
        listPendingDeletion = nil
    }

    /// Opens a task's detail panel with one of its pickers already showing.
    func openTask(_ id: UUID, showing picker: DetailPicker?) {
        requestedPicker = picker
        navigator.openTask(id)
    }

    func beginTaskTitleCapture(_ block: Block) {
        guard block.text.isEmpty else { return }
        pendingTitleCaptures[block.id] = PendingTitleCapture(block)
    }

    /// Ends one pending capture. Cancellation only removes a still-empty task
    /// whose data matches its initial defaults; existing tasks never enter here.
    func finishTaskTitleCapture(_ id: UUID, discardEmpty: Bool = false) {
        guard let initial = pendingTitleCaptures.removeValue(forKey: id),
              let block = store.block(id: id) else { return }
        let events = (try? store.context.fetch(FetchDescriptor<ActivityEvent>(
            predicate: #Predicate { $0.blockID == id }
        ))) ?? []
        if discardEmpty, initial.canDiscard(block, store: store) {
            store.deleteBlock(block)
            for event in events { store.context.delete(event) }
            navigator.selection.remove(id)
        } else {
            // The empty capture's creation event should display its final name.
            for event in events where event.kind == .created {
                event.title = block.displayTitle
            }
        }
        store.save()
    }

    /// Capture behaviour implied by the user's settings.
    var captureDefaults: CaptureDefaults {
        CaptureDefaults(
            parsesNaturalLanguage: settings.parsesNaturalLanguageDates,
            dueTodayWhenUndated: settings.defaultDestination == .today
        )
    }
}

/// Widget links land the way the main window's own navigation does.
extension Workbench: WidgetLinkScreens {}

private struct PendingTitleCapture {
    let listID: UUID?
    let parentID: UUID?
    let sortIndex: Double
    let dueDate: Date?
    let includesTime: Bool
    let labelIDs: [UUID]
    let selectedForDay: Date?
    let deferredUntil: Date?
    let estimate: Int
    let keepTogether: Bool
    let tracksAway: Bool
    let occurrenceID: UUID

    init(_ block: Block) {
        listID = block.listID
        parentID = block.parentID
        sortIndex = block.sortIndex
        dueDate = block.dueDate
        includesTime = block.includesTime
        labelIDs = block.labelIDs
        selectedForDay = block.selectedForDay
        deferredUntil = block.deferredUntil
        estimate = block.schedulingEstimateMinutes
        keepTogether = block.keepsSessionsTogether
        tracksAway = block.tracksAwayFromMac
        occurrenceID = block.occurrenceID
    }

    func canDiscard(_ block: Block, store: Store) -> Bool {
        guard block.isTask, block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              block.listID == listID, block.parentID == parentID, block.sortIndex == sortIndex,
              block.dueDate == dueDate, block.includesTime == includesTime, block.labelIDs == labelIDs,
              !block.isCompleted, block.completedAt == nil, !block.isStarred, block.priorityRaw == 0,
              block.reminderAt == nil, block.recurrenceData == nil, block.note.isEmpty,
              block.mediaFilename == nil, block.mediaCaption.isEmpty,
              block.selectedForDay == selectedForDay, block.deferredUntil == deferredUntil,
              block.schedulingEstimateMinutes == estimate, block.keepsSessionsTogether == keepTogether,
              block.tracksAwayFromMac == tracksAway, store.workSessions(taskID: block.id).isEmpty,
              block.occurrenceID == occurrenceID, store.completionRecords(taskID: block.id).isEmpty,
              store.placements(taskID: block.id).isEmpty,
              store.attachments(for: block.id).isEmpty,
              let listID, store.children(of: block.id, listID: listID).isEmpty
        else { return false }
        return true
    }
}
