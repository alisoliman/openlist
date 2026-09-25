//
//  AppEnvironment.swift
//  openlist
//

import AppKit
import Foundation
import Observation
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
    let calendarNotifications: CalendarNotificationBridge
    private var hasBootstrapped = false
    @ObservationIgnored private var notificationActivityObserver: NSObjectProtocol?
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?
    @ObservationIgnored private var derivedRecoveryTask: Task<Void, Never>?

    var templateCopyRequest: TemplateCopyRequest?

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
    /// Format ▸ Add Link…'s question, for the window's link sheet.
    var linkPrompt: LinkPrompt?

    /// Which picker the inspector should pop open, set by ⇧⌘D / ⇧⌘L.
    var requestedPicker: DetailPicker?

    /// The document menu commands apply to: the list document on show, which
    /// claims it, or `nil` on the other screens, whose targets are the
    /// workbench's.
    var activeDocument: DocumentContext?

    /// Whether the main window is key. The Task menu acts on that window's
    /// rows, so it stays off while Quick Add or the menu bar's popover has
    /// the keyboard.
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
        widgetPublisher = WidgetSnapshotPublisher(store: store,
            sources: .live(calendar: calendar, settings: settings, libraryID: libraryID))
        workbench = Workbench(store: store, navigator: navigator, settings: settings, calendar: calendar,
                              defaults: ReviewSession.defaults)
        calendarNotifications = CalendarNotificationBridge(store: store, calendar: calendar, workbench: workbench)
        widgetLinks = WidgetLinkRouter(store: store, navigator: navigator, screens: workbench)
        widgetCommands = WidgetCommandProcessor(store: store, calendar: calendar, publisher: widgetPublisher, actions: workbench)
        assert(WidgetLink.scheme == LocalLink.scheme, "Widget links and item links share the app's URL scheme")

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
        watchWidgetInputs()
    }

    /// Lets widget buttons and links reach the app. The command handler goes
    /// in first thing, because an intent can be what launched the app: App.init
    /// builds the environment, and the processor bootstraps before applying
    /// anything.
    private func installWidgetActions() {
        widgetCommands.prepare = { [weak self] in self?.bootstrap() }
        WidgetCommandRouter.handler = { [weak widgetCommands] command in widgetCommands?.handle(command) }
        // Quick Add floats over the app in front without activating Openlist.
        widgetLinks.capture = { request in QuickCapturePanel.shared.showFromWidget(request) }
        widgetLinks.activate = { NSApp.activate(ignoringOtherApps: true) }
        widgetLinks.unavailable = { [weak localLinks] in localLinks?.error = .targetUnavailable }
    }

    /// Refreshes the widgets when something they mirror changes without a
    /// save: the accent, serif titles, the first weekday their weeks start on,
    /// and the calendars, whose revision moves with every meeting added, moved
    /// or renamed, earlier in the week included. Runs from init, then again
    /// after each change it sees.
    private func watchWidgetInputs() {
        withObservationTracking {
            _ = (settings.accent, settings.serifTitles, settings.firstWeekday, calendar.externalCalendars.revision)
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.widgetPublisher.scheduleRefresh()
                self?.watchWidgetInputs()
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
        pendingCommand = command
        commandToken &+= 1
    }

    /// File ▸ New Task… (⌘N). The capture lives on the workbench, so a main
    /// window opened for it shows the capture as soon as it appears. On Today
    /// the task it makes is due today, as `openCapture` decides.
    func presentTaskCapture() {
        workbench.openCapture()
    }

    /// Opens an Openlist link, whether a widget sent it or someone put it in
    /// their own text, such as a task note, and returns whether it was a
    /// widget's. A widget's link goes where the widget would take you, and
    /// brings Openlist forward as it needs. Anything else, including a widget
    /// link this build cannot open, is read as an item link, whose notice says
    /// what is wrong with it: a link that silently does nothing explains nothing.
    @discardableResult
    func openLink(_ url: URL) -> Bool {
        if widgetLinks.receive(url) { return true }
        localLinks.receive(url)
        return false
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
    /// Every Copy Link, from a menu or Task ▸: the link on the clipboard and
    /// "Link copied" in the tray, or, drawn red as other failed actions are,
    /// the action notice saying why there is none. The link notice is for a
    /// link that can't open.
    func copyLink(to target: LocalLink.Target) {
        do {
            let url = try localLinks.link(to: target)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([url as NSURL])
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
            workbench.showTray("Link copied", icon: "link")
        } catch {
            // In the link notice's words: the library's identity, or the item gone.
            let reason: LocalLinkError = error as? LocalLinkError == .identityUnavailable ? .identityUnavailable : .targetUnavailable
            store.actionError = "The link was not copied. \(reason.localizedDescription)"
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
}
