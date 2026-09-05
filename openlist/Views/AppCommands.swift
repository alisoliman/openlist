//
//  AppCommands.swift
//  openlist
//

import SwiftUI

/// The macOS menu bar, carrying the same shortcut set Superlist uses.
struct AppCommands: Commands {
    let env: AppEnvironment

    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // File ▸ replaces the template "New Window" with task and list creation.
        CommandGroup(replacing: .newItem) {
            Button("New Task") { env.send(.newTask) }
                .keyboardShortcut("n", modifiers: .command)

            Button("New List") { newList() }
                .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("New Section") { _ = env.store.createSection() }
                .keyboardShortcut("n", modifiers: [.command, .option])

            Divider()

            Button("Quick Add…") { openWindow(id: WindowID.quickAdd) }
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
            Button("Outdent") { env.send(.outdent) }
                .keyboardShortcut("[", modifiers: [.command, .option])
            Button("Move Up") { env.send(.moveUp) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            Button("Move Down") { env.send(.moveDown) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
        }

        // Task ▸ everything that acts on the current selection.
        CommandMenu("Task") {
            Button("Complete / Reopen") { env.send(.toggleCompletion) }
                .keyboardShortcut("d", modifiers: .command)
            Button("Open Details") { env.send(.openDetails) }
                .keyboardShortcut(.return, modifiers: .command)

            Divider()

            Button("Due Today") { env.send(.setDueToday) }
                .keyboardShortcut("t", modifiers: .control)
            Button("Add Due Date…") { env.send(.pickDueDate) }
                .keyboardShortcut("d", modifiers: .control)
            Button("Clear Due Date") { env.send(.clearDueDate) }
                .keyboardShortcut("d", modifiers: [.control, .shift])

            Divider()

            Button("Add Label…") { env.send(.pickLabel) }
                .keyboardShortcut("l", modifiers: .control)
            Button("Clear Labels") { env.send(.clearLabels) }
                .keyboardShortcut("l", modifiers: [.control, .shift])
            Button("Toggle Star") { env.send(.toggleStar) }
                .keyboardShortcut("s", modifiers: [.command, .shift])

            Divider()

            Button("Add to Inbox") { env.send(.moveToInbox) }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            Button("Remove from List") { env.send(.removeFromList) }
                .keyboardShortcut("r", modifiers: [.command, .shift])

            Divider()

            // Deliberately no key equivalent: AppKit matches menu shortcuts
            // before the text view sees the event, so ⌘⌫ here would delete the
            // task instead of the line the user was editing.
            Button("Delete Task", role: .destructive) { env.send(.deleteSelection) }
        }

        // View ▸ navigation between the five fixed destinations.
        CommandGroup(before: .sidebar) {
            Button("Inbox") { env.navigator.go(to: .inbox) }
                .keyboardShortcut("1", modifiers: .command)
            Button("Today") { env.navigator.go(to: .today) }
                .keyboardShortcut("2", modifiers: .command)
            Button("Updates") { env.navigator.go(to: .updates) }
                .keyboardShortcut("3", modifiers: .command)
            Button("Tasks") { env.navigator.go(to: .tasks) }
                .keyboardShortcut("4", modifiers: .command)
            Button("Lists") { env.navigator.go(to: .lists) }
                .keyboardShortcut("5", modifiers: .command)

            Divider()

            Button("Back") { env.navigator.goBack() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(!env.navigator.canGoBack)
            Button("Forward") { env.navigator.goForward() }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(!env.navigator.canGoForward)

            Divider()

            Button("Expand All") { env.send(.expandAll) }
            Button("Collapse All") { env.send(.collapseAll) }

            Divider()
        }

        CommandGroup(replacing: .help) {
            Button("Keyboard Shortcuts") { env.navigator.isShortcutSheetOpen = true }
                .keyboardShortcut("/", modifiers: .command)
        }
    }

    // MARK: - Actions

    /// Dispatches a formatting action down the responder chain to whichever
    /// block editor currently has focus.
    private func sendToResponder(_ selectorName: String) {
        NSApp.sendAction(Selector((selectorName)), to: nil, from: nil)
    }

    private func newList() {
        let list = env.store.createList()
        env.navigator.go(to: .list(list.id))
    }

    private func exportCurrentList() {
        guard
            let listID = env.navigator.route.listID,
            let list = env.store.list(id: listID)
        else { return }
        MarkdownExporter.presentSavePanel(for: list, store: env.store)
    }
}
