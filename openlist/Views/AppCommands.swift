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
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some Commands {
        // Installed here, which SwiftUI builds as the app starts, whether or
        // not a window opens: a reminder or nudge clicked in a session whose
        // window never appeared opens it, and the palette opens Keyboard
        // Shortcuts.
        let _ = installOpeners()
        // Each Task item reads the same targets, so resolve them once per update:
        // a single target on its own, more in one fetch, for the titles.
        let targets = taskTargetIDs
        let single = singleTask(among: targets)
        let tasks = targets.count == 1 ? (single.map { [$0] } ?? []) : fetchTasks(targets)
        let reopens = !tasks.isEmpty && tasks.allSatisfy(env.workbench.isDoneOrClosing)
        let unstars = !tasks.isEmpty && tasks.allSatisfy(\.isStarred)
        let plans = env.workbench.canPlan(tasks)
        // What acts on the window stands down over an open capture, as the
        // design's keys do, rather than close it and drop the draft or change
        // the page under it: Settings…, New List and New Section, Export,
        // Search, the View items and the Work items are off while the window
        // is key, and from elsewhere those that show something there only
        // bring the window and its draft forward. Under a sheet they stand
        // down too, New Task… and Actions… with them, so nothing changes
        // behind the question the sheet asks.
        let keepsCapture = env.isMainWindowKey && env.workbench.captureOpen
        let waits = keepsCapture || env.mainWindowHasSheet

        CommandMenu("Work") {
            // With the window closed, its toolbar shows the panel once it's up.
            Button("Show Work") { besideCapture { env.calendar.showWork(); env.showsWorkPanelOnOpen = true } }
                .disabled(waits)
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
                .disabled(waits || env.workbench.workTask == nil)
            // As the notch's ⏸ and ▶: in place, a failure in the tray.
            Button(env.workbench.isWorkPaused ? "Resume Task" : "Pause Task") { env.workbench.toggleWorkPause() }
                .disabled(waits || env.workbench.workTask == nil)
            Button("Complete Current Task") {
                env.calendar.isWorkPanelPresented = false
                env.workbench.finishWork()
            }
                .disabled(waits || env.workbench.workTask == nil)
        }
        // Openlist ▸ Settings… opens the Settings page in the main window;
        // there is no Settings window.
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { showSettings() }
                .keyboardShortcut(",", modifiers: .command)
                .disabled(waits)
        }
        // File ▸ replaces the template "New Window" with task and list creation.
        CommandGroup(replacing: .newItem) {
            Button("New Task…") { inMainWindow { env.presentTaskCapture() } }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(env.mainWindowHasSheet)

            // Open capture takes ⌥⌘V itself, to stop listening.
            Button("New Tasks by Voice…") { inMainWindow { env.presentVoiceCapture() } }
                .keyboardShortcut("v", modifiers: [.command, .option])
                .disabled(env.mainWindowHasSheet)

            Button("New List") { besideCapture(newList) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(waits)

            Button("New Section") { besideCapture { env.workbench.createSection() } }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(waits)

            Divider()

            // Held by another app, ⇧⌥Space opens that app's feature even over
            // Openlist, so the menu doesn't promise it, as the menu bar's key
            // cap doesn't. Off, it still opens Quick Add from here.
            Button("Quick Add…") { QuickCapturePanel.shared.show() }
                .keyboardShortcut(QuickCaptureHotKey.shared.failure == .taken
                    ? nil : KeyboardShortcut(.space, modifiers: [.shift, .option]))
        }

        // The list on show, only while the main window is key, as Task and
        // Format are: closed, it would export a list no one can see, and
        // its tray would go unseen.
        CommandGroup(after: .newItem) {
            Divider()
            Button("Export List as Markdown…") { exportCurrentList() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(!env.isMainWindowKey || waits || shownListID == nil)
            // Trash's Hold to empty Trash, for the keyboard, asking first as
            // its VoiceOver action does. Off with nothing in Trash.
            Button("Empty Trash…") { besideCapture { env.confirmsEmptyingTrash = true } }
                .disabled(waits || !hasTrash)
        }

        // Edit ▸ find.
        CommandGroup(after: .textEditing) {
            Divider()
            Button("Search") { besideCapture { env.navigator.isSearchOpen = true } }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(waits)

            // The palette, named as the toolbar names it.
            Button("Actions…") { inMainWindow { env.navigator.isCommandPaletteOpen = true } }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(env.mainWindowHasSheet)
        }

        // Format ▸ inline styling. These actions travel the responder chain to
        // the focused block editor, which implements the selectors itself.
        // They style selected text, so they're on only while a line in the
        // main window has some (SwiftUI's items skip AppKit's validation).
        let formats = env.isMainWindowKey && InlineFormatting.shared.hasSelection
        CommandMenu("Format") {
            Button("Bold") { sendToResponder("toggleBold:") }
                .keyboardShortcut("b", modifiers: .command)
                .disabled(!formats)
            Button("Italic") { sendToResponder("toggleItalic:") }
                .keyboardShortcut("i", modifiers: .command)
                .disabled(!formats)
            Button("Strikethrough") { sendToResponder("toggleStrikethrough:") }
                .keyboardShortcut("x", modifiers: [.command, .shift])
                .disabled(!formats)
            Button("Inline Code") { sendToResponder("toggleInlineCode:") }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(!formats)
            Button("Add Link…") { sendToResponder("promptForLink:") }
                .keyboardShortcut("l", modifiers: .command)
                .disabled(!formats)

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
            // ⌘↩ finishes a note being written in the list document or the
            // inspector, as the design's does. A disabled item leaves the key
            // to the note, where an enabled one would take it first.
            Button("Open Details") { env.send(.openDetails) }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(single == nil || env.workbench.editingNoteID != nil || env.workbench.isWritingInspectorNote)
            // The open task over the whole main pane, and back beside the
            // screen; with none open, the one target opens there.
            Button(env.workbench.isTaskPageOpen ? "Collapse Details" : "Expand Details") {
                if env.workbench.inspectedTaskID == nil, let single { env.workbench.inspect(single.id) }
                env.workbench.toggleTaskPage()
            }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
                .disabled(!env.isMainWindowKey || keepsCapture || (env.workbench.inspectedTaskID == nil && single == nil))

            Divider()

            Button("Due Today") { env.send(.setDueToday) }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(targets.isEmpty)
            Button("Due Tonight") { act { env.workbench.scheduleTonight($0) } }
                .disabled(targets.isEmpty || Tonight.time(now: .now) == nil)
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

            // Both skip completed tasks, so they're off when every target is done.
            Button("Plan for Today") { act { env.workbench.plan($0) } }
                .disabled(!plans)
            Button("Find a Slot") { act { env.workbench.fit($0) } }
                .disabled(!plans)
            Button("Start Working") { act { env.workbench.startWork($0[0]) } }
                .disabled(workTask(single) == nil)
            // As the row menu's, for the inspected task too, whose row may be
            // on no screen: the keyboard's way to them with no pointer.
            Button("Copy Link") { act { env.copyLink(to: .task($0[0])) } }
                .disabled(single == nil)
            Button("Copy Text") { act { env.workbench.copyText($0[0]) } }
                .disabled(single == nil)
            Button("Copy Content and Subtasks") { act { env.workbench.copyContent($0[0]) } }
                .disabled(single == nil)

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

            Button("Duplicate") { act { env.workbench.duplicate($0[0]) } }
                .disabled(single == nil)
            Button("Use as Template…") { act { env.templateCopyRequest = TemplateCopyRequest(source: .task($0[0])) } }
                .disabled(single == nil)

            Divider()

            // Deliberately no key equivalent: AppKit matches menu shortcuts
            // before the text view sees the event, so ⌘⌫ here would delete the
            // task instead of the line the user was editing.
            Button("Move to Trash", role: .destructive) { env.send(.deleteSelection) }
                .disabled(targets.isEmpty)
        }

        // View ▸ navigation, in sidebar order.
        CommandGroup(before: .sidebar) {
            Button("Inbox") { besideCapture { env.workbench.go(.inbox) } }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(waits)
            Button("Today") { besideCapture { env.workbench.go(.today) } }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(waits)
            Button("Calendar") { besideCapture { env.workbench.go(.calendar) } }
                .keyboardShortcut("3", modifiers: .command)
                .disabled(waits)
            Button("Tasks") { besideCapture { env.workbench.go(.tasks) } }
                .keyboardShortcut("4", modifiers: .command)
                .disabled(waits)
            Button("Lists") { besideCapture { env.workbench.go(.lists) } }
                .keyboardShortcut("5", modifiers: .command)
                .disabled(waits)
            Button("Activity") { besideCapture { env.workbench.go(.activity) } }
                .keyboardShortcut("6", modifiers: .command)
                .disabled(waits)
            Button("Trash") { besideCapture { env.workbench.go(.trash) } }
                .disabled(waits)

            Divider()

            // The task opened out as a page goes back beside its screen first.
            Button("Back") { besideCapture { env.workbench.goBack() } }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(waits || !env.workbench.canGoBack)
            Button("Forward") { besideCapture { env.navigator.goForward() } }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(waits || !env.navigator.canGoForward)

            Divider()

            Button(env.workbench.showsSidebar ? "Hide Sidebar" : "Show Sidebar") { besideCapture { env.workbench.toggleSidebar() } }
                .keyboardShortcut("s", modifiers: [.control, .command])
                .disabled(waits)

            Divider()

            Button("Expand All") { env.send(.expandAll) }
                .disabled(!hasDocumentContext || waits)
            Button("Collapse All") { env.send(.collapseAll) }
                .disabled(!hasDocumentContext || waits)

            Divider()
        }

        // A reference to keep beside the window, which ⌘/ shows and hides.
        CommandGroup(replacing: .help) {
            Button(env.isShowingShortcuts ? "Hide Keyboard Shortcuts" : "Show Keyboard Shortcuts") {
                if env.isShowingShortcuts { dismissWindow(id: WindowID.shortcuts) } else { openWindow(id: WindowID.shortcuts) }
            }
            .keyboardShortcut("/", modifiers: .command)
        }
    }

    /// The main window's opener, for a reminder or nudge clicked with the
    /// window closed, and Keyboard Shortcuts', for the palette.
    private func installOpeners() {
        env.openMainWindow = { [openWindow] in openWindow(id: WindowID.main) }
        env.showShortcuts = { [openWindow] in openWindow(id: WindowID.shortcuts) }
    }

    /// What the Task menu acts on, only while the main window is key: the
    /// tasks the commands it sends would reach. The Next screens run them on
    /// the workbench targets (selection, focused row, inspected task), as
    /// `RootView.handleGlobalCommand` does; a list document on its own, the
    /// line being written first.
    private var taskTargetIDs: [UUID] {
        guard env.isMainWindowKey, !env.workbench.captureOpen, !env.navigator.isCommandPaletteOpen,
              !env.navigator.isSearchOpen, !env.mainWindowHasSheet else { return [] }
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

    /// A list document on show in the main window, only while it is key, as
    /// Task and Format's styles are: closed, no document is left to take the
    /// command, though it stays the active one.
    private var hasDocumentContext: Bool {
        env.isMainWindowKey && env.activeDocument != nil && env.navigator.documentOwnsEditorCommands
    }

    /// Whether anything is in Trash, a trashed task or list, read in a count
    /// that stops at the first.
    private var hasTrash: Bool {
        var blocks = FetchDescriptor<Block>(predicate: #Predicate { $0.trashID != nil })
        blocks.fetchLimit = 1
        var lists = FetchDescriptor<TaskList>(predicate: #Predicate { $0.trashID != nil })
        lists.fetchLimit = 1
        let context = env.store.context
        return ((try? context.fetchCount(blocks)) ?? 0) + ((try? context.fetchCount(lists)) ?? 0) > 0
    }

    // MARK: - Actions

    /// Dispatches a formatting action down the responder chain to whichever
    /// block editor currently has focus.
    private func sendToResponder(_ selectorName: String) {
        NSApp.sendAction(Selector((selectorName)), to: nil, from: nil)
    }

    /// The main window's Settings page, over search or the palette. With the
    /// main window key, NextKeyMonitor takes ⌘, before the menu does. From
    /// elsewhere, over a capture left open there, it only brings the window
    /// and its draft forward, as New Task… does.
    private func showSettings() {
        besideCapture { env.workbench.go(.settings) }
    }

    /// As `inMainWindow`, but over a capture open there it only brings the
    /// window and its draft forward: what `body` does would act under the card.
    private func besideCapture(_ body: () -> Void) {
        inMainWindow { if !env.workbench.captureOpen { body() } }
    }

    /// Runs `body` in the main window, opening it again if it was closed, and
    /// brings Openlist forward: what these items show is that window's, and
    /// would otherwise wait unseen until it opened again.
    private func inMainWindow(_ body: () -> Void) {
        openWindow(id: WindowID.main)
        body()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// The same list the sidebar's New list makes, with its tray and undo.
    private func newList() {
        env.workbench.createList()
    }

    /// The list on show: a list's page, or the Inbox as triage or as its
    /// document, which is routed as `.inbox`.
    private var shownListID: UUID? {
        env.navigator.route == .inbox ? env.navigator.inboxListID : env.navigator.route.listID
    }

    private func exportCurrentList() {
        guard
            let listID = shownListID,
            let list = env.store.list(id: listID)
        else { return }
        env.workbench.exportMarkdown(list)
    }
}
