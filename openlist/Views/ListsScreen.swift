//
//  ListsScreen.swift
//  openlist
//

import SwiftData
import SwiftUI

/// A gallery of every list, including ones not pinned to the sidebar.
struct ListsScreen: View {
    @Environment(AppEnvironment.self) private var env

    @Query(sort: [SortDescriptor(\TaskList.sortIndex)])
    private var lists: [TaskList]

    @Query(filter: #Predicate<Block> { $0.kindRaw == "task" })
    private var tasks: [Block]

    @State private var showsArchived = false

    var body: some View {
        // One pass over all tasks instead of two scans per card.
        var counts: [UUID: (open: Int, done: Int)] = [:]
        for task in tasks {
            guard let listID = task.listID else { continue }
            var entry = counts[listID] ?? (0, 0)
            if task.isCompleted { entry.done += 1 } else { entry.open += 1 }
            counts[listID] = entry
        }

        return ScreenScaffold(maxContentWidth: 960) {
            ScreenHeader(
                icon: "square.stack",
                title: "Lists",
                subtitle: "\(visibleLists.count) \(visibleLists.count == 1 ? "list" : "lists")"
            ) {
                HStack(spacing: 4) {
                    Menu {
                        Button(showsArchived ? "Hide Archived" : "Show Archived") {
                            showsArchived.toggle()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 15))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 26)

                    Button {
                        let list = env.store.createList(in: env.store.defaultSection())
                        env.navigator.go(to: .list(list.id))
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("New list (⇧⌘N)")
                }
            }
        } content: {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 220, maximum: 300), spacing: 12)],
                spacing: 12
            ) {
                ForEach(visibleLists) { list in
                    ListCard(
                        list: list,
                        openCount: counts[list.id]?.open ?? 0,
                        doneCount: counts[list.id]?.done ?? 0
                    )
                }
            }
        }
    }

    private var visibleLists: [TaskList] {
        lists.filter { showsArchived || !$0.isArchived }
    }
}

/// One tile in the Lists gallery.
struct ListCard: View {
    let list: TaskList
    let openCount: Int
    let doneCount: Int

    @Environment(AppEnvironment.self) private var env
    @State private var isHovering = false

    private var total: Int { openCount + doneCount }

    var body: some View {
        Button {
            env.navigator.go(to: .list(list.id))
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Text(list.icon)
                        .font(.system(size: 22))
                        .frame(width: 34, height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(list.accent.softBackground)
                        )

                    Spacer()

                    if list.isSystemInbox {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.tertiaryText)
                    } else if list.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.tertiaryText)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(list.displayTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(Theme.Font.metadata)
                        .foregroundStyle(Theme.tertiaryText)
                        .lineLimit(2)
                }

                if total > 0 {
                    ProgressBar(done: doneCount, total: total, accent: list.accent)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(isHovering ? Theme.rowHover : Theme.chipFill.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.separator, lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Open") { env.navigator.go(to: .list(list.id)) }
            Divider()
            Button(list.isPinned ? "Remove from Sidebar" : "Pin to Sidebar") {
                env.store.setPinned(!list.isPinned, for: list)
            }
            Button("Duplicate") {
                let copy = env.store.duplicateList(list)
                env.navigator.go(to: .list(copy.id))
            }
            Button("Export as Markdown…") {
                MarkdownExporter.presentSavePanel(for: list, store: env.store)
            }
            if !list.isSystemInbox {
                Button(list.isArchived ? "Unarchive" : "Archive") {
                    env.store.setArchived(!list.isArchived, for: list)
                }
                Divider()
                Button("Delete List", role: .destructive) {
                    env.requestDeleteList(list)
                }
            }
        }
    }

    private var subtitle: String {
        if !list.summary.isEmpty { return list.summary }
        if total == 0 { return "Empty" }
        return openCount == 0 ? "All \(total) done" : "\(openCount) open · \(doneCount) done"
    }
}

/// A personal history of what changed, grouped by day.
struct UpdatesScreen: View {
    @Environment(AppEnvironment.self) private var env

    @Query(sort: [SortDescriptor(\ActivityEvent.timestamp, order: .reverse)])
    private var events: [ActivityEvent]

    var body: some View {
        ScreenScaffold {
            ScreenHeader(
                icon: "sparkles",
                title: "Updates",
                subtitle: "What you have been up to"
            ) {
                if !events.isEmpty {
                    Menu {
                        Button("Clear History", role: .destructive) {
                            env.store.clearActivity()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 15))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 26)
                }
            }
        } content: {
            if events.isEmpty {
                EmptyStateView(
                    icon: "sparkles",
                    title: "No activity yet",
                    message: "Completing, scheduling and moving tasks shows up here."
                )
            } else {
                ForEach(days) { day in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(day.title)
                            .font(.system(size: 12.5, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.top, 10)
                            .padding(.bottom, 4)

                        ForEach(day.events) { event in
                            ActivityRow(event: event)
                        }
                    }
                }
            }
        }
    }

    private struct Day: Identifiable {
        var id: Date
        var title: String
        var events: [ActivityEvent]
    }

    private var days: [Day] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: events) { calendar.startOfDay(for: $0.timestamp) }
        return grouped.keys.sorted(by: >).map { date in
            Day(
                id: date,
                title: Store.dayHeading(for: date),
                events: (grouped[date] ?? []).sorted { $0.timestamp > $1.timestamp }
            )
        }
    }
}

/// A single line in the Updates feed.
struct ActivityRow: View {
    let event: ActivityEvent

    @Environment(AppEnvironment.self) private var env
    @State private var isHovering = false

    var body: some View {
        Button {
            open()
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: event.kind.symbol)
                    .font(.system(size: 12))
                    .foregroundStyle(event.kind.accent.color)
                    .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(event.kind.verb)
                            .font(Theme.Font.body)
                            .foregroundStyle(Theme.secondaryText)
                        Text(event.title)
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)
                    }

                    HStack(spacing: 6) {
                        if !event.listTitle.isEmpty {
                            Text("\(event.listIcon) \(event.listTitle)")
                                .font(Theme.Font.metadata)
                                .foregroundStyle(Theme.tertiaryText)
                        }
                        if !event.detail.isEmpty {
                            Text(event.detail)
                                .font(Theme.Font.metadata)
                                .foregroundStyle(Theme.tertiaryText)
                        }
                    }
                }

                Spacer(minLength: 8)

                Text(event.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(Theme.Font.metadata)
                    .foregroundStyle(Theme.tertiaryText)
                    .monospacedDigit()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .fill(isHovering ? Theme.rowHover : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private func open() {
        // Prefer the task itself; fall back to the list it belonged to.
        if let blockID = event.blockID, env.store.block(id: blockID) != nil {
            if let listID = event.listID, env.store.list(id: listID) != nil {
                env.navigator.go(to: .list(listID))
            }
            env.navigator.openTask(blockID)
            return
        }
        if let listID = event.listID, env.store.list(id: listID) != nil {
            env.navigator.go(to: .list(listID))
        }
    }
}
