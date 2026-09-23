//
//  NextSidebar.swift
//  openlist
//

import SwiftUI

struct NextSidebar: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    @Environment(\.nextLibrary) private var library
    var trashCount: Int
    @State private var renamingListID: UUID?
    @State private var renameDraft = ""
    @FocusState private var renameFocused: Bool

    private var workbench: Workbench { env.workbench }
    private var route: AppRoute { env.navigator.route }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 52)
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
            searchField
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(spacing: 1) {
                        ForEach(NavItem.all, id: \.route) { item in navRow(item) }
                    }
                    ForEach(library.sections, id: \.id) { section in
                        sectionBlock(title: section.displayTitle, collapsed: section.isCollapsed,
                                     lists: library.lists(in: section)) {
                            env.store.setCollapsed(!section.isCollapsed, for: section)
                        }
                    }
                    if !library.unsectioned.isEmpty {
                        sectionBlock(title: "Other lists", collapsed: workbench.collapsedGroups.contains("sec-other"),
                                     lists: library.unsectioned.filter(\.isPinned)) { toggle("sec-other") }
                    }
                    labelsBlock
                }
                .padding(.horizontal, 8)
                .padding(.top, 2)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.never)
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
        .buttonStyle(NXHoverButtonStyle(hover: NX.ink(0.08), radius: 8, padding: EdgeInsets(),
                                        foreground: NX.ink(0.45)))
        .background(NX.ink(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
            NavItem(route: .lists, icon: "square.stack", filledIcon: "square.stack.fill", label: "Lists", color: NX.lists),
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

    private func navRow(_ item: NavItem) -> some View {
        let on = route == item.route || (item.route == .activity && route == .updates)
        let pulsing = item.route == .inbox && workbench.pulseListID != nil && workbench.pulseListID == library.inbox?.id
        let count = count(for: item.route)
        return NXSidebarRow(on: on, pulsing: pulsing, height: 29) {
            Image(systemName: on ? item.filledIcon : item.icon)
                .font(.system(size: 13.5, weight: .medium))
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
    }

    private func countText(_ count: Int, pulsing: Bool, opacity: Double = 0.38) -> some View {
        Text("\(count)")
            .font(.system(size: 11, weight: pulsing ? .bold : .medium))
            .foregroundStyle(pulsing ? style.accent : NX.ink(opacity))
            .monospacedDigit()
            .contentTransition(.numericText())
            .modifier(NXBump(trigger: pulsing ? workbench.pulseRevision : 0))
    }

    // MARK: Sections

    private func sectionBlock(title: String, collapsed: Bool, lists: [TaskList], onToggle: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(title, open: !collapsed, action: onToggle)
            if !collapsed {
                VStack(spacing: 1) {
                    ForEach(lists, id: \.id) { list in
                        listRow(list, depth: 0)
                        ForEach(library.children(of: list), id: \.id) { child in
                            listRow(child, depth: 1)
                        }
                    }
                }
            }
        }
        .padding(.top, 14)
    }

    private func sectionHeader(_ title: String, open: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(style.ease(160)) { action() }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .kerning(0.7)
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
    }

    @ViewBuilder
    private func listRow(_ list: TaskList, depth: Int) -> some View {
        let on = route == .list(list.id)
        let pulsing = workbench.pulseListID == list.id
        let count = library.openCount(in: list.id)
        NXSidebarRow(on: on, pulsing: pulsing, ring: pulsing ? style.accent.opacity(0.25) : nil, height: 29) {
            NXListGlyph(list: list, size: 12)
                .frame(width: 16)
            if renamingListID == list.id {
                TextField("List name", text: $renameDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .focused($renameFocused)
                    .onSubmit { commitRename(list) }
                    .onExitCommand { renamingListID = nil }
                    .onChange(of: renameFocused) { _, focused in if !focused { commitRename(list) } }
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
        .padding(.leading, CGFloat(depth) * 14)
        .contextMenu {
            Button("Open") { workbench.go(workbench.route(for: list)) }
            Button("Rename List…") { renameDraft = list.title; renamingListID = list.id; renameFocused = true }
            Button("Move List…") { env.listPendingMove = list }
            Picker("Hours", selection: Binding(get: { workbench.hours(for: list) },
                                               set: { workbench.setHours($0, for: list.id) })) {
                ForEach(AvailabilityCategory.allCases) { Text("\($0.title) Hours").tag($0) }
            }
            Button(workbench.documentListIDs.contains(list.id) ? "Show as Tasks" : "Show as Document") {
                if workbench.documentListIDs.contains(list.id) { workbench.documentListIDs.remove(list.id) }
                else { workbench.documentListIDs.insert(list.id) }
                workbench.go(workbench.route(for: list))
            }
            Divider()
            Button("Duplicate") { workbench.go(.list(env.store.duplicateList(list).id)) }
            Button("Use as Template…") { env.templateCopyRequest = TemplateCopyRequest(source: .list(list.id), undoManager: nil) }
            Button("Export as Markdown…") { MarkdownExporter.presentSavePanel(for: list, store: env.store) }
            Button("Remove from Sidebar") { env.store.setPinned(false, for: list) }
            Divider()
            Button("Delete List", role: .destructive) { env.requestDeleteList(list) }
        }
        .dropDestination(for: String.self) { items, _ in
            let ids = items.compactMap { DragPayload.block.decode($0) }
            guard !ids.isEmpty else { return false }
            workbench.move(ids, to: list.id)
            return true
        }
    }

    private func commitRename(_ list: TaskList) {
        guard renamingListID == list.id else { return }
        let name = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty, name != list.title { env.store.rename(list, to: name) }
        renamingListID = nil
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
                        NXSidebarRow(on: on, pulsing: false, height: 27) {
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
                            Button("Delete Label", role: .destructive) {
                                if route == .label(label.id) { env.navigator.replace(with: .tasks) }
                                env.store.deleteLabel(label)
                            }
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
            footerButton(on: route == .trash, help: "Trash") {
                HStack(spacing: 4) {
                    Image(systemName: "trash").font(.system(size: 13, weight: .medium))
                    if trashCount > 0 {
                        Text("\(trashCount)").font(.system(size: 10.5, weight: .medium)).foregroundStyle(NX.ink(0.4)).monospacedDigit()
                    }
                }
            } action: { workbench.go(.trash) }
            footerButton(on: route == .settings, help: "Settings (⌘,)") {
                Image(systemName: "gearshape").font(.system(size: 13, weight: .medium))
            } action: { workbench.go(.settings) }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .overlay(alignment: .top) { Rectangle().fill(NX.ink(0.09)).frame(height: 0.5) }
    }

    private func footerButton<Label: View>(on: Bool, help: String, @ViewBuilder label: () -> Label, action: @escaping () -> Void) -> some View {
        Button(action: action, label: label)
            .buttonStyle(NXHoverButtonStyle(hover: NX.ink(0.05), radius: 7,
                                            padding: EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6),
                                            foreground: on ? NX.ink : NX.ink(0.5)))
            .background(on ? NX.ink(0.07) : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .help(help)
    }
}

/// A sidebar row with the raised "current" look and a hover wash.
private struct NXSidebarRow<Content: View>: View {
    @Environment(\.nextStyle) private var style
    let on: Bool
    let pulsing: Bool
    var ring: Color?
    let height: CGFloat
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
            }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture(perform: action)
    }
}

/// The count bump when something lands in a list.
struct NXBump: ViewModifier {
    let trigger: Int
    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 1.0, trigger: trigger) { view, scale in
            view.scaleEffect(scale)
        } keyframes: { _ in
            CubicKeyframe(1.35, duration: 0.17)
            CubicKeyframe(1, duration: 0.25)
        }
    }
}
