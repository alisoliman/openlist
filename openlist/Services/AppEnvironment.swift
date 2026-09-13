//
//  AppEnvironment.swift
//  openlist
//

import AppKit
import Foundation
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
    case moveToInbox
    case removeFromList
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
    let settings: AppSettings
    let sync: ICloudSyncMonitor
    let calendar: CalendarCoordinator
    let mcp: MCPIntegration
    /// Keeps the widget's shared snapshot up to date.
    private let widgetPublisher: WidgetSnapshotPublisher
    /// Retained so the notification centre keeps a live delegate.
    private let notificationDelegate = NotificationDelegate()
    private let calendarNotifications: CalendarNotificationBridge
    private var hasBootstrapped = false

    /// A command awaiting pickup by the focused document view.
    var taskCaptureRequest: TaskCaptureRequest?

    var pendingCommand: EditorCommand?
    /// Bumped to make the focused document re-read `pendingCommand` even when
    /// the same command is issued twice in a row.
    private(set) var commandToken: Int = 0

    /// A list awaiting the user's confirmation before deletion. Every delete
    /// affordance routes through ``requestDeleteList(_:)`` so the preference is
    /// honoured everywhere rather than only in the sidebar.
    var listPendingDeletion: TaskList?

    /// Which picker the task detail panel should pop open, set by ⌃D / ⌃L.
    var requestedPicker: DetailPicker?

    /// The document menu commands apply to. Several `DocumentView`s can be on
    /// screen at once — a list plus an open task's detail page — so exactly one
    /// of them claims each command.
    var activeDocument: DocumentContext?

    /// Only captures created by the empty-title flow can be removed on cancel.
    /// Keeping their inherited defaults distinguishes them from existing blank
    /// tasks and from a new task the user has already given meaningful details.
    @ObservationIgnored private var pendingTitleCaptures: [UUID: PendingTitleCapture] = [:]

    init(context: ModelContext, sync: ICloudSyncMonitor) {
        let store = Store(context: context)
        let settings = AppSettings()
        self.store = store
        self.settings = settings
        self.sync = sync
        calendar = CalendarCoordinator(store: store)
        mcp = MCPIntegration(store: store, settings: settings)
        navigator = Navigator()
        widgetPublisher = WidgetSnapshotPublisher(store: store)
        calendarNotifications = CalendarNotificationBridge(store: store, calendar: calendar, navigator: navigator)

        calendar.onNudgesChanged = { [weak calendarNotifications] in calendarNotifications?.update() }

        store.onLabelsMerged = { [weak navigator] sourceID, destinationID in
            navigator?.retargetLabel(from: sourceID, to: destinationID)
        }
        store.onDidSave = { [weak widgetPublisher, weak calendar] in
            widgetPublisher?.scheduleRefresh()
            calendar?.storeDidChange()
        }
        sync.onRemoteChange = { [weak self] in self?.refreshAfterRemoteChange() }
    }

    /// Wires notification handling once the environment is fully built.
    private func installNotificationDelegate() {
        notificationDelegate.onCalendarAction = { [weak calendarNotifications] action, identifier, taskID, occurrenceID in
            calendarNotifications?.handle(action: action, identifier: identifier, taskID: taskID, occurrenceID: occurrenceID)
        }
        notificationDelegate.onOpenTask = { [weak self] id in
            guard let self, let block = store.block(id: id) else { return }
            if let listID = block.listID, store.list(id: listID) != nil {
                navigator.go(to: .list(listID))
            }
            navigator.openTask(id)
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

    func presentTaskCapture(text: String = "") {
        taskCaptureRequest = TaskCaptureRequest(
            text: text, suggestedListID: navigator.route.listID,
            plansForToday: navigator.route == .calendar
        )
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
        } else if ReviewSession.identifier != nil, !settings.hasSeededSampleData,
                  store.allLists(includeArchived: true).allSatisfy(\.isSystemInbox),
                  (try? store.context.fetchCount(FetchDescriptor<Block>())) == 0 {
            SampleData.seed(into: store)
            if store.persistenceError == nil { settings.hasSeededSampleData = true }
        }
        installNotificationDelegate()
        store.refreshAllReminders()
        navigator.replace(with: .today)
        widgetPublisher.refreshNow()
        sync.checkAccount()
        if sync.state.isEnabled { NSApplication.shared.registerForRemoteNotifications() }
        calendar.bootstrap()
        calendarNotifications.update()
        mcp.start(storageAvailable: store.persistenceError == nil)
    }

    private func refreshAfterRemoteChange() {
        guard hasBootstrapped else { return }
        store.context.processPendingChanges()
        store.prepareForSync()
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
        let wasOpen = navigator.route == .list(list.id)
        store.deleteList(list)
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
