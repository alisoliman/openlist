//
//  AppCommands.swift
//  openlist
//

import SwiftData
import SwiftUI

/// Context-aware macOS commands; capture is available from every screen.
struct AppCommands: Commands {
    let env: AppEnvironment

    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // Each Task item reads the same targets, so resolve them once per update:
        // a single target on its own, more in one fetch, for the titles.
        let targets = taskTargetIDs
        let single = singleTask(among: targets)
        let tasks = targets.count == 1 ? (single.map { [$0] } ?? []) : fetchTasks(targets)
        let reopens = !tasks.isEmpty && tasks.allSatisfy(env.workbench.isDoneOrClosing)
        let unstars = !tasks.isEmpty && tasks.allSatisfy(\.isStarred)

        CommandMenu("Work") {
            Button("Show Work") { env.calendar.showWork() }
            // As Task ▸ Start Working, the palette's and the row menu's: the
            // notch shows the work, and a failure the tray.
            Button("Start Selected Task") { act { env.workbench.startWork($0[0]) } }
                .disabled(workTask(single) == nil)
            Divider()
            // As the notch's ✕ and ✓: the Stopped tray, or the dwell and the
            // done tray with Undo, and the panel goes with them.
            Button("Stop Current Session") {
                env.calendar.isWorkPanelPresented = false
                env.workbench.stopWork()
            }
                .disabled(env.workbench.workTask == nil)
            // As the notch's ⏸ and ▶: in place, a failure in the tray.
            Button(env.workbench.isWorkPaused ? "Resume Task" : "Pause Task") { env.workbench.toggleWorkPause() }
                .disabled(env.workbench.workTask == nil)
            Button("Complete Current Task") {
                env.calendar.isWorkPanelPresented = false
                env.workbench.finishWork()
            }
                .disabled(env.workbench.workTask == nil)
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

            // The palette, named as the toolbar names it.
            Button("Actions…") { env.navigator.isCommandPaletteOpen = true }
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

        // Task ▸ everything that acts on the current targets, named as the
        // palette and the row menu name it. Items that open one task's
        // details need exactly one; the rest take every target. The design's
        // single keys (E, T, M, P, F, D) stay off the menu, since a menu key
        // equivalent would fire while typing; ⌘/ lists them. The keys here
        // carry ⌘ for the same reason: AppKit matches them before the text
        // view, and ⌃T, ⌃D or ⌃L would take its transpose, delete forward
        // and centre-the-line keys from the line being written.
        CommandMenu("Task") {
            Button(reopens ? "Reopen" : "Mark as Done") { env.send(.toggleCompletion) }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(targets.isEmpty)
            Button("Open Details") { env.send(.openDetails) }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(single == nil)

            Divider()

            Button("Due Today") { env.send(.setDueToday) }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(targets.isEmpty)
            Button("Due Tomorrow") { act { env.workbench.schedule($0, offset: 1) } }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(targets.isEmpty)
            Button("Add Due Date…") { env.send(.pickDueDate) }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(single == nil)
            Button("Clear Due Date") { env.send(.clearDueDate) }
                .keyboardShortcut("d", modifiers: [.command, .option, .shift])
                .disabled(targets.isEmpty)

            Divider()

            Button("Plan for Today") { act { env.workbench.plan($0) } }
                .disabled(targets.isEmpty)
            Button("Find a Slot") { act { $0.forEach(env.workbench.fit) } }
                .disabled(targets.isEmpty)
            Button("Start Working") { act { env.workbench.startWork($0[0]) } }
                .disabled(workTask(single) == nil)

            Divider()

            Button("Add Label…") { env.send(.pickLabel) }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(single == nil)
            Button("Clear Labels") { env.send(.clearLabels) }
                .keyboardShortcut("l", modifiers: [.command, .option, .shift])
                .disabled(targets.isEmpty)
            Button(unstars ? "Unstar" : "Star") { env.send(.toggleStar) }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(targets.isEmpty)
            Menu("Move to") {
                // The lists the window last drew, only while there is something to move.
                if !targets.isEmpty {
                    ForEach(env.workbench.drawnLists, id: \.id) { list in
                        NXListMenuButton(list: list) { act { env.workbench.move($0, to: list.id) } }
                    }
                }
            }
            .disabled(targets.isEmpty)

            Divider()

            // Deliberately no key equivalent: AppKit matches menu shortcuts
            // before the text view sees the event, so ⌘⌫ here would delete the
            // task instead of the line the user was editing.
            Button("Move to Trash", role: .destructive) { env.send(.deleteSelection) }
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

    /// What the Task menu acts on, only while the main window is key: the
    /// tasks the commands it sends would reach. The Next screens run them on
    /// the workbench targets (selection, focused row, inspected task), as
    /// `RootView.handleGlobalCommand` does; a list document on its own, the
    /// line being written first.
    private var taskTargetIDs: [UUID] {
        guard env.isMainWindowKey, !env.workbench.captureOpen, !env.navigator.isCommandPaletteOpen,
              !env.navigator.isSearchOpen, !env.navigator.isShortcutSheetOpen else { return [] }
        guard let active = env.activeDocument else { return env.workbench.targetIDs }
        // Only the document that claimed them runs the commands.
        guard let document = env.workbench.document, document.document == active else { return [] }
        return document.commandTaskIDs
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

    /// The target tasks in one fetch.
    private func fetchTasks(_ ids: [UUID]) -> [Block] {
        guard !ids.isEmpty else { return [] }
        let descriptor = FetchDescriptor<Block>(predicate: #Predicate { ids.contains($0.id) && $0.trashID == nil })
        return ((try? env.store.context.fetch(descriptor)) ?? []).filter(\.isTask)
    }

    /// Runs a Workbench action on the targets as they are when the item is
    /// chosen, after the list document's line being written, as its own step:
    /// the order a command the document receives runs in.
    private func act(_ body: ([UUID]) -> Void) {
        env.workbench.document?.commitLine()
        let ids = env.workbench.tasks(taskTargetIDs).map(\.id)
        guard !ids.isEmpty else { return }
        body(ids)
    }

    private var hasBlockSelection: Bool {
        guard !env.workbench.captureOpen, !env.navigator.isCommandPaletteOpen else { return false }
        if env.navigator.selection.count == 1, env.navigator.selection.contains(where: { env.store.block(id: $0) != nil }) {
            return true
        }
        // The list document's rows are focused and selected on the workbench.
        return !env.workbench.targetIDs.isEmpty
    }

    private var hasDocumentContext: Bool {
        env.activeDocument != nil && (env.navigator.documentOwnsEditorCommands || env.navigator.openTaskID != nil)
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
