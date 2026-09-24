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
    @State private var earlier: [[ActivityEvent]] = []
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
            NXChangesSection(events: events, earlier: earlier).padding(.top, 28)
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
    /// session never crowds Earlier out. Earlier's rows are changes, not
    /// events, so it reads on until it has its 40, however many tasks one
    /// change saved history for, up to a bound.
    private func loadEvents() {
        let start = env.workbench.startedAt
        var saved: [ActivityEvent] = []
        var facts: [NXSavedFact] = []
        var rows: [[Int]] = []
        while saved.count < 4000 {
            let page = env.store.recentActivity(limit: 200, before: start, offset: saved.count)
            saved += page
            facts += page.map(\.savedFact)
            rows = NXSavedChanges.rows(facts)
            if page.count < 200 || rows.count > NXChangesSection.earlierRows { break }
        }
        events = env.store.recentActivity(limit: 200, since: start)
        earlier = rows.prefix(NXChangesSection.earlierRows).map { $0.map { saved[$0] } }
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
        env.store.blocksIncludingTrash(ids: items.compactMap(\.taskID))
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

extension ActivityEvent {
    /// How Changes groups it with the rest of the change that saved it:
    /// the tasks one change moved, scheduled or trashed read as its one row,
    /// as they do in the log, and a list's own event takes in its tasks'.
    fileprivate var savedFact: NXSavedFact {
        let change = change
        let after = change?.after
        var fact = NXSavedFact(batch: change?.batchID, kind: kindRaw)
        switch kind {
        case .listDeleted: fact.takes = ActivityKind.deleted.rawValue
        case .listCreated: fact.takes = ActivityKind.created.rawValue
        case .restored where blockID == nil: fact.takes = ActivityKind.restored.rawValue
        case _ where blockID == nil: break
        case .completed, .deleted, .unscheduled, .reopened, .completionUndone, .starred: fact.key = kindRaw
        case .moved, .restored: fact.key = "\(kindRaw) \(after?.listID?.uuidString ?? listTitle)"
        case .created: fact.key = "\(kindRaw) \(listID?.uuidString ?? "")"
        // The day, which the row names; each task keeps its own time.
        case .scheduled:
            fact.key = "\(kindRaw) \(after?.dueDate.map { Calendar.current.startOfDay(for: $0).timeIntervalSinceReferenceDate } ?? 0)"
        case .labeled: fact.key = "\(kindRaw) \(detail)"
        // An edit or a note names its one task.
        default: break
        }
        return fact
    }

    /// Whether it's a task's tracked history, with the task's state.
    fileprivate var hasTaskHistory: Bool {
        change.map { $0.before != nil || $0.after != nil } == true
    }
}

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
    /// Saved history from this session.
    let events: [ActivityEvent]
    /// Saved history from before it, a row of events for each change.
    let earlier: [[ActivityEvent]]

    static let earlierRows = 40

    var body: some View {
        let workbench = env.workbench
        let _ = workbench.undoRevision
        let saved = sessionSaved()
        let rows = saved + earlier
        let blocks = savedBlocks(rows)
        let lines = addedLines(rows, blocks: blocks)
        let session = sessionItems(saved, lines: lines, blocks: blocks)
        let earlier = earlier.map { item($0, lines: lines, blocks: blocks) }
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

    /// This session's saved history the log doesn't tell, a row for each
    /// change: what the log's own changes saved, or their Undo and Redo, is
    /// already there or was taken back.
    private func sessionSaved() -> [[ActivityEvent]] {
        let workbench = env.workbench
        let saved = events.filter { event in
            event.timestamp >= workbench.startedAt
                && !workbench.logWrote(at: event.timestamp, about: [event.blockID, event.listID])
        }
        return NXSavedChanges.rows(saved.map(\.savedFact)).map { $0.map { saved[$0] } }
    }

    /// The log, with the saved history it doesn't tell merged in by time:
    /// changes made over MCP or on another Mac.
    private func sessionItems(_ saved: [[ActivityEvent]], lines: Set<UUID>, blocks: [UUID: Block]) -> [NXChangeItem] {
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
        var rest = saved.map { item($0, lines: lines, blocks: blocks) }[...]
        var merged: [NXChangeItem] = []
        for item in items {
            while let next = rest.first, next.at > item.at { merged.append(rest.removeFirst()) }
            merged.append(item)
        }
        return merged + rest
    }

    /// Each logged task's list, the task found in the library or in Trash,
    /// which keeps it, so a row about a task still shows its list once it's
    /// trashed, as the design's do. An erased task has none.
    private func loggedLists(_ log: [ChangeEntry]) -> [UUID: TaskList] {
        env.store.blocksIncludingTrash(ids: log.compactMap(\.taskID)).compactMapValues { library.list($0.listID) }
    }

    /// The saved rows' blocks, in the library or in Trash, in one read: a
    /// line MCP added, a restored task's provenance, and the tasks a change
    /// took with it. A row of one needs the first two only.
    private func savedBlocks(_ rows: [[ActivityEvent]]) -> [UUID: Block] {
        env.store.blocksIncludingTrash(ids: rows.flatMap { row in
            row.count > 1 ? row.compactMap(\.blockID)
                : row.filter { $0.kind == .noteAdded || $0.kind == .restored }.compactMap(\.blockID)
        })
    }

    /// The saved notes that are a heading or text line MCP added, which it
    /// saves as a note: each reads as the line added, as the design's new
    /// line does. The line is found in the library or in Trash; one erased
    /// since is a line when no history here tracks it as a task, as none
    /// tracks a line.
    private func addedLines(_ rows: [[ActivityEvent]], blocks: [UUID: Block]) -> Set<UUID> {
        let events = rows.joined()
        let ids = Set(events.filter { $0.kind == .noteAdded }.compactMap(\.blockID))
        guard !ids.isEmpty else { return [] }
        let tracked = Set(events.filter { $0.blockID.map(ids.contains) == true && $0.hasTaskHistory }.compactMap(\.blockID))
        let found = ids.filter { blocks[$0] != nil }
        return Set(found.filter { blocks[$0]?.isTask == false })
            .union(ids.subtracting(found).subtracting(tracked))
    }

    /// A row of saved history: one event as it was recorded, or one change's,
    /// named as the log names it.
    private func item(_ row: [ActivityEvent], lines: Set<UUID>, blocks: [UUID: Block]) -> NXChangeItem {
        let lead = row[0]
        // A list's own event names its tasks' with it, as the log does.
        guard row.count > 1, lead.savedFact.takes == nil else { return item(lead, lines: lines, blocks: blocks) }
        // The tasks the change was about, not the subtasks it took with them,
        // as the log counts them, but for a trash, which counts those too.
        let ids = Set(row.compactMap(\.blockID))
        let roots = row.filter { event in event.blockID.flatMap { blocks[$0] }?.parentID.map(ids.contains) != true }
        let counted = [.moved, .restored, .created, .completed].contains(lead.kind) ? roots : row
        guard counted.count > 1 else { return item(counted.first ?? lead, lines: lines, blocks: blocks) }
        let tasks = "\(counted.count) tasks"
        let after = lead.change?.after
        let label: String
        switch lead.kind {
        case .completed: label = "\(tasks) done"
        case .created: label = "Added \(tasks)"
        case .moved: label = after.map { $0.listTitle.isEmpty ? "Moved \(tasks)" : "Moved \(tasks) to \($0.listTitle)" } ?? "Moved \(tasks)"
        case .scheduled:
            label = after?.dueDate.map { "\(tasks) → " + NXFormat.dueLabel($0, now: lead.timestamp) } ?? "Scheduled \(tasks)"
        case .unscheduled: label = "Cleared date on \(tasks)"
        case .deleted: label = "Moved \(tasks) to Trash"
        case .labeled: label = "Added #\(lead.detail) · \(tasks)"
        case .restored:
            let list = after.flatMap { $0.listTitle.isEmpty ? nil : $0.listTitle } ?? lead.listTitle
            label = list.isEmpty ? "Restored \(tasks)" : "Restored \(tasks) to \(list)"
        default: label = "\(lead.kind.verb) \(tasks)"
        }
        return NXChangeItem(id: "e\(lead.id)", icon: Self.icon(lead.kind), tone: Self.tone(lead.kind), label: label,
                            list: library.list(lead.listID), listTitle: lead.listTitle, at: lead.timestamp)
    }

    private func item(_ event: ActivityEvent, lines: Set<UUID>, blocks: [UUID: Block]) -> NXChangeItem {
        // A line taken out as it was left empty is an edit, as the log draws it.
        let change = event.change
        let removedLine = change?.removedEmptyLine == true
        let addedLine = event.kind == .noteAdded && event.blockID.map(lines.contains) == true
        let kind: ActivityKind = removedLine ? .renamed : addedLine ? .created : event.kind
        // A copy, as the log draws Duplicate's and Use as Template…'s.
        let icon = change?.copy == nil ? Self.icon(kind) : "plus.square.on.square"
        return NXChangeItem(id: "e\(event.id)", icon: icon, tone: Self.tone(kind),
                            label: addedLine ? "Added \(Self.title(event))" : label(event, change: change, blocks: blocks),
                            detail: event.recordedDetail, list: library.list(event.listID), listTitle: event.listTitle,
                            at: event.timestamp)
    }

    private static func title(_ event: ActivityEvent) -> String {
        NXFormat.quoted(event.title.isEmpty ? "Untitled" : event.title)
    }

    /// A saved change worded as the log words it when it's made, so it reads
    /// the same after a relaunch.
    private func label(_ event: ActivityEvent, change: TaskActivityChange?, blocks: [UUID: Block]) -> String {
        let title = Self.title(event)
        let before = change?.before
        let after = change?.after
        switch event.kind {
        case .completed: return "\(title) done"
        // A copy's, named as it was made: a list's by the list it copied.
        case .created where change?.copy != nil, .listCreated where change?.copy != nil:
            return change?.copy == .template ? "Copied \(title) as a template" : "Duplicated \(title)"
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
        case .deleted where change?.removedEmptyLine == true: return "Removed an empty line"
        // A list's, like a task's, is in Trash, where it can be restored.
        case .deleted, .listDeleted: return "Moved \(title) to Trash"
        case .labeled where !event.detail.isEmpty: return "Added #\(event.detail) · \(title)"
        case .noteAdded: return "Edited note on \(title)"
        // A list's own, whose tasks came back with it.
        case .restored where event.blockID == nil: return "Restored \(title)"
        case .restored:
            let list = after.flatMap { $0.listTitle.isEmpty ? nil : $0.listTitle } ?? event.listTitle
            guard !list.isEmpty else { return "Restored \(title)" }
            if let from = recoveredFrom(event, to: list, blocks: blocks) { return "Restored \(title) to \(list) — from \(from)" }
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
    private func recoveredFrom(_ event: ActivityEvent, to list: String, blocks: [UUID: Block]) -> String? {
        guard list == "Recovered items", let metadata = event.blockID.flatMap({ blocks[$0] })?.trashMetadata,
              metadata.recoveryNote != nil
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
            // One line for VoiceOver, as it reads: the change, its list, when.
            HStack(spacing: 11) {
                Image(systemName: item.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(foreground)
                    .frame(width: 26, height: 26)
                    .background(background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)
                Text(item.label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(NX.ink)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let list = item.list {
                    HStack(spacing: 4) {
                        NXListGlyph(list: list, size: 11).accessibilityHidden(true)
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
            }
            .accessibilityElement(children: .combine)
            if item.canUndo {
                Button("Undo") { env.workbench.undoLast() }
                    .font(.system(size: 10.5, weight: .semibold))
                    .buttonStyle(NXHoverButtonStyle(hover: style.accent.opacity(0.14), rest: NX.ink(0.06), radius: 6,
                                                    padding: EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8),
                                                    foreground: NX.ink(0.6), hoverForeground: style.accent))
                    // What it takes back, as the tray says it.
                    .accessibilityLabel("Undo \(item.label)")
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
