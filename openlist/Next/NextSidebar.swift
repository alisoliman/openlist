//
//  NextSidebar.swift
//  openlist
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// What a list in the sidebar takes: another list, or the rows a task row
/// or a list document's grip drags, in this library's own payloads.
private nonisolated struct NXSidebarDrop: Transferable {
    let value: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: UTType(exportedAs: DragPayload.listTypeIdentifier)) { data in
            NXSidebarDrop(value: String(decoding: data, as: UTF8.self))
        }
        DataRepresentation(importedContentType: UTType(exportedAs: DragPayload.blockTypeIdentifier)) { data in
            NXSidebarDrop(value: String(decoding: data, as: UTF8.self))
        }
    }
}

/// What the Inbox takes: only rows, as it can't take a list.
private nonisolated struct NXSidebarRowDrop: Transferable {
    let value: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: UTType(exportedAs: DragPayload.blockTypeIdentifier)) { data in
            NXSidebarRowDrop(value: String(decoding: data, as: UTF8.self))
        }
    }
}

/// What a sidebar section takes: only a list, so a row dragged over it
/// marks no drop it would refuse.
private nonisolated struct NXSidebarListDrop: Transferable {
    let value: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: UTType(exportedAs: DragPayload.listTypeIdentifier)) { data in
            NXSidebarListDrop(value: String(decoding: data, as: UTF8.self))
        }
    }
}

struct NextSidebar: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    @Environment(\.nextLibrary) private var library
    @Query(filter: #Predicate<Block> { $0.trashID != nil }) private var trashedBlocks: [Block]
    @Query(filter: #Predicate<TaskList> { $0.trashID != nil }) private var trashedLists: [TaskList]
    @State private var renaming: Renaming?
    @State private var renameDraft = ""
    @FocusState private var renameFocused: Bool
    /// The list row or section header a drag is over.
    @State private var dropTargetID: UUID?

    /// What the shared rename field is editing.
    private enum Renaming: Equatable {
        case list(UUID)
        case section(UUID)
    }

    private var workbench: Workbench { env.workbench }
    private var route: AppRoute { env.navigator.route }

    /// Trash entries: a trashed list counts once, not once per item inside it.
    private var trashCount: Int {
        trashedBlocks.filter { $0.trashID == $0.id }.count + trashedLists.filter { $0.trashID == $0.id }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 52)
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
            searchField
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(spacing: 1) {
                            ForEach(NavItem.all, id: \.route) { item in navRow(item) }
                        }
                        ForEach(library.sections, id: \.id) { section in
                            sectionBlock(section, title: section.displayTitle, collapsed: section.isCollapsed,
                                         lists: library.lists(in: section)) {
                                env.store.setCollapsed(!section.isCollapsed, for: section)
                            }
                            .id(section.id)
                        }
                        // Unpinned lists are only in the Lists gallery.
                        let other = library.unsectioned.filter(\.isPinned)
                        if !other.isEmpty {
                            sectionBlock(nil, title: "Other lists", collapsed: workbench.collapsedGroups.contains("sec-other"),
                                         lists: other) { toggle("sec-other") }
                        }
                        labelsBlock
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 2)
                    .padding(.bottom, 12)
                }
                .scrollIndicators(.automatic)
                // File ▸ New Section's section: its name field opens, in view.
                .onChange(of: workbench.namingSectionID, initial: true) { _, id in
                    guard let id, let section = env.store.allSections().first(where: { $0.id == id }) else { return }
                    workbench.namingSectionID = nil
                    startRename(.section(id), draft: section.title)
                    DispatchQueue.main.async { withAnimation(style.ease(240)) { proxy.scrollTo(id, anchor: .center) } }
                }
            }
            footer
        }
        .frame(width: 236)
        .background(NX.sidebar)
        .overlay(alignment: .trailing) { Rectangle().fill(NX.ink(0.09)).frame(width: 0.5) }
    }

    // MARK: Search

    private var searchField: some View {
        Button { env.navigator.isSearchOpen = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 12.5, weight: .medium))
                Text("Search").font(.system(size: 12.5, weight: .medium))
                Spacer()
                NXKey("/", opacity: 0.7)
            }
            .frame(height: 28)
            .padding(.horizontal, 9)
        }
        .buttonStyle(NXHoverButtonStyle(hover: NX.ink(0.08), rest: NX.ink(0.05), radius: 8, padding: EdgeInsets(),
                                        foreground: NX.ink(0.45)))
        .pointerStyle(.horizontalText)
    }

    // MARK: Nav

    struct NavItem {
        var route: AppRoute
        var icon: String
        var filledIcon: String
        var label: String
        var color: Color?

        static let all: [NavItem] = [
            NavItem(route: .inbox, icon: "tray", filledIcon: "tray.fill", label: "Inbox", color: NX.inbox),
            NavItem(route: .today, icon: "sun.max", filledIcon: "sun.max.fill", label: "Today", color: NX.today),
            NavItem(route: .calendar, icon: "calendar", filledIcon: "calendar", label: "Calendar"),
            NavItem(route: .tasks, icon: "checklist", filledIcon: "checklist", label: "Tasks", color: NX.green),
            NavItem(route: .lists, icon: "square.2.layers.3d", filledIcon: "square.2.layers.3d.fill", label: "Lists", color: NX.lists),
            NavItem(route: .activity, icon: "square.grid.2x2", filledIcon: "square.grid.2x2.fill", label: "Activity"),
        ]
    }

    private func count(for route: AppRoute) -> Int {
        switch route {
        case .inbox: library.inboxQueue(workbench).count
        case .today: library.todayCount(workbench)
        default: 0
        }
    }

    @ViewBuilder
    private func navRow(_ item: NavItem) -> some View {
        let on = route == item.route
        // The Inbox is a list too: rows dragged onto it move there, as onto any list.
        let inbox = item.route == .inbox ? library.inbox : nil
        let pulsing = inbox != nil && workbench.pulseListID == inbox?.id
        let count = count(for: item.route)
        let row = NXSidebarRow(on: on, pulsing: pulsing, ring: inbox != nil && dropTargetID == inbox?.id ? style.accent.opacity(0.6) : nil,
                               height: 29, title: item.label,
                               value: count > 0 ? "\(count) \(count == 1 ? "task" : "tasks")" : "") {
            // Sized to the design's 16px Material glyphs, which draw about 12pt wide.
            Image(systemName: on ? item.filledIcon : item.icon)
                .font(.system(size: 12, weight: on ? .medium : .regular))
                .foregroundStyle(on ? (item.color ?? style.accent) : NX.ink(0.55))
                .frame(width: 16)
            Text(item.label)
                .font(.system(size: 13, weight: on ? .semibold : .medium))
                .foregroundStyle(on ? NX.ink : NX.ink(0.66))
            Spacer(minLength: 4)
            if count > 0 { countText(count, pulsing: pulsing) }
        } action: {
            workbench.go(item.route)
        }
        if let inbox {
            row.dropDestination(for: NXSidebarRowDrop.self) { items, _ in
                dropRows(items.map(\.value), on: inbox.id)
            } isTargeted: { setDropTarget(inbox.id, $0) }
        } else {
            row
        }
    }

    private func countText(_ count: Int, pulsing: Bool, opacity: Double = 0.38) -> some View {
        Text("\(count)")
            .font(.system(size: 11, weight: pulsing ? .bold : .medium))
            .foregroundStyle(pulsing ? style.accent : NX.ink(opacity))
            .monospacedDigit()
            .contentTransition(.numericText())
            .modifier(NXBump(trigger: workbench.pulseRevision, active: pulsing))
    }

    // MARK: Sections

    /// A header and its lists, each followed by its nested lists. `section`
    /// is nil for "Other lists", which can't be renamed or filed into.
    private func sectionBlock(_ section: SidebarSection?, title: String, collapsed: Bool, lists: [TaskList],
                              onToggle: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let section {
                sectionHeader(for: section, open: !collapsed, action: onToggle)
            } else {
                sectionHeader(title, open: !collapsed, action: onToggle)
            }
            if !collapsed {
                VStack(spacing: 1) {
                    ForEach(library.outline(lists)) { row in
                        listRow(row.list, depth: row.depth)
                    }
                }
            }
        }
        .padding(.top, 14)
    }

    /// A section's header, renamed in place. Dropping a list on it files the
    /// list at the end of the section.
    @ViewBuilder
    private func sectionHeader(for section: SidebarSection, open: Bool, action: @escaping () -> Void) -> some View {
        if renaming == .section(section.id) {
            renameField("Section name", .section(section.id))
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(NX.ink(0.6))
                .padding(.top, 4)
                .padding(.bottom, 5)
                .padding(.horizontal, 8)
        } else {
            sectionHeader(section.displayTitle, open: open, action: action)
                .background(dropTargetID == section.id ? style.accent.opacity(0.12) : .clear,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contextMenu {
                    Button("Rename Section…") { startRename(.section(section.id), draft: section.title) }
                    Button("New List in Section") { workbench.createList(in: section) }
                    if !section.isDefault {
                        Divider()
                        Button("Delete Section", role: .destructive) { deleteSection(section) }
                    }
                }
                .dropDestination(for: NXSidebarListDrop.self) { items, _ in
                    guard let dragged = draggedList(items.map(\.value)) else { return false }
                    workbench.moveList(dragged, toSection: section.id, above: nil)
                    return true
                } isTargeted: { setDropTarget(section.id, $0) }
        }
    }

    private func sectionHeader(_ title: String, open: Bool, action: @escaping () -> Void) -> some View {
        Button {
            // The design's chevron turns over 160ms, whatever the Motion setting.
            withAnimation(NX.cssEase(160)) { action() }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .kerning(0.735)
                    .textCase(.uppercase)
                    .foregroundStyle(NX.ink(0.34))
                Image(systemName: "chevron.right")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(NX.ink(0.3))
                    .rotationEffect(.degrees(open ? 90 : 0))
                Spacer()
            }
            .padding(.top, 4)
            .padding(.bottom, 5)
            .padding(.horizontal, 8)
        }
        .buttonStyle(NXHoverButtonStyle(hover: NX.ink(0.035), radius: 6, padding: EdgeInsets()))
        .accessibilityValue(open ? "Expanded" : "Collapsed")
    }

    /// Its lists stay in the sidebar, under "Other lists"; Undo files them back.
    private func deleteSection(_ section: SidebarSection) {
        if renaming == .section(section.id) { renaming = nil }
        workbench.deleteSection(section)
    }

    @ViewBuilder
    private func listRow(_ list: TaskList, depth: Int) -> some View {
        let on = route == .list(list.id)
        let pulsing = workbench.pulseListID == list.id
        let count = library.openCount(in: list.id)
        let editing = renaming == .list(list.id)
        let ring: Color? = dropTargetID == list.id ? style.accent.opacity(0.6) : pulsing ? style.accent.opacity(0.25) : nil
        NXSidebarRow(on: on, pulsing: pulsing, ring: ring, height: 29, title: list.displayTitle,
                     value: "\(count) open \(count == 1 ? "task" : "tasks")", isEditing: editing) {
            NXListGlyph(list: list, size: 12)
                .frame(width: 16)
            if editing {
                renameField("List name", .list(list.id))
                    .font(.system(size: 13, weight: .semibold))
            } else {
                Text(list.displayTitle)
                    .font(.system(size: 13, weight: on ? .semibold : .medium))
                    .foregroundStyle(on ? NX.ink : NX.ink(0.66))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if count > 0 { countText(count, pulsing: pulsing, opacity: 0.36) }
        } action: {
            workbench.go(workbench.route(for: list))
        }
        // Never as text, which a document line would take in.
        .onDrag { DragPayload.list.provider(for: list.id) }
        // Past three levels the title keeps its room.
        .padding(.leading, CGFloat(min(depth, 3)) * 14)
        .contextMenu { NXListMenu(list: list, surface: .sidebar, rename: { startRename(.list(list.id), draft: list.title) }) }
        .dropDestination(for: NXSidebarDrop.self) { items, _ in
            drop(items.map(\.value), on: list, nested: depth > 0)
        } isTargeted: { setDropTarget(list.id, $0) }
    }

    // MARK: Drag and drop

    /// Rows dropped on a list move into it. A list dropped on a top-level
    /// list moves above it, in its section.
    private func drop(_ items: [String], on list: TaskList, nested: Bool) -> Bool {
        if items.contains(where: { DragPayload.list.decode($0) != nil }) {
            guard !nested, let sectionID = list.sectionID, let dragged = draggedList(items),
                  dragged.id != list.id else { return false }
            workbench.moveList(dragged, toSection: sectionID, above: list)
            return true
        }
        return dropRows(items, on: list.id)
    }

    /// Rows move only in this library's session payload. A bare row ID,
    /// from another app or library, is not one. Any line a document's grip
    /// drags moves, a heading or text too. Rows already all in the list are
    /// refused, as they'd go nowhere, and so is any line but a task on the
    /// Inbox while it shows as triage, which draws only tasks.
    private func dropRows(_ items: [String], on listID: UUID) -> Bool {
        let session = env.navigator.blockDragSessionID
        let ids = items.flatMap { item -> [UUID] in
            guard case let .blocks(ids) = DragPayload.blockDrop(item, session: session) else { return [] }
            return ids
        }
        guard ids.contains(where: { env.store.block(id: $0).map { $0.listID != listID } ?? false }) else { return false }
        if listID == library.inbox?.id, env.navigator.listViewMode(for: listID) != .document,
           ids.contains(where: { env.store.block(id: $0).map { !$0.isTask } ?? false }) {
            env.store.refuse("Only tasks go to the Inbox while it shows as triage.")
            return false
        }
        workbench.move(ids, to: listID, lines: true)
        return true
    }

    /// The dragged list, when it's one the sidebar can reorder: an active,
    /// top-level list. Nested lists move with their parent.
    private func draggedList(_ items: [String]) -> TaskList? {
        guard let id = items.lazy.compactMap({ DragPayload.list.decode($0) }).first,
              library.hierarchy.activeIDs.contains(id), library.hierarchy.parent(of: id) == nil,
              let list = library.list(id), !list.isSystemInbox else { return nil }
        return list
    }

    private func setDropTarget(_ id: UUID, _ targeted: Bool) {
        if targeted { dropTargetID = id } else if dropTargetID == id { dropTargetID = nil }
    }

    // MARK: Rename

    /// The field that replaces a list's or section's title while renaming.
    private func renameField(_ prompt: String, _ target: Renaming) -> some View {
        TextField(prompt, text: $renameDraft)
            .textFieldStyle(.plain)
            .focused($renameFocused)
            // Focus once the field is on screen. Set in the menu action that
            // inserts it, focus can miss, and typed keys then run commands.
            .onAppear { DispatchQueue.main.async { renameFocused = true } }
            .onSubmit { commitRename(target) }
            .onExitCommand { renaming = nil }
            .onChange(of: renameFocused) { _, focused in if !focused { commitRename(target) } }
    }

    /// The draft and focus are shared, so an unfinished rename commits first.
    private func startRename(_ target: Renaming, draft: String) {
        // Already open: keep what's typed and just return focus to it.
        guard renaming != target else {
            DispatchQueue.main.async { renameFocused = true }
            return
        }
        if let renaming { commitRename(renaming) }
        renameFocused = false
        renameDraft = draft
        renaming = target
    }

    private func commitRename(_ target: Renaming) {
        guard renaming == target else { return }
        let name = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        switch target {
        case let .list(id):
            if let list = library.list(id), !name.isEmpty, name != list.title { env.workbench.renameList(id, to: name) }
        case let .section(id):
            if let section = library.sections.first(where: { $0.id == id }), !section.isDeleted, section.modelContext != nil {
                workbench.renameSection(section.id, to: name)
            }
        }
        renaming = nil
    }

    // MARK: Labels

    private var labelsBlock: some View {
        let collapsed = workbench.collapsedGroups.contains("sec-labels")
        return VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Labels", open: !collapsed) { toggle("sec-labels") }
            if !collapsed {
                VStack(spacing: 1) {
                    ForEach(library.labels, id: \.id) { label in
                        let on = route == .label(label.id)
                        let count = library.openCount(label: label.id)
                        NXSidebarRow(on: on, pulsing: false, fades: false, height: 27, title: label.name,
                                     value: "\(count) open \(count == 1 ? "task" : "tasks")") {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(label.nxColor)
                                .frame(width: 8, height: 8)
                                .padding(.horizontal, 4)
                            Text(label.name)
                                .font(.system(size: 12.5, weight: on ? .semibold : .medium))
                                .foregroundStyle(on ? NX.ink : NX.ink(0.62))
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            if count > 0 {
                                Text("\(count)").font(.system(size: 11, weight: .medium)).foregroundStyle(NX.ink(0.36)).monospacedDigit()
                            }
                        } action: {
                            workbench.go(.label(label.id))
                        }
                        .contextMenu {
                            Button("Delete Label", role: .destructive) { workbench.deleteLabel(label) }
                        }
                    }
                }
            }
        }
        .padding(.top, 14)
    }

    private func toggle(_ key: String) {
        if workbench.collapsedGroups.contains(key) { workbench.collapsedGroups.remove(key) }
        else { workbench.collapsedGroups.insert(key) }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 4) {
            Button { workbench.createList() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 11.5, weight: .semibold))
                    Text("New list").font(.system(size: 12.5, weight: .medium))
                }
            }
            .buttonStyle(NXHoverButtonStyle(hover: NX.ink(0.05), radius: 7,
                                            padding: EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8)))
            Spacer()
            footerButton(on: route == .trash, title: "Trash",
                         value: trashCount > 0 ? "\(trashCount) \(trashCount == 1 ? "item" : "items")" : "") {
                HStack(spacing: 4) {
                    Image(systemName: "trash").font(.system(size: 13, weight: .medium))
                    if trashCount > 0 {
                        Text("\(trashCount)").font(.system(size: 10.5, weight: .medium)).foregroundStyle(NX.ink(0.4)).monospacedDigit()
                    }
                }
            } action: { workbench.go(.trash) }
            footerButton(on: route == .settings, title: "Settings", help: "Settings (⌘,)") {
                Image(systemName: "gearshape").font(.system(size: 13, weight: .medium))
            } action: { workbench.go(.settings) }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .overlay(alignment: .top) { Rectangle().fill(NX.ink(0.09)).frame(height: 0.5) }
    }

    /// An icon button; `title` is what VoiceOver reads, `help` the tooltip.
    private func footerButton<Label: View>(on: Bool, title: String, value: String = "", help: String? = nil,
                                           @ViewBuilder label: () -> Label, action: @escaping () -> Void) -> some View {
        Button(action: action, label: label)
            .buttonStyle(NXHoverButtonStyle(hover: NX.ink(on ? 0.07 : 0.05), rest: on ? NX.ink(0.07) : .clear, radius: 7,
                                            padding: EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6),
                                            foreground: on ? NX.ink : NX.ink(0.5)))
            .help(help ?? title)
            .accessibilityLabel(title)
            .accessibilityValue(value)
            .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A sidebar row with the raised "current" look and a hover wash. To
/// VoiceOver it's one button named `title`, unless a rename field is open.
private struct NXSidebarRow<Content: View>: View {
    @Environment(\.nextStyle) private var style
    let on: Bool
    let pulsing: Bool
    /// Nav and list rows fade between rest, hover and current; label rows snap.
    var fades = true
    var ring: Color?
    let height: CGFloat
    let title: String
    var value = ""
    var isEditing = false
    @ViewBuilder var content: () -> Content
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) { content() }
            .frame(height: height)
            .padding(.horizontal, 8)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(on ? NX.paper : pulsing ? style.accent.opacity(0.12) : hovering ? NX.ink(0.045) : .clear)
                    .shadow(color: on ? NX.ink(0.08) : .clear, radius: 1, y: 1)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(on ? NX.ink(0.06) : ring ?? .clear, lineWidth: on ? 0.5 : 1)
                    }
                    .animation(.easeOut(duration: 0.3), value: pulsing)
                    .animation(fades ? fade : nil, value: on)
                    .animation(fades ? fade : nil, value: hovering)
            }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture(perform: action)
            .accessibilityElement(children: isEditing ? .contain : .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(value)
            .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { action() }
    }

    /// The design's `300ms ease` (CSS `ease`) on the background and shadow,
    /// whatever the Motion setting.
    private var fade: Animation { NX.cssEase(300) }
}

/// The count bump when something lands in a list. It plays when `trigger`
/// moves on while `active`, and when the count first appears mid-pulse, so a
/// list's first task bumps too and the pulse ending doesn't bump again.
struct NXBump: ViewModifier {
    let trigger: Int
    var active = true
    @State private var plays = 0

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: 1.0, trigger: plays) { view, scale in
                view.scaleEffect(scale)
            } keyframes: { _ in
                CubicKeyframe(1.35, duration: 0.17)
                CubicKeyframe(1, duration: 0.25)
            }
            .onChange(of: trigger) { if active { plays += 1 } }
            .onAppear { if active { plays += 1 } }
    }
}
