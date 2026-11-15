//
//  ListPageScreen.swift
//  OpenlistiOS
//

import SwiftData
import SwiftUI

/// A list's page (mockup 10): its tint band and glyph, the open count, its
/// tasks as its document orders them with subtasks under their task, the
/// done ones folded under "N done", and lists nested in it. The check-circle
/// selects many (mockup 11); the menu renames, sorts, archives or trashes it.
/// The glyph, like the menu's Icon & colour, changes the list's icon and colour.
struct ListPageScreen: View {
    let listID: UUID
    @Environment(PhoneEnvironment.self) private var env
    @Environment(\.phoneLibrary) private var library
    @Environment(\.olStyle) private var style
    @Query private var blocks: [Block]
    @State private var isSelecting = false
    @State private var showsDone: Bool?
    @State private var renaming = false
    @State private var name = ""
    @State private var namesChild = false
    @State private var confirmsTrash = false
    @State private var editsAppearance = false
    @State private var activeSection: UUID?
    @State private var sectionDrafts: [UUID: String] = [:]
    @State private var addedTask: UUID?

    init(listID: UUID) {
        self.listID = listID
        _blocks = Query(filter: #Predicate<Block> { $0.listID == listID && $0.trashID == nil })
    }

    var body: some View {
        ScrollViewReader { scroll in screen(scroll: scroll) }
    }

    private func screen(scroll: ScrollViewProxy) -> some View {
        let navigator = env.navigator
        let list = env.store.list(id: listID)
        let document = ListDocument(blocks: blocks, sorting: list?.sorting ?? .manual, closing: env.actions.closing)
        let page = document.page
        let allowsTaskEntry = list?.isEffectivelyArchived == false && !isSelecting
        let items = document.items(allowsTaskEntry: allowsTaskEntry)
        let activeEntryVisible = activeSection.map { section in items.contains { $0.id == .taskEntry(section) } } ?? false
        let addedTaskIsVisible = addedTask.map { id in page.rows.contains { $0.id == id } } ?? false
        let children = list.map(library.children(of:)) ?? []
        let doneOpen = showsDone ?? list?.showsCompleted(default: env.settings.showsCompletedTasks) ?? false
        return OLScreen(identifier: PhoneRoute.list(listID).screenIdentifier) {
            OLListHeaderBand(icon: list?.icon ?? "📋", accent: list?.accent ?? .graphite,
                             editAppearance: list?.isSystemInbox == false ? { editsAppearance = true } : nil) {
                OLTopBar {
                    OLBackButton(env.backTitle(for: .list(listID))) { navigator.pop() }
                } trailing: {
                    let nothingToSelect = document.selectableTasks.isEmpty
                    OLIconButton("checkmark.circle", label: "Select tasks", kind: .bare, iconSize: 22) { isSelecting = true }
                        .disabled(nothingToSelect)
                        .accessibilityHint(nothingToSelect ? "No open tasks to select" : "")
                        .accessibilityIdentifier("list.select")
                        // Dimmed, it still answers a tap with why.
                        .overlay {
                            if nothingToSelect {
                                Color.clear
                                    .contentShape(.rect)
                                    .onTapGesture {
                                        env.tray.show("No open tasks to select", icon: "checkmark.circle", tone: .neutral, seconds: 3)
                                    }
                                    .accessibilityHidden(true)
                            }
                        }
                    if let list { menu(list) }
                }
            }
        } content: {
            // "Empty" with no tasks at all, as its card says, not "All done".
            OLHeader(list?.displayTitle ?? "List",
                     sub: page.openCount > 0 ? "\(page.openCount) open" : library.tasks(in: listID).isEmpty ? "Empty" : "All done",
                     subFont: .caption.monospacedDigit(), topSpacing: 14)
            if page.rows.isEmpty && page.completed.isEmpty && children.isEmpty {
                let archived = list?.isEffectivelyArchived == true
                // Archived, it offers its way back; a list archived with its
                // parent comes back with the parent, as on the Mac.
                let unarchives = archived && list?.isArchived == true
                OLEmptyState(symbol: "checklist", tint: list?.accent.color ?? OL.accentText, title: "Nothing here yet",
                             message: archived ? "This list is archived." : "Tasks you add to this list show here.",
                             actionTitle: archived ? (unarchives ? "Unarchive" : nil) : "Add a task") {
                    if !archived { navigator.open(.capture(CaptureRequest(listID: listID))) }
                    else if let list { env.actions.setArchived(false, for: list) }
                }
                .padding(.top, 60)
            }
            if !items.isEmpty {
                documentCard(document, items: items)
            }
            if !page.completed.isEmpty {
                OLFold("done", count: page.completed.count,
                       isExpanded: Binding(get: { doneOpen }, set: { showsDone = $0 })) {
                    OLCardRows(page.completed, lazy: true, shadow: .softCard) { task, separator in
                        PhoneTaskRow(task: task, context: .list, separator: separator)
                    }
                }
                .accessibilityIdentifier("list.done")
            }
            if !children.isEmpty {
                OLGroup("Lists") {
                    OLListGrid {
                        ForEach(children) { child in
                            OLListCard(title: child.displayTitle, icon: child.icon, accent: child.accent,
                                       detail: library.cardDetail(for: child), shadow: .softCard,
                                       detailFont: .caption.monospacedDigit()) {
                                navigator.open(.list(child.id))
                            }
                        }
                    }
                }
            }
        }
        .modifier(SelectMode(isSelecting: $isSelecting, listTitle: list?.displayTitle ?? "",
                             tasks: document.selectableTasks))
        .alert("Rename list", isPresented: $renaming) {
            TextField("Name", text: $name)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { if let list { env.actions.rename(list, to: name) } }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert("New list inside", isPresented: $namesChild) {
            TextField("Name", text: $name)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                if let list, let child = env.actions.createList(named: name, under: list) { navigator.open(.list(child.id)) }
            }
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .sheet(isPresented: $editsAppearance) {
            if let list { ListAppearanceSheet(list: list) }
        }
        .confirmationDialog("Move “\(list?.displayTitle ?? "")” to Trash?", isPresented: $confirmsTrash, titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) {
                if let list, env.actions.trashList(list) { navigator.pop() }
            }
        } message: {
            Text("Its tasks go with it. You can put it back from Trash.")
        }
        // Somewhere else taking the screen takes its questions with it.
        .onChange(of: env.navigator.arrivals) {
            renaming = false
            namesChild = false
            confirmsTrash = false
            editsAppearance = false
            activeSection = nil
        }
        .onChange(of: activeEntryVisible) { _, visible in
            if !visible { activeSection = nil }
        }
        .onChange(of: addedTaskIsVisible) { _, visible in
            guard visible else { return }
            addedTask = nil
            guard let activeSection else { return }
            // The entry moves with the new row. Keep it above the Undo tray
            // that appears at the bottom of the keyboard's safe area.
            withAnimation(style.animation(.easeOut(duration: 0.2))) {
                scroll.scrollTo(ListDocument.Item.ID.taskEntry(activeSection), anchor: .center)
            }
        }
        .onAppear { list.map(env.store.markOpened) }
        .onDisappear { activeSection = nil }
    }

    private func documentCard(_ document: ListDocument, items: [ListDocument.Item]) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(items) { item in
                switch item {
                case let .block(row, previousTaskDepth):
                    if row.block.isTask {
                        ListDocumentTaskRow(row: row, separator: .task(depth: row.depth, previousDepth: previousTaskDepth),
                                            canDisclose: document.canDisclose(row), progress: document.progress(for: row.block))
                    } else {
                        ListDocumentTextRow(row: row, canDisclose: document.canDisclose(row))
                    }
                case let .taskEntry(heading):
                    let headingID = heading.id
                    ListSectionTaskEntry(headingID: headingID, headingTitle: heading.displayTitle,
                                         activeSection: $activeSection, draft: draft(for: headingID)) { title in
                        addTask(title, under: headingID)
                    }
                    .id(item.id)
                }
            }
        }
        .olCard(shadow: .softCard)
        .padding(.top, OLMetrics.headerGap)
    }

    private func draft(for headingID: UUID) -> Binding<String> {
        Binding(get: { sectionDrafts[headingID, default: ""] },
                set: { sectionDrafts[headingID] = $0.isEmpty ? nil : $0 })
    }

    private func addTask(_ title: String, under headingID: UUID) -> Bool {
        do {
            let task = try env.store.saveCapture(.init(title: title), destinationID: listID, headingID: headingID)
            addedTask = task.id
            env.actions.reportCapture(task)
            return true
        } catch {
            let message = "Task wasn’t added. \(error.localizedDescription)"
            env.tray.show(message, icon: "exclamationmark.circle", tone: .danger, seconds: 5)
            env.haptics.play(.error)
            return false
        }
    }

    private func menu(_ list: TaskList) -> some View {
        Menu {
            if !list.isSystemInbox {
                Button("Rename", systemImage: "pencil") {
                    name = list.title
                    renaming = true
                }
                Button("Icon & colour", systemImage: "face.smiling") { editsAppearance = true }
            }
            Picker(selection: Binding(get: { list.sorting }, set: { env.store.setSorting($0, for: list) })) {
                ForEach(ListSorting.allCases, id: \.self) { Text($0.title).tag($0) }
            } label: {
                Label("Sort by", systemImage: "arrow.up.arrow.down")
            }
            .pickerStyle(.menu)
            Picker(selection: Binding(get: { list.completedVisibility },
                                      set: { env.store.setCompletedVisibility($0, for: list); showsDone = nil })) {
                ForEach(TaskList.CompletedVisibility.allCases) { Text($0.title).tag($0) }
            } label: {
                Label("Done tasks", systemImage: "checkmark.circle")
            }
            .pickerStyle(.menu)
            if !list.isSystemInbox {
                Button("New list inside", systemImage: "plus.square.on.square") {
                    name = ""
                    namesChild = true
                }
                Divider()
                ListMenuItems(list: list) { confirmsTrash = true }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(OL.ink)
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .accessibilityLabel("List options")
        .accessibilityIdentifier("list.options")
    }
}

/// A list's archive and trash items, in its long-press menu and on its page.
struct ListMenuItems: View {
    let list: TaskList
    /// Asks before trashing; without it the item trashes at once, with Undo.
    var confirmTrash: (() -> Void)?
    @Environment(PhoneEnvironment.self) private var env

    var body: some View {
        if !list.isSystemInbox {
            Button(list.isArchived ? "Unarchive" : "Archive", systemImage: "archivebox") {
                env.actions.setArchived(!list.isArchived, for: list)
            }
            Button("Move to Trash", systemImage: "trash", role: .destructive) {
                if let confirmTrash { confirmTrash() } else { env.actions.trashList(list) }
            }
        }
    }
}
