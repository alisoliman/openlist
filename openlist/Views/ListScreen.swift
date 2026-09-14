//
//  ListScreen.swift
//  openlist
//

import AppKit
import SwiftData
import SwiftUI

/// A list's document or task-only queue, sharing the original title and models.
struct ListScreen: View {
    let list: TaskList

    @Environment(AppEnvironment.self) private var env
    @State private var isIconPickerOpen = false
    @State private var isSummaryVisible = false
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isSummaryFocused: Bool
    @State private var titleSelection: TextSelection?
    @State private var summarySelection: TextSelection?

    private var revealsSummary: Bool { env.navigator.contentReveal?.revealsSummary(for: list.id) == true }
    private var readyRevealID: UUID? {
        guard !env.navigator.isSearchOpen, env.navigator.contentReveal?.destination == .list(list.id) else { return nil }
        return env.navigator.contentReveal?.id
    }

    var body: some View {
        ScreenScaffold(headerSpacing: 10) {
            ListBreadcrumbs(list: list)
            header
        } content: {
            ChildListDocuments(list: list)
            if let note = list.trashMetadata?.recoveryNote {
                Text(note).font(.callout).foregroundStyle(Theme.secondaryText)
            }
            if viewMode == .document {
                DocumentView(
                    document: DocumentContext(listID: list.id),
                    emptyPlaceholder: "Add a task…",
                    showsCompleted: showsCompleted,
                    sorting: list.sorting
                )
                .id(list.id)
            } else {
                ListTasksView(list: list, showsCompleted: showsCompleted)
                    .id(list.id)
            }
        }
        .onAppear {
            isSummaryVisible = !list.summary.isEmpty
            env.store.markOpened(list)
            // A freshly created list opens ready to be named.
            if list.title.isEmpty {
                DispatchQueue.main.async { isTitleFocused = true }
            }
        }
        .onChange(of: isTitleFocused) { _, focused in
            if focused { adoptListTextFocus() }
        }
        .onChange(of: isSummaryFocused) { _, focused in
            if focused { adoptListTextFocus() }
        }
        .onChange(of: list.summary) { old, new in
            if old.isEmpty && !new.isEmpty { isSummaryVisible = true }
        }
        .onChange(of: viewMode) { _, _ in
            isTitleFocused = false
            isSummaryFocused = false
            env.requestedPicker = nil
            // A removed outline or inspector must not retain menu commands.
            env.activeDocument = viewMode == .document ? DocumentContext(listID: list.id) : nil
        }
        .task(id: readyRevealID) {
            guard readyRevealID != nil, let reveal = env.navigator.contentReveal else { return }
            await Task.yield()
            guard !Task.isCancelled else { return }
            if revealsSummary {
                isSummaryFocused = true
                summarySelection = SearchProjection.range(of: reveal.query, in: list.summary).map { TextSelection(range: $0) }
            } else {
                isTitleFocused = true
                titleSelection = SearchProjection.range(of: reveal.query, in: list.title).map { TextSelection(range: $0) }
            }
        }
    }

    private func adoptListTextFocus() {
        // A delayed callback from a removed list or the previous field must
        // not clear a newer gutter selection or another pane's selection.
        guard list.modelContext != nil, !list.isDeleted,
              env.navigator.route == .list(list.id),
              isTitleFocused || isSummaryFocused,
              NSApp.keyWindow?.firstResponder is NSTextView else { return }
        env.navigator.clearSelection()
    }

    private var showsCompleted: Bool {
        list.showsCompleted(default: env.settings.showsCompletedTasks)
    }

    private var viewMode: ListViewMode { env.navigator.listViewMode(for: list.id) }

    private var viewModeSelection: Binding<ListViewMode> {
        Binding(get: { viewMode }, set: { env.navigator.setListViewMode($0, for: list.id) })
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            ListCoverBanner(list: list)
            HStack(alignment: .center, spacing: 12) {
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
                .accessibilityLabel("Change list icon and colour")
                .popover(isPresented: $isIconPickerOpen, arrowEdge: .bottom) {
                    ListAppearancePicker(list: list)
                        .environment(env)
                }

                Spacer(minLength: 12)
                headerControls
            }

            TextField(
                "Untitled list",
                text: Binding(
                    get: { list.title },
                    set: { env.store.rename(list, to: $0) }
                ),
                selection: $titleSelection,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(Theme.Font.documentTitle)
            .lineLimit(1...)
            .fixedSize(horizontal: false, vertical: true)
            .focused($isTitleFocused)
            .onSubmit {
                env.store.save()
                isTitleFocused = false
                env.send(.newTask)
            }
            .accessibilityLabel("List title")

            if viewMode == .document && (isSummaryVisible || revealsSummary) {
                TextField(
                    "Add a description…",
                    text: Binding(
                        get: { list.summary },
                        set: { env.store.setSummary($0, for: list) }
                    ),
                    selection: $summarySelection,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(revealsSummary ? nil : 5)
                .focused($isSummaryFocused)
                .id(ContentReveal.Anchor.listSummary(list.id))
                .accessibilityLabel("List description")
                .overlay {
                    if revealsSummary {
                        RoundedRectangle(cornerRadius: 6).stroke(Theme.accent, lineWidth: 2).allowsHitTesting(false)
                    }
                }
                .onSubmit { env.store.save() }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    viewPicker
                    Spacer(minLength: 8)
                    CompletedTasksControl(list: list, showsAsTaskQueue: viewMode == .tasks)
                }
                VStack(alignment: .leading, spacing: 10) {
                    viewPicker
                    CompletedTasksControl(list: list, showsAsTaskQueue: viewMode == .tasks)
                }
            }
            .padding(.top, 8)
        }
    }

    private var headerControls: some View {
        HStack(spacing: 10) {
            ListCoverMenu(list: list)
            Menu {
                Section("Calendar availability") {
                    ForEach(AvailabilityCategory.allCases) { category in
                        CheckmarkMenuItem(category.title, isSelected: list.availabilityCategoryRaw == category.rawValue) {
                            env.store.setAvailabilityCategory(category.rawValue, for: list)
                            env.calendar.storeDidChange()
                        }
                    }
                }

                Section("Sort by") {
                    ForEach(ListSorting.allCases, id: \.self) { sorting in
                        CheckmarkMenuItem(sorting.title, isSelected: list.sorting == sorting) {
                            env.store.setSorting(sorting, for: list)
                        }
                    }
                }

                Divider()

                Section("Completed tasks") {
                    ForEach(TaskList.CompletedVisibility.allCases) { preference in
                        CheckmarkMenuItem(preference.title, isSelected: list.completedVisibility == preference) {
                            env.store.setCompletedVisibility(preference, for: list)
                        }
                    }
                }
                if viewMode == .document {
                    Button(isSummaryVisible ? "Hide Description" : "Add Description") {
                        isSummaryVisible.toggle()
                    }
                }

                Divider()

                Button(list.isPinned ? "Remove from Sidebar" : "Pin to Sidebar") {
                    env.store.setPinned(!list.isPinned, for: list)
                }
                if !list.isSystemInbox {
                    Button("New Child List") {
                        if let child = env.store.createChildList(in: list) { env.navigator.go(to: .list(child.id)) }
                    }
                    .disabled(list.isEffectivelyArchived)
                    Button("Move List…") { env.listPendingMove = list }
                    Button(list.isArchived ? "Unarchive List" : "Archive List") {
                        env.store.setArchived(!list.isArchived, for: list)
                    }
                }
                Button("Duplicate List") {
                    let copy = env.store.duplicateList(list)
                    env.navigator.go(to: .list(copy.id))
                }
                Button("Use as template…") {
                    env.templateCopyRequest = TemplateCopyRequest(source: .list(list.id), undoManager: nil)
                }
                Button("Export as Markdown…") {
                    MarkdownExporter.presentSavePanel(for: list, store: env.store)
                }
                Button("Copy as Markdown") {
                    MarkdownExporter.copyToPasteboard(list: list, store: env.store)
                }
                CopyItemLinkButton(target: .list(list.id))

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
            .accessibilityLabel("List options")
        }
    }

    private var viewPicker: some View {
        Picker("List view", selection: viewModeSelection) {
            ForEach(ListViewMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
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
                    .accessibilityLabel("\(accent.title) list colour")
                    .accessibilityValue(list.accent == accent ? "Selected" : "")
                }
            }
        }
        .padding(14)
        .frame(width: 360)
    }
}
