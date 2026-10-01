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
struct ListPageScreen: View {
    let listID: UUID
    @Environment(PhoneEnvironment.self) private var env
    @Environment(\.phoneLibrary) private var library
    @Query private var blocks: [Block]
    @State private var isSelecting = false
    @State private var showsDone: Bool?
    @State private var renaming = false
    @State private var name = ""
    @State private var namesChild = false
    @State private var confirmsTrash = false

    init(listID: UUID) {
        self.listID = listID
        _blocks = Query(filter: #Predicate<Block> { $0.listID == listID && $0.trashID == nil })
    }

    var body: some View {
        let navigator = env.navigator
        let list = env.store.list(id: listID)
        let document = ListDocument(blocks: blocks, sorting: list?.sorting ?? .manual, closing: env.actions.closing)
        let page = document.page
        let children = list.map(library.children(of:)) ?? []
        let doneOpen = showsDone ?? list?.showsCompleted(default: env.settings.showsCompletedTasks) ?? false
        OLScreen(identifier: PhoneRoute.list(listID).screenIdentifier) {
            OLListHeaderBand(icon: list?.icon ?? "📋", accent: list?.accent ?? .graphite, isInbox: list?.isSystemInbox == true) {
                OLTopBar {
                    OLBackButton(env.backTitle(for: .list(listID))) { navigator.pop() }
                } trailing: {
                    OLIconButton("checkmark.circle", label: "Select tasks", kind: .bare, iconSize: 22) { isSelecting = true }
                        .disabled(document.selectableTasks.isEmpty)
                        .accessibilityIdentifier("list.select")
                    if let list { menu(list) }
                }
            }
        } content: {
            OLHeader(list?.displayTitle ?? "List", sub: page.openCount == 0 ? "All done" : "\(page.openCount) open",
                     topSpacing: 14)
            if page.rows.isEmpty && page.completed.isEmpty && children.isEmpty {
                let archived = list?.isEffectivelyArchived == true
                OLEmptyState(symbol: "checklist", tint: list?.accent.color ?? OL.accentText, title: "Nothing here yet",
                             message: archived ? "This list is archived." : "Tasks you add to this list show here.",
                             actionTitle: archived ? nil : "Add a task") {
                    navigator.open(.capture(CaptureRequest(listID: listID)))
                }
                .padding(.top, 60)
            }
            if !page.rows.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(page.rows.enumerated()), id: \.element.id) { index, row in
                        if row.block.isTask {
                            let previous = index > 0 ? page.rows[index - 1] : nil
                            ListDocumentTaskRow(row: row,
                                                separator: .task(depth: row.depth, previousDepth: previous?.block.isTask == true ? previous?.depth : nil),
                                                canDisclose: document.canDisclose(row), progress: document.progress(for: row.block))
                        } else {
                            ListDocumentTextRow(row: row, canDisclose: document.canDisclose(row))
                        }
                    }
                }
                .olCard()
                .padding(.top, OLMetrics.headerGap)
            }
            if !page.completed.isEmpty {
                OLFold("done", count: page.completed.count,
                       isExpanded: Binding(get: { doneOpen }, set: { showsDone = $0 })) {
                    OLCardRows(page.completed) { task, separator in
                        PhoneTaskRow(task: task, context: .list, separator: separator)
                    }
                }
                .accessibilityIdentifier("list.done")
            }
            if !children.isEmpty {
                OLGroup("Lists") {
                    OLListGrid {
                        ForEach(children) { child in
                            let open = library.openCount(in: child.id)
                            OLListCard(title: child.displayTitle, icon: child.icon, accent: child.accent,
                                       detail: open == 0 ? "All done" : "\(open) open") {
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
        }
        .alert("New list inside", isPresented: $namesChild) {
            TextField("Name", text: $name)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                if let list, let child = env.actions.createList(named: name, under: list) { navigator.open(.list(child.id)) }
            }
        }
        .confirmationDialog("Move “\(list?.displayTitle ?? "")” to Trash?", isPresented: $confirmsTrash, titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) {
                if let list, env.actions.trashList(list) { navigator.pop() }
            }
        } message: {
            Text("Its tasks go with it. You can put it back from Trash.")
        }
        .onAppear { list.map(env.store.markOpened) }
    }

    private func menu(_ list: TaskList) -> some View {
        Menu {
            if !list.isSystemInbox {
                Button("Rename", systemImage: "pencil") {
                    name = list.title
                    renaming = true
                }
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
