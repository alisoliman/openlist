//
//  ShortcutsSheet.swift
//  openlist
//

import SwiftUI

/// ⌘/ — the full keyboard reference.
struct ShortcutsSheet: View {
    @Environment(\.dismiss) private var dismiss

    private struct Shortcut: Identifiable {
        var id: String { keys + action }
        var keys: String
        var action: String
    }

    private struct Group: Identifiable {
        var id: String { title }
        var title: String
        var symbol: String
        var shortcuts: [Shortcut]
    }

    private let groups: [Group] = [
        Group(title: "Navigation", symbol: "arrow.left.arrow.right", shortcuts: [
            Shortcut(keys: "⌘1", action: "Inbox"),
            Shortcut(keys: "⌘2", action: "Today"),
            Shortcut(keys: "⌘3", action: "Calendar"),
            Shortcut(keys: "⌘4", action: "Tasks"),
            Shortcut(keys: "⌘5", action: "Lists"),
            Shortcut(keys: "⌘6", action: "Activity"),
            Shortcut(keys: "G then I T C A L H", action: "Go to Inbox, Today, Calendar, Tasks, Lists, Activity"),
            Shortcut(keys: "⌘[", action: "Back"),
            Shortcut(keys: "⌘]", action: "Forward"),
            Shortcut(keys: "⌃⌘S", action: "Hide or show the sidebar"),
            Shortcut(keys: "⌘F", action: "Search"),
            Shortcut(keys: "⌘K", action: "Every action"),
            Shortcut(keys: "/", action: "Search"),
            Shortcut(keys: "⌘Z", action: "Undo the latest change"),
            Shortcut(keys: "⌘,", action: "Settings"),
            Shortcut(keys: "⌘/", action: "This list of shortcuts"),
        ]),
        Group(title: "Creating", symbol: "plus", shortcuts: [
            Shortcut(keys: "⌘N", action: "Draft a new task"),
            Shortcut(keys: "⇧⌘N", action: "New list"),
            Shortcut(keys: "⌥⌘N", action: "New section"),
            Shortcut(keys: "⇧⌥Space", action: "Quick add from anywhere"),
            Shortcut(keys: "⇧⌘E", action: "Export list as Markdown"),
        ]),
        Group(title: "Capture", symbol: "plus.circle", shortcuts: [
            Shortcut(keys: "N", action: "Capture a task"),
            Shortcut(keys: "↩", action: "Add"),
            Shortcut(keys: "⇧↩", action: "Add another"),
            Shortcut(keys: "⇥ ⇧⇥", action: "Change destination"),
            Shortcut(keys: "Esc", action: "Cancel capture"),
        ]),
        Group(title: "Rows", symbol: "list.bullet", shortcuts: [
            Shortcut(keys: "J K  ↑ ↓", action: "Move focus"),
            Shortcut(keys: "⇧J ⇧K", action: "Extend the selection"),
            Shortcut(keys: "X", action: "Select the focused row"),
            Shortcut(keys: "⌘A", action: "Select every visible row"),
            Shortcut(keys: "↩", action: "Open details"),
            Shortcut(keys: "E", action: "Complete or reopen"),
            Shortcut(keys: "T  M", action: "Due today, tomorrow"),
            Shortcut(keys: "F", action: "Star"),
            Shortcut(keys: "P", action: "Plan into the calendar"),
            Shortcut(keys: "D", action: "Move to Trash"),
            Shortcut(keys: "Esc", action: "Close details, clear selection"),
        ]),
        Group(title: "Inbox triage", symbol: "tray", shortcuts: [
            Shortcut(keys: "1–9", action: "File into a list"),
            Shortcut(keys: "T  M", action: "Schedule today, tomorrow"),
            Shortcut(keys: "→", action: "Keep for later"),
            Shortcut(keys: "E", action: "Already done"),
            Shortcut(keys: "D", action: "Discard"),
            Shortcut(keys: "↩", action: "Details"),
        ]),
        Group(title: "Tasks", symbol: "checkmark.circle", shortcuts: [
            Shortcut(keys: "⌘D", action: "Complete or reopen"),
            Shortcut(keys: "⌘↩", action: "Open task details"),
            Shortcut(keys: "⌃T", action: "Due today"),
            Shortcut(keys: "⌃D", action: "Add due date"),
            Shortcut(keys: "⌃⇧D", action: "Clear due date"),
            Shortcut(keys: "⌃L", action: "Add label"),
            Shortcut(keys: "⌃⇧L", action: "Clear labels"),
            Shortcut(keys: "⇧⌘S", action: "Toggle star"),
        ]),
        Group(title: "Selecting rows", symbol: "checklist", shortcuts: [
            Shortcut(keys: "Click gutter", action: "Select a row"),
            Shortcut(keys: "⌘ click", action: "Add or remove a row in the gutter"),
            Shortcut(keys: "⇧ click", action: "Select a visible range in the gutter"),
            Shortcut(keys: "↑ ↓", action: "Move selection while gutter is focused"),
            Shortcut(keys: "⇧↑ ⇧↓", action: "Extend or shrink a row range"),
            Shortcut(keys: "Space", action: "Toggle the focused gutter row"),
            Shortcut(keys: "Drag gutter", action: "Move selected rows and descendants"),
            Shortcut(keys: "Esc", action: "Clear row selection"),
        ]),
        Group(title: "Editing", symbol: "text.cursor", shortcuts: [
            Shortcut(keys: "↩", action: "New block below"),
            Shortcut(keys: "⇧↩", action: "Line break inside a block"),
            Shortcut(keys: "⇥", action: "Indent"),
            Shortcut(keys: "⇧⇥", action: "Outdent"),
            Shortcut(keys: "⌥⌘↑", action: "Move block up"),
            Shortcut(keys: "⌥⌘↓", action: "Move block down"),
            Shortcut(keys: "⌫", action: "Merge into the block above"),
            Shortcut(keys: "esc", action: "Leave the editor"),
        ]),
        Group(title: "Formatting", symbol: "bold", shortcuts: [
            Shortcut(keys: "⌘B", action: "Bold"),
            Shortcut(keys: "⌘I", action: "Italic"),
            Shortcut(keys: "⇧⌘X", action: "Strikethrough"),
            Shortcut(keys: "⌘E", action: "Inline code"),
            Shortcut(keys: "⌘L", action: "Add link"),
        ]),
        Group(title: "Typed shortcuts", symbol: "keyboard", shortcuts: [
            Shortcut(keys: "/", action: "Open the block menu"),
            Shortcut(keys: "[]", action: "Create a task"),
            Shortcut(keys: "-", action: "Bullet list"),
            Shortcut(keys: "1.", action: "Numbered list"),
            Shortcut(keys: "#", action: "Heading 1"),
            Shortcut(keys: "##", action: "Heading 2"),
            Shortcut(keys: "###", action: "Heading 3"),
            Shortcut(keys: ">", action: "Quote"),
            Shortcut(keys: "---", action: "Divider"),
            Shortcut(keys: "**bold**", action: "Bold inline"),
            Shortcut(keys: "*italic*", action: "Italic inline"),
            Shortcut(keys: "`code`", action: "Inline code"),
            Shortcut(keys: "#label", action: "Attach a label"),
            Shortcut(keys: "tomorrow at 6pm", action: "Set a due date by typing"),
            Shortcut(keys: "every monday", action: "Make a task repeat"),
        ]),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Keyboard shortcuts")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.tertiaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close keyboard shortcuts")
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            Divider()

            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 260, maximum: 360), spacing: 18)],
                    alignment: .leading,
                    spacing: 18
                ) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 5) {
                                Image(systemName: group.symbol)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Theme.accent)
                                Text(group.title)
                                    .font(Theme.Font.sectionHeader)
                                    .textCase(.uppercase)
                                    .foregroundStyle(Theme.tertiaryText)
                            }
                            .padding(.bottom, 2)

                            ForEach(group.shortcuts) { shortcut in
                                HStack(spacing: 8) {
                                    Text(shortcut.action)
                                        .font(Theme.Font.body)
                                        .foregroundStyle(Theme.secondaryText)
                                    Spacer(minLength: 8)
                                    Text(shortcut.keys)
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(
                                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                                .fill(Theme.chipFill)
                                        )
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("\(shortcut.action), \(shortcut.keys)")
                            }
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel(group.title)
                    }
                }
                .padding(18)
            }
        }
        .frame(minWidth: 640, idealWidth: 820, maxWidth: 900, minHeight: 420, idealHeight: 640, maxHeight: 760)
        .background(Theme.canvas)
    }
}
