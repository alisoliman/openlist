//
//  SidebarView.swift
//  openlist
//

import SwiftData
import SwiftUI

/// The left rail: five fixed destinations, then user sections of lists.
struct SidebarView: View {
    @Environment(AppEnvironment.self) private var env

    @Query(sort: [SortDescriptor(\SidebarSection.sortIndex)])
    private var sections: [SidebarSection]

    @Query(filter: #Predicate<TaskList> { !$0.isArchived }, sort: [SortDescriptor(\TaskList.sidebarIndex)])
    private var lists: [TaskList]

    @Query(filter: #Predicate<Block> { $0.kindRaw == "task" && !$0.isCompleted })
    private var openTasks: [Block]

    @Query(sort: [SortDescriptor(\TaskLabel.name)])
    private var labels: [TaskLabel]

    @State private var renamingSectionID: UUID?
    @State private var renamingText = ""
    @FocusState private var isRenamingFocused: Bool
    @State private var dropTargetSectionID: UUID?
    @State private var renamingListID: UUID?
    @State private var listNameDraft = ""

    var body: some View {
        // The sidebar is always on screen and re-renders on every task change,
        // so counts are accumulated in one pass rather than one scan per row.
        let counts = Counts(
            openTasks: ActiveTaskPolicy(lists: lists).tasks(in: openTasks),
            inboxID: lists.first(where: \.isSystemInbox)?.id
        )

        return ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                smartDestinations(counts: counts)
                sectionsList(counts: counts)
                labelsSection(counts: counts)
                Color.clear.frame(height: 12)
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.chrome)
        .safeAreaInset(edge: .bottom) { footer }
        .alert("Rename list", isPresented: Binding(
            get: { renamingListID != nil },
            set: { if !$0 { renamingListID = nil } }
        )) {
            TextField("List name", text: $listNameDraft)
            Button("Cancel", role: .cancel) { renamingListID = nil }
            Button("Rename") {
                if let list = env.store.list(id: renamingListID) {
                    env.store.rename(list, to: listNameDraft.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                renamingListID = nil
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Fixed destinations

    private func smartDestinations(counts: Counts) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            SidebarRow(
                icon: "tray",
                title: "Inbox",
                accent: .blue,
                badge: counts.inbox,
                isSelected: env.navigator.route == .inbox,
                shortcutHint: "⌘1"
            ) { env.navigator.go(to: .inbox) }

            SidebarRow(
                icon: "sun.max",
                title: "Today",
                accent: .orange,
                badge: counts.today,
                isSelected: env.navigator.route == .today,
                shortcutHint: "⌘2"
            ) { env.navigator.go(to: .today) }

            SidebarRow(
                icon: "sparkles",
                title: "Updates",
                accent: .violet,
                badge: 0,
                isSelected: env.navigator.route == .updates,
                shortcutHint: "⌘3"
            ) { env.navigator.go(to: .updates) }

            SidebarRow(
                icon: "checklist",
                title: "Tasks",
                accent: .green,
                badge: 0,
                isSelected: env.navigator.route == .tasks,
                shortcutHint: "⌘4"
            ) { env.navigator.go(to: .tasks) }

            SidebarRow(
                icon: "square.stack",
                title: "Lists",
                accent: .indigo,
                badge: 0,
                isSelected: env.navigator.route == .lists,
                shortcutHint: "⌘5"
            ) { env.navigator.go(to: .lists) }
        }
        .padding(.bottom, Theme.Spacing.sectionGap - 6)
    }

    /// Every badge the sidebar shows, accumulated in a single pass.
    private struct Counts {
        var inbox = 0
        var today = 0
        var byList: [UUID: Int] = [:]
        var byLabel: [UUID: Int] = [:]

        init(openTasks: [Block], inboxID: UUID?) {
            // Hoisted: `isDueOnOrBeforeToday` builds a Calendar per call.
            let calendar = Calendar.current
            let cutoff = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)) ?? .now

            for task in openTasks {
                if let listID = task.listID {
                    byList[listID, default: 0] += 1
                    if listID == inboxID { inbox += 1 }
                }
                if task.isStarred || (task.dueDate.map { $0 < cutoff } ?? false) { today += 1 }
                for labelID in task.labelIDs { byLabel[labelID, default: 0] += 1 }
            }
        }
    }

    // MARK: - Sections

    private func sectionsList(counts: Counts) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(sections) { section in
                sectionView(section, counts: counts)
            }

            // Lists whose section was removed still need somewhere to live —
            // but a list the user deliberately unpinned must not reappear here,
            // which is what made "Remove from Sidebar" look like a no-op.
            let orphans = lists.filter { list in
                !list.isSystemInbox
                    && list.isPinned
                    && (list.sectionID == nil || !sections.contains { $0.id == list.sectionID })
            }
            if !orphans.isEmpty {
                SidebarSectionHeader(
                    title: "Other lists",
                    isCollapsed: false,
                    canEdit: false,
                    onToggle: {},
                    onRename: {},
                    onDelete: {},
                    onAddList: {}
                )
                ForEach(orphans) { list in
                    listRow(list, count: counts.byList[list.id] ?? 0)
                }
            }
        }
    }

    @ViewBuilder
    private func sectionView(_ section: SidebarSection, counts: Counts) -> some View {
        let members = lists.filter { $0.sectionID == section.id && !$0.isSystemInbox }

        VStack(alignment: .leading, spacing: 1) {
            if renamingSectionID == section.id {
                TextField("Section name", text: $renamingText)
                    .textFieldStyle(.plain)
                    .font(Theme.Font.sectionHeader)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .focused($isRenamingFocused)
                    .onAppear { DispatchQueue.main.async { isRenamingFocused = true } }
                    .onSubmit { commitRename(section) }
                    .onExitCommand { renamingSectionID = nil }
                    // Clicking away commits rather than leaving the header stuck
                    // as an editable field.
                    .onChange(of: isRenamingFocused) { _, focused in
                        if !focused, renamingSectionID == section.id { commitRename(section) }
                    }
            } else {
                SidebarSectionHeader(
                    title: section.displayTitle,
                    isCollapsed: section.isCollapsed,
                    canEdit: true,
                    canDelete: !section.isDefault,
                    onToggle: {
                        env.store.setCollapsed(!section.isCollapsed, for: section)
                    },
                    onRename: {
                        renamingText = section.title
                        renamingSectionID = section.id
                    },
                    onDelete: { env.store.deleteSection(section) },
                    onAddList: {
                        let list = env.store.createList(in: section)
                        env.navigator.go(to: .list(list.id))
                    }
                )
            }

            if !section.isCollapsed {
                ForEach(members) { list in
                    listRow(list, count: counts.byList[list.id] ?? 0)
                }

                if members.isEmpty {
                    Text("No lists yet")
                        .font(Theme.Font.metadata)
                        .foregroundStyle(Theme.tertiaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }
            }
        }
        .padding(.bottom, 10)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(dropTargetSectionID == section.id ? Theme.accent.opacity(0.1) : Color.clear)
        )
        .dropDestination(for: String.self) { items, _ in
            dropTargetSectionID = nil
            guard let payload = items.first, let id = DragPayload.list.decode(payload),
                  let list = env.store.list(id: id) else { return false }
            env.store.move(list: list, toSection: section.id, above: nil)
            return true
        } isTargeted: { targeted in
            dropTargetSectionID = targeted ? section.id : nil
        }
    }

    private func listRow(_ list: TaskList, count: Int) -> some View {
        SidebarListRow(
            list: list,
            openCount: count,
            isSelected: env.navigator.route == .list(list.id),
            onOpen: { env.navigator.go(to: .list(list.id)) },
            onRename: {
                listNameDraft = list.title
                renamingListID = list.id
            },
            onUnpin: { env.store.setPinned(false, for: list) },
            onDuplicate: {
                let copy = env.store.duplicateList(list)
                env.navigator.go(to: .list(copy.id))
            },
            onExport: { MarkdownExporter.presentSavePanel(for: list, store: env.store) },
            onDelete: { env.requestDeleteList(list) },
            onDropAbove: { draggedID in
                guard let dragged = env.store.list(id: draggedID), dragged.id != list.id else { return }
                env.store.move(list: dragged, toSection: list.sectionID, above: list)
            }
        )
    }

    private func commitRename(_ section: SidebarSection) {
        env.store.rename(section, to: renamingText)
        renamingSectionID = nil
    }

    // MARK: - Labels

    @ViewBuilder
    private func labelsSection(counts: Counts) -> some View {
        if !labels.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                Text("Labels")
                    .font(Theme.Font.sectionHeader)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.tertiaryText)
                    .padding(.horizontal, 8)
                    .padding(.top, 6)
                    .padding(.bottom, 3)

                ForEach(labels) { label in
                    SidebarRow(
                        icon: "tag",
                        title: label.name,
                        accent: label.accent,
                        badge: counts.byLabel[label.id] ?? 0,
                        isSelected: env.navigator.route == .label(label.id),
                        shortcutHint: nil
                    ) { env.navigator.go(to: .label(label.id)) }
                    .contextMenu {
                        Button("Delete Label", role: .destructive) {
                            if env.navigator.route == .label(label.id) {
                                env.navigator.replace(with: .tasks)
                            }
                            env.store.deleteLabel(label)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 6) {
                Button {
                    let list = env.store.createList(in: env.store.defaultSection())
                    env.navigator.go(to: .list(list.id))
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text("New list")
                            .font(Theme.Font.sidebar)
                    }
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("New list (⇧⌘N)")

                Spacer()

                Button {
                    _ = env.store.createSection()
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.tertiaryText)
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("New section (⌥⌘N)")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
        }
        .background(Theme.chrome)
    }
}

// MARK: - Rows

/// A fixed destination or label row.
struct SidebarRow: View {
    let icon: String
    let title: String
    let accent: ListAccent
    let badge: Int
    let isSelected: Bool
    let shortcutHint: String?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? accent.color : Theme.secondaryText)
                    .frame(width: 16)

                Text(title)
                    .font(Theme.Font.sidebar)
                    .foregroundStyle(isSelected ? Color.primary : Theme.secondaryText)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if badge > 0 {
                    Text("\(badge)")
                        .font(Theme.Font.metadata)
                        .foregroundStyle(Theme.tertiaryText)
                        .monospacedDigit()
                } else if let shortcutHint, isHovering {
                    Text(shortcutHint)
                        .font(Theme.Font.metadata)
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: Theme.Spacing.sidebarRowHeight)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .fill(isSelected ? Theme.accent.opacity(0.14) : (isHovering ? Theme.rowHover : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(title)
    }
}

/// A pinned list in the sidebar.
struct SidebarListRow: View {
    let list: TaskList
    let openCount: Int
    let isSelected: Bool
    let onOpen: () -> Void
    let onRename: () -> Void
    let onUnpin: () -> Void
    let onDuplicate: () -> Void
    let onExport: () -> Void
    let onDelete: () -> Void
    /// Another list was dropped onto this row's upper half.
    var onDropAbove: (UUID) -> Void = { _ in }

    @State private var isHovering = false
    @State private var isDropTarget = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 8) {
                Text(list.icon)
                    .font(.system(size: 12))
                    .frame(width: 16)

                Text(list.displayTitle)
                    .font(Theme.Font.sidebar)
                    .foregroundStyle(isSelected ? Color.primary : Theme.secondaryText)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if openCount > 0 {
                    Text("\(openCount)")
                        .font(Theme.Font.metadata)
                        .foregroundStyle(Theme.tertiaryText)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 8)
            .frame(height: Theme.Spacing.sidebarRowHeight)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .fill(isSelected ? Theme.accent.opacity(0.14) : (isHovering ? Theme.rowHover : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(list.displayTitle)
        .accessibilityLabel(list.displayTitle)
        .accessibilityValue("\(openCount) open tasks")
        .overlay(alignment: .top) {
            if isDropTarget {
                Capsule()
                    .fill(Theme.accent)
                    .frame(height: 2)
            }
        }
        .draggable(DragPayload.list.encode(list.id))
        .dropDestination(for: String.self) { items, _ in
            isDropTarget = false
            guard let payload = items.first, let id = DragPayload.list.decode(payload) else { return false }
            onDropAbove(id)
            return true
        } isTargeted: { isDropTarget = $0 }
        .contextMenu {
            Button("Open") { onOpen() }
            Button("Rename List…") { onRename() }
            Divider()
            Button("Duplicate") { onDuplicate() }
            Button("Export as Markdown…") { onExport() }
            Button("Remove from Sidebar") { onUnpin() }
            Divider()
            Button("Delete List", role: .destructive) { onDelete() }
        }
    }
}

/// The uppercase header above each sidebar section.
struct SidebarSectionHeader: View {
    let title: String
    let isCollapsed: Bool
    let canEdit: Bool
    var canDelete: Bool = true
    let onToggle: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    let onAddList: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 3) {
            Button(action: onToggle) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.tertiaryText)
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    .frame(width: 12)
            }
            .buttonStyle(.plain)
            .disabled(!canEdit)
            .opacity(canEdit ? 1 : 0)
            .accessibilityLabel("\(isCollapsed ? "Expand" : "Collapse") \(title) section")
            .accessibilityValue(isCollapsed ? "Collapsed" : "Expanded")

            Text(title)
                .font(Theme.Font.sectionHeader)
                .textCase(.uppercase)
                .foregroundStyle(Theme.tertiaryText)
                .lineLimit(1)

            Spacer(minLength: 4)

            if canEdit, isHovering {
                Button(action: onAddList) {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.tertiaryText)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Add a list to this section")
                .accessibilityLabel("Add list to \(title)")
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 3)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { if canEdit { onToggle() } }
        .contextMenu {
            if canEdit {
                Button("Rename Section") { onRename() }
                Button("Add List") { onAddList() }
                if canDelete {
                    Divider()
                    Button("Remove Section", role: .destructive) { onDelete() }
                }
            }
        }
    }
}
