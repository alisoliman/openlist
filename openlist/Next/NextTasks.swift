//
//  NextTasks.swift
//  openlist
//

import SwiftUI

// MARK: - Query language

/// The Tasks filter's word language: dates, flags, list keys and `#labels`
/// combine, and anything else matches the title.
struct NXTaskQuery {
    enum Kind { case date, flag, list, label }

    struct Word {
        let word: String
        let kind: Kind
        var listID: UUID?
        var labelID: UUID?
        var color: Color?
    }

    struct Segment: Identifiable {
        let id: Int
        let text: String
        let kind: Kind?
        let color: Color?
    }

    struct Filter {
        var lists: [UUID] = []
        var due: [String] = []
        var labels: [UUID] = []
        var flags: [String] = []
        var text: [String] = []
    }

    static let dateWords = ["overdue", "today", "tomorrow", "week", "later", "undated"]
    static let flagWords = ["starred", "planned", "high"]

    let vocab: [Word]

    @MainActor
    init(library: NextLibrary) {
        var vocab = Self.dateWords.map { Word(word: $0, kind: .date) } + Self.flagWords.map { Word(word: $0, kind: .flag) }
        for list in library.lists {
            var keys = [Self.key(for: list)]
            for word in list.displayTitle.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
            where word.count >= 4 && !keys.contains(word) {
                keys.append(word)
            }
            vocab += keys.map { Word(word: $0, kind: .list, listID: list.id, color: list.nxColor) }
        }
        vocab += library.labels.map { Word(word: Self.key(for: $0), kind: .label, labelID: $0.id, color: $0.nxColor) }
        self.vocab = vocab
    }

    static func key(for list: TaskList) -> String {
        if list.isSystemInbox { return "inbox" }
        return list.displayTitle.lowercased().split(whereSeparator: \.isWhitespace).last.map(String.init) ?? "list"
    }

    static func key(for label: TaskLabel) -> String {
        "#" + label.name.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: "-")
    }

    func parse(_ query: String) -> (segments: [Segment], filter: Filter, ghost: String) {
        var segments: [Segment] = []
        var filter = Filter()
        var index = 0
        var current = ""
        var currentIsSpace: Bool?
        func flush() {
            guard !current.isEmpty else { return }
            defer { current = ""; index += 1 }
            if currentIsSpace == true {
                segments.append(Segment(id: index, text: current, kind: nil, color: nil))
                return
            }
            let lower = current.lowercased()
            guard let hit = vocab.first(where: { $0.word == lower }) else {
                segments.append(Segment(id: index, text: current, kind: nil, color: nil))
                filter.text.append(lower)
                return
            }
            segments.append(Segment(id: index, text: current, kind: hit.kind, color: hit.color))
            switch hit.kind {
            case .list: filter.lists.append(hit.listID!)
            case .label: filter.labels.append(hit.labelID!)
            case .date: filter.due.append(lower)
            case .flag: filter.flags.append(lower)
            }
        }
        for character in query {
            let isSpace = character.isWhitespace
            if currentIsSpace != isSpace { flush(); currentIsSpace = isSpace }
            current.append(character)
        }
        flush()

        var ghost = ""
        if let last = query.split(whereSeparator: \.isWhitespace).last, query.last?.isWhitespace == false {
            let lower = last.lowercased()
            if !vocab.contains(where: { $0.word == lower }), let match = vocab.first(where: { $0.word.hasPrefix(lower) }) {
                ghost = String(match.word.dropFirst(lower.count))
            }
        }
        return (segments, filter, ghost)
    }

    @MainActor
    func apply(_ query: String, to pool: [Block], workbench: Workbench) -> [Block] {
        let filter = parse(query).filter
        func dueMatches(_ word: String, _ offset: Int?) -> Bool {
            switch word {
            case "overdue": offset.map { $0 < 0 } ?? false
            case "today": offset == 0
            case "tomorrow": offset == 1
            case "week": offset.map { (0...6).contains($0) } ?? false
            case "later": offset.map { $0 > 6 } ?? false
            default: offset == nil
            }
        }
        return pool.filter { task in
            let offset = task.dueDate.map { NXFormat.dayOffset($0) }
            let title = task.displayTitle.lowercased()
            return (filter.lists.isEmpty || task.listID.map(filter.lists.contains) == true)
                && (filter.due.isEmpty || filter.due.contains { dueMatches($0, offset) })
                && (filter.labels.isEmpty || filter.labels.contains { task.labelIDs.contains($0) })
                && filter.flags.allSatisfy { flag in
                    switch flag {
                    case "starred": task.isStarred
                    case "planned": workbench.isPlanned(task)
                    default: task.priority == .high
                    }
                }
                && filter.text.allSatisfy { title.contains($0) }
        }
    }

    /// Adds or removes one word, leaving a trailing space to keep typing.
    static func toggle(_ word: String, in query: String) -> String {
        var parts = query.split(whereSeparator: \.isWhitespace).map(String.init)
        if let index = parts.firstIndex(where: { $0.lowercased() == word }) {
            parts.remove(at: index)
        } else {
            parts.append(word)
        }
        return parts.isEmpty ? "" : parts.joined(separator: " ") + " "
    }

    static func words(in query: String) -> Set<String> {
        Set(query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init))
    }
}

// MARK: - Screen

struct NextTasksScreen: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    @Environment(\.nextLibrary) private var library

    var body: some View {
        let workbench = env.workbench
        let queryMode = env.settings.tasksFilterStyle == .query
        let pool = Self.pool(library: library, workbench: workbench, queryMode: queryMode)
        let groups = Self.groups(pool: pool, library: library, workbench: workbench, accent: style.accent)
        let listCount = library.lists.count
        NXPage(rowIDs: NXGroupsStack.rowIDs(groups, workbench: workbench)) {
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
            NXGroupsStack(groups: groups, options: NXRowOptions(showList: workbench.tasksGrouping != .list, quiet: true))
        }
    }

    @MainActor
    static func pool(library: NextLibrary, workbench: Workbench, queryMode: Bool) -> [Block] {
        var pool = library.tasks.filter { task in
            switch workbench.tasksStatus {
            case .open: !task.isCompleted || workbench.closing[task.id] != nil
            case .done: task.isCompleted
            case .all: true
            }
        }
        if queryMode {
            pool = NXTaskQuery(library: library).apply(workbench.tasksQuery, to: pool, workbench: workbench)
        } else {
            if !workbench.tasksListFilter.isEmpty {
                pool = pool.filter { $0.listID.map(workbench.tasksListFilter.contains) == true }
            }
            let text = workbench.tasksTitleFilter.trimmingCharacters(in: .whitespaces).lowercased()
            if !text.isEmpty { pool = pool.filter { $0.displayTitle.lowercased().contains(text) } }
        }
        return pool.sorted(by: NXSort.byDue)
    }

    @MainActor
    static func groups(pool: [Block], library: NextLibrary, workbench: Workbench, accent: Color) -> [NXGroup] {
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
            let buckets: [(String, Color, (Int?) -> Bool)] = [
                ("Overdue", NX.red, { $0.map { $0 < 0 } ?? false }),
                ("Today", accent, { $0 == 0 }),
                ("Tomorrow", muted, { $0 == 1 }),
                ("This week", muted, { $0.map { $0 > 1 && $0 <= 6 } ?? false }),
                ("Later", muted, { $0.map { $0 > 6 } ?? false }),
                ("No date", NX.ink(0.35), { $0 == nil }),
            ]
            for (title, color, matches) in buckets {
                let rows = pool.filter { matches($0.dueDate.map { NXFormat.dayOffset($0) }) }
                if !rows.isEmpty {
                    groups.append(NXGroup(id: "d-\(title)", title: title, icon: "calendar", color: color, rows: rows, collapsible: true))
                }
            }
        case .none:
            if !pool.isEmpty {
                groups.append(NXGroup(id: "all", title: "All tasks", icon: "checklist", color: NX.green, rows: pool))
            }
        }
        if groups.isEmpty {
            groups.append(NXGroup(id: "none", rows: [], showHead: false, emptyText: "Nothing matches these filters."))
        }
        return groups
    }
}

// MARK: - Query bar

private struct NXTasksQueryBar: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    @Environment(\.nextLibrary) private var library
    let count: Int
    @FocusState private var fieldFocused: Bool

    var body: some View {
        let workbench = env.workbench
        let focused = workbench.tasksQueryFocused
        let query = workbench.tasksQuery
        let hasQuery = !query.trimmingCharacters(in: .whitespaces).isEmpty
        HStack(alignment: .bottom, spacing: 20) {
            tabs
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 22) {
                field(query: query, focused: focused, hasQuery: hasQuery)
                Button { workbench.tasksGrouping = workbench.tasksGrouping.next } label: {
                    Text(workbench.tasksGrouping.title)
                        .font(.system(size: 13.5, weight: .medium))
                        .padding(.bottom, 13)
                        .contentShape(Rectangle())
                }
                .buttonStyle(NXTextHoverStyle(color: NX.ink(0.42), hover: NX.ink))
                .help("Group by list, date or nothing")
            }
            .overlay(alignment: .topTrailing) {
                if focused {
                    pillPopover(query: query)
                        .offset(y: 38)
                        .transition(.scale(scale: 0.96, anchor: .topTrailing).combined(with: .opacity))
                }
            }
        }
        .padding(.top, 22)
        .overlay(alignment: .bottom) { Rectangle().fill(NX.ink(0.08)).frame(height: 0.5) }
        .animation(style.ease(170), value: focused)
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
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(status.title).font(.system(size: 13.5, weight: on ? .semibold : .medium))
                            .foregroundStyle(on ? NX.ink : NX.ink(0.42))
                        Text("\(counts[status] ?? 0)")
                            .font(.system(size: 11, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(NX.ink(on ? 0.45 : 0.28))
                    }
                    .padding(.bottom, 13)
                    .overlay(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 2).fill(NX.ink)
                            .frame(height: 2)
                            .scaleEffect(x: on ? 1 : 0, anchor: .center)
                            .offset(y: 0.5)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .animation(style.ease(280), value: on)
            }
        }
    }

    private func field(query: String, focused: Bool, hasQuery: Bool) -> some View {
        let workbench = env.workbench
        let parsed = NXTaskQuery(library: library).parse(query)
        return HStack(spacing: 8) {
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(parsed.segments) { segment in
                        segmentText(segment)
                    }
                    if focused, !parsed.ghost.isEmpty {
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
                .allowsHitTesting(false)

                TextField("", text: Binding(get: { workbench.tasksQuery }, set: { workbench.tasksQuery = $0 }))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5))
                    .foregroundStyle(.clear)
                    .focused($fieldFocused)
                    .onSubmit { fieldFocused = false }
            }
            .frame(height: 20)
            if hasQuery {
                Text("\(count)")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(NX.ink(0.4))
                    .transition(.opacity)
                Button {
                    workbench.tasksQuery = ""
                    fieldFocused = true
                } label: {
                    Image(systemName: "xmark").font(.system(size: 10.5, weight: .semibold))
                }
                .buttonStyle(NXHoverButtonStyle(hover: NX.ink(0.07), radius: 5,
                                                padding: EdgeInsets(top: 2, leading: 2, bottom: 2, trailing: 2),
                                                foreground: NX.ink(0.4), hoverForeground: NX.ink))
                .transition(.opacity)
            }
        }
        // 20 pt field + 11 pt puts the text on the same line as the tabs' 13 pt padding.
        .padding(.bottom, 11)
        .frame(width: focused ? 300 : hasQuery ? 240 : 44, alignment: .leading)
        .clipped()
        .overlay(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 2)
                .fill(focused ? NX.ink : NX.ink(0.22))
                .frame(height: 2)
                .scaleEffect(x: focused || hasQuery ? 1 : 0, anchor: .leading)
                .offset(y: 0.5)
        }
        .contentShape(Rectangle())
        .onTapGesture { fieldFocused = true }
        .animation(style.ease(280), value: focused)
        .animation(style.ease(280), value: hasQuery)
    }

    @ViewBuilder
    private func segmentText(_ segment: NXTaskQuery.Segment) -> some View {
        if let kind = segment.kind {
            let color = segment.color ?? (kind == .flag ? NX.amberText : style.accent)
            let fill = kind == .flag ? NX.amber : color
            Text(segment.text)
                .foregroundStyle(color)
                .background(fill.opacity(0.11), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(alignment: .bottom) { Rectangle().fill(color.opacity(0.33)).frame(height: 1.5) }
        } else {
            Text(segment.text).foregroundStyle(NX.ink)
        }
    }

    private func pillPopover(query: String) -> some View {
        let words = NXTaskQuery.words(in: query)
        let rows: [(String, [(word: String, label: String, color: Color, list: TaskList?)])] = [
            ("When", [("overdue", "Overdue"), ("today", "Today"), ("tomorrow", "Tomorrow"), ("week", "This week"),
                      ("later", "Later"), ("undated", "No date")].map { ($0.0, $0.1, style.accent, nil) }),
            ("List", library.lists.map { (NXTaskQuery.key(for: $0), $0.displayTitle, $0.nxColor, $0) }),
            ("Label", library.labels.map { (NXTaskQuery.key(for: $0), "#\($0.name)", $0.nxColor, nil) }),
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
                        .frame(width: 44, alignment: .leading)
                        .padding(.top, 7)
                    NXFlow(spacing: 5) {
                        ForEach(pills, id: \.word) { pill in
                            NXQueryPill(label: pill.label, list: pill.list, color: pill.color, isOn: words.contains(pill.word)) {
                                env.workbench.tasksQuery = NXTaskQuery.toggle(pill.word, in: env.workbench.tasksQuery)
                                fieldFocused = true
                            }
                        }
                    }
                }
                .padding(.vertical, 5)
            }
            HStack(spacing: 8) {
                Text("Words combine — “kyoto overdue #travel”. Anything else matches the title.")
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
        .frame(width: 460)
        .background(NX.card, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .nxCardShadow(radius: 13, hairline: 0.14, drop: 0.16, y: 18, blur: 44)
    }
}

private struct NXQueryPill: View {
    let label: String
    var list: TaskList?
    let color: Color
    let isOn: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 5) {
            if let list { NXListGlyph(list: list, size: 11) }
            Text(label).font(.system(size: 12, weight: .medium)).lineLimit(1)
        }
        .foregroundStyle(isOn ? .white : NX.ink(0.7))
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(isOn ? color : hovering ? NX.ink(0.04) : .clear, in: Capsule())
        .overlay(Capsule().strokeBorder(isOn ? color : NX.ink(0.12), lineWidth: 1))
        .contentShape(Capsule())
        .onHover { hovering = $0 }
        .onTapGesture(perform: action)
        .animation(.easeOut(duration: 0.14), value: isOn)
    }
}

/// Plain text button that changes colour on hover.
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
                .opacity(configuration.isPressed ? 0.7 : 1)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.16), value: hovering)
        }
    }
}

/// Left-to-right wrapping layout for pills.
struct NXFlow: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * (lineSpacing ?? spacing)
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + (lineSpacing ?? spacing)
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

// MARK: - Sentence bar

private struct NXTasksSentenceBar: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    @Environment(\.nextLibrary) private var library
    let count: Int
    @State private var menu: Menu?
    @FocusState private var titleFocused: Bool

    enum Menu { case status, lists, group }

    var body: some View {
        let workbench = env.workbench
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 3) {
                Text("Showing")
                token(.status, workbench.tasksStatus.word)
                Text("tasks in")
                token(.lists, listsLabel)
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
                    .transition(.opacity)
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(NX.ink(0.45))
            .padding(.bottom, 10)

            Spacer(minLength: 0)

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
                }
            }
            .padding(.leading, 2)
            .padding(.trailing, 4)
            .frame(width: 200, height: 28)
            .padding(.bottom, 10)
        }
        .padding(.top, 18)
        .padding(.bottom, 4)
        .overlay(alignment: .bottom) { Rectangle().fill(NX.ink(0.07)).frame(height: 0.5) }
        .animation(style.ease(160), value: isDirty)
        .animation(style.ease(160), value: menu)
        .onChange(of: env.navigator.route) { _, _ in menu = nil }
    }

    private var isDirty: Bool {
        let workbench = env.workbench
        return workbench.tasksStatus != .open || workbench.tasksGrouping != .list
            || !workbench.tasksListFilter.isEmpty || !workbench.tasksTitleFilter.isEmpty
    }

    private var listsLabel: String {
        let filter = env.workbench.tasksListFilter
        if filter.isEmpty { return "all lists" }
        if filter.count == 1, let list = library.list(filter.first) { return "\(list.glyph) \(list.displayTitle)" }
        return "\(filter.count) lists"
    }

    private func token(_ key: Menu, _ label: String) -> some View {
        NXSentenceToken(label: label, isOpen: menu == key) {
            menu = menu == key ? nil : key
        }
        .overlay(alignment: .topLeading) {
            if menu == key {
                menuView(key)
                    .offset(y: 32)
                    .transition(.scale(scale: 0.96, anchor: .topLeading).combined(with: .opacity))
            }
        }
        .zIndex(menu == key ? 5 : 0)
    }

    private func menuView(_ key: Menu) -> some View {
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
        .frame(width: 250)
        .background(NX.card, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .nxCardShadow(radius: 11, hairline: 0.14, drop: 0.18, y: 16, blur: 40)
    }

    private func menuRow(label: String, list: TaskList? = nil, count: Int? = nil, isOn: Bool,
                         action: @escaping () -> Void) -> some View {
        NXMenuRow(isOn: isOn, action: action) {
            Group {
                if let list { NXListGlyph(list: list, size: 12) } else { Color.clear }
            }
            .frame(width: 16)
            Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(NX.ink).lineLimit(1)
            Spacer(minLength: 6)
            if let count {
                Text("\(count)").font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundStyle(NX.ink(0.36))
            }
        }
    }
}

private struct NXSentenceToken: View {
    let label: String
    let isOpen: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 1) {
            Text(label).font(.system(size: 13, weight: .semibold)).foregroundStyle(NX.ink).lineLimit(1)
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(NX.ink(0.5))
                .padding(.leading, 2)
        }
        .padding(.vertical, 5)
        .padding(.leading, 7)
        .padding(.trailing, 4)
        .background(isOpen ? NX.ink(0.07) : hovering ? NX.ink(0.06) : .clear,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: action)
    }
}

/// A row in the sentence menus and other small Next menus.
struct NXMenuRow<Content: View>: View {
    @Environment(\.nextStyle) private var style
    let isOn: Bool
    let action: () -> Void
    @ViewBuilder var content: () -> Content
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            content()
            Image(systemName: "checkmark")
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(style.accent)
                .opacity(isOn ? 1 : 0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 9)
        .background(isOn ? style.accent.opacity(0.06) : hovering ? NX.ink(0.05) : .clear,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: action)
        .animation(.easeOut(duration: 0.12), value: isOn)
    }
}
