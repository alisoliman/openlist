//
//  ListScreen.swift
//  openlist
//

import SwiftData
import SwiftUI

/// A list document: editable title, icon, summary, then the block outline.
struct ListScreen: View {
    let list: TaskList

    @Environment(AppEnvironment.self) private var env
    @State private var isIconPickerOpen = false
    @State private var isSummaryVisible = false
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        ScreenScaffold(headerSpacing: 10) {
            header
        } content: {
            DocumentView(
                document: DocumentContext(listID: list.id),
                emptyPlaceholder: "Add a task, or press / for blocks",
                showsCompleted: list.showsCompleted,
                sorting: list.sorting
            )
            .id(list.id)
        }
        .onAppear {
            isSummaryVisible = !list.summary.isEmpty
            env.store.markOpened(list)
            // A freshly created list opens ready to be named.
            if list.title.isEmpty {
                DispatchQueue.main.async { isTitleFocused = true }
            }
        }
        .onChange(of: list.summary) { old, new in
            if old.isEmpty && !new.isEmpty { isSummaryVisible = true }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                Button {
                    isIconPickerOpen = true
                } label: {
                    Text(list.icon)
                        .font(.system(size: 28))
                        .frame(width: 40, height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(list.accent.softBackground)
                        )
                }
                .buttonStyle(.plain)
                .help("Change icon and colour")
                .popover(isPresented: $isIconPickerOpen, arrowEdge: .bottom) {
                    ListAppearancePicker(list: list)
                        .environment(env)
                }

                TextField(
                    "Untitled list",
                    text: Binding(
                        get: { list.title },
                        set: { env.store.rename(list, to: $0) }
                    )
                )
                .textFieldStyle(.plain)
                .font(Theme.Font.documentTitle)
                .focused($isTitleFocused)
                .onSubmit {
                    env.store.save()
                    isTitleFocused = false
                    env.send(.newTask)
                }

                Spacer(minLength: 8)
                headerControls
            }

            if isSummaryVisible {
                TextField(
                    "Add a description…",
                    text: Binding(
                        get: { list.summary },
                        set: { env.store.setSummary($0, for: list) }
                    ),
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1...5)
                .padding(.leading, 50)
                .onSubmit { env.store.save() }
            }

            statsRow
                .padding(.leading, 50)
        }
    }

    private var headerControls: some View {
        HStack(spacing: 4) {
            Menu {
                Section("Sort by") {
                    ForEach(ListSorting.allCases, id: \.self) { sorting in
                        CheckmarkMenuItem(sorting.title, isSelected: list.sorting == sorting) {
                            env.store.setSorting(sorting, for: list)
                        }
                    }
                }

                Divider()

                Button(list.showsCompleted ? "Hide Completed" : "Show Completed") {
                    env.store.setShowsCompleted(!list.showsCompleted, for: list)
                }
                Button(isSummaryVisible ? "Hide Description" : "Add Description") {
                    isSummaryVisible.toggle()
                }

                Divider()

                Button(list.isPinned ? "Remove from Sidebar" : "Pin to Sidebar") {
                    env.store.setPinned(!list.isPinned, for: list)
                }
                Button("Duplicate List") {
                    let copy = env.store.duplicateList(list)
                    env.navigator.go(to: .list(copy.id))
                }
                Button("Export as Markdown…") {
                    MarkdownExporter.presentSavePanel(for: list, store: env.store)
                }
                Button("Copy as Markdown") {
                    MarkdownExporter.copyToPasteboard(list: list, store: env.store)
                }

                if !list.isSystemInbox {
                    Divider()
                    Button("Delete List", role: .destructive) {
                        env.requestDeleteList(list)
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 15))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 26)
            .help("List options")
        }
    }

    @ViewBuilder
    private var statsRow: some View {
        let blocks = env.store.blocks(inList: list.id)
        let tasks = blocks.filter(\.isTask)
        let done = tasks.filter(\.isCompleted).count

        if !tasks.isEmpty {
            HStack(spacing: 8) {
                Text("\(done) of \(tasks.count) done")
                    .font(Theme.Font.metadata)
                    .foregroundStyle(Theme.tertiaryText)

                ProgressBar(done: done, total: tasks.count, accent: list.accent)
                    .frame(width: 90)

                if !list.showsCompleted, done > 0 {
                    Button("Show \(done) completed") {
                        env.store.setShowsCompleted(true, for: list)
                    }
                    .buttonStyle(.plain)
                    .font(Theme.Font.metadata)
                    .foregroundStyle(Theme.accent)
                }
            }
        }
    }
}

/// Emoji and colour picker for a list.
struct ListAppearancePicker: View {
    let list: TaskList

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    private static let emoji = [
        "📋", "✅", "🌱", "🏡", "💼", "📚", "🗻", "✈️", "🛒", "🎯",
        "💡", "🎨", "🎵", "🍳", "🏋️", "💰", "🐾", "🎁", "🧹", "📝",
        "🔧", "🌍", "☕️", "🌙", "🔥", "⭐️", "🧠", "🎬", "🚲", "🧺",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Icon")
                .font(Theme.Font.sectionHeader)
                .textCase(.uppercase)
                .foregroundStyle(Theme.tertiaryText)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 4), count: 10), spacing: 4) {
                ForEach(Self.emoji, id: \.self) { symbol in
                    Button {
                        env.store.setAppearance(icon: symbol, for: list)
                    } label: {
                        Text(symbol)
                            .font(.system(size: 17))
                            .frame(width: 30, height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(list.icon == symbol ? Theme.accent.opacity(0.18) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            Text("Colour")
                .font(Theme.Font.sectionHeader)
                .textCase(.uppercase)
                .foregroundStyle(Theme.tertiaryText)

            HStack(spacing: 6) {
                ForEach(ListAccent.allCases) { accent in
                    Button {
                        env.store.setAppearance(accent: accent, for: list)
                    } label: {
                        Circle()
                            .fill(accent.color)
                            .frame(width: 20, height: 20)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.primary.opacity(list.accent == accent ? 0.75 : 0), lineWidth: 2)
                                    .padding(-3)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(accent.title)
                }
            }
        }
        .padding(14)
        .frame(width: 360)
    }
}
