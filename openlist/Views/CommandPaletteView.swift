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
                    Text("↑↓ to choose · Return to open · Esc to close")
                        .font(.caption).foregroundStyle(.secondary).padding(10)
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
                withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(item.id, anchor: .center) }
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
                    subtitle: "Open list",
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
            PaletteItem(id: "new-task", title: "New Task", subtitle: "⌘N · Choose a destination and review details", symbol: "plus.circle", accent: .violet, kind: .createTask("")),
            PaletteItem(id: "go-inbox", title: "Go to Inbox", subtitle: "⌘1", symbol: "tray", accent: .blue, kind: .navigate(.inbox)),
            PaletteItem(id: "go-today", title: "Go to Today", subtitle: "⌘2", symbol: "sun.max", accent: .orange, kind: .navigate(.today)),
            PaletteItem(id: "go-updates", title: "Go to Updates", subtitle: "⌘3", symbol: "sparkles", accent: .violet, kind: .navigate(.updates)),
            PaletteItem(id: "go-activity", title: "Go to Activity", subtitle: "Recorded completion heatmap", symbol: "square.grid.3x3.fill", accent: .violet, kind: .navigate(.activity)),
            PaletteItem(id: "go-tasks", title: "Go to Tasks", subtitle: "⌘4", symbol: "checklist", accent: .green, kind: .navigate(.tasks)),
            PaletteItem(id: "go-calendar", title: "Go to Calendar", subtitle: "⌘6", symbol: "calendar", accent: .violet, kind: .navigate(.calendar)),
            PaletteItem(id: "go-lists", title: "Go to Lists", subtitle: "⌘5", symbol: "square.stack", accent: .indigo, kind: .navigate(.lists)),
            PaletteItem(id: "go-completed", title: "Go to Completed", subtitle: "Archive of finished tasks", symbol: "checkmark.circle", accent: .green, kind: .navigate(.completed)),
            PaletteItem(id: "new-list", title: "New List", subtitle: "⇧⌘N", symbol: "plus.rectangle.on.folder", accent: .indigo, kind: .newList),
            PaletteItem(id: "new-section", title: "New Section", subtitle: "⌥⌘N", symbol: "folder.badge.plus", accent: .graphite, kind: .newSection),
            PaletteItem(id: "search", title: "Search", subtitle: "⌘F", symbol: "magnifyingglass", accent: .graphite, kind: .search),
            PaletteItem(id: "shortcuts", title: "Keyboard Shortcuts", subtitle: "⌘/", symbol: "keyboard", accent: .graphite, kind: .showShortcuts),
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
        parts.append("Review destination and details before adding")
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
