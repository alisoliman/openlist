//
//  ShortcutsSheet.swift
//  openlist
//

import SwiftUI

/// ⌘/ — the full keyboard reference: the Next single keys first, then
/// documents, formatting and the menu commands.
struct ShortcutsSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    private struct Shortcut: Identifiable {
        var id: String { keys + action }
        var keys: String
        var action: String
    }

    private struct Group: Identifiable {
        var id: String { title }
        var title: String
        var shortcuts: [Shortcut]
    }

    private let groups: [Group] = [
        Group(title: "Everywhere", shortcuts: [
            Shortcut(keys: "N", action: "Capture a task"),
            Shortcut(keys: "/  ⌘F", action: "Search"),
            Shortcut(keys: "G then I T C A L H", action: "Go to Inbox, Today, Calendar, Tasks, Lists, Activity"),
            Shortcut(keys: "⌘K", action: "Every action and place"),
            Shortcut(keys: "⌘Z", action: "Undo the latest change"),
            Shortcut(keys: "⌘1–⌘6", action: "Inbox, Today, Calendar, Tasks, Lists, Activity"),
            Shortcut(keys: "⌘[  ⌘]", action: "Back, forward"),
            Shortcut(keys: "⌃⌘S", action: "Hide or show the sidebar"),
            Shortcut(keys: "⌘,", action: "Settings"),
            Shortcut(keys: "⌘/", action: "This list of shortcuts"),
        ]),
        Group(title: "Rows", shortcuts: [
            Shortcut(keys: "J K  ↑ ↓", action: "Move focus"),
            Shortcut(keys: "⇧J ⇧K", action: "Extend the selection"),
            Shortcut(keys: "↩", action: "Open details"),
            Shortcut(keys: "E", action: "Complete or reopen"),
            Shortcut(keys: "T  M", action: "Due today, tomorrow"),
            Shortcut(keys: "F", action: "Star"),
            Shortcut(keys: "P", action: "Plan into the calendar"),
            Shortcut(keys: "D  ⌫", action: "Move to Trash"),
            Shortcut(keys: "X", action: "Select the focused row"),
            Shortcut(keys: "⌘A", action: "Select every visible row"),
            Shortcut(keys: "Esc", action: "Close details, clear selection"),
        ]),
        Group(title: "Inbox triage", shortcuts: [
            Shortcut(keys: "1–9", action: "File into a list"),
            Shortcut(keys: "T  M", action: "Schedule today, tomorrow"),
            Shortcut(keys: "→", action: "Keep for later"),
            Shortcut(keys: "E", action: "Already done"),
            Shortcut(keys: "D", action: "Discard"),
            Shortcut(keys: "↩", action: "Details"),
        ]),
        Group(title: "Capture", shortcuts: [
            Shortcut(keys: "N  ⌘N", action: "Capture a task"),
            Shortcut(keys: "↩", action: "Add"),
            Shortcut(keys: "⇧↩", action: "Add another"),
            Shortcut(keys: "⇥ ⇧⇥", action: "Change destination"),
            Shortcut(keys: "Esc", action: "Cancel capture"),
            Shortcut(keys: "⇧⌥Space", action: "Quick add from anywhere"),
            Shortcut(keys: "friday 6pm", action: "Due date and time"),
            Shortcut(keys: "every monday", action: "Repeat"),
            Shortcut(keys: "#label", action: "Attach a label"),
            Shortcut(keys: "!high", action: "Priority"),
            Shortcut(keys: "~15m", action: "Estimate"),
        ]),
        Group(title: "Documents", shortcuts: [
            Shortcut(keys: "#  ##  ###", action: "Heading 1, 2, 3"),
            Shortcut(keys: "-", action: "Bullet list"),
            Shortcut(keys: "[ ]", action: "Task"),
            Shortcut(keys: "1.", action: "Numbered list"),
            Shortcut(keys: ">", action: "Quote"),
            Shortcut(keys: "---", action: "Divider"),
            Shortcut(keys: "/", action: "Open the block menu"),
            Shortcut(keys: "↩", action: "New block below"),
            Shortcut(keys: "⇥", action: "Indent"),
            Shortcut(keys: "⇧⇥", action: "Outdent"),
            Shortcut(keys: "⇧↩", action: "Line break inside a block"),
            Shortcut(keys: "⌫", action: "Merge into the block above"),
            Shortcut(keys: "⌥⌘↑  ⌥⌘↓", action: "Move block up, down"),
            Shortcut(keys: "Esc", action: "Leave the editor"),
            Shortcut(keys: "#label", action: "Attach a label"),
            Shortcut(keys: "tomorrow at 6pm", action: "Set a due date by typing"),
            Shortcut(keys: "every monday", action: "Make a task repeat"),
        ]),
        Group(title: "Formatting", shortcuts: [
            Shortcut(keys: "⌘B", action: "Bold"),
            Shortcut(keys: "⌘I", action: "Italic"),
            Shortcut(keys: "⇧⌘X", action: "Strikethrough"),
            Shortcut(keys: "⌘E", action: "Inline code"),
            Shortcut(keys: "⌘L", action: "Add link"),
            Shortcut(keys: "**bold**", action: "Bold inline"),
            Shortcut(keys: "*italic*", action: "Italic inline"),
            Shortcut(keys: "`code`", action: "Inline code"),
        ]),
        Group(title: "Task menu", shortcuts: [
            Shortcut(keys: "⌘D", action: "Complete or reopen"),
            Shortcut(keys: "⌘↩", action: "Open task details"),
            Shortcut(keys: "⌃T", action: "Due today"),
            Shortcut(keys: "⌃D", action: "Add due date"),
            Shortcut(keys: "⌃⇧D", action: "Clear due date"),
            Shortcut(keys: "⌃L", action: "Add label"),
            Shortcut(keys: "⌃⇧L", action: "Clear labels"),
            Shortcut(keys: "⇧⌘S", action: "Toggle star"),
        ]),
        Group(title: "Creating", shortcuts: [
            Shortcut(keys: "⇧⌘N", action: "New list"),
            Shortcut(keys: "⌥⌘N", action: "New section"),
            Shortcut(keys: "⇧⌘E", action: "Export list as Markdown"),
        ]),
    ]

    var body: some View {
        let style = env.workbench.style
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                NXPanelTitle("Keyboard shortcuts")
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(NXPanelButtonStyle(kind: .quiet, size: .icon))
                .accessibilityLabel("Close keyboard shortcuts")
                .help("Close (Esc)")
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 14)
            .overlay(alignment: .bottom) { Rectangle().fill(NX.ink(0.07)).frame(height: 0.5) }

            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 260, maximum: 360), spacing: 22)],
                    alignment: .leading,
                    spacing: 22
                ) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 2) {
                            NXCapsTitle(text: group.title)
                                .padding(.bottom, 6)
                                .accessibilityAddTraits(.isHeader)

                            ForEach(group.shortcuts) { shortcut in
                                HStack(spacing: 8) {
                                    Text(shortcut.action)
                                        .font(.system(size: 12.5))
                                        .foregroundStyle(NX.ink(0.66))
                                    Spacer(minLength: 8)
                                    // The design's key hints: monospaced, on a faint key cap.
                                    Text(shortcut.keys)
                                        .font(NX.mono(10.5))
                                        .foregroundStyle(NX.ink(0.6))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(NX.ink(0.06), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                                }
                                .padding(.vertical, 2)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("\(shortcut.action), \(shortcut.keys)")
                            }
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel(group.title)
                    }
                }
                .padding(22)
            }
        }
        .frame(minWidth: 640, idealWidth: 820, maxWidth: 900, minHeight: 420, idealHeight: 640, maxHeight: 760)
        .presentationBackground(NX.card)
        // Presented from the window, outside the Next shell's style.
        .environment(\.nextStyle, style)
    }
}
