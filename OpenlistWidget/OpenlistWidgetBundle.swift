//
//  OpenlistWidgetBundle.swift
//  OpenlistWidget
//

import SwiftUI
import WidgetKit

@main
struct OpenlistWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        SummaryWidget()
        ListsWidget()
    }
}

// MARK: - Timeline plumbing

/// One entry per refresh. The widget reads the snapshot the app publishes into
/// the shared App Group container.
struct SnapshotEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetSnapshot
    /// `true` when no snapshot has been published yet.
    var isPlaceholder: Bool = false
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .placeholder, isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(currentEntry(preview: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = currentEntry(preview: false)
        // The app reloads timelines whenever data changes; this scheduled
        // refresh only exists so "Today" rolls over at midnight even if the
        // app never runs.
        let nextMidnight = Calendar.current.nextDate(
            after: .now,
            matching: DateComponents(hour: 0, minute: 1),
            matchingPolicy: .nextTime
        ) ?? Date.now.addingTimeInterval(3_600)

        completion(Timeline(entries: [entry], policy: .after(nextMidnight)))
    }

    private func currentEntry(preview: Bool) -> SnapshotEntry {
        if preview {
            return SnapshotEntry(date: .now, snapshot: .placeholder, isPlaceholder: true)
        }
        guard let snapshot = WidgetSnapshotStore.read() else {
            return SnapshotEntry(date: .now, snapshot: WidgetSnapshot(), isPlaceholder: true)
        }
        return SnapshotEntry(date: .now, snapshot: snapshot)
    }
}

// MARK: - Today

/// Overdue and due-today work.
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OpenlistToday", provider: SnapshotProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("What is due today, and anything overdue.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct TodayWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var items: [WidgetSnapshot.Item] {
        Array(entry.snapshot.todayItems.prefix(maxRows))
    }

    private var remainingCount: Int {
        max(0, entry.snapshot.overdueCount + entry.snapshot.dueTodayCount - items.count)
    }

    private var maxRows: Int {
        switch family {
        // Two readable titles and their metadata fit the small family; a
        // third squeezed row hides the very information the widget is for.
        case .systemSmall: 2
        case .systemMedium: 4
        default: 9
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 5 : 7) {
            header

            if entry.snapshot.todayItems.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: family == .systemSmall ? 20 : 26))
                            .foregroundStyle(ListAccent.green.color)
                        Text(entry.isPlaceholder ? "Open Openlist" : "All clear")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: family == .systemSmall ? 4 : 5) {
                    ForEach(items) { item in
                        WidgetTaskRow(item: item, isCompact: family == .systemSmall)
                    }
                }

                if remainingCount > 0 {
                    Text("+\(remainingCount) more")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ListAccent.orange.color)

            Text("Today")
                .font(.system(size: 13, weight: .bold))

            Spacer()

            if entry.snapshot.overdueCount > 0 {
                Text("\(entry.snapshot.overdueCount) late")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ListAccent.red.color)
            } else if entry.snapshot.dueTodayCount > 0 {
                Text("\(entry.snapshot.dueTodayCount)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

/// One task line inside a widget.
struct WidgetTaskRow: View {
    let item: WidgetSnapshot.Item
    var isCompact = false

    private var accent: ListAccent {
        ListAccent(rawValue: item.accent) ?? .graphite
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Circle()
                .strokeBorder(item.isOverdue ? ListAccent.red.color : accent.color, lineWidth: 1.5)
                .frame(width: 10, height: 10)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: isCompact ? 11 : 12, weight: .medium))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: isCompact)

                if isCompact {
                    metadata
                } else if !item.listName.isEmpty {
                    Text("\(item.listIcon) \(item.listName)")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            if !isCompact { metadata }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.title), \(item.dueText)\(item.isStarred ? ", starred" : "")\(item.hasRepeat ? ", repeating" : "")")
    }

    private var metadata: some View {
        HStack(spacing: 4) {
            if item.hasRepeat {
                Image(systemName: "repeat")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }

            if item.isStarred {
                Image(systemName: "star.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(ListAccent.amber.color)
                    .padding(.top, 2)
            }

            if !item.dueText.isEmpty {
                Text(item.dueText)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(item.isOverdue ? ListAccent.red.color : .secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }
}

// MARK: - Summary

/// Counts at a glance: inbox, due today, overdue, done today.
struct SummaryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OpenlistSummary", provider: SnapshotProvider()) { entry in
            SummaryWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Summary")
        .description("How much is on your plate right now.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct SummaryWidgetView: View {
    let entry: SnapshotEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ListAccent.violet.color)
                Text("Openlist")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
            }

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 8
            ) {
                stat("Due today", entry.snapshot.dueTodayCount, .violet, "sun.max.fill")
                stat("Overdue", entry.snapshot.overdueCount, .red, "exclamationmark.circle.fill")
                stat("Inbox", entry.snapshot.inboxCount, .blue, "tray.fill")
                stat("Done today", entry.snapshot.completedTodayCount, .green, "checkmark.circle.fill")
            }

            Spacer(minLength: 0)
        }
    }

    private func stat(_ title: String, _ value: Int, _ accent: ListAccent, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 8.5))
                    .foregroundStyle(accent.color)
                Text("\(value)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(value == 0 ? Color.secondary : Color.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value)")
    }
}

// MARK: - Lists

/// Per-list progress.
struct ListsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OpenlistLists", provider: SnapshotProvider()) { entry in
            ListsWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Lists")
        .description("Progress across your lists.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct ListsWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var lists: [WidgetSnapshot.ListSummary] {
        Array(entry.snapshot.lists.prefix(family == .systemMedium ? 3 : 6))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: "square.stack.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ListAccent.indigo.color)
                Text("Lists")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Text("\(entry.snapshot.totalOpenCount) open")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if lists.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    Text(entry.isPlaceholder ? "Open Openlist" : "No lists yet")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                Spacer()
            } else {
                ForEach(lists) { list in
                    listRow(list)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func listRow(_ list: WidgetSnapshot.ListSummary) -> some View {
        let accent = ListAccent(rawValue: list.accent) ?? .graphite
        let total = list.openCount + list.doneCount

        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Text(list.icon)
                    .font(.system(size: 10))
                Text(list.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Spacer()
                Text(list.openCount == 0 ? "Done" : "\(list.openCount)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            ProgressBar(done: list.doneCount, total: total, accent: accent, height: 3)
        }
    }
}
