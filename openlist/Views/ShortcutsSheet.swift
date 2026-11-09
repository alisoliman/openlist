//
//  ShortcutsSheet.swift
//  openlist
//

import SwiftUI

/// ⌘/ — the full keyboard reference: the Next single keys first, then
/// writing in a list, formatting and the menu commands. A window of its own
/// beside the main one, so a key can be tried while its line is read.
struct ShortcutsSheet: View {
    @Environment(AppEnvironment.self) private var env

    private struct Shortcut: Identifiable {
        var id: String { keys + action }
        var keys: String
        var action: String
        /// Read only while Settings reads dates from typed text.
        var readsDates = false
    }

    private struct Group: Identifiable {
        var id: String { title }
        var title: String
        var shortcuts: [Shortcut]
    }

    /// The keys the app handles today: the Next key map (NextKeys), the list
    /// document's line keys (OutlineEditor), and the menus.
    private var groups: [Group] { [
        Group(title: "Everywhere", shortcuts: [
            Shortcut(keys: "N", action: "New task"),
            Shortcut(keys: "/  ⌘F", action: "Search"),
            Shortcut(keys: "⇥", action: "In search, go to Include completed and back"),
            Shortcut(keys: "G then I T C A L H", action: "Go to Inbox, Today, Calendar, Tasks, Lists, Activity"),
            Shortcut(keys: "⌘K", action: "Actions: every action and place"),
            Shortcut(keys: "⌘Z", action: "Undo the latest change"),
            Shortcut(keys: "⌘1–⌘6", action: "Inbox, Today, Calendar, Tasks, Lists, Activity"),
            Shortcut(keys: "⌘[  ⌘]", action: "Back, forward"),
            Shortcut(keys: "⌃⌘S", action: "Hide or show the sidebar"),
            Shortcut(keys: "⌘,", action: "Settings"),
            Shortcut(keys: "⌘/", action: "Show or hide this list of shortcuts"),
        ]),
        Group(title: "Rows", shortcuts: [
            Shortcut(keys: "J K  ↑ ↓", action: "Move focus"),
            Shortcut(keys: "⇧J ⇧K  ⇧↑ ⇧↓", action: "Extend the selection"),
            Shortcut(keys: "⌘ click", action: "Add or remove a row from the selection"),
            Shortcut(keys: "⇧ click", action: "Select the rows from the focused one to it"),
            Shortcut(keys: "X", action: "Select or deselect the focused row"),
            Shortcut(keys: "⌘A", action: "Select every visible row"),
            Shortcut(keys: "↩", action: "Open details; again, write in the task"),
            Shortcut(keys: "E", action: "Mark as done"),
            Shortcut(keys: "T  M", action: "Due today, tomorrow"),
            Shortcut(keys: "P", action: "Plan for today, or unplan"),
            Shortcut(keys: "F", action: "Star or unstar"),
            Shortcut(keys: "1–9", action: "In the Inbox, file the rows into a list"),
            Shortcut(keys: "S  ⇧S", action: "In the Inbox, snooze until tomorrow, next week"),
            Shortcut(keys: "D  ⌫", action: "Move to Trash"),
            Shortcut(keys: "Space", action: "Show or hide the note, in a list"),
            Shortcut(keys: "⇥  ⇧⇥", action: "Nest or lift the rows, in a list"),
            Shortcut(keys: "←  →", action: "Fold or unfold a task's subtasks, in a list"),
            Shortcut(keys: "Esc", action: "Collapse or close details, clear selection or focus, leave Settings"),
        ]),
        Group(title: "Inbox triage", shortcuts: [
            Shortcut(keys: "1–9", action: "File into a list"),
            Shortcut(keys: "0", action: "File into the suggested list"),
            Shortcut(keys: "L", action: "File into any list, by name"),
            Shortcut(keys: "T  M", action: "Schedule today, tomorrow"),
            Shortcut(keys: "⇧T  ⇧M  ⇧ click", action: "Pick the day to file with, then a list's number"),
            Shortcut(keys: "R", action: "Edit: a new title, or a date, @list, #label, !priority, ~estimate"),
            Shortcut(keys: "S  ⇧S", action: "Snooze until tomorrow, next week"),
            Shortcut(keys: "→", action: "Keep for later"),
            Shortcut(keys: "E", action: "Already done"),
            Shortcut(keys: "D", action: "Discard"),
            Shortcut(keys: "↩", action: "Open details"),
        ]),
        Group(title: "Capture", shortcuts: [
            Shortcut(keys: "N  ⌘N", action: "New task"),
            Shortcut(keys: "↩", action: "Add"),
            Shortcut(keys: "⇧↩", action: "Add another"),
            Shortcut(keys: "⇥ ⇧⇥", action: "Change destination"),
            Shortcut(keys: "↑ ↓  ⇥", action: "Choose a suggested list or label, and take it"),
            Shortcut(keys: "⌥↩", action: "Write a note, and back to the title"),
            Shortcut(keys: "⌘V", action: "Paste lines as a task each"),
            Shortcut(keys: "⇧⌘V", action: "Paste lines as one"),
            Shortcut(keys: "Esc", action: "Close capture; the draft waits for the next"),
            Shortcut(keys: "⇧⌥Space", action: "Quick add from anywhere"),
            Shortcut(keys: "⌥⌘V", action: "Say tasks, or stop listening"),
            Shortcut(keys: "↩  Esc", action: "While reading what was said, skip Apple Intelligence"),
            Shortcut(keys: env.settings.voiceCaptureShortcut.display,
                     action: "Voice Quick Add from anywhere (opt-in in Settings)"),
            Shortcut(keys: "friday 6pm", action: "Due date and time", readsDates: true),
            Shortcut(keys: "every monday", action: "Repeat", readsDates: true),
            Shortcut(keys: "#label", action: "Attach a label"),
            Shortcut(keys: "@list", action: "Add to a list"),
            Shortcut(keys: "!high", action: "Priority"),
            Shortcut(keys: "~15m", action: "Estimate"),
        ]),
        // Only the design's prefixes turn a line as it's typed, and a line
        // keeps its text as typed: dates and labels are read in capture.
        Group(title: "Writing in a list", shortcuts: [
            Shortcut(keys: "#  ##", action: "Heading, subheading"),
            Shortcut(keys: "-  *", action: "Bullet"),
            Shortcut(keys: "[ ]", action: "Task"),
            Shortcut(keys: ">", action: "Text"),
            Shortcut(keys: "/", action: "Turn into"),
            Shortcut(keys: "/ then a name", action: "Heading 3, numbered, quote, code, divider, image"),
            Shortcut(keys: "↩", action: "New line below"),
            Shortcut(keys: "↩", action: "On an empty line: out a level, or a task"),
            Shortcut(keys: "⇥", action: "Subtask"),
            Shortcut(keys: "⇧⇥", action: "Out a level"),
            Shortcut(keys: "⇧↩", action: "A task's note; in code, a line break"),
            Shortcut(keys: "⌫", action: "At the start: text, or out a level"),
            Shortcut(keys: "⌫", action: "On an empty line: remove it"),
            Shortcut(keys: "↑ ↓", action: "Line above, below"),
            Shortcut(keys: "⌥⌘]  ⌥⌘[", action: "Indent, outdent the line"),
            Shortcut(keys: "⌥⌘↑  ⌥⌘↓", action: "Move the line up, down"),
            Shortcut(keys: "Esc", action: "Stop writing; a task keeps the focus"),
        ]),
        Group(title: "Formatting", shortcuts: [
            Shortcut(keys: "⌘B", action: "Bold"),
            Shortcut(keys: "⌘I", action: "Italic"),
            Shortcut(keys: "⇧⌘X", action: "Strikethrough"),
            Shortcut(keys: "⌘E", action: "Inline code"),
            Shortcut(keys: "⌘L", action: "Add link"),
            Shortcut(keys: "**bold**", action: "Bold inline"),
            Shortcut(keys: "*italic*", action: "Italic inline"),
            Shortcut(keys: "~~strike~~", action: "Strikethrough inline"),
            Shortcut(keys: "`code`", action: "Inline code"),
        ]),
        Group(title: "Task menu", shortcuts: [
            Shortcut(keys: "⌘D", action: "Mark as done, or reopen"),
            Shortcut(keys: "⌘↩", action: "Open details"),
            Shortcut(keys: "⇧⌘↩", action: "Expand details to the whole window, or collapse them"),
            Shortcut(keys: "⇧⌘T  ⇧⌘M", action: "Due today, tomorrow"),
            Shortcut(keys: "⇧⌘D", action: "Add due date"),
            Shortcut(keys: "⌥⇧⌘D", action: "Clear due date"),
            Shortcut(keys: "⇧⌘L", action: "Add label"),
            Shortcut(keys: "⌥⇧⌘L", action: "Clear labels"),
            Shortcut(keys: "⇧⌘S", action: "Star or unstar"),
        ]),
        Group(title: "Creating", shortcuts: [
            Shortcut(keys: "⇧⌘N", action: "New list"),
            Shortcut(keys: "⌥⌘N", action: "New section"),
            Shortcut(keys: "⇧⌘E", action: "Export list as Markdown"),
        ]),
    ] }

    var body: some View {
        let style = env.workbench.style
        VStack(spacing: 0) {
            // Under the window's own title. As in the design, the single keys
            // stand down while a line or field has the caret.
            Text("Single keys work when you’re not writing. Esc stops writing.")
                .font(.system(size: 12))
                .foregroundStyle(NX.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22)
                .padding(.top, 14)
                .padding(.bottom, 14)
                .overlay(alignment: .bottom) { NXHairline(NX.ink(0.07)) }

            ScrollView {
                // Each group starts at the top of its row, rather than centred
                // beside a longer one with a gap above it.
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 260, maximum: 360), spacing: 22, alignment: .top)],
                    alignment: .leading,
                    spacing: 22
                ) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 2) {
                            NXCapsTitle(text: group.title)
                                .padding(.bottom, 6)

                            ForEach(group.shortcuts.filter { !$0.readsDates || env.settings.parsesNaturalLanguageDates }) { shortcut in
                                HStack(spacing: 8) {
                                    Text(shortcut.action)
                                        .font(.system(size: 12.5))
                                        .foregroundStyle(NX.textSecondary)
                                    Spacer(minLength: 8)
                                    // The design's key hints: monospaced, on a faint key cap,
                                    // line-height 1 inside 2/5 padding.
                                    NXKey(shortcut.keys)
                                        .foregroundStyle(NX.ink)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2 + (10 - NX.lineHeight(10)) / 2)
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
        .background(NX.card)
        // A window of its own, outside the Next shell's style.
        .environment(\.nextStyle, style)
    }
}
