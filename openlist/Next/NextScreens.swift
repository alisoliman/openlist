//
//  NextScreens.swift
//  openlist
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

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
            group.isOpen(in: workbench) ? group.rows.map(\.id) : []
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
        // The design's 20s clock: done-ago chips, the date and the buckets
        // all move on with it, midnight included.
        TimelineView(.periodic(from: .now, by: 20)) { context in
            let now = context.date
            let workbench = env.workbench
            let model = Self.model(library: library, workbench: workbench, showsCompleted: env.settings.showsCompletedTasks,
                                   accent: style.accent, now: now) { !workbench.placedTaskIDs().contains($0) }
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
        // By day, as the design: Overdue is earlier days only, so a timed
        // task whose time has passed stays in Due today.
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
                                  rows: doneToday, collapsible: true, defaultOpen: showsCompleted, completed: true))
        }
        let open = overdue.count + due.count + planned.count + starred.count
        return Model(groups: groups, progress: (doneToday.count, doneToday.count + open), clear: open == 0)
    }

    private func todayClear(done: Int) -> some View {
        HStack(spacing: 18) {
            Image(systemName: "sun.max.fill").font(.system(size: 34)).foregroundStyle(NX.today)
            VStack(alignment: .leading, spacing: 4) {
                Text("Today is clear").font(NX.serif(26)).padding(.vertical, NX.serifLeading(26, lineHeight: 1.1)).foregroundStyle(NX.ink)
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

/// A list: its cover and header, its description and nested lists, then the
/// list itself as the design's document, then the tasks done at its top
/// level, which leave the document once settled.
struct NextListScreen: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextLibrary) private var library
    let list: TaskList
    /// The Tasks presentation: the same document with only its tasks.
    var tasksOnly = false
    /// The document's task rows, which lead the page's J/K order.
    @State private var documentRowIDs: [UUID] = []
    @State private var renaming = false
    /// A list just made is named from an empty field, its placeholder
    /// standing in for "Untitled list".
    @State private var naming = false
    @State private var describing = false

    var body: some View {
        let workbench = env.workbench
        let tasks = library.tasks(in: list.id)
        let open = tasks.filter { !$0.isCompleted || workbench.closing[$0.id] != nil }
        let groups = Self.completedGroups(tasks, in: list.id, workbench: workbench,
                                          showsCompleted: list.showsCompleted(default: env.settings.showsCompletedTasks),
                                          inDocument: Set(documentRowIDs))
        let section = library.sectionTitle(for: list)
        let archived = library.archived.contains { $0.id == list.id }
        NXPage(rowIDs: documentRowIDs + NXGroupsStack.rowIDs(groups, workbench: workbench)) {
            NXListCover(list: list)
            NXScreenHeader(tile: .list(list), color: list.nxColor, title: list.displayTitle,
                           subtitle: "\(open.count) open" + (section.isEmpty ? "" : " · \(section)")
                               + (archived ? " · Archived" : ""),
                           progress: (tasks.filter(\.isCompleted).count, tasks.count),
                           rename: list.isSystemInbox ? nil : NXTitleRename(isEditing: $renaming,
                                                                           value: naming ? "" : list.title,
                                                                           placeholder: "Untitled list") { name in
                               workbench.renameList(list.id, to: name)
                           }) {
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
                NXListOptions(list: list) { describing = true }
            }
            NXListDescription(list: list, editing: $describing)
            NXChildLists(list: list)
            NXDocumentOutline(list: list, tasksOnly: tasksOnly)
                // The Turn into card draws over the Completed group.
                .zIndex(1)
                .onPreferenceChange(NXDocumentRowsKey.self) { documentRowIDs = $0 }
            // The design's 20s clock, so Completed's done-ago chips move on.
            TimelineView(.periodic(from: .now, by: 20)) { context in
                NXGroupsStack(groups: groups, options: NXRowOptions(showList: false, listID: list.id, notes: true,
                                                                    now: context.date))
            }
        }
        .onAppear {
            env.store.markOpened(list)
            // A list just made opens ready to be named.
            if workbench.namingListID == list.id || list.title.isEmpty, !list.isSystemInbox {
                workbench.namingListID = nil
                naming = true
                renaming = true
            }
        }
        .onChange(of: renaming) { _, editing in if !editing { naming = false } }
    }

    /// The Completed group under a list's document: the tasks done at its top
    /// level once they've settled. As the design's list branch, done subtasks
    /// stay struck in place. A done task the document still draws, with a
    /// task under it still open, isn't listed twice.
    @MainActor
    static func completedGroups(_ tasks: [Block], in listID: UUID, workbench: Workbench, showsCompleted: Bool,
                                inDocument: Set<UUID> = []) -> [NXGroup] {
        let done = tasks.filter {
            $0.isCompleted && workbench.closing[$0.id] == nil && $0.parentID == nil && !inDocument.contains($0.id)
        }
            .sorted(by: Block.byCompletionDate)
        guard !done.isEmpty else { return [] }
        return [NXGroup(id: "ldone", title: "Completed", icon: "checkmark.circle.fill", color: NX.green, rows: done,
                        collapsible: true, defaultOpen: showsCompleted, completed: true, listID: listID)]
    }

    static func groups(open: [Block], done: [Block], showsCompleted: Bool) -> [NXGroup] {
        var groups = [NXGroup(id: "open", rows: open, showHead: false, emptyText: "No open tasks. Press N to capture one.")]
        if !done.isEmpty {
            groups.append(NXGroup(id: "ldone", title: "Completed", icon: "checkmark.circle.fill", color: NX.green,
                                  rows: done, collapsible: true, defaultOpen: showsCompleted, completed: true))
        }
        return groups
    }
}

/// The list's cover above its header, while it has one on show.
private struct NXListCover: View {
    let list: TaskList
    @State private var image: NSImage?

    var body: some View {
        VStack(spacing: 0) {
            // Always there, so the image loads before there's anything to show.
            Color.clear.frame(height: 0)
            if list.coverFilename != nil, list.coverPresentation == .compact, let image {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 140)
                    .overlay {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(NX.ink(0.1), lineWidth: 0.5))
                    .padding(.bottom, 22)
                    .accessibilityElement()
                    .accessibilityLabel("List cover: \(list.coverMetadata?.displayName ?? list.displayTitle)")
            }
        }
        .task(id: list.coverFilename) { load() }
        .onChange(of: list.coverData) { _, _ in load() }
    }

    private func load() {
        image = list.coverFilename.flatMap { MediaStore.shared.image(named: $0, data: list.coverData) }
    }
}

/// The list header's options, the native extras the design has no place
/// for: the Tasks presentation, order, completed tasks, hours, appearance,
/// description, cover, nesting, moving, linking and exporting.
private struct NXListOptions: View {
    @Environment(AppEnvironment.self) private var env
    let list: TaskList
    /// Starts the description under the header, or writes the one there.
    let describe: () -> Void
    @State private var appearanceOpen = false
    @State private var coverError: String?

    var body: some View {
        let navigator = env.navigator
        Menu {
            Toggle("Show Tasks Only", isOn: Binding(get: { navigator.listViewMode(for: list.id) == .tasks },
                                                    set: { navigator.setListViewMode($0 ? .tasks : .document, for: list.id) }))
            Picker("Sort", selection: Binding(get: { list.sorting }, set: { env.workbench.setSorting($0, for: list) })) {
                ForEach(ListSorting.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("Completed Tasks", selection: Binding(get: { list.completedVisibility }, set: { visibility in
                // The list's new choice shows on it at once, over the Completed groups' last fold.
                env.workbench.completedFold?.lapsed.insert(list.id)
                env.workbench.setCompletedVisibility(visibility, for: list)
            })) {
                ForEach(TaskList.CompletedVisibility.allCases) { Text($0.title).tag($0) }
            }
            Menu("Hours") { hoursItems }
                .accessibilityLabel("Hours: \(env.workbench.hours(for: list).title)")
            Divider()
            Button("Icon & Colour…") { appearanceOpen = true }
            Button(list.summary.isEmpty ? "Add Description" : "Edit Description", action: describe)
            Menu("Cover") { coverItems }
            Divider()
            if !list.isSystemInbox {
                Button("New Child List") { env.workbench.createChildList(in: list) }
                    .disabled(list.isEffectivelyArchived)
                Button("Move List…") { env.listPendingMove = list }
            }
            CopyItemLinkButton(target: .list(list.id))
            // A native extra: the design exports, and has no copy.
            Button("Copy as Markdown") { copyMarkdown() }
            Button("Export as Markdown…") { MarkdownExporter.presentSavePanel(for: list, store: env.store) }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 14, weight: .medium))
        }
        .menuStyle(.button)
        .buttonStyle(NXHoverButtonStyle(hover: NX.ink(0.07), radius: 7,
                                        padding: EdgeInsets(top: 5, leading: 5, bottom: 5, trailing: 5),
                                        foreground: NX.ink(0.45), hoverForeground: NX.ink))
        .menuIndicator(.hidden)
        .fixedSize()
        .help("List options")
        .accessibilityLabel("List options")
        .popover(isPresented: $appearanceOpen, arrowEdge: .bottom) {
            ListAppearancePicker(list: list).environment(env)
        }
        .alert("Cover could not be changed", isPresented: Binding(get: { coverError != nil },
                                                                  set: { if !$0 { coverError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(coverError ?? "")
        }
    }

    /// Which hours Plan and Start working use for this list, and where they're set.
    @ViewBuilder
    private var hoursItems: some View {
        let workbench = env.workbench
        Picker("Plan and Start working use", selection: Binding(get: { workbench.hours(for: list) },
                                                                set: { workbench.setHours($0, for: list.id) })) {
            ForEach(AvailabilityCategory.allCases) { category in
                let summary = NXHours.summary(env.calendar.preferences.profile(for: category), calendar: env.settings.calendar)
                Text("\(category.title) Hours · \(summary)").tag(category)
            }
        }
        .pickerStyle(.inline)
        Divider()
        Button("Edit Hours in Settings…") { workbench.go(.settings) }
    }

    /// The cover's own choices: a local image, how it shows, and removing it.
    @ViewBuilder
    private var coverItems: some View {
        Button(list.coverFilename == nil ? "Add Cover from File…" : "Replace Cover from File…") {
            guard let source = Self.chooseCoverImage(for: list) else { return }
            perform { try env.workbench.setCover(of: list, from: source) }
        }
        if list.coverFilename != nil {
            Picker("Cover Display", selection: Binding(get: { list.coverPresentation }, set: { presentation in
                perform { try env.workbench.setCoverPresentation(presentation, of: list) }
            })) {
                ForEach(ListCoverPresentation.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
            Divider()
            Button("Remove Cover", role: .destructive) { perform { try env.workbench.removeCover(of: list) } }
        }
    }

    private func perform(_ operation: () throws -> Void) {
        do { try operation() } catch { coverError = error.localizedDescription }
    }

    /// The list's document on the clipboard, as Export writes it, said in the tray.
    private func copyMarkdown() {
        guard MarkdownExporter.copyToPasteboard(list: list, store: env.store) else { return }
        env.workbench.showTray("Copied \(NXFormat.quoted(list.displayTitle)) as Markdown", icon: "doc.on.clipboard")
    }

    /// Asks for the image a list's cover should show.
    private static func chooseCoverImage(for list: TaskList) -> URL? {
        let panel = NSOpenPanel()
        panel.title = list.coverFilename == nil ? "Add list cover" : "Replace list cover"
        panel.prompt = "Choose image"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose an image up to 20 MB and 40 megapixels. Openlist keeps its own copy."
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}

/// The list's description under its header, 13.8 at ink .62, written in
/// place: a click starts, Return or clicking away commits, Esc cancels.
private struct NXListDescription: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    let list: TaskList
    @Binding var editing: Bool
    @State private var draft = ""
    @State private var selection: TextSelection?
    /// The reveal whose description is lit, until it fades.
    @State private var litRevealID: UUID?
    @FocusState private var focused: Bool

    private var revealsSummary: Bool { env.navigator.contentReveal?.revealsSummary(for: list.id) == true }

    /// A search hit in the description, once search has stepped aside.
    private var readyRevealID: UUID? {
        guard revealsSummary, !env.navigator.isSearchOpen else { return nil }
        return env.navigator.contentReveal?.id
    }

    var body: some View {
        // The design's 1.45 line box, as the rows' titles have it.
        let leading = max(0, 13.8 * 1.45 - NXStrikeText.glyphLineHeight(13.8))
        VStack(alignment: .leading, spacing: 0) {
            if editing || !list.summary.isEmpty || revealsSummary {
                Group {
                    if editing {
                        TextField("Add a description…", text: $draft, selection: $selection, axis: .vertical)
                            .textFieldStyle(.plain)
                            .focused($focused)
                            .onSubmit(commit)
                            .onExitCommand { editing = false }
                            .onAppear {
                                draft = list.summary
                                if selection == nil { selection = TextSelection(insertionPoint: draft.endIndex) }
                                // Once the field is on screen, or the focus can miss it.
                                DispatchQueue.main.async { focused = true }
                            }
                            .onChange(of: focused) { _, now in if !now { commit() } }
                            .accessibilityLabel("List description")
                    } else {
                        Text(list.summary.isEmpty ? "Add a description…" : list.summary)
                            .fixedSize(horizontal: false, vertical: true)
                            .contentShape(Rectangle())
                            .onTapGesture { editing = true }
                            .pointerStyle(.horizontalText)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityHint("Edits the description")
                            .accessibilityAction { editing = true }
                    }
                }
                .font(.system(size: 13.8))
                .lineSpacing(leading)
                .foregroundStyle(NX.ink(list.summary.isEmpty && !editing ? 0.32 : 0.62))
                .padding(.vertical, leading / 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    // Where a search hit landed, in the design's fresh tint, as a revealed line has it.
                    if revealsSummary, litRevealID != nil, litRevealID == env.navigator.contentReveal?.id {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(style.accent.opacity(0.11))
                            .padding(-5)
                            .transition(.opacity)
                    }
                }
                .id(ContentReveal.Anchor.listSummary(list.id))
                // Under the title, past the header's tile.
                .padding(.leading, 56)
                .padding(.top, 12)
            }
        }
        .task(id: readyRevealID) {
            litRevealID = readyRevealID
            guard readyRevealID != nil else { return }
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled else { return }
            // The design's row background transition: 700ms ease.
            withAnimation(NX.cssEase(700)) { litRevealID = nil }
        }
        .task(id: readyRevealID) {
            guard readyRevealID != nil, let reveal = env.navigator.contentReveal else { return }
            await Task.yield()
            guard !Task.isCancelled else { return }
            selection = SearchProjection.range(of: reveal.query, in: list.summary).map { TextSelection(range: $0) }
            if editing { focused = true } else { editing = true }
        }
    }

    private func commit() {
        guard editing else { return }
        editing = false
        let summary = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if summary != list.summary { env.workbench.setListDescription(list.id, to: summary) }
        selection = nil
    }
}

/// The lists nested in this one, as a compact group above its document.
private struct NXChildLists: View {
    @Environment(\.nextLibrary) private var library
    let list: TaskList

    var body: some View {
        let children = library.children(of: list)
        VStack(alignment: .leading, spacing: 0) {
            if !children.isEmpty {
                HStack(spacing: 7) {
                    Text("Lists")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(NX.ink)
                    Text("\(children.count)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(NX.ink(0.38))
                        .monospacedDigit()
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(children, id: \.id) { NXChildListRow(list: $0) }
                }
                .padding(.top, 2)
            }
        }
        .padding(.top, children.isEmpty ? 0 : 16)
    }
}

/// A nested list: its glyph where a row's checkbox sits, its title and its
/// open count. A click opens it.
private struct NXChildListRow: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    @Environment(\.nextLibrary) private var library
    let list: TaskList
    @State private var hovering = false

    var body: some View {
        let workbench = env.workbench
        let count = library.openCount(in: list.id)
        HStack(spacing: 0) {
            NXListGlyph(list: list, size: 13)
                .frame(width: 26, alignment: .leading)
            // 13.8 on the rows' 1.45 line box.
            Text(list.displayTitle)
                .font(.system(size: 13.8))
                .foregroundStyle(NX.ink)
                .lineLimit(1)
                .padding(.vertical, max(0, 13.8 * 1.45 - NXStrikeText.glyphLineHeight(13.8)) / 2)
            Spacer(minLength: 8)
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(NX.ink(0.38))
                    .monospacedDigit()
            }
        }
        .padding(.vertical, style.rowVerticalPadding)
        .padding(.horizontal, 10)
        .background(hovering ? NX.ink(0.03) : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { workbench.go(workbench.route(for: list)) }
        .contextMenu {
            Button("Open") { workbench.go(workbench.route(for: list)) }
            Button("Move List…") { env.listPendingMove = list }
            CopyItemLinkButton(target: .list(list.id))
            Divider()
            Button("Delete List", role: .destructive) { env.requestDeleteList(list) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(list.displayTitle)
        .accessibilityValue("\(count) open")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { workbench.go(workbench.route(for: list)) }
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
