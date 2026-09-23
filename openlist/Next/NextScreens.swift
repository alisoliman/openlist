//
//  NextScreens.swift
//  openlist
//

import SwiftUI

/// Renders a screen's groups and returns nothing else; screens compose it
/// under their header.
struct NXGroupsStack: View {
    let groups: [NXGroup]
    var options = NXRowOptions()
    var topPadding: CGFloat = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(groups) { group in
                NXGroupView(group: group, options: options)
            }
        }
        .padding(.top, topPadding)
    }

    /// Row IDs in on-screen order, skipping collapsed groups.
    @MainActor
    static func rowIDs(_ groups: [NXGroup], workbench: Workbench) -> [UUID] {
        groups.flatMap { group -> [UUID] in
            let open = !group.collapsible || group.defaultOpen != workbench.collapsedGroups.contains(group.id)
            return open ? group.rows.map(\.id) : []
        }
    }
}

enum NXSort {
    /// Due first, then undated, then capture order.
    static func byDue(_ a: Block, _ b: Block) -> Bool {
        switch (a.dueDate, b.dueDate) {
        case let (x?, y?) where x != y: return x < y
        case (_?, nil): return true
        case (nil, _?): return false
        default: return a.createdAt < b.createdAt
        }
    }
}

// MARK: - Today

struct NextTodayScreen: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    @Environment(\.nextLibrary) private var library

    var body: some View {
        // The design's 20s clock: done-ago chips, late times, the date and the
        // buckets all move on with it, midnight included.
        TimelineView(.periodic(from: .now, by: 20)) { context in
            let now = context.date
            let workbench = env.workbench
            let model = Self.model(library: library, workbench: workbench, showsCompleted: env.settings.showsCompletedTasks,
                                   accent: style.accent, now: now) { env.store.placements(taskID: $0).isEmpty }
            NXPage(rowIDs: NXGroupsStack.rowIDs(model.groups, workbench: workbench)) {
                NXScreenHeader(tile: .icon("sun.max.fill"), color: NX.today, title: "Today",
                               subtitle: now.formatted(.dateTime.weekday(.wide).day().month(.wide)),
                               progress: model.progress)
                if model.clear {
                    todayClear(done: model.progress.done)
                }
                NXGroupsStack(groups: model.groups, options: NXRowOptions(now: now))
                NXAddRow(text: "Add a task for today", forToday: true)
            }
        }
    }

    struct Model {
        var groups: [NXGroup]
        var progress: (done: Int, total: Int)
        var clear: Bool
    }

    @MainActor
    static func model(library: NextLibrary, workbench: Workbench, showsCompleted: Bool, accent: Color, now: Date,
                      isUnplaced: @escaping (UUID) -> Bool) -> Model {
        let visible = library.tasks.filter { !$0.isCompleted || workbench.closing[$0.id] != nil }
        func offset(_ task: Block) -> Int? { task.dueDate.map { NXFormat.dayOffset($0, now: now) } }
        // By day, as the design: Overdue is earlier days only. A timed task
        // whose time has passed stays in Due today, its time chip turned red.
        let overdue = visible.filter { (offset($0) ?? 0) < 0 }.sorted(by: NXSort.byDue)
        let due = visible.filter { offset($0) == 0 }.sorted(by: NXSort.byDue)
        let planned = visible.filter { workbench.isPlanned($0) && (offset($0) ?? 1) > 0 }.sorted(by: NXSort.byDue)
        let starred = visible.filter { $0.isStarred && (offset($0) ?? 1) > 0 && !workbench.isPlanned($0) }.sorted(by: NXSort.byDue)
        let doneToday = library.tasks
            .filter { $0.isCompleted && $0.completedAt.map { NXFormat.dayOffset($0, now: now) == 0 } == true }
            .sorted(by: Block.byCompletionDate)

        var groups: [NXGroup] = []
        if !overdue.isEmpty {
            let ids = overdue.map(\.id)
            groups.append(NXGroup(id: "overdue", title: "Overdue", icon: "exclamationmark.circle.fill", color: NX.red,
                                  rows: overdue, actionLabel: "Move all to today") { workbench.schedule(ids, offset: 0) })
        }
        if !due.isEmpty {
            groups.append(NXGroup(id: "due", title: "Due today", icon: "calendar", color: accent, rows: due))
        }
        if !planned.isEmpty {
            let ids = planned.map(\.id)
            groups.append(NXGroup(id: "planned", title: "Planned for today", icon: "calendar.badge.clock", color: accent,
                                  rows: planned, actionLabel: "Fit into calendar") {
                for id in ids where isUnplaced(id) { workbench.fit(id) }
            })
        }
        if !starred.isEmpty {
            groups.append(NXGroup(id: "starred", title: "Starred", icon: "star.fill", color: NX.amber, rows: starred))
        }
        if !doneToday.isEmpty {
            groups.append(NXGroup(id: "done", title: "Completed today", icon: "checkmark.circle.fill", color: NX.green,
                                  rows: doneToday, collapsible: true, defaultOpen: showsCompleted))
        }
        let open = overdue.count + due.count + planned.count + starred.count
        return Model(groups: groups, progress: (doneToday.count, doneToday.count + open), clear: open == 0)
    }

    private func todayClear(done: Int) -> some View {
        HStack(spacing: 18) {
            Image(systemName: "sun.max.fill").font(.system(size: 34)).foregroundStyle(NX.today)
            VStack(alignment: .leading, spacing: 4) {
                Text("Today is clear").font(NX.serif(26)).foregroundStyle(NX.ink)
                Text("\(done) finished today. Nothing is overdue, due, planned or starred.")
                    .font(.system(size: 13))
                    .foregroundStyle(NX.ink(0.56))
            }
            Spacer(minLength: 8)
            Button("Look at tomorrow") { env.workbench.go(.calendar) }
                .font(.system(size: 12, weight: .semibold))
                .buttonStyle(NXHoverButtonStyle(hover: NX.inspector, rest: NX.card, radius: 8,
                                                padding: EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12),
                                                foreground: NX.ink(0.7)))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(NX.ink(0.14), lineWidth: 0.5))
        }
        .padding(.vertical, 30)
        .padding(.horizontal, 28)
        .background(LinearGradient(colors: [NX.today.opacity(0.08), NX.today.opacity(0.02)], startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.top, 24)
        .modifier(NXLiftIn())
    }
}

/// The design's liftIn entrance: y 10, scale .985, fade.
struct NXLiftIn: ViewModifier {
    @Environment(\.nextStyle) private var style
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .offset(y: shown ? 0 : 10)
            .scaleEffect(shown ? 1 : 0.985)
            .opacity(shown ? 1 : 0)
            .onAppear { withAnimation(style.ease(320)) { shown = true } }
    }
}

// MARK: - List & label

/// The list header's switch between Work and Personal hours.
struct NXHoursMenu: View {
    @Environment(AppEnvironment.self) private var env
    let list: TaskList

    var body: some View {
        let workbench = env.workbench
        let current = workbench.hours(for: list)
        Menu {
            Picker("Plan and Start working use", selection: Binding(get: { current },
                                                                    set: { workbench.setHours($0, for: list.id) })) {
                ForEach(AvailabilityCategory.allCases) { category in
                    let summary = NXHours.summary(env.calendar.preferences.profile(for: category), calendar: env.settings.calendar)
                    Text("\(category.title) Hours · \(summary)").tag(category)
                }
            }
            .pickerStyle(.inline)
            Divider()
            Button("Edit Hours in Settings…") { workbench.go(.settings) }
        } label: {
            HStack(spacing: 4) {
                Text("\(current.title) hours").font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
        }
        .menuStyle(.button)
        .buttonStyle(NXHoverButtonStyle(hover: NX.ink(0.06), radius: 6,
                                        padding: EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4),
                                        foreground: NX.ink(0.48), hoverForeground: NX.ink))
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Which hours Plan and Start working use for this list")
        .accessibilityLabel("Hours: \(current.title)")
    }
}

/// Switches a list between the Next task list and its document, where notes
/// and headings live. The choice is remembered per list on this Mac.
struct NXViewModeButton: View {
    @Environment(AppEnvironment.self) private var env
    let listID: UUID
    var showsTitle = false

    var body: some View {
        let target: ListViewMode = env.navigator.listViewMode(for: listID) == .document ? .tasks : .document
        Button { env.navigator.setListViewMode(target, for: listID) } label: {
            HStack(spacing: 5) {
                Image(systemName: target == .document ? "doc.text" : "checklist").font(.system(size: 14, weight: .medium))
                if showsTitle { Text("Show as \(target.title)").font(.system(size: 12, weight: .medium)) }
            }
        }
        .buttonStyle(NXHoverButtonStyle(hover: NX.ink(0.07), radius: 7,
                                        padding: EdgeInsets(top: 5, leading: 5, bottom: 5, trailing: showsTitle ? 8 : 5),
                                        foreground: NX.ink(0.45), hoverForeground: NX.ink))
        .fixedSize()
        .help(target == .document ? "Show notes and headings" : "Show as a task list")
        .accessibilityLabel("Show as \(target.title)")
    }
}

struct NextListScreen: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextLibrary) private var library
    let list: TaskList

    var body: some View {
        let workbench = env.workbench
        let (ordered, ancestors) = outline()
        let open = ordered.filter { !$0.isCompleted || workbench.closing[$0.id] != nil }
        let done = ordered.filter { $0.isCompleted && workbench.closing[$0.id] == nil }.sorted(by: Block.byCompletionDate)
        let depths = Self.depths(open, ancestors: ancestors)
        let groups = Self.groups(open: open, done: done, showsCompleted: env.settings.showsCompletedTasks)
        let section = library.sectionTitle(for: list)
        let archived = library.archived.contains { $0.id == list.id }
        NXPage(rowIDs: NXGroupsStack.rowIDs(groups, workbench: workbench)) {
            NXScreenHeader(tile: .list(list), color: list.nxColor, title: list.displayTitle,
                           subtitle: "\(open.count) open" + (section.isEmpty ? "" : " · \(section)")
                               + (archived ? " · Archived" : "") + " ·",
                           progress: (ordered.filter(\.isCompleted).count, ordered.count),
                           accessory: AnyView(NXHoursMenu(list: list))) {
                // A list archived through its parent unarchives with the parent.
                if list.isArchived {
                    Button("Unarchive") { workbench.setArchived(false, for: list) }
                        .buttonStyle(NXHoverButtonStyle(hover: NX.ink(0.07), radius: 7,
                                                        padding: EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8),
                                                        foreground: NX.ink(0.55), hoverForeground: NX.ink))
                        .font(.system(size: 12, weight: .medium))
                        .fixedSize()
                        .help("Return this list to the sidebar and active tasks")
                }
                NXViewModeButton(listID: list.id)
            }
            // The design's 20s clock, so Completed's done-ago chips move on.
            TimelineView(.periodic(from: .now, by: 20)) { context in
                NXGroupsStack(groups: groups, options: NXRowOptions(showList: false, listID: list.id, notes: true,
                                                                    depths: depths, now: context.date))
            }
            NXAddRow(text: "Add to \(list.displayTitle)", listID: list.id)
        }
        .onAppear { env.store.markOpened(list) }
    }

    static func groups(open: [Block], done: [Block], showsCompleted: Bool) -> [NXGroup] {
        var groups = [NXGroup(id: "open", rows: open, showHead: false, emptyText: "No open tasks. Press N to capture one.")]
        if !done.isEmpty {
            groups.append(NXGroup(id: "ldone", title: "Completed", icon: "checkmark.circle.fill", color: NX.green,
                                  rows: done, collapsible: true, defaultOpen: showsCompleted))
        }
        return groups
    }

    /// Outline depth within the rows shown: only task ancestors in the same run
    /// count, so a subtask whose parent is finished, or anything in Completed,
    /// never looks nested under an unrelated row.
    static func depths(_ rows: [Block], ancestors: [UUID: [UUID]]) -> [UUID: Int] {
        let shown = Set(rows.lazy.map(\.id))
        var depths: [UUID: Int] = [:]
        for row in rows {
            let depth = ancestors[row.id, default: []].filter(shown.contains).count
            if depth > 0 { depths[row.id] = depth }
        }
        return depths
    }

    /// Tasks in document order, with each one's task ancestors, outermost first.
    private func outline() -> ([Block], [UUID: [UUID]]) {
        // Archived lists opened from the Lists gallery keep their tasks too.
        let tasks = library.tasks(in: list.id)
        let taskIDs = Set(tasks.lazy.map(\.id))
        guard !taskIDs.isEmpty else { return ([], [:]) }
        let rows = BlockTree.flatten(env.store.blocks(inList: list.id), respectCollapse: false)
        var ordered: [Block] = []
        var ancestors: [UUID: [UUID]] = [:]
        // Stack of (document depth, task id or nil) for the current ancestor chain.
        var chain: [(depth: Int, taskID: UUID?)] = []
        for row in rows {
            while let last = chain.last, last.depth >= row.depth { chain.removeLast() }
            let isTask = taskIDs.contains(row.id)
            if isTask {
                ordered.append(row.block)
                let above = chain.compactMap(\.taskID)
                if !above.isEmpty { ancestors[row.id] = above }
            }
            chain.append((row.depth, isTask ? row.id : nil))
        }
        // Tasks the outline could not reach still belong on the screen.
        let seen = Set(ordered.map(\.id))
        ordered += tasks.filter { !seen.contains($0.id) }
        return (ordered, ancestors)
    }
}

struct NextLabelScreen: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextLibrary) private var library
    let label: TaskLabel

    var body: some View {
        let workbench = env.workbench
        let mine = library.tasks.filter { $0.labelIDs.contains(label.id) }
        let open = mine.filter { !$0.isCompleted || workbench.closing[$0.id] != nil }.sorted(by: NXSort.byDue)
        let done = mine.filter { $0.isCompleted && workbench.closing[$0.id] == nil }.sorted(by: Block.byCompletionDate)
        let groups = NextListScreen.groups(open: open, done: done, showsCompleted: env.settings.showsCompletedTasks)
        NXPage(rowIDs: NXGroupsStack.rowIDs(groups, workbench: workbench)) {
            NXScreenHeader(tile: .icon("tag.fill"), color: label.nxColor, title: "#\(label.name)",
                           subtitle: "\(open.count) open \(open.count == 1 ? "task" : "tasks") with this label",
                           progress: (mine.filter(\.isCompleted).count, mine.count))
            // The design's 20s clock, so Completed's done-ago chips move on.
            TimelineView(.periodic(from: .now, by: 20)) { context in
                NXGroupsStack(groups: groups, options: NXRowOptions(showList: true, notes: true, now: context.date))
            }
            NXAddRow(text: "Add a task")
        }
    }
}
