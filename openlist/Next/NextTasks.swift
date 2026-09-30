//
//  NextTasks.swift
//  openlist
//

import AppKit
import SwiftData
import SwiftUI

// MARK: - Query language

/// The Tasks field's reading of the shared word language (`TaskQuery`), over
/// the window's library and workbench.
extension TaskQuery {
    @MainActor
    init(library: NextLibrary) {
        self.init(lists: library.lists, labels: library.labels)
    }

    @MainActor
    func apply(_ query: String, to pool: [Block], workbench: Workbench, now: Date = .now) -> [Block] {
        apply(query, to: pool, now: now, isPlanned: workbench.isPlanned)
    }
}

extension TaskQuery.Segment {
    /// A list or label pill in its list's or label's colour; nil for the rest.
    @MainActor
    func color(in library: NextLibrary) -> Color? {
        switch kind {
        case .list: library.list(listID)?.nxColor
        case .label: labelID.flatMap(library.label)?.nxColor
        default: nil
        }
    }
}

// MARK: - Screen

struct NextTasksScreen: View {
    @Environment(\.nextLibrary) private var library
    /// Every document block, for the order the lists show their tasks in.
    @Query(filter: #Predicate<Block> { $0.trashID == nil }) private var blocks: [Block]

    var body: some View {
        // Ordered here, where nothing reads the filters, so typing in them doesn't walk every outline again.
        NXTasksPage(tasks: Self.outlineOrder(library: library, blocks: blocks))
    }

    /// Every task in the order the lists show it: lists in sidebar order, each in its document's
    /// order under the list's Sort, as its page draws it. Like the design, Tasks keeps that order
    /// in every grouping rather than sorting.
    @MainActor
    static func outlineOrder(library: NextLibrary, blocks: [Block]) -> [Block] {
        library.tasksInOutlineOrder(blocks: blocks)
    }

    @MainActor
    static func pool(tasks: [Block], library: NextLibrary, workbench: Workbench, queryMode: Bool, now: Date) -> [Block] {
        var pool = tasks.filter { task in
            switch workbench.tasksStatus {
            case .open: !task.isCompleted || workbench.closing[task.id] != nil
            case .done: task.isCompleted
            case .all: true
            }
        }
        if queryMode {
            pool = TaskQuery(library: library).apply(workbench.tasksQuery, to: pool, workbench: workbench, now: now)
        } else {
            if !workbench.tasksListFilter.isEmpty {
                pool = pool.filter { $0.listID.map(workbench.tasksListFilter.contains) == true }
            }
            let text = workbench.tasksTitleFilter.trimmingCharacters(in: .whitespaces).lowercased()
            if !text.isEmpty { pool = pool.filter { $0.displayTitle.lowercased().contains(text) } }
        }
        return pool
    }

    @MainActor
    static func groups(pool: [Block], library: NextLibrary, workbench: Workbench, queryMode: Bool, accent: Color,
                       now: Date) -> [NXGroup] {
        var groups: [NXGroup] = []
        switch workbench.tasksGrouping {
        case .list:
            for list in library.lists {
                let rows = pool.filter { $0.listID == list.id }
                if !rows.isEmpty {
                    groups.append(NXGroup(id: "l-\(list.id)", title: list.displayTitle, glyph: list, rows: rows, collapsible: true))
                }
            }
        case .due:
            let muted = NX.ink(0.5)
            let offset = { (task: Block) in task.dueDate.map { NXFormat.dayOffset($0, now: now) } }
            let buckets: [(String, Color, (Block) -> Bool)] = [
                ("Overdue", NX.red, { offset($0).map { $0 < 0 } ?? false }),
                ("Today", accent, { offset($0) == 0 }),
                ("Tomorrow", muted, { offset($0) == 1 }),
                ("This week", muted, { offset($0).map { $0 > 1 && $0 <= 6 } ?? false }),
                ("Later", muted, { offset($0).map { $0 > 6 } ?? false }),
                ("No date", NX.ink(0.35), { $0.dueDate == nil }),
            ]
            for (title, color, matches) in buckets {
                let rows = pool.filter(matches)
                if !rows.isEmpty {
                    groups.append(NXGroup(id: "d-\(title)", title: title, icon: "calendar", color: color, rows: rows, collapsible: true))
                }
            }
        case .none:
            if !pool.isEmpty {
                groups.append(NXGroup(id: "all", title: "All tasks", icon: "checklist", color: NX.green, rows: pool))
            }
        }
        if groups.isEmpty { groups.append(emptyGroup(library: library, workbench: workbench, queryMode: queryMode)) }
        return groups
    }
}

extension NextTasksScreen {
    /// Why the page is empty, from what the filters of the mode in use hide:
    /// nothing yet, nothing open, or a filter, with the way back to every
    /// open task when there are some for it to show.
    @MainActor
    static func emptyGroup(library: NextLibrary, workbench: Workbench, queryMode: Bool) -> NXGroup {
        let trimmed = { (text: String) in text.trimmingCharacters(in: .whitespaces) }
        let filtered = workbench.tasksStatus != .open || (queryMode
            ? !trimmed(workbench.tasksQuery).isEmpty
            : !workbench.tasksListFilter.isEmpty || !trimmed(workbench.tasksTitleFilter).isEmpty)
        if library.tasks.isEmpty {
            return NXGroup(id: "none", rows: [], showHead: false, emptyText: "No tasks in your lists. Press N to capture one.")
        }
        if library.open.isEmpty && (workbench.tasksStatus == .open || !filtered) {
            return NXGroup(id: "none", rows: [], showHead: false, emptyText: "Everything is done. Nothing is open.")
        }
        guard !library.open.isEmpty else {
            return NXGroup(id: "none", rows: [], showHead: false, emptyText: "Nothing matches these filters.")
        }
        return NXGroup(id: "none", rows: [], showHead: false, emptyText: "Nothing matches these filters.",
                       actionLabel: "Show all open tasks") {
            workbench.tasksStatus = .open
            workbench.tasksListFilter = []
            workbench.tasksTitleFilter = ""
            workbench.tasksQuery = ""
        }
    }
}

/// The Tasks screen for tasks already in outline order.
private struct NXTasksPage: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    @Environment(\.nextLibrary) private var library
    let tasks: [Block]

    var body: some View {
        // The design's 20s clock: done-ago chips move on, and the date
        // buckets and words read the day it is, midnight included.
        TimelineView(.periodic(from: .now, by: 20)) { context in
            page(now: context.date)
        }
    }

    private func page(now: Date) -> some View {
        let workbench = env.workbench
        let queryMode = env.settings.tasksFilterStyle == .query
        let pool = NextTasksScreen.pool(tasks: tasks, library: library, workbench: workbench, queryMode: queryMode, now: now)
        let groups = NextTasksScreen.groups(pool: pool, library: library, workbench: workbench, queryMode: queryMode,
                                            accent: style.accent, now: now)
        let listCount = library.lists.count
        return NXPage(rowIDs: NXGroupsStack.rowIDs(groups, workbench: workbench)) {
            NXScreenHeader(tile: .icon("checklist"), color: NX.green, title: "Tasks",
                           subtitle: "\(library.open.count) open across \(listCount) \(listCount == 1 ? "list" : "lists")")
            Group {
                if queryMode {
                    NXTasksQueryBar(count: pool.count)
                } else {
                    NXTasksSentenceBar(count: pool.count)
                }
            }
            .zIndex(10)
            NXGroupsStack(groups: groups, options: NXRowOptions(showList: workbench.tasksGrouping != .list, quiet: true, now: now))
        }
    }
}

// MARK: - Query bar

private struct NXTasksQueryBar: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    @Environment(\.nextLibrary) private var library
    let count: Int
    @FocusState private var fieldFocused: Bool
    /// Natural width of the coloured query text, and the room the field gives it.
    @State private var queryWidth: CGFloat = 0
    @State private var fieldWidth: CGFloat = .infinity
    /// The bar's width and where the field and group label end in it, so the popover fits the page.
    @State private var barWidth: CGFloat = 460
    @State private var clusterEnd: CGFloat = 460
    @State private var clicks = NXBarClicks()

    private nonisolated static let space = "tasks-query-bar"

    var body: some View {
        let workbench = env.workbench
        let focused = workbench.tasksQueryFocused
        let query = workbench.tasksQuery
        let hasQuery = !query.trimmingCharacters(in: .whitespaces).isEmpty
        // The field and group label drop below the tabs when the page is too narrow for both.
        NXWrapBar(gap: 20, alignment: .bottom) {
            tabs
            HStack(alignment: .bottom, spacing: 22) {
                field(query: query, focused: focused, hasQuery: hasQuery)
                Button { workbench.tasksGrouping = workbench.tasksGrouping.next } label: {
                    Text(workbench.tasksGrouping.title)
                        .font(.system(size: 13.5, weight: .medium))
                        .fixedSize()
                        // The design's 13.5/1 line box.
                        .padding(.vertical, (13.5 - NX.lineHeight(13.5)) / 2)
                        .padding(.bottom, 13)
                        .contentShape(Rectangle())
                }
                .buttonStyle(NXTextHoverStyle(color: NX.ink(0.42), hover: NX.ink))
            }
            .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .named(Self.space)).maxX }) { clusterEnd = $0 }
            .overlay(alignment: .topTrailing) {
                if focused {
                    let width = min(460, barWidth)
                    // Right-aligned with the field, unless that would push it past the page's leading edge.
                    let shift = max(0, width - clusterEnd)
                    pillPopover(query: query, width: width)
                        // 8 pt under the 29 pt field, as the design's. Guides
                        // rather than an offset, so its click region moves with it.
                        .alignmentGuide(.top) { $0[.top] - 37 }
                        .alignmentGuide(.trailing) { $0[.trailing] - shift }
                        // The design's popIn as it shows; it goes at once.
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.97, anchor: .topTrailing).combined(with: .opacity)
                                .combined(with: .offset(y: -4)),
                            removal: .identity))
                }
            }
        }
        .coordinateSpace(.named(Self.space))
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { barWidth = $0 }
        .padding(.top, 22)
        .overlay(alignment: .bottom) { Rectangle().fill(NX.ink(0.08)).frame(height: 0.5) }
        // The popover's popIn plays at the design's 170ms whatever the Motion
        // setting, as the tabs' and field's 280ms do.
        .animation(NX.ease(170), value: focused)
        .onChange(of: fieldFocused) { _, value in
            if value { workbench.tasksQueryFocused = true } else {
                // Leave room for a click on a pill before the popover goes.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(120))
                    if !fieldFocused { workbench.tasksQueryFocused = false }
                }
            }
        }
        .onChange(of: workbench.tasksQueryFocused) { _, value in
            if fieldFocused != value { fieldFocused = value }
        }
        .onAppear {
            clicks.install { clicks, event in
                // Clicking a row, tab or the group label blurs the field, as in a browser, so E, T or J
                // act on the rows instead of typing into the query.
                guard let window = event.window, clicks.isEditing(in: "field", window: window),
                      !clicks.contains(event, in: "field", "pills") else { return }
                window.makeFirstResponder(nil)
                // Like the design's blur, the popover and the field's width wait for the click to
                // finish, so the bar doesn't unwrap and move what was clicked out from under it.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(120))
                    if !clicks.isEditing(in: "field", window: window) { workbench.tasksQueryFocused = false }
                }
            }
        }
        // Switching to the sentence bar must not leave the keyboard thinking the field is active.
        .onDisappear {
            clicks.uninstall()
            workbench.tasksQueryFocused = false
        }
    }

    private var tabs: some View {
        let workbench = env.workbench
        let counts: [TasksStatusFilter: Int] = [
            .open: library.open.count,
            .done: library.tasks.count - library.open.count,
            .all: library.tasks.count,
        ]
        return HStack(alignment: .bottom, spacing: 22) {
            ForEach(TasksStatusFilter.allCases) { status in
                let on = workbench.tasksStatus == status
                Button { workbench.tasksStatus = status } label: {
                    // The design's 13.5/1 and 11/1 line boxes.
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(status.title).font(.system(size: 13.5, weight: on ? .semibold : .medium))
                            .foregroundStyle(on ? NX.ink : NX.ink(0.42))
                            .padding(.vertical, (13.5 - NX.lineHeight(13.5)) / 2)
                        Text("\(counts[status] ?? 0)")
                            .font(.system(size: 11, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(NX.ink(on ? 0.45 : 0.28))
                            .padding(.vertical, (11 - NX.lineHeight(11)) / 2)
                    }
                    .animation(NX.cssEase(160), value: on)
                    .padding(.bottom, 13)
                    .overlay(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 2).fill(NX.ink)
                            .frame(height: 2)
                            .scaleEffect(x: on ? 1 : 0, anchor: .center)
                            .offset(y: 0.5)
                            .animation(NX.ease(280), value: on)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .fixedSize()
    }

    private func field(query: String, focused: Bool, hasQuery: Bool) -> some View {
        let workbench = env.workbench
        let parsed = TaskQuery(library: library).parse(query)
        // The overlay can't follow the field editor's scroll, so once the query outgrows the
        // field the real text shows instead and scrolls with the caret.
        let overflowing = queryWidth + 4 > fieldWidth
        let showsGhost = focused && !parsed.ghost.isEmpty
        let width: CGFloat = focused ? 300 : hasQuery ? 240 : 44
        return HStack(spacing: 8) {
            HStack(spacing: 0) {
                ZStack(alignment: .leading) {
                    HStack(spacing: 0) {
                        HStack(spacing: 0) {
                            ForEach(parsed.segments) { segment in
                                segmentText(segment)
                            }
                        }
                        .onGeometryChange(for: CGFloat.self, of: \.size.width) { queryWidth = $0 }
                        if showsGhost, !overflowing {
                            Text(parsed.ghost).foregroundStyle(NX.ink(0.3))
                        }
                        if query.isEmpty {
                            Text(focused ? "Try “kyoto overdue”" : "Filter")
                                .fontWeight(focused ? .regular : .medium)
                                .foregroundStyle(NX.ink(focused ? 0.34 : 0.42))
                        }
                    }
                    .font(.system(size: 13.5))
                    .lineLimit(1)
                    .fixedSize()
                    // The field sets the width, never the text, so `fieldWidth` is the room on offer.
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    .clipped()
                    .opacity(overflowing ? 0 : 1)
                    .allowsHitTesting(false)

                    TextField("", text: Binding(get: { workbench.tasksQuery }, set: { workbench.tasksQuery = $0 }))
                        .textFieldStyle(.plain)
                        .font(.system(size: 13.5))
                        .foregroundStyle(overflowing ? NX.ink : Color.clear)
                        .focused($fieldFocused)
                        .onSubmit { fieldFocused = false }
                        .accessibilityLabel("Filter tasks")
                }
                .frame(height: 20)
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { fieldWidth = $0 }
                // The scrolled text ends at the field's edge, so the completion Tab adds still shows after it.
                if showsGhost, overflowing {
                    Text(parsed.ghost)
                        .font(.system(size: 13.5))
                        .foregroundStyle(NX.ink(0.3))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            if hasQuery {
                Text("\(count)")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(NX.ink(0.4))
                    // The design's fadeIn, 160ms ease, whatever the field animates; gone at once.
                    .transition(.asymmetric(insertion: .opacity.animation(NX.cssEase(160)), removal: .identity))
                    .accessibilityLabel(count == 1 ? "1 matching task" : "\(count) matching tasks")
                Button {
                    workbench.tasksQuery = ""
                    fieldFocused = true
                } label: {
                    // The design's 14 pt icon box.
                    Image(systemName: "xmark").font(.system(size: 10.5, weight: .semibold))
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(NXHoverButtonStyle(hover: NX.ink(0.07), radius: 5,
                                                padding: EdgeInsets(top: 2, leading: 2, bottom: 2, trailing: 2),
                                                foreground: NX.ink(0.4), hoverForeground: NX.ink))
                // Shows and goes at once, as the design's.
                .transition(.identity)
                .accessibilityLabel("Clear filter")
            }
        }
        // The design's 20 pt field and 9 pt under it.
        .padding(.bottom, 9)
        // Narrower than its width only when the bar has wrapped and the page is narrower still.
        .frame(minWidth: 0, idealWidth: width, maxWidth: width, alignment: .leading)
        .clipped()
        .overlay(alignment: .bottom) {
            // It grows over the field's 280ms and darkens over the design's 180ms.
            RoundedRectangle(cornerRadius: 2)
                .animation(NX.cssEase(180)) { $0.foregroundStyle(focused ? NX.ink : NX.ink(0.22)) }
                .frame(height: 2)
                .scaleEffect(x: focused || hasQuery ? 1 : 0, anchor: .leading)
                .offset(y: 0.5)
        }
        .contentShape(Rectangle())
        .onTapGesture { fieldFocused = true }
        .nxClickRegion("field", in: clicks)
        .animation(NX.ease(280), value: focused)
        .animation(NX.ease(280), value: hasQuery)
    }

    @ViewBuilder
    private func segmentText(_ segment: TaskQuery.Segment) -> some View {
        if let kind = segment.kind {
            let color = segment.color(in: library) ?? (kind == .flag ? NX.amberText : style.accent)
            let fill = kind == .flag ? NX.amber : color
            Text(segment.text)
                .foregroundStyle(color)
                .background(fill.opacity(0.11))
                .overlay(alignment: .bottom) { Rectangle().fill(color.opacity(0.33)).frame(height: 1.5) }
                // The underline is an inset shadow in the design, so it follows the rounded corners.
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else {
            Text(segment.text).foregroundStyle(NX.ink)
        }
    }

    private func pillPopover(query: String, width: CGFloat) -> some View {
        let words = TaskQuery.words(in: query)
        let vocabulary = TaskQuery(library: library)
        let rows: [(String, [(word: String, label: String, color: Color, list: TaskList?)])] = [
            ("When", [("overdue", "Overdue"), ("today", "Today"), ("tomorrow", "Tomorrow"), ("week", "This week"),
                      ("later", "Later"), ("undated", "No date")].map { ($0.0, $0.1, style.accent, nil) }),
            ("List", library.lists.map { (vocabulary.key(for: $0), $0.displayTitle, $0.nxColor, $0) }),
            ("Label", library.labels.map { (vocabulary.key(for: $0), "#\($0.name)", $0.nxColor, nil) }),
            ("Only", [("starred", "Starred"), ("planned", "Planned"), ("high", "High priority")]
                .map { ($0.0, $0.1, NX.amberText, nil) }),
        ]
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(rows.filter { !$0.1.isEmpty }, id: \.0) { title, pills in
                HStack(alignment: .top, spacing: 10) {
                    Text(title)
                        .font(.system(size: 9.5, weight: .semibold))
                        .kerning(0.76)
                        .textCase(.uppercase)
                        .foregroundStyle(NX.ink(0.34))
                        // The design's 9.5/1 line box.
                        .padding(.vertical, (9.5 - NX.lineHeight(9.5)) / 2)
                        .frame(width: 44, alignment: .leading)
                        .padding(.top, 7)
                    NXFlow(spacing: 5) {
                        // TaskQuery gives every list and label its own word, so words identify pills.
                        ForEach(pills, id: \.word) { pill in
                            NXQueryPill(label: pill.label, list: pill.list, color: pill.color, isOn: words.contains(pill.word)) {
                                env.workbench.tasksQuery = TaskQuery.toggle(pill.word, in: env.workbench.tasksQuery)
                                fieldFocused = true
                            }
                        }
                    }
                }
                .padding(.vertical, 5)
            }
            // The design's 10.5/1.3: the extra leading between lines and,
            // halved, above the first and below the last.
            let footLeading = 10.5 * 1.3 - NX.lineHeight(10.5)
            HStack(spacing: 8) {
                Text("Words combine — “kyoto overdue #travel”. Anything else matches the title.")
                    .lineSpacing(footLeading)
                    .padding(.vertical, footLeading / 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("⇥ complete · esc clear").fixedSize()
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(NX.ink(0.42))
            .padding(.top, 9)
            .overlay(alignment: .top) { Rectangle().fill(NX.ink(0.07)).frame(height: 0.5) }
            .padding(.top, 6)
        }
        .padding(.top, 10)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .frame(width: width)
        .background(NX.card, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        // Like the design's mouse-down guard, clicks on the pills keep the field focused.
        .nxClickRegion("pills", in: clicks)
        .nxCardShadow(radius: 13, hairline: 0.14, drop: 0.16, y: 18, blur: 44)
        // Its own height, not the field's it is overlaid on, so wrapped pills and copy never clip.
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct NXQueryPill: View {
    let label: String
    var list: TaskList?
    let color: Color
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            // A symbol taller than the text, as some are, keeps to its 12 pt box.
            if let list { NXListGlyph(list: list, size: 11).frame(height: 12) }
            // The design's 12/1 line box, so the pill is 24 pt.
            Text(label).font(.system(size: 12, weight: .medium)).lineLimit(1)
                .padding(.vertical, (12 - NX.lineHeight(12)) / 2)
        }
        .foregroundStyle(isOn ? .white : NX.ink(0.7))
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        // Filled only when on: the design's pills have no hover.
        .background(isOn ? color : .clear, in: Capsule())
        .overlay(Capsule().strokeBorder(isOn ? color : NX.ink(0.12), lineWidth: 1))
        .contentShape(Capsule())
        .onTapGesture(perform: action)
        .animation(NX.cssEase(140), value: isOn)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { action() }
    }
}

/// Plain text button that changes colour on hover, over the design's 160ms,
/// with no pressed state, as the design has none.
struct NXTextHoverStyle: ButtonStyle {
    var color: Color
    var hover: Color

    func makeBody(configuration: Configuration) -> some View {
        Inner(configuration: configuration, color: color, hover: hover)
    }

    private struct Inner: View {
        let configuration: Configuration
        let color: Color
        let hover: Color
        @State private var hovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(hovering ? hover : color)
                .onHover { hovering = $0 }
                .animation(NX.cssEase(160), value: hovering)
        }
    }
}

/// Left-to-right wrapping layout for pills.
struct NXFlow: Layout {
    var spacing: CGFloat = 6
    /// Where shorter views sit in a row of taller ones.
    var alignment: VerticalAlignment = .top
    /// The design's `flex:1` spacer before a final view: the last view sits on the
    /// trailing edge of whichever line it wraps onto.
    var pinsLastToTrailing = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * spacing
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                let inset = alignment == .center ? (row.height - size.height) / 2
                    : alignment == .bottom ? row.height - size.height : 0
                if pinsLastToTrailing, index == subviews.indices.last { x = bounds.maxX - size.width }
                subviews[index].place(at: CGPoint(x: x, y: y + inset), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if needed > width, !row.indices.isEmpty {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

/// The design's wrapping filter bars: the first view on the leading edge and the second on
/// the trailing edge of one line or, when they don't both fit, the second on a line of its
/// own below, leading-aligned and no wider than the bar, with the first wrapping to the bar.
private struct NXWrapBar: Layout {
    /// The design's flex `gap`. Its spacer between the two views takes a gap on each side, so
    /// on one line they keep two gaps apart; a wrapped line sits one gap below.
    var gap: CGFloat
    /// Where the views sit against each other when they share a line.
    var alignment: VerticalAlignment

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let sizes = sizes(width: proposal.width, subviews: subviews) else { return .zero }
        if sizes.wraps {
            return CGSize(width: proposal.width ?? max(sizes.lead.width, sizes.trail.width),
                          height: sizes.lead.height + gap + sizes.trail.height)
        }
        return CGSize(width: proposal.width ?? sizes.lead.width + 2 * gap + sizes.trail.width,
                      height: max(sizes.lead.height, sizes.trail.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let sizes = sizes(width: bounds.width, subviews: subviews) else { return }
        let (lead, trail) = (sizes.lead, sizes.trail)
        if sizes.wraps {
            subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(lead))
            subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.minY + lead.height + gap),
                              proposal: ProposedViewSize(trail))
        } else {
            let line = max(lead.height, trail.height)
            subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.minY + inset(lead.height, in: line)),
                              proposal: ProposedViewSize(lead))
            subviews[1].place(at: CGPoint(x: bounds.maxX - trail.width, y: bounds.minY + inset(trail.height, in: line)),
                              proposal: ProposedViewSize(trail))
        }
    }

    private func sizes(width: CGFloat?, subviews: Subviews) -> (lead: CGSize, trail: CGSize, wraps: Bool)? {
        guard subviews.count == 2 else { return nil }
        let lead = subviews[0].sizeThatFits(.unspecified)
        let trail = subviews[1].sizeThatFits(.unspecified)
        guard let width, lead.width + 2 * gap + trail.width > width else { return (lead, trail, false) }
        return (subviews[0].sizeThatFits(ProposedViewSize(width: width, height: nil)),
                subviews[1].sizeThatFits(ProposedViewSize(width: min(trail.width, width), height: nil)), true)
    }

    private func inset(_ height: CGFloat, in line: CGFloat) -> CGFloat {
        alignment == .center ? (line - height) / 2 : alignment == .bottom ? line - height : 0
    }
}

/// A local mouse-down monitor for the Tasks bars. AppKit leaves a text field first responder
/// when a SwiftUI row, tab or label is clicked, and the sentence menus are overlays rather than
/// popovers, so the bars blur their fields and close their menus themselves. Views mark the
/// areas a click is judged against with `nxClickRegion(_:in:)`.
@MainActor
private final class NXBarClicks {
    private var monitor: Any?
    private var handler: ((NXBarClicks, NSEvent) -> Void)?
    private var regions: [String: NSHashTable<NSView>] = [:]

    /// The handler sees every mouse-down in the app; the event always carries on.
    func install(_ handler: @escaping (NXBarClicks, NSEvent) -> Void) {
        self.handler = handler
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, let handler = self.handler else { return }
                handler(self, event)
            }
            return event
        }
    }

    func uninstall() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        handler = nil
    }

    fileprivate func mark(_ view: NSView, as name: String) {
        regions[name, default: .weakObjects()].add(view)
    }

    /// Whether a region with this name is on screen in `window`.
    func shows(_ name: String, in window: NSWindow?) -> Bool {
        !views(name, in: window).isEmpty
    }

    /// Whether the event landed in a region with one of these names.
    func contains(_ event: NSEvent, in names: String...) -> Bool {
        names.contains { name in
            views(name, in: event.window).contains { $0.bounds.contains($0.convert(event.locationInWindow, from: nil)) }
        }
    }

    /// Whether the window's field editor is editing a text field inside the named region.
    func isEditing(in name: String, window: NSWindow) -> Bool {
        guard let editor = window.firstResponder as? NSText else { return false }
        let field = editor.delegate as? NSView ?? editor
        let frame = field.convert(field.visibleRect, to: nil)
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return views(name, in: window).contains { $0.convert($0.bounds, to: nil).contains(center) }
    }

    private func views(_ name: String, in window: NSWindow?) -> [NSView] {
        guard let window else { return [] }
        return regions[name]?.allObjects.filter { $0.window === window } ?? []
    }
}

/// Marks the area of the view it backs for `NXBarClicks`.
private struct NXClickRegion: NSViewRepresentable {
    let name: String
    let clicks: NXBarClicks

    func makeNSView(context: Context) -> NSView {
        let view = RegionView()
        clicks.mark(view, as: name)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    /// Takes no clicks from the views drawn over it.
    private final class RegionView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

private extension View {
    func nxClickRegion(_ name: String, in clicks: NXBarClicks) -> some View {
        background(NXClickRegion(name: name, clicks: clicks))
    }
}

// MARK: - Sentence bar

/// The sentence bar's menus. The workbench holds the open one so Esc can close it first.
enum NXTasksMenu { case status, lists, group }

private struct NXTasksSentenceBar: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextLibrary) private var library
    let count: Int
    @FocusState private var titleFocused: Bool
    @State private var clicks = NXBarClicks()
    /// The bar's width and where each token starts in it, so a menu stays on the page.
    @State private var barWidth: CGFloat = .infinity
    @State private var tokenStarts: [NXTasksMenu: CGFloat] = [:]
    /// Whether the open menu pops in, decided as it opens and kept while it's
    /// open. The design's is one card, so a menu opened straight from another
    /// moves to its token without its popIn.
    @State private var menuPops = true

    private nonisolated static let space = "tasks-sentence-bar"
    private static let menuWidth: CGFloat = 250

    private var menu: NXTasksMenu? {
        get { env.workbench.tasksMenu }
        nonmutating set { env.workbench.tasksMenu = newValue }
    }

    var body: some View {
        let workbench = env.workbench
        // The sentence wraps, and the title field drops below it when the page is too narrow for both.
        NXWrapBar(gap: 12, alignment: .center) {
            NXFlow(spacing: 3, alignment: .center) {
                Text("Showing")
                token(.status, workbench.tasksStatus.word)
                Text("tasks in")
                token(.lists, listsToken.label, list: listsToken.list)
                Text("by")
                token(.group, workbench.tasksGrouping.word)
                if isDirty {
                    Button("Reset") {
                        workbench.tasksStatus = .open
                        workbench.tasksGrouping = .list
                        workbench.tasksListFilter = []
                        workbench.tasksTitleFilter = ""
                        menu = nil
                    }
                    .font(.system(size: 12, weight: .medium))
                    .buttonStyle(NXHoverButtonStyle(hover: NX.ink(0.05), radius: 6,
                                                    padding: EdgeInsets(top: 5, leading: 7, bottom: 5, trailing: 7),
                                                    foreground: NX.ink(0.45), hoverForeground: NX.ink))
                    .padding(.leading, 4)
                    // The design's fadeIn, 160ms ease, whatever the Motion
                    // setting; it goes at once.
                    .transition(.asymmetric(insertion: .opacity.animation(NX.cssEase(160)), removal: .identity))
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(NX.ink(0.45))
            .padding(.bottom, 10)
            // An open menu stays over the title field once that wraps below the sentence.
            .zIndex(1)

            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 13))
                    .foregroundStyle(NX.ink(0.35))
                TextField("Filter by title", text: Binding(get: { workbench.tasksTitleFilter },
                                                            set: { workbench.tasksTitleFilter = $0 }))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($titleFocused)
                    .onKeyPress(.escape) {
                        workbench.tasksTitleFilter = ""
                        titleFocused = false
                        return .handled
                    }
                if !workbench.tasksTitleFilter.isEmpty {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(NX.ink(0.38))
                        .accessibilityLabel(count == 1 ? "1 matching task" : "\(count) matching tasks")
                }
            }
            // 200 pt wide inside the padding, as the design's box measures it, and no wider than the bar.
            .frame(minWidth: 0, idealWidth: 200, maxWidth: 200, minHeight: 28, maxHeight: 28)
            .padding(.leading, 2)
            .padding(.trailing, 4)
            // The design's transparent 1 pt bottom border.
            .padding(.bottom, 1)
            .nxClickRegion("title", in: clicks)
            .padding(.bottom, 10)
        }
        .coordinateSpace(.named(Self.space))
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { barWidth = $0 }
        .padding(.top, 18)
        .padding(.bottom, 4)
        .overlay(alignment: .bottom) { Rectangle().fill(NX.ink(0.07)).frame(height: 0.5) }
        .onChange(of: env.navigator.route) { _, _ in menu = nil }
        .onAppear {
            clicks.install { clicks, event in
                // A click outside the open menu closes it; the tokens open and close their own.
                if clicks.shows("menu", in: event.window), !clicks.contains(event, in: "menu", "tokens") {
                    menu = nil
                }
                // Clicking anywhere else blurs the title field, as in a browser, so J, K and E
                // reach the rows instead of the filter.
                if let window = event.window, clicks.isEditing(in: "title", window: window),
                   !clicks.contains(event, in: "title") {
                    window.makeFirstResponder(nil)
                }
            }
        }
        // The menu goes with the bar, so Esc never closes one that isn't on screen.
        .onDisappear {
            clicks.uninstall()
            menu = nil
        }
    }

    private var isDirty: Bool {
        let workbench = env.workbench
        return workbench.tasksStatus != .open || workbench.tasksGrouping != .list
            || !workbench.tasksListFilter.isEmpty || !workbench.tasksTitleFilter.isEmpty
    }

    /// The lists token's words, and the one list whose glyph leads them.
    private var listsToken: (label: String, list: TaskList?) {
        let filter = env.workbench.tasksListFilter
        if filter.isEmpty { return ("all lists", nil) }
        if filter.count == 1, let list = library.list(filter.first) { return (list.displayTitle, list) }
        return ("\(filter.count) lists", nil)
    }

    private func token(_ key: NXTasksMenu, _ label: String, list: TaskList? = nil) -> some View {
        NXSentenceToken(label: label, list: list, isOpen: menu == key) {
            menuPops = menu == nil
            menu = menu == key ? nil : key
        }
        .nxClickRegion("tokens", in: clicks)
        .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .named(Self.space)).minX }) { tokenStarts[key] = $0 }
        // The design's dropdown: a card flush with the token's leading edge, 6 pt below it.
        .overlay(alignment: .bottomLeading) {
            if menu == key {
                // Moved left only as far as keeps it inside the page's trailing edge.
                let start = tokenStarts[key] ?? 0
                let shift = max(0, min(start, start + Self.menuWidth - barWidth))
                menuView(key)
                    .alignmentGuide(.bottom) { $0[.top] - 6 }
                    // Guides rather than an offset, so its click region moves with it.
                    .alignmentGuide(.leading) { $0[.leading] + shift }
                    // The design's popIn, 160ms whatever the Motion setting,
                    // as it opens; it goes at once.
                    .transition(.asymmetric(
                        insertion: menuPops
                            ? .scale(scale: 0.97, anchor: .topLeading).combined(with: .opacity)
                                .combined(with: .offset(y: -4)).animation(NX.ease(160))
                            : .identity,
                        removal: .identity))
            }
        }
        // Over the words and tokens after it.
        .zIndex(menu == key ? 1 : 0)
    }

    private func menuView(_ key: NXTasksMenu) -> some View {
        let workbench = env.workbench
        return VStack(alignment: .leading, spacing: 1) {
            switch key {
            case .status:
                let counts: [TasksStatusFilter: Int] = [.open: library.open.count,
                                                        .done: library.tasks.count - library.open.count,
                                                        .all: library.tasks.count]
                ForEach(TasksStatusFilter.allCases) { status in
                    menuRow(label: status.title, count: counts[status], isOn: workbench.tasksStatus == status) {
                        workbench.tasksStatus = status
                        menu = nil
                    }
                }
            case .group:
                ForEach(TasksGroupingMode.allCases) { mode in
                    menuRow(label: mode == .none ? "Nothing — one list" : mode == .list ? "List" : "Due date",
                            isOn: workbench.tasksGrouping == mode) {
                        workbench.tasksGrouping = mode
                        menu = nil
                    }
                }
            case .lists:
                menuRow(label: "All lists", isOn: workbench.tasksListFilter.isEmpty) { workbench.tasksListFilter = [] }
                ForEach(library.lists, id: \.id) { list in
                    menuRow(label: list.displayTitle, list: list, count: library.openCount(in: list.id),
                            isOn: workbench.tasksListFilter.contains(list.id)) {
                        if workbench.tasksListFilter.contains(list.id) {
                            workbench.tasksListFilter.remove(list.id)
                        } else {
                            workbench.tasksListFilter.insert(list.id)
                        }
                    }
                }
            }
        }
        .padding(5)
        .frame(width: Self.menuWidth)
        .background(NX.card, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .nxClickRegion("menu", in: clicks)
        .nxCardShadow(radius: 11, hairline: 0.14, drop: 0.18, y: 16, blur: 40)
        .fixedSize()
    }

    private func menuRow(label: String, list: TaskList? = nil, count: Int? = nil, isOn: Bool,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Group {
                    if let list { NXListGlyph(list: list, size: 12) } else { Color.clear }
                }
                .frame(width: 16)
                .accessibilityHidden(true)
                Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(NX.ink).lineLimit(1)
                Spacer(minLength: 6)
                if let count {
                    Text("\(count)").font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundStyle(NX.ink(0.36))
                }
            }
        }
        .buttonStyle(NXPanelRowStyle(isOn: isOn))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private struct NXSentenceToken: View {
    let label: String
    /// A single list, whose glyph leads the label.
    var list: TaskList?
    let isOpen: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 1) {
            // One run, as the design's `emoji + " " + name`, the emoji at the design's size.
            Group {
                if let list { Text("\(NXListGlyph.text(list, size: 13)) \(label)") } else { Text(label) }
            }
            .font(.system(size: 13, weight: .semibold)).foregroundStyle(NX.ink).lineLimit(1)
            // The design's 14 pt icon box, which spaces the chevron from the label and the edge.
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(NX.ink(0.5))
                .frame(width: 14, height: 14)
        }
        .padding(.vertical, 5)
        .padding(.leading, 7)
        .padding(.trailing, 4)
        // The design's `background 140ms ease`, under the pointer and as its
        // menu opens and closes. Only the fill eases: a pick's new label and
        // width land at once, as the design's.
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .animation(NX.cssEase(140)) {
                    $0.foregroundStyle(isOpen ? NX.ink(0.07) : hovering ? NX.ink(0.06) : .clear)
                }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: action)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(isOpen ? "Expanded" : "Collapsed")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }
}
