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
    @State private var history = NXSavedHistory()
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
            NXChangesSection(history: history).padding(.top, 28)
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
    /// change saved history for, up to a bound. Each event is decoded once,
    /// here, and Earlier's rows are worded here, not as Changes draws.
    private func loadEvents() {
        let store = env.store
        let start = env.workbench.startedAt
        var saved: [NXSavedEvent] = []
        var facts: [NXSavedFact] = []
        var rows: [[Int]] = []
        while saved.count < 4000 {
            let page = store.recentActivity(limit: 200, before: start, offset: saved.count).map(NXSavedEvent.init)
            saved += page
            facts += page.map(\.fact)
            rows = NXSavedChanges.rows(facts)
            if page.count < 200 || rows.count > NXChangesSection.earlierRows { break }
        }
        let earlier = rows.prefix(NXChangesSection.earlierRows).map { $0.map { saved[$0] } }
        let session = store.recentActivity(limit: 200, since: start).map(NXSavedEvent.init)
        // The session's rows as they'd be with nothing the log wrote left
        // out, which only ever takes some of a row's history away.
        let sessionRows = NXSavedChanges.rows(session.map(\.fact)).map { $0.map { session[$0] } }
        let tasks = NXSavedTasks(earlier + sessionRows, store: store)
        history = NXSavedHistory(session: session, earlier: earlier.map(tasks.item), tasks: tasks)
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
                    // The design's 500 10/1, fitted over SwiftUI's 13pt line.
                    Text(monthLabel(week: week))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(NX.ink(0.42))
                        .fixedSize()
                        .padding(.vertical, (10 - NX.lineHeight(10)) / 2)
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
            // The design's `background 500ms ease, box-shadow 150ms ease`.
            .animation(NX.cssEase(500), value: count)
            .animation(NX.cssEase(150), value: selected)
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
                .accessibilityAddTraits(.isHeader)
            // The design's 500 11.5/1, fitted over SwiftUI's 14pt line.
            Text(items.isEmpty ? "No completions recorded" : "\(items.count) \(items.count == 1 ? "task" : "tasks") completed")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(NX.ink(0.48))
                .padding(.vertical, (11.5 - NX.lineHeight(11.5)) / 2)
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
                        // The design's 400 12.5/1.3 over SwiftUI's 15pt line.
                        Text(title)
                            .font(.system(size: 12.5))
                            .foregroundStyle(NX.ink)
                            .lineLimit(1)
                            .padding(.vertical, (12.5 * 1.3 - NX.lineHeight(12.5)) / 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let list {
                            NXListGlyph(list: list, size: 10.5).help(list.displayTitle)
                        } else if !item.listIcon.isEmpty || !item.listTitle.isEmpty {
                            // 📋 for one that had no icon, as its glyph.
                            NXListGlyph.text(item.listIcon.isEmpty ? "📋" : item.listIcon, size: 10.5)
                                .foregroundStyle(NX.ink(0.42)).help(item.listTitle)
                        }
                        Text(NXFormat.clock(item.date)).font(NX.mono(10.5)).foregroundStyle(NX.ink(0.4))
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, 4)
                    // The design's 0.5pt top border takes its own half point,
                    // so the row is its 30.75pt.
                    .padding(.top, 0.5)
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
        // The design's fadeIn plays once, as the screen opens, at its own
        // speed whatever the Motion setting; a day picked after that changes
        // the panel in place.
        .opacity(shown ? 1 : 0)
        .onAppear { withAnimation(NX.cssEase(200)) { shown = true } }
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

/// A saved event as Changes reads it, its change decoded once, as it loads.
private struct NXSavedEvent {
    var id: UUID
    var kind: ActivityKind
    var title: String
    var detail: String
    var blockID: UUID?
    var listID: UUID?
    var listTitle: String
    /// Its list's icon then, which draws it once the list is gone.
    var listIcon: String
    var at: Date
    var change: TaskActivityChange?
    /// How Changes groups it with the rest of the change that saved it:
    /// the tasks one change moved, scheduled or trashed read as its one row,
    /// as they do in the log, and a list's own event takes in its tasks'.
    var fact: NXSavedFact

    init(_ event: ActivityEvent) {
        id = event.id
        kind = event.kind
        title = event.title
        detail = event.detail
        blockID = event.blockID
        listID = event.listID
        listTitle = event.listTitle
        listIcon = event.listIcon
        at = event.timestamp
        change = event.change
        let after = change?.after
        fact = NXSavedFact(batch: change?.batchID, kind: event.kindRaw)
        switch kind {
        case .listDeleted: fact.takes = ActivityKind.deleted.rawValue
        case .listCreated: fact.takes = ActivityKind.created.rawValue
        case .restored where blockID == nil: fact.takes = ActivityKind.restored.rawValue
        case _ where blockID == nil: break
        case .completed, .deleted, .unscheduled, .reopened, .completionUndone, .starred: fact.key = event.kindRaw
        case .moved, .restored: fact.key = "\(event.kindRaw) \(after?.listID?.uuidString ?? listTitle)"
        case .created: fact.key = "\(event.kindRaw) \(listID?.uuidString ?? "")"
        // The day, which the row names; each task keeps its own time.
        case .scheduled:
            fact.key = "\(event.kindRaw) \(after?.dueDate.map { Calendar.current.startOfDay(for: $0).timeIntervalSinceReferenceDate } ?? 0)"
        case .labeled: fact.key = "\(event.kindRaw) \(detail)"
        // An edit or a note names its one task.
        default: break
        }
    }

    /// Whether it's a task's tracked history, with the task's state.
    var hasTaskHistory: Bool { change.map { $0.before != nil || $0.after != nil } == true }

    /// A repeat's completion, which rolled it on to its next date.
    var rolls: Bool { kind == .completed && change?.advancesOccurrence == true }

    /// The list a restore put the task back in, as it was then.
    var restoredList: String { change?.after.flatMap { $0.listTitle.isEmpty ? nil : $0.listTitle } ?? listTitle }
}

/// A row of saved history, worded as it loads. What it shows of the library
/// as it is now, its list and whether that's archived, is read as it draws.
private struct NXSavedItem {
    var id: String
    var icon: String
    var tone: TrayTone
    var label: String
    /// A list that, archived now, words the row as `archivedLabel`, as the
    /// tray says it.
    var archivable: UUID?
    var archivedLabel = ""
    var detail: String?
    var listID: UUID?
    var listTitle: String
    var listIcon: String
    var at: Date
}

/// Saved history as Changes reads it, each time it loads: this session's,
/// which Changes merges with the log as it draws, and Earlier's rows.
private struct NXSavedHistory {
    var session: [NXSavedEvent] = []
    var earlier: [NXSavedItem] = []
    var tasks = NXSavedTasks()
}

/// What saved rows read of their tasks, found in the library or in Trash as
/// they load, and the wording that reads them by.
private struct NXSavedTasks {
    /// The parents of the tasks a change's row counts.
    var parents: [UUID: UUID] = [:]
    /// The saved notes that are a heading or text line MCP added, which it
    /// saves as a note: each reads as the line added, as the design's new
    /// line does.
    var lines: Set<UUID> = []
    /// Where a task restored to Recovered items came from.
    var recoveredFrom: [UUID: String] = [:]

    init() {}

    /// Read in one go for `rows`: a line MCP added, a restored task's
    /// provenance, and the tasks a move, restore, add or completion took with
    /// it, which only a row of more than one needs, and never a list's.
    init(_ rows: [[NXSavedEvent]], store: Store) {
        var notes: Set<UUID> = [], recovered: Set<UUID> = [], tracked: Set<UUID> = []
        var counted: Set<UUID> = [], rolled: Set<UUID> = []
        for row in rows {
            for event in row {
                guard let id = event.blockID else { continue }
                if event.kind == .noteAdded { notes.insert(id) }
                if event.kind == .restored, event.restoredList == "Recovered items" { recovered.insert(id) }
                if event.hasTaskHistory { tracked.insert(id) }
            }
            guard row.count > 1, row[0].fact.takes == nil else { continue }
            switch row[0].kind {
            case .moved, .restored, .created: counted.formUnion(row.compactMap(\.blockID))
            // A repeat resets its subtasks at any depth, so its row reads theirs.
            case .completed where row.contains(where: \.rolls): rolled.formUnion(row.compactMap(\.blockID))
            default: break
            }
        }
        let blocks = store.blocksIncludingTrash(ids: notes.union(recovered).union(counted).union(rolled))
        for id in counted.union(rolled) { parents[id] = blocks[id]?.parentID }
        var seen = rolled
        var above = Set(rolled.compactMap { parents[$0] }).subtracting(seen)
        while !above.isEmpty {
            seen.formUnion(above)
            let found = store.blocksIncludingTrash(ids: above)
            for (id, block) in found { parents[id] = block.parentID }
            above = Set(found.values.compactMap(\.parentID)).subtracting(seen)
        }
        // One erased since is a line when no history here tracks it as a
        // task, as none tracks a line.
        lines = notes.filter { blocks[$0].map { !$0.isTask } ?? !tracked.contains($0) }
        // The provenance its Trash entry keeps on it, until it's trashed
        // again or erased.
        for id in recovered {
            if let metadata = blocks[id]?.trashMetadata, metadata.recoveryNote != nil { recoveredFrom[id] = metadata.formerLocation }
        }
    }

    /// A row of saved history: one event as it was recorded, or one change's,
    /// named as the log names it.
    func item(_ row: [NXSavedEvent]) -> NXSavedItem {
        let lead = row[0]
        // A list's own event names its tasks' with it, as the log does.
        guard row.count > 1, lead.fact.takes == nil else { return item(lead) }
        let counted = NXSavedChanges.counted(row.map { NXSavedTask(id: $0.blockID, rolls: $0.rolls) },
                                             kind: lead.fact.kind) { parents[$0] }.map { row[$0] }
        guard counted.count > 1 else { return item(counted.first ?? lead) }
        let tasks = "\(counted.count) tasks"
        let after = lead.change?.after
        let label: String
        switch lead.kind {
        case .completed: label = "\(tasks) done"
        case .created: label = "Added \(tasks)"
        case .moved: label = after.map { $0.listTitle.isEmpty ? "Moved \(tasks)" : "Moved \(tasks) to \($0.listTitle)" } ?? "Moved \(tasks)"
        case .scheduled:
            label = after?.dueDate.map { "\(tasks) → " + NXFormat.dueLabel($0, now: lead.at) } ?? "Scheduled \(tasks)"
        case .unscheduled: label = "Cleared date on \(tasks)"
        case .deleted: label = "Moved \(tasks) to Trash"
        case .labeled: label = "Added #\(lead.detail) · \(tasks)"
        case .restored: label = lead.restoredList.isEmpty ? "Restored \(tasks)" : "Restored \(tasks) to \(lead.restoredList)"
        default: label = "\(lead.kind.verb) \(tasks)"
        }
        // Repeats rolled on with no other task closing, as the log draws them.
        let icon = counted.allSatisfy(\.rolls) ? "repeat" : NXChangesSection.icon(lead.kind)
        return NXSavedItem(id: "e\(lead.id)", icon: icon, tone: NXChangesSection.tone(lead.kind),
                           label: label, listID: lead.listID, listTitle: lead.listTitle, listIcon: lead.listIcon, at: lead.at)
    }

    func item(_ event: NXSavedEvent) -> NXSavedItem {
        // A line taken out as it was left empty is an edit, as the log draws it.
        let change = event.change
        let removedLine = change?.removedEmptyLine == true
        let addedLine = event.kind == .noteAdded && event.blockID.map(lines.contains) == true
        let kind: ActivityKind = removedLine ? .renamed : addedLine ? .created : event.kind
        // A copy, as the log draws Duplicate's and Use as Template…'s, and a
        // repeat rolled on, as it draws one alone.
        let icon = change?.copy != nil ? "plus.square.on.square" : event.rolls ? "repeat" : NXChangesSection.icon(kind)
        var item = NXSavedItem(id: "e\(event.id)", icon: icon, tone: NXChangesSection.tone(kind),
                               label: addedLine ? "Added \(Self.title(event))" : label(event),
                               // Its days named as of the change, as its label names them.
                               detail: ActivityEvent.recordedDetail(event.kind, detail: event.detail, change: change,
                                                                    dateText: { NXFormat.moment($0, includesTime: $1, now: event.at) }),
                               listID: event.listID, listTitle: event.listTitle, listIcon: event.listIcon, at: event.at)
        // "archived list" as the tray says it, of the list as it is now.
        if event.kind == .restored, event.blockID != nil, !event.restoredList.isEmpty, recovered(event) == nil,
           let list = change?.after?.listID ?? event.listID {
            item.archivable = list
            item.archivedLabel = "Restored \(Self.title(event)) to archived list \(event.restoredList)"
        }
        return item
    }

    private static func title(_ event: NXSavedEvent) -> String {
        NXFormat.quoted(event.title.isEmpty ? "Untitled" : event.title)
    }

    /// A saved change worded as the log words it when it's made, so it reads
    /// the same after a relaunch.
    private func label(_ event: NXSavedEvent) -> String {
        let title = Self.title(event)
        let change = event.change
        let before = change?.before
        let after = change?.after
        switch event.kind {
        // A repeat's names the next date the same save rolled it on to, as it
        // was named then.
        case .completed:
            if event.rolls, let due = after?.dueDate { return "\(title) rolls to \(NXFormat.dueLabel(due, now: event.at))" }
            return "\(title) done"
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
                                                          oldIncludesTime: before?.includesTime == true, now: event.at)
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
        // A list's own, whose tasks came back with it, where its tray said
        // it went; history saved before that says only what came back.
        case .restored where event.blockID == nil: return event.detail.isEmpty ? "Restored \(title)" : "Restored \(title) \(event.detail)"
        case .restored:
            let list = event.restoredList
            guard !list.isEmpty else { return "Restored \(title)" }
            if let from = recovered(event) { return "Restored \(title) to \(list) — from \(from)" }
            return "Restored \(title) to \(list)"
        default: return "\(event.kind.verb) \(title)"
        }
    }

    /// Where a task restored to Recovered items, the list the Store makes
    /// for it, came from, as its tray said.
    private func recovered(_ event: NXSavedEvent) -> String? {
        guard event.restoredList == "Recovered items" else { return nil }
        return event.blockID.flatMap { recoveredFrom[$0] }
    }
}

private struct NXChangeItem: Identifiable {
    var id: String
    var icon: String
    var tone: TrayTone
    var label: String
    var detail: String?
    var list: TaskList?
    /// A list since gone, as the row last knew it: its title and icon, or
    /// the list itself while the session still holds it, in Trash.
    var listTitle: String
    var listIcon = ""
    var goneList: TaskList?
    var at: Date
    var canUndo = false
}

private struct NXChangesSection: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextLibrary) private var library
    /// Saved history, read as it loaded.
    let history: NXSavedHistory

    static let earlierRows = 40

    var body: some View {
        let workbench = env.workbench
        let _ = workbench.undoRevision
        let session = sessionItems()
        let earlier = history.earlier.map(item)
        VStack(alignment: .leading, spacing: 0) {
            // The subtitle sits beside the title while it fits whole, and
            // otherwise wraps onto a line of its own, 10pt under, as the
            // design's flex-wrap does.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    changesTitle
                    changesSubtitle.fixedSize()
                }
                VStack(alignment: .leading, spacing: 10) {
                    changesTitle
                    changesSubtitle.fixedSize(horizontal: false, vertical: true)
                }
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

    private var changesTitle: some View {
        Text("Changes").font(NX.serif(22)).padding(.vertical, NX.serifLeading(22, lineHeight: 1.1)).foregroundStyle(NX.ink)
            .accessibilityAddTraits(.isHeader)
    }

    /// The design's 500 11.5/1.3 over SwiftUI's 14pt line, its extra leading
    /// between lines and, halved, around them.
    private var changesSubtitle: some View {
        let leading = 11.5 * 1.3 - NX.lineHeight(11.5)
        return Text("Every edit, newest first. The latest one can be undone here.")
            .font(.system(size: 11.5, weight: .medium))
            .lineSpacing(leading)
            .foregroundStyle(NX.ink(0.45))
            .padding(.vertical, leading / 2)
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
    private func sessionSaved() -> [NXSavedItem] {
        let workbench = env.workbench
        let saved = history.session.filter { !workbench.logWrote(at: $0.at, about: [$0.blockID, $0.listID]) }
        return NXSavedChanges.rows(saved.map(\.fact)).map { history.tasks.item($0.map { saved[$0] }) }
    }

    /// The log, with the saved history it doesn't tell merged in by time:
    /// changes made over MCP or on another Mac.
    private func sessionItems() -> [NXChangeItem] {
        let workbench = env.workbench
        var seen: Set<String> = []
        var items: [NXChangeItem] = []
        let lists = loggedLists(workbench.log)
        for entry in workbench.log {
            let key = "\(entry.batch)\(entry.label)"
            guard seen.insert(key).inserted else { continue }
            let list = entry.taskID.flatMap { lists[$0] }
            // A list since gone draws by its title and icon, as Earlier's do.
            let live = list.flatMap { library.list($0.id) }
            items.append(NXChangeItem(id: "s\(entry.id)", icon: Self.outline(entry.icon), tone: entry.tone, label: entry.label,
                                      list: live, listTitle: list?.displayTitle ?? "", goneList: live == nil ? list : nil, at: entry.at,
                                      canUndo: items.isEmpty && entry.batch == workbench.latestBatch && workbench.canUndo))
        }
        var rest = sessionSaved().map(item)[...]
        var merged: [NXChangeItem] = []
        for item in items {
            while let next = rest.first, next.at > item.at { merged.append(rest.removeFirst()) }
            merged.append(item)
        }
        return merged + rest
    }

    /// A saved row with what it shows of the library as it is now.
    private func item(_ saved: NXSavedItem) -> NXChangeItem {
        let archived = saved.archivable.map { library.hierarchy.isArchived($0) } == true
        return NXChangeItem(id: saved.id, icon: saved.icon, tone: saved.tone, label: archived ? saved.archivedLabel : saved.label,
                            detail: saved.detail, list: library.list(saved.listID), listTitle: saved.listTitle,
                            listIcon: saved.listIcon, at: saved.at)
    }

    /// Each logged task's list, the task found in the library or in Trash,
    /// which keeps it, so a row about a task still shows its list once it's
    /// trashed, as the design's do, and once its list is trashed too. An
    /// erased task has none.
    private func loggedLists(_ log: [ChangeEntry]) -> [UUID: TaskList] {
        let tasks = env.store.blocksIncludingTrash(ids: log.compactMap(\.taskID))
        let gone = Array(Set(tasks.values.compactMap(\.listID).filter { library.list($0) == nil }))
        let found = gone.isEmpty ? [] : (try? env.store.context.fetch(FetchDescriptor<TaskList>(predicate: #Predicate {
            gone.contains($0.id)
        }))) ?? []
        let byID = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return tasks.compactMapValues { task in library.list(task.listID) ?? task.listID.flatMap { byID[$0] } }
    }

    /// The glyph the tray and the log give the same change, always outline,
    /// as the design draws every Changes icon.
    fileprivate static func icon(_ kind: ActivityKind) -> String {
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

    fileprivate static func tone(_ kind: ActivityKind) -> TrayTone {
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
                    // A list since gone, with the icon it had, as the day panel
                    // draws it: the session's own as the live row draws it, a
                    // saved one's symbol in the row's ink, since the log keeps
                    // no colour, and 📋 for one that had no icon, as its glyph.
                    HStack(spacing: 4) {
                        (item.goneList.map { NXListGlyph.text($0, size: 11) }
                            ?? NXListGlyph.text(item.listIcon.isEmpty ? "📋" : item.listIcon, size: 11))
                            .accessibilityHidden(true)
                        Text(item.listTitle)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(NX.ink(0.4))
                    .lineLimit(1)
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
                Button { env.workbench.undoLast() } label: {
                    // The design's 600 10.5/1, so the pill is its 20.5pt.
                    Text("Undo").padding(.vertical, (10.5 - NX.lineHeight(10.5)) / 2)
                }
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
