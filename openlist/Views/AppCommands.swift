//
//  AppCommands.swift
//  openlist
//

import SwiftUI

/// Context-aware macOS commands; capture is available from every screen.
struct AppCommands: Commands {
    let env: AppEnvironment

    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // Each Task item reads the same targets, so resolve them once per update.
        // Only a single target is fetched; RootView resolves the rest on use.
        let targets = taskTargetIDs
        let single = singleTask(among: targets)

        CommandMenu("Work") {
            Button("Show Work") { env.calendar.showWork() }
            Button("Start Selected Task") {
                if let task = workTask(singleTask(among: taskTargetIDs)) {
                    env.calendar.requestWork(WorkTaskReference(task))
                }
            }.disabled(workTask(single) == nil)
            Divider()
            Button("Stop Current Session") { env.calendar.stopWorking(); env.calendar.showWork() }
                .disabled(env.calendar.activeSession == nil)
            Button("Resume Task") { env.calendar.resume() }
                .disabled(env.calendar.activeSession != nil || env.calendar.resumableTask == nil)
            Button("Complete Current Task") {
                if let id = env.calendar.activeSession?.taskID, let task = env.store.block(id: id) {
                    env.calendar.complete(task: task); env.calendar.showWork()
                }
            }.disabled(env.calendar.activeSession == nil)
        }
        // Openlist ▸ Settings… opens the Settings page in the main window;
        // there is no Settings window.
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { showSettings() }
                .keyboardShortcut(",", modifiers: .command)
        }
        // File ▸ replaces the template "New Window" with task and list creation.
        CommandGroup(replacing: .newItem) {
            Button("New Task…") {
                openWindow(id: WindowID.main)
                env.presentTaskCapture()
                NSApp.activate(ignoringOtherApps: true)
            }
                .keyboardShortcut("n", modifiers: .command)

            Button("New List") { newList() }
                .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("New Section") { _ = env.store.createSection() }
                .keyboardShortcut("n", modifiers: [.command, .option])

            Divider()

            Button("Quick Add…") { QuickCapturePanel.shared.show() }
                .keyboardShortcut(.space, modifiers: [.shift, .option])
        }

        CommandGroup(after: .newItem) {
            Divider()
            Button("Export List as Markdown…") { exportCurrentList() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(env.navigator.route.listID == nil)
        }

        // Edit ▸ find.
        CommandGroup(after: .textEditing) {
            Divider()
            Button("Search") { env.navigator.isSearchOpen = true }
                .keyboardShortcut("f", modifiers: .command)

            Button("Quick Command") { env.navigator.isCommandPaletteOpen = true }
                .keyboardShortcut("k", modifiers: .command)
        }

        // Format ▸ inline styling. These actions travel the responder chain to
        // the focused block editor, which implements the selectors itself.
        CommandMenu("Format") {
            Button("Bold") { sendToResponder("toggleBold:") }
                .keyboardShortcut("b", modifiers: .command)
            Button("Italic") { sendToResponder("toggleItalic:") }
                .keyboardShortcut("i", modifiers: .command)
            Button("Strikethrough") { sendToResponder("toggleStrikethrough:") }
                .keyboardShortcut("x", modifiers: [.command, .shift])
            Button("Inline Code") { sendToResponder("toggleInlineCode:") }
                .keyboardShortcut("e", modifiers: .command)
            Button("Add Link…") { sendToResponder("promptForLink:") }
                .keyboardShortcut("l", modifiers: .command)

            Divider()

            Button("Indent") { env.send(.indent) }
                .keyboardShortcut("]", modifiers: [.command, .option])
                .disabled(!hasDocumentContext || !hasBlockSelection)
            Button("Outdent") { env.send(.outdent) }
                .keyboardShortcut("[", modifiers: [.command, .option])
                .disabled(!hasDocumentContext || !hasBlockSelection)
            Button("Move Up") { env.send(.moveUp) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                .disabled(!hasDocumentContext || !hasBlockSelection)
            Button("Move Down") { env.send(.moveDown) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                .disabled(!hasDocumentContext || !hasBlockSelection)
        }

        // Task ▸ everything that acts on the current targets. Items that open
        // one task's details need exactly one; the rest take every target.
        CommandMenu("Task") {
            Button("Complete / Reopen") { env.send(.toggleCompletion) }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(targets.isEmpty)
            Button("Open Details") { env.send(.openDetails) }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(single == nil)

            Divider()

            Button("Due Today") { env.send(.setDueToday) }
                .keyboardShortcut("t", modifiers: .control)
                .disabled(targets.isEmpty)
            Button("Add Due Date…") { env.send(.pickDueDate) }
                .keyboardShortcut("d", modifiers: .control)
                .disabled(single == nil)
            Button("Clear Due Date") { env.send(.clearDueDate) }
                .keyboardShortcut("d", modifiers: [.control, .shift])
                .disabled(targets.isEmpty)

            Divider()

            Button("Add Label…") { env.send(.pickLabel) }
                .keyboardShortcut("l", modifiers: .control)
                .disabled(single == nil)
            Button("Clear Labels") { env.send(.clearLabels) }
                .keyboardShortcut("l", modifiers: [.control, .shift])
                .disabled(targets.isEmpty)
            Button("Toggle Star") { env.send(.toggleStar) }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(targets.isEmpty)

            Divider()

            // Deliberately no key equivalent: AppKit matches menu shortcuts
            // before the text view sees the event, so ⌘⌫ here would delete the
            // task instead of the line the user was editing.
            Button("Delete Task", role: .destructive) { env.send(.deleteSelection) }
                .disabled(targets.isEmpty)
        }

        // View ▸ navigation, in sidebar order.
        CommandGroup(before: .sidebar) {
            Button("Inbox") { env.workbench.go(.inbox) }
                .keyboardShortcut("1", modifiers: .command)
            Button("Today") { env.workbench.go(.today) }
                .keyboardShortcut("2", modifiers: .command)
            Button("Calendar") { env.workbench.go(.calendar) }
                .keyboardShortcut("3", modifiers: .command)
            Button("Tasks") { env.workbench.go(.tasks) }
                .keyboardShortcut("4", modifiers: .command)
            Button("Lists") { env.workbench.go(.lists) }
                .keyboardShortcut("5", modifiers: .command)
            Button("Activity") { env.workbench.go(.activity) }
                .keyboardShortcut("6", modifiers: .command)
            Button("Trash") { env.workbench.go(.trash) }

            Divider()

            Button("Back") { env.navigator.goBack() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(!env.navigator.canGoBack)
            Button("Forward") { env.navigator.goForward() }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(!env.navigator.canGoForward)

            Divider()

            Button(env.workbench.showsSidebar ? "Hide Sidebar" : "Show Sidebar") { env.workbench.toggleSidebar() }
                .keyboardShortcut("s", modifiers: [.control, .command])

            Divider()

            Button("Expand All") { env.send(.expandAll) }
                .disabled(!hasDocumentContext)
            Button("Collapse All") { env.send(.collapseAll) }
                .disabled(!hasDocumentContext)

            Divider()
        }

        CommandGroup(replacing: .help) {
            Button("Keyboard Shortcuts") { env.navigator.isShortcutSheetOpen = true }
                .keyboardShortcut("/", modifiers: .command)
        }
    }

    /// What the Task menu acts on, only while the main window is key. A
    /// document editor that has claimed commands keeps its single selected
    /// task; the Next screens use the workbench targets (selection, focused
    /// row, inspected task) that `RootView.handleGlobalCommand` runs on.
    private var taskTargetIDs: [UUID] {
        guard env.isMainWindowKey, !env.workbench.captureOpen, !env.navigator.isCommandPaletteOpen,
              !env.navigator.isSearchOpen, !env.navigator.isShortcutSheetOpen else { return [] }
        guard env.activeDocument != nil else { return env.workbench.targetIDs }
        guard env.navigator.selection.count == 1, let id = env.navigator.selection.first,
              env.store.block(id: id)?.isTask == true else { return [] }
        return [id]
    }

    /// The only target, when it is a task.
    private func singleTask(among ids: [UUID]) -> Block? {
        guard ids.count == 1, let task = env.store.block(id: ids[0]), task.isTask else { return nil }
        return task
    }

    /// The task, when it can start a Work session.
    private func workTask(_ task: Block?) -> Block? {
        task.flatMap { env.calendar.validWorkTask(WorkTaskReference($0)) }
    }

    private var hasBlockSelection: Bool {
        !env.workbench.captureOpen && !env.navigator.isCommandPaletteOpen
            && env.navigator.selection.count == 1 && env.navigator.selection.contains { env.store.block(id: $0) != nil }
    }

    private var hasDocumentContext: Bool {
        env.activeDocument != nil && (env.navigator.hasDocumentEditor || env.navigator.openTaskID != nil)
    }

    // MARK: - Actions

    /// Dispatches a formatting action down the responder chain to whichever
    /// block editor currently has focus.
    private func sendToResponder(_ selectorName: String) {
        NSApp.sendAction(Selector((selectorName)), to: nil, from: nil)
    }

    /// The main window's Settings page, over whatever was open. With the main
    /// window key, NextKeyMonitor takes ⌘, before the menu does.
    private func showSettings() {
        openWindow(id: WindowID.main)
        if env.workbench.captureOpen { env.workbench.closeCapture() }
        env.workbench.go(.settings)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// The same list the sidebar's New list makes, with its tray and undo.
    private func newList() {
        env.workbench.createList()
    }

    private func exportCurrentList() {
        guard
            let listID = env.navigator.route.listID,
            let list = env.store.list(id: listID)
        else { return }
        MarkdownExporter.presentSavePanel(for: list, store: env.store)
    }
}
