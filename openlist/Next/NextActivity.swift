//
//  NextActivity.swift
//  openlist
//
//  Completion heatmap, the selected day and the change log.
//

import AppKit
import CoreData
import SwiftData
import SwiftUI

struct NextActivityScreen: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    @State private var heatmap: ActivityHeatmap?
    @State private var events: [ActivityEvent] = []
    @State private var loadError: String?

    var body: some View {
        NXPage(wide: true) {
            NXScreenHeader(tile: .icon("square.grid.2x2.fill"), color: style.accent, title: "Activity",
                           subtitle: "What you finished and what changed")
            Group {
                if let heatmap {
                    // The panel wraps below only when less than its 260pt minimum
                    // is left, however long a title it truncates.
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 22) {
                            NXHeatmapCard(heatmap: heatmap)
                            NXActivityDayPanel(heatmap: heatmap).frame(minWidth: 260, idealWidth: 260, maxWidth: .infinity)
                        }
                        VStack(alignment: .leading, spacing: 22) {
                            // Narrower than the card, it scrolls sideways, as the
                            // design's page does, opened at today's end.
                            ScrollView(.horizontal) { NXHeatmapCard(heatmap: heatmap) }
                                .defaultScrollAnchor(.trailing, for: .initialOffset)
                                .defaultScrollAnchor(.leading, for: .alignment)
                                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                                .fixedSize(horizontal: false, vertical: true)
                            NXActivityDayPanel(heatmap: heatmap).frame(maxWidth: .infinity)
                        }
                    }
                } else if let loadError {
                    NXDashedEmpty(text: loadError)
                } else {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(40)
                }
            }
            .padding(.top, 22)
            NXChangesSection(events: events).padding(.top, 28)
        }
        .task { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
        .onChange(of: env.settings.firstWeekday) { refresh() }
    }

    private func refresh() {
        do {
            heatmap = try env.store.activityHeatmap(calendar: env.settings.calendar)
            loadError = nil
        } catch {
            heatmap = nil
            loadError = "Saved activity could not be read. \(error.localizedDescription)"
        }
        loadEvents()
    }

    /// Saved history from this session, which Changes merges with the log,
    /// then the newest from before it for Earlier. Fetched apart so a long
    /// session never crowds Earlier out.
    private func loadEvents() {
        let start = env.workbench.startedAt
        events = env.store.recentActivity(limit: 200, since: start) + env.store.recentActivity(limit: 40, before: start)
    }
}

// MARK: Heatmap

private enum NXHeat {
    static let cell: CGFloat = 30
    static let gap: CGFloat = 4

    @MainActor static func band(_ count: Int?, accent: Color) -> Color {
        guard let count else { return .clear }
        switch ActivityBand.level(count) {
        case 0: return NX.ink(0.05)
        case 1: return accent.opacity(0.2)
        case 2: return accent.opacity(0.4)
        case 3: return accent.opacity(0.65)
        default: return accent
        }
    }
}

private struct NXHeatmapCard: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    let heatmap: ActivityHeatmap

    var body: some View {
        let calendar = heatmap.calendar
        let weeks = Int((Double(heatmap.days.count) / 7).rounded(.up))
        let today = calendar.startOfDay(for: .now)
        let selected = env.workbench.activityDay.map { calendar.startOfDay(for: $0) } ?? today
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: NXHeat.gap) {
                ForEach(0..<weeks, id: \.self) { week in
                    Text(monthLabel(week: week))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(NX.ink(0.42))
                        .fixedSize()
                        .frame(width: NXHeat.cell, alignment: .leading)
                }
            }
            .padding(.leading, NXHeat.cell + NXHeat.gap)
            .padding(.bottom, 6)
            HStack(alignment: .top, spacing: NXHeat.gap) {
                VStack(alignment: .leading, spacing: NXHeat.gap) {
                    ForEach(0..<7, id: \.self) { row in
                        Text(row.isMultiple(of: 2) ? weekdaySymbol(row) : "")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(NX.ink(0.4))
                            .frame(width: NXHeat.cell, height: NXHeat.cell, alignment: .leading)
                    }
                }
                ForEach(0..<weeks, id: \.self) { week in
                    VStack(spacing: NXHeat.gap) {
                        ForEach(0..<7, id: \.self) { row in
                            let index = week * 7 + row
                            let day = index < heatmap.days.count ? heatmap.days[index] : nil
                            NXHeatCell(day: day, selected: day?.id == selected, isToday: day?.id == today) {
                                env.workbench.activityDay = day?.id
                            }
                        }
                    }
                }
            }
            HStack(spacing: 6) {
                Text("Fewer")
                ForEach([(0, "0"), (1, "1"), (2, "2–3"), (5, "4–6"), (8, "7+")], id: \.0) { count, label in
                    Text(label)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(count >= 4 ? .white : NX.ink(0.55))
                        .padding(.horizontal, 4)
                        .frame(minWidth: 22, minHeight: 16)
                        .background(NXHeat.band(count, accent: style.accent), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                Text("More")
                Spacer(minLength: 20)
                Text(summary)
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(NX.ink(0.45))
            .padding(.top, 14)
            .padding(.leading, NXHeat.cell + NXHeat.gap)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
        .fixedSize()
        .background(NX.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(NX.ink(0.12), lineWidth: 0.5))
    }

    private var summary: String {
        let total = heatmap.total
        var streak = 0
        for day in heatmap.days.reversed() {
            if day.count > 0 { streak += 1 } else if day.id != heatmap.end { break }
        }
        return "\(total) \(total == 1 ? "completion" : "completions") · \(streak)-day streak"
    }

    private func weekdaySymbol(_ row: Int) -> String {
        let calendar = heatmap.calendar
        let symbols = calendar.shortWeekdaySymbols
        return symbols[(calendar.firstWeekday - 1 + row) % 7]
    }

    /// A month name over the first week of the range and each week a new month starts in.
    private func monthLabel(week: Int) -> String {
        let calendar = heatmap.calendar
        guard let start = calendar.date(byAdding: .day, value: week * 7, to: heatmap.start),
              let end = calendar.date(byAdding: .day, value: 6, to: start) else { return "" }
        let startsMonth = calendar.component(.month, from: start) != calendar.component(.month, from: end)
            || calendar.component(.day, from: start) == 1
        guard week == 0 || startsMonth else { return "" }
        let month = calendar.component(.day, from: end) < 7 ? end : start
        return month.formatted(.dateTime.month(.abbreviated))
    }
}

private struct NXHeatCell: View {
    @Environment(\.nextStyle) private var style
    let day: ActivityHeatmapDay?
    let selected: Bool
    let isToday: Bool
    let action: () -> Void

    var body: some View {
        let count = day?.count
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        Text(count.map { $0 > 0 ? "\($0)" : "" } ?? "")
            .font(.system(size: 10.5, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle((count ?? 0) >= 4 ? .white : NX.ink(0.62))
            .frame(width: NXHeat.cell, height: NXHeat.cell)
            .background(NXHeat.band(count, accent: style.accent), in: shape)
            .overlay {
                if selected {
                    shape.inset(by: -2).strokeBorder(NX.ink, lineWidth: 2)
                } else if isToday {
                    shape.inset(by: -1.5).strokeBorder(style.accent, lineWidth: 1.5)
                } else if day == nil {
                    shape.strokeBorder(NX.ink(0.07), lineWidth: 1)
                }
            }
            .animation(.easeOut(duration: 0.5), value: count)
            .animation(.easeOut(duration: 0.15), value: selected)
            .contentShape(shape)
            .onTapGesture { if day != nil { action() } }
            .accessibilityElement()
            .accessibilityLabel(day?.accessibilityDescription ?? "Future day")
            .accessibilityAddTraits(day == nil ? [] : [.isButton])
            .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

private struct NXActivityDayPanel: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    @Environment(\.nextLibrary) private var library
    let heatmap: ActivityHeatmap
    @State private var shown = false

    var body: some View {
        let calendar = heatmap.calendar
        let today = calendar.startOfDay(for: .now)
        let selected = env.workbench.activityDay.map { calendar.startOfDay(for: $0) } ?? today
        let day = heatmap.days.first { $0.id == selected }
        let items = (day?.completions ?? []).sorted { $0.date > $1.date }
        let tasks = completedTasks(items)
        VStack(alignment: .leading, spacing: 0) {
            Text(selected == today ? "Today" : selected.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(NX.serif(22))
                .padding(.vertical, NX.serifLeading(22, lineHeight: 1.1))
                .foregroundStyle(NX.ink)
            Text(items.isEmpty ? "No completions recorded" : "\(items.count) \(items.count == 1 ? "task" : "tasks") completed")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(NX.ink(0.48))
                .padding(.top, 6)
                .padding(.bottom, 12)
            VStack(spacing: 2) {
                ForEach(items) { item in
                    let task = item.taskID.flatMap { tasks[$0] }
                    // One in Trash keeps its list, as the design's rows keep
                    // theirs, and one erased since the list it was done in.
                    let list = task.map { library.list($0.listID) } ?? library.list(item.listID)
                    // Only one still in the library opens.
                    let open: (() -> Void)? = task.flatMap { env.store.block(id: $0.id) }.map { task in { env.workbench.inspect(task.id) } }
                    let title = item.title.isEmpty ? "Untitled" : item.title
                    HStack(spacing: 9) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 13)).foregroundStyle(NX.green)
                        Text(title)
                            .font(.system(size: 12.5))
                            .foregroundStyle(NX.ink)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let list {
                            NXListGlyph(list: list, size: 10.5).help(list.displayTitle)
                        } else if !item.listIcon.isEmpty {
                            NXListGlyph.text(item.listIcon, size: 10.5).foregroundStyle(NX.ink(0.42)).help(item.listTitle)
                        } else if !item.listTitle.isEmpty {
                            Text(item.listTitle).font(.system(size: 10.5, weight: .medium)).foregroundStyle(NX.ink(0.42)).lineLimit(1)
                        }
                        Text(NXFormat.clock(item.date)).font(NX.mono(10.5)).foregroundStyle(NX.ink(0.4))
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, 4)
                    .overlay(alignment: .top) { Rectangle().fill(NX.ink(0.06)).frame(height: 0.5) }
                    .contentShape(Rectangle())
                    .onTapGesture { open?() }
                    // One element, which opens the task while it's there.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(title)
                    .accessibilityValue([list?.displayTitle ?? item.listTitle, "completed at \(NXFormat.clock(item.date))"]
                        .filter { !$0.isEmpty }.joined(separator: ", "))
                    .modifier(NXDayRowOpen(open: open))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .background(NX.inspector, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(NX.ink(0.08), lineWidth: 0.5))
        // The design's fadeIn plays once, as the screen opens; a day picked
        // after that changes the panel in place.
        .opacity(shown ? 1 : 0)
        .onAppear { withAnimation(style.cssEase(200)) { shown = true } }
    }

    /// The day's tasks, found in the library or in Trash, which keeps them
    /// with their list; one erased since isn't there.
    private func completedTasks(_ items: [ActivityCompletion]) -> [UUID: Block] {
        let ids = Array(Set(items.compactMap(\.taskID)))
        guard !ids.isEmpty,
              let tasks = try? env.store.context.fetch(FetchDescriptor<Block>(predicate: #Predicate { ids.contains($0.id) }))
        else { return [:] }
        return Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

/// A day panel row's role for VoiceOver: a button that opens its task, only
/// while there's one to open.
private struct NXDayRowOpen: ViewModifier {
    let open: (() -> Void)?

    func body(content: Content) -> some View {
        if let open {
            content
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { open() }
        } else {
            content
        }
    }
}

// MARK: Changes

private struct NXChangeItem: Identifiable {
    var id: String
    var icon: String
    var tone: TrayTone
    var label: String
    var detail: String?
    var list: TaskList?
    var listTitle: String
    var at: Date
    var canUndo = false
}

private struct NXChangesSection: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextLibrary) private var library
    let events: [ActivityEvent]

    var body: some View {
        let workbench = env.workbench
        let _ = workbench.undoRevision
        let lines = addedLines()
        let session = sessionItems(lines)
        let earlier = earlierItems(lines)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Changes").font(NX.serif(22)).padding(.vertical, NX.serifLeading(22, lineHeight: 1.1)).foregroundStyle(NX.ink)
                Text("Every edit, newest first. The latest one can be undone here.")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(NX.ink(0.45))
            }
            .padding(.bottom, 4)
            VStack(alignment: .leading, spacing: 12) {
                if !session.isEmpty { group("This session", session) }
                if !earlier.isEmpty { group("Earlier", earlier) }
                if session.isEmpty && earlier.isEmpty {
                    NXDashedEmpty(text: "Nothing has changed yet.").padding(.top, 8)
                }
            }
        }
    }

    private func group(_ title: String, _ items: [NXChangeItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            NXCapsTitle(text: title).padding(.top, 6).padding(.bottom, 8)
            VStack(spacing: 2) {
                ForEach(items) { NXChangeRow(item: $0) }
            }
        }
    }

    /// The log, with the saved history it doesn't tell merged in by time:
    /// edits in the document, over MCP or from another Mac.
    private func sessionItems(_ lines: Set<UUID>) -> [NXChangeItem] {
        let workbench = env.workbench
        var seen: Set<String> = []
        var items: [NXChangeItem] = []
        let lists = loggedLists(workbench.log)
        for entry in workbench.log {
            let key = "\(entry.batch)\(entry.label)"
            guard seen.insert(key).inserted else { continue }
            let list = entry.taskID.flatMap { lists[$0] }
            items.append(NXChangeItem(id: "s\(entry.id)", icon: Self.outline(entry.icon), tone: entry.tone, label: entry.label,
                                      list: list, listTitle: list?.displayTitle ?? "", at: entry.at,
                                      canUndo: items.isEmpty && entry.batch == workbench.latestBatch && workbench.canUndo))
        }
        // History the log's own changes saved, or their Undo and Redo, is
        // already here or was taken back.
        var saved = events.filter { event in
            event.timestamp >= workbench.startedAt
                && !workbench.logWrote(at: event.timestamp, about: [event.blockID, event.listID])
        }.map { item($0, lines: lines) }[...]
        var merged: [NXChangeItem] = []
        for item in items {
            while let next = saved.first, next.at > item.at { merged.append(saved.removeFirst()) }
            merged.append(item)
        }
        return merged + saved
    }

    /// Saved history from before this session.
    private func earlierItems(_ lines: Set<UUID>) -> [NXChangeItem] {
        events.filter { $0.timestamp < env.workbench.startedAt }.prefix(40).map { item($0, lines: lines) }
    }

    /// Each logged task's list, the task found in the library or in Trash,
    /// which keeps it, so a row about a task still shows its list once it's
    /// trashed, as the design's do. An erased task has none.
    private func loggedLists(_ log: [ChangeEntry]) -> [UUID: TaskList] {
        let ids = Array(Set(log.compactMap(\.taskID)))
        guard !ids.isEmpty,
              let tasks = try? env.store.context.fetch(FetchDescriptor<Block>(predicate: #Predicate { ids.contains($0.id) }))
        else { return [:] }
        return Dictionary(tasks.compactMap { task in library.list(task.listID).map { (task.id, $0) } },
                          uniquingKeysWith: { first, _ in first })
    }

    /// The saved notes that are a heading or text line MCP added, which it
    /// saves as a note: each reads as the line added, as the design's new
    /// line does. The line is found in the library or in Trash; one erased
    /// since is a line when no history here tracks it as a task, as none
    /// tracks a line.
    private func addedLines() -> Set<UUID> {
        let ids = Set(events.filter { $0.kind == .noteAdded }.compactMap(\.blockID))
        guard !ids.isEmpty else { return [] }
        let wanted = Array(ids)
        guard let found = try? env.store.context.fetch(FetchDescriptor<Block>(predicate: #Predicate { wanted.contains($0.id) }))
        else { return [] }
        let tracked = Set(events.filter { $0.changeData != nil }.compactMap(\.blockID))
        return Set(found.filter { !$0.isTask }.map(\.id))
            .union(ids.subtracting(found.map(\.id)).subtracting(tracked))
    }

    private func item(_ event: ActivityEvent, lines: Set<UUID>) -> NXChangeItem {
        // A line taken out as it was left empty is an edit, as the log draws it.
        let removedLine = event.change?.removedEmptyLine == true
        let addedLine = event.kind == .noteAdded && event.blockID.map(lines.contains) == true
        let kind: ActivityKind = removedLine ? .renamed : addedLine ? .created : event.kind
        return NXChangeItem(id: "e\(event.id)", icon: Self.icon(kind), tone: Self.tone(kind),
                            label: addedLine ? "Added \(Self.title(event))" : label(event), detail: event.recordedDetail,
                            list: library.list(event.listID), listTitle: event.listTitle, at: event.timestamp)
    }

    private static func title(_ event: ActivityEvent) -> String {
        NXFormat.quoted(event.title.isEmpty ? "Untitled" : event.title)
    }

    /// A saved change worded as the log words it when it's made, so it reads
    /// the same after a relaunch.
    private func label(_ event: ActivityEvent) -> String {
        let title = Self.title(event)
        let before = event.change?.before
        let after = event.change?.after
        switch event.kind {
        case .completed: return "\(title) done"
        case .created: return "Added \(title)"
        case .moved:
            if let list = after?.listTitle, !list.isEmpty { return "Moved \(title) to \(list)" }
            return "Moved \(title)"
        // The day as it was named when it was set, not as it is today.
        case .scheduled:
            if let due = after?.dueDate {
                return "\(title) → " + NXFormat.dueChange(due, includesTime: after?.includesTime == true, from: before?.dueDate,
                                                          oldIncludesTime: before?.includesTime == true, now: event.timestamp)
            }
            return "Scheduled \(title)"
        case .unscheduled: return "Cleared date on \(title)"
        // A task's title is its line's text, which the design edits.
        case .renamed: return "Edited \(title)"
        case .deleted where event.change?.removedEmptyLine == true: return "Removed an empty line"
        // A list's, like a task's, is in Trash, where it can be restored.
        case .deleted, .listDeleted: return "Moved \(title) to Trash"
        case .labeled where !event.detail.isEmpty: return "Added #\(event.detail) · \(title)"
        case .noteAdded: return "Edited note on \(title)"
        case .restored:
            let list = after.flatMap { $0.listTitle.isEmpty ? nil : $0.listTitle } ?? event.listTitle
            guard !list.isEmpty else { return "Restored \(title)" }
            if let from = recoveredFrom(event, to: list) { return "Restored \(title) to \(list) — from \(from)" }
            // "archived list" as the tray says it, of the list as it is now.
            let archived = (after?.listID ?? event.listID).map { library.hierarchy.isArchived($0) } == true
            return "Restored \(title) to \(archived ? "archived list " : "")\(list)"
        default: return "\(event.kind.verb) \(title)"
        }
    }

    /// Where a task restored to Recovered items, the list the Store makes
    /// for it, came from, as its tray said: the provenance its Trash entry
    /// keeps on it, found in the library or in Trash, until it's trashed
    /// again or erased.
    private func recoveredFrom(_ event: ActivityEvent, to list: String) -> String? {
        guard list == "Recovered items", let id = event.blockID,
              let block = try? env.store.context.fetch(FetchDescriptor<Block>(predicate: #Predicate { $0.id == id })).first,
              let metadata = block.trashMetadata, metadata.recoveryNote != nil
        else { return nil }
        return metadata.formerLocation
    }

    /// The glyph the tray and the log give the same change, always outline,
    /// as the design draws every Changes icon.
    private static func icon(_ kind: ActivityKind) -> String {
        switch kind {
        case .created, .listCreated: "plus.circle"
        case .completed: "checkmark.circle"
        case .reopened, .completionUndone: "arrow.uturn.backward"
        case .scheduled, .unscheduled: "calendar"
        case .moved: "folder"
        case .deleted, .listDeleted: "trash"
        case .labeled: "tag"
        case .starred: "star"
        case .noteAdded, .renamed: "pencil"
        case .restored: "arrow.up.bin"
        }
    }

    /// A snap's glyph as Changes draws it, unfilled as the design's are, so
    /// the same change looks the same this session and after a relaunch.
    private static func outline(_ icon: String) -> String {
        icon.hasSuffix(".fill") ? String(icon.dropLast(".fill".count)) : icon
    }

    private static func tone(_ kind: ActivityKind) -> TrayTone {
        switch kind {
        case .completed: .green
        case .deleted, .listDeleted: .red
        case .starred: .amber
        case .reopened, .completionUndone, .renamed, .noteAdded: .neutral
        default: .accent
        }
    }
}

private struct NXChangeRow: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    let item: NXChangeItem
    @State private var hovering = false

    var body: some View {
        let (foreground, background) = colors
        HStack(spacing: 11) {
            Image(systemName: item.icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(foreground)
                .frame(width: 26, height: 26)
                .background(background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(item.label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(NX.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let list = item.list {
                HStack(spacing: 4) {
                    NXListGlyph(list: list, size: 11)
                    Text(list.displayTitle)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(NX.ink(0.4))
                .lineLimit(1)
            } else if !item.listTitle.isEmpty {
                Text(item.listTitle).font(.system(size: 11, weight: .medium)).foregroundStyle(NX.ink(0.4)).lineLimit(1)
            }
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(NXFormat.relative(item.at, now: context.date))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(NX.ink(0.34))
                    .lineLimit(1)
                    .frame(width: 64, alignment: .trailing)
            }
            if item.canUndo {
                Button("Undo") { env.workbench.undoLast() }
                    .font(.system(size: 10.5, weight: .semibold))
                    .buttonStyle(NXHoverButtonStyle(hover: style.accent.opacity(0.14), rest: NX.ink(0.06), radius: 6,
                                                    padding: EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8),
                                                    foreground: NX.ink(0.6), hoverForeground: style.accent))
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(hovering ? NX.ink(0.035) : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onHover { hovering = $0 }
        .help(item.detail ?? "")
    }

    private var colors: (Color, Color) {
        switch item.tone {
        case .green: (NX.green, NX.green.opacity(0.14))
        case .red: (NX.redText, NX.red.opacity(0.12))
        case .accent: (style.accent, style.accent.opacity(0.1))
        case .amber: (NX.amberText, NX.amber.opacity(0.16))
        case .neutral: (NX.ink(0.6), NX.ink(0.07))
        }
    }
}
