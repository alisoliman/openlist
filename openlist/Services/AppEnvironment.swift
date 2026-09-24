//
//  AppEnvironment.swift
//  openlist
//

import AppKit
import Foundation
import SwiftData
import SwiftUI

/// A picker inside the inspector that a keyboard shortcut can summon.
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
    /// Keeps the widget's shared snapshot up to date.
    private let widgetPublisher: WidgetSnapshotPublisher
    /// Applies what widget checkboxes and buttons ask for.
    private let widgetActions: WidgetActionApplier
    /// Retained so the notification centre keeps a live delegate.
    private let notificationDelegate = NotificationDelegate()
    private let calendarNotifications: CalendarNotificationBridge
    private var hasBootstrapped = false
    @ObservationIgnored private var notificationActivityObserver: NSObjectProtocol?
    @ObservationIgnored private var derivedRecoveryTask: Task<Void, Never>?
    @ObservationIgnored private var widgetCalendarSignature: [String] = []

    var templateCopyRequest: TemplateCopyRequest?

    /// Where a widget tap asked to go, awaiting the main window.
    var pendingWidgetRoute: WidgetRoute?

    /// Work ▸ Show Work asked for the Work panel as it opened the main window,
    /// so its toolbar shows the panel once up. The window's closing clears it.
    @ObservationIgnored var showsWorkPanelOnOpen = false

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

    /// Which picker the inspector should pop open, set by ⇧⌘D / ⇧⌘L.
    var requestedPicker: DetailPicker?

    /// The document menu commands apply to: the list document on show, which
    /// claims it, or `nil` on the other screens, whose targets are the
    /// workbench's.
    var activeDocument: DocumentContext?

    /// Whether the main window is key. The Task menu acts on that window's
    /// rows, so it stays off while Quick Add or Settings has the keyboard.
    var isMainWindowKey = false

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
        widgetPublisher = WidgetSnapshotPublisher(store: store, libraryID: libraryID)
        calendarNotifications = CalendarNotificationBridge(store: store, calendar: calendar, navigator: navigator)
        workbench = Workbench(store: store, navigator: navigator, settings: settings, calendar: calendar,
                              defaults: ReviewSession.defaults)
        widgetActions = WidgetActionApplier(store: store, workbench: workbench, calendar: calendar, publisher: widgetPublisher)
        assert(WidgetRoute.scheme == LocalLink.scheme, "Widget routes and item links share the app's URL scheme")

        widgetPublisher.settingsCalendar = { [weak settings] in settings?.calendar ?? .current }
        let widgetCalendar = WidgetCalendarFeed(store: store, calendar: calendar) { [weak settings] in settings?.calendar ?? .current }
        widgetPublisher.calendarFeed = { widgetCalendar($0) }

        calendar.onNudgesChanged = { [weak calendarNotifications] in calendarNotifications?.update() }

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
        }
        store.onDidSave = { [weak widgetPublisher, weak calendar] in
            widgetPublisher?.scheduleRefresh()
            calendar?.storeDidChange()
        }
        sync.onRemoteChange = { [weak self] in self?.refreshAfterRemoteChange() }
        installNotificationDelegate()
        notificationActivityObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.store.refreshAllReminders()
                    NotificationService.shared.reminders.refresh()
                    if self?.hasBootstrapped == true { self?.widgetActions.drainQueue() }
                }
            }
        // Registered before any intent can run in this process: App.init builds
        // the environment. Launched only to run one, the app bootstraps first.
        widgetActions.bootstrap = { [weak self] in self?.bootstrap() }
        WidgetActionDispatcher.performer = { [weak self] action in await self?.widgetActions.apply(action) }
        widgetActions.startWatching()
    }

    /// Republishes the widget snapshot when what Up Next and Agenda show
    /// changes without a save: the plan, the timer, meetings, the week's start.
    /// Starts at bootstrap, then follows each change it sees.
    private func watchCalendarForWidgets() {
        let signature = withObservationTracking {
            calendar.visibleBlocks.map { block in
                // The running block's end moves with each heartbeat; the widget
                // only sees it by the quarter hour.
                let end = block.isActive ? WidgetCalendarFeed.quarter(after: block.end) : block.end
                return "\(block.id)|\(block.start.timeIntervalSinceReferenceDate)|\(end.timeIntervalSinceReferenceDate)|\(block.isCompleted)"
            }
                + calendar.plan.blocks.map { "p\($0.id)|\($0.start.timeIntervalSinceReferenceDate)" }
                + ["\(calendar.activeSession?.id.uuidString ?? "-")", "\(calendar.resumeTaskID?.uuidString ?? "-")",
                   // Bumped by every calendar change, a meeting moved or renamed included.
                   "\(calendar.externalCalendars.revision)", "\(settings.firstWeekday)"]
        } onChange: { [weak self] in
            Task { @MainActor in self?.watchCalendarForWidgets() }
        }
        defer { widgetCalendarSignature = signature }
        guard signature != widgetCalendarSignature else { return }
        widgetPublisher.scheduleRefresh()
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
    /// On Today the task it makes is due today.
    func presentTaskCapture(text: String = "") {
        workbench.openCapture(text: text)
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
        // After the calendar: its monitor pauses running work first when
        // Openlist quits, so the widget's last snapshot shows it paused.
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.widgetPublisher.refreshNow() }
        }
        // Ticks made in widgets while Openlist was closed, then the snapshot
        // with the work, the plan and the week the calendar has just loaded.
        widgetActions.drainQueue()
        watchCalendarForWidgets()
        widgetPublisher.refreshNow()
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
    /// Every Copy Link, from a menu or Task ▸: the link on the clipboard and
    /// "Link copied" in the tray, or the link notice saying why there is none.
    func copyLink(to target: LocalLink.Target) {
        // An earlier link's error would otherwise hide this copy's result.
        localLinks.error = nil
        do {
            let url = try localLinks.link(to: target)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([url as NSURL])
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
            workbench.showTray("Link copied", icon: "link")
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

    /// Moves the list to Trash as one change with Undo in the tray, stepping
    /// off it if it is the one on screen.
    func performDeleteList(_ list: TaskList) {
        listPendingDeletion = nil
        workbench.trashList(list)
    }

    /// Opens a task in the inspector with one of its pickers already showing.
    func openTask(_ id: UUID, showing picker: DetailPicker?) {
        requestedPicker = picker
        navigator.openTask(id)
    }
}
