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
    /// Keeps the widget's shared snapshot up to date.
    private let widgetPublisher: WidgetSnapshotPublisher
    /// Retained so the notification centre keeps a live delegate.
    private let notificationDelegate = NotificationDelegate()

    /// A command awaiting pickup by the focused document view.
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

    init(context: ModelContext) {
        let store = Store(context: context)
        let settings = AppSettings()
        self.store = store
        self.settings = settings
        navigator = Navigator()
        widgetPublisher = WidgetSnapshotPublisher(store: store)

        store.onDidSave = { [weak widgetPublisher] in
            widgetPublisher?.scheduleRefresh()
        }
        store.onDidCompleteTask = { [weak settings] _ in
            guard settings?.playsCompletionSound == true else { return }
            NSSound(named: "Tink")?.play()
        }
    }

    /// Wires notification handling once the environment is fully built.
    private func installNotificationDelegate() {
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
        pendingCommand = command
        commandToken &+= 1
    }

    func consumeCommand() -> EditorCommand? {
        defer { pendingCommand = nil }
        return pendingCommand
    }

    /// First-launch setup: system list, default section, sample content and
    /// re-registration of any reminders that survived a relaunch.
    func bootstrap() {
        store.bootstrap()
        if !settings.hasSeededSampleData {
            SampleData.seed(into: store)
            settings.hasSeededSampleData = true
        }
        installNotificationDelegate()
        store.refreshAllReminders()
        navigator.replace(with: .today)
        widgetPublisher.refreshNow()
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

    /// Capture behaviour implied by the user's settings.
    var captureDefaults: CaptureDefaults {
        CaptureDefaults(
            parsesNaturalLanguage: settings.parsesNaturalLanguageDates,
            dueTodayWhenUndated: settings.defaultDestination == .today
        )
    }
}
