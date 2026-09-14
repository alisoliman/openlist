//
//  CommandPaletteView.swift
//  openlist
//

import SwiftData
import SwiftUI

/// ⌘K — one field that creates tasks, jumps to lists and runs commands.
struct CommandPaletteView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<Block> { $0.trashID == nil && $0.kindRaw == "task" && !$0.isCompleted })
    private var openTasks: [Block]

    @State private var captureRequest: TaskCaptureRequest?
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        Group {
            if let captureRequest {
                TaskCaptureView(request: captureRequest)
            } else {
                VStack(spacing: 0) {
                    field
                    Divider()
                    results
                }
                .frame(width: 560, height: 420)
                .background(.regularMaterial)
                .onAppear { isFieldFocused = true }
            }
        }
    }

    private var field: some View {
        HStack(spacing: 9) {
            Image(systemName: "command")
                .font(.system(size: 13))
                .foregroundStyle(Theme.tertiaryText)

            TextField("Find a list, task, or command…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($isFieldFocused)
                .accessibilityLabel("Find a list, task, or command")
                .accessibilityHint("Use arrow keys to choose and Return to open.")
                .onSubmit { run(items[safe: selection]) }
                .onChange(of: query) { _, _ in selection = 0 }
                .onKeyPress(.upArrow) {
                    selection = max(0, selection - 1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    selection = min(items.count - 1, selection + 1)
                    return .handled
                }
                .onKeyPress(.escape) {
                    dismiss()
                    return .handled
                }

            Button("Close commands", systemImage: "xmark") { dismiss() }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var results: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        Button { run(item) } label: {
                            PaletteRow(item: item, isSelected: index == selection)
                        }
                            .buttonStyle(.plain)
                            .id(item.id)
                            .onHover { if $0 { selection = index } }
                    }
                }
                .padding(6)
            }
            .onChange(of: selection) { _, newValue in
                guard let item = items[safe: newValue] else { return }
                proxy.scrollTo(item.id, anchor: .center)
            }
        }
    }

    // MARK: - Items

    struct PaletteItem: Identifiable {
        enum Kind {
            case createTask(String)
            case navigate(AppRoute)
            case openTask(Block)
            case openList(TaskList)
            case newList
            case newSection
            case showShortcuts
            case search
        }

        var id: String
        var title: String
        var subtitle: String
        var symbol: String
        var accent: ListAccent
        var kind: Kind
        var shortcut: String?
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var items: [PaletteItem] {
        var result: [PaletteItem] = []

        if !trimmedQuery.isEmpty {
            let parsed = env.settings.parsesNaturalLanguageDates
                ? DateParser.parse(trimmedQuery)
                : ParsedSchedule(cleanedText: trimmedQuery)
            let taskTitle = parsed.cleanedText.isEmpty ? trimmedQuery : parsed.cleanedText

            result.append(
                PaletteItem(
                    id: "create",
                    title: "Create “\(taskTitle)”",
                    subtitle: createSubtitle(parsed),
                    symbol: "plus.circle.fill",
                    accent: .violet,
                    kind: .createTask(trimmedQuery)
                )
            )
        }

        // Lists
        for list in env.store.allLists() where !list.isSystemInbox && matches(list.displayTitle) {
            result.append(
                PaletteItem(
                    id: "list-\(list.id)",
                    title: list.displayTitle,
                    subtitle: "",
                    symbol: "square.stack",
                    accent: list.accent,
                    kind: .openList(list)
                )
            )
        }

        // Tasks
        if !trimmedQuery.isEmpty {
            for task in openTasks.filter({ matches($0.text) }).prefix(8) {
                let listName = env.store.list(id: task.listID)?.displayTitle ?? ""
                result.append(
                    PaletteItem(
                        id: "task-\(task.id)",
                        title: task.displayTitle,
                        subtitle: listName.isEmpty ? "Task" : "in \(listName)",
                        symbol: "checkmark.circle",
                        accent: .green,
                        kind: .openTask(task)
                    )
                )
            }
        }

        // Destinations and commands
        let commands: [PaletteItem] = [
            PaletteItem(id: "new-task", title: "New Task", subtitle: "", symbol: "plus.circle", accent: .violet, kind: .createTask(""), shortcut: "⌘N"),
            PaletteItem(id: "go-inbox", title: "Inbox", subtitle: "", symbol: "tray", accent: .blue, kind: .navigate(.inbox), shortcut: "⌘1"),
            PaletteItem(id: "go-today", title: "Today", subtitle: "", symbol: "sun.max", accent: .orange, kind: .navigate(.today), shortcut: "⌘2"),
            PaletteItem(id: "go-updates", title: "Updates", subtitle: "", symbol: "sparkles", accent: .violet, kind: .navigate(.updates), shortcut: "⌘3"),
            PaletteItem(id: "go-activity", title: "Activity", subtitle: "", symbol: "square.grid.3x3.fill", accent: .violet, kind: .navigate(.activity)),
            PaletteItem(id: "go-tasks", title: "Tasks", subtitle: "", symbol: "checklist", accent: .green, kind: .navigate(.tasks), shortcut: "⌘4"),
            PaletteItem(id: "go-calendar", title: "Calendar", subtitle: "", symbol: "calendar", accent: .violet, kind: .navigate(.calendar), shortcut: "⌘6"),
            PaletteItem(id: "go-lists", title: "Lists", subtitle: "", symbol: "square.stack", accent: .indigo, kind: .navigate(.lists), shortcut: "⌘5"),
            PaletteItem(id: "go-completed", title: "Completed", subtitle: "", symbol: "checkmark.circle", accent: .green, kind: .navigate(.completed)),
            PaletteItem(id: "new-list", title: "New List", subtitle: "", symbol: "plus.rectangle.on.folder", accent: .indigo, kind: .newList, shortcut: "⇧⌘N"),
            PaletteItem(id: "new-section", title: "New Section", subtitle: "", symbol: "folder.badge.plus", accent: .graphite, kind: .newSection, shortcut: "⌥⌘N"),
            PaletteItem(id: "search", title: "Search", subtitle: "", symbol: "magnifyingglass", accent: .graphite, kind: .search, shortcut: "⌘F"),
            PaletteItem(id: "shortcuts", title: "Keyboard Shortcuts", subtitle: "", symbol: "keyboard", accent: .graphite, kind: .showShortcuts, shortcut: "⌘/"),
        ]
        result.append(contentsOf: commands.filter { trimmedQuery.isEmpty || matches($0.title) })

        return result.enumerated().sorted { lhs, rhs in
            let left = rank(lhs.element)
            let right = rank(rhs.element)
            return left == right ? lhs.offset < rhs.offset : left < right
        }.map(\.element)
    }

    private func rank(_ item: PaletteItem) -> Int {
        let isTask: Bool
        if case .openTask = item.kind { isTask = true } else { isTask = false }
        return CommandMatchRank.rank(title: item.title, query: trimmedQuery, isCreation: item.id == "create", isTask: isTask)
    }

    private func createSubtitle(_ parsed: ParsedSchedule) -> String {
        var parts: [String] = []
        if let date = parsed.date {
            parts.append(
                parsed.includesTime
                    ? date.formatted(date: .abbreviated, time: .shortened)
                    : date.formatted(date: .abbreviated, time: .omitted)
            )
        }
        if let recurrence = parsed.recurrence {
            parts.append(recurrence.displayText)
        }
        return parts.joined(separator: " · ")
    }

    private func matches(_ text: String) -> Bool {
        guard !trimmedQuery.isEmpty else { return true }
        return text.localizedCaseInsensitiveContains(trimmedQuery)
    }

    // MARK: - Running

    private func run(_ item: PaletteItem?) {
        guard let item else { return }

        switch item.kind {
        case let .createTask(rawText):
            captureRequest = TaskCaptureRequest(text: rawText, suggestedListID: env.navigator.route.listID)
            return
        case let .navigate(route):
            env.navigator.go(to: route)
        case let .openTask(task):
            if let listID = task.listID { env.navigator.go(to: .list(listID)) }
            env.navigator.openTask(task.id)
        case let .openList(list):
            env.navigator.go(to: .list(list.id))
        case .newList:
            let list = env.store.createList(in: env.store.defaultSection())
            env.navigator.go(to: .list(list.id))
        case .newSection:
            _ = env.store.createSection()
        case .showShortcuts:
            env.navigator.isShortcutSheetOpen = true
        case .search:
            env.navigator.isSearchOpen = true
        }
        dismiss()
    }


}

/// One row in the palette.
struct PaletteRow: View {
    let item: CommandPaletteView.PaletteItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.symbol)
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? Color.white : item.accent.color)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Color.white.opacity(0.2) : item.accent.softBackground)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.75) : Theme.tertiaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)
            if let shortcut = item.shortcut {
                Text(shortcut)
                    .font(Theme.Font.metadata)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.75) : Theme.secondaryText)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Theme.accent : Color.clear)
        )
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .contentShape(Rectangle())
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
