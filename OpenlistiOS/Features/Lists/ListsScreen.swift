//
//  ListsScreen.swift
//  OpenlistiOS
//

import SwiftUI

/// Lists (mockup 09): browse the list cards or one task queue across lists.
/// Labels open Find and archived lists remain folded away under the cards.
struct ListsScreen: View {
    @Environment(PhoneEnvironment.self) private var env
    @Environment(\.phoneLibrary) private var library
    @State private var namesList = false
    @State private var newName = ""
    @State private var showsArchived = false
    @AppStorage("phone.lists.view", store: ReviewSession.defaults) private var mode: ListsViewMode = .cards
    @State private var selectedLists: Set<UUID> = []

    var body: some View {
        let navigator = env.navigator
        let lists = library.lists.filter { !$0.isSystemInbox && library.hierarchy.parent(of: $0.id) == nil }
        let archived = library.archivedRoots
        OLScreen(identifier: PhoneRoute.lists.screenIdentifier) {
            OLTopBar {
                EmptyView()
            } trailing: {
                OLIconButton("gearshape", label: "Settings", kind: .plain) { navigator.open(.settings) }
                    .accessibilityIdentifier("lists.settings")
            }
        } content: {
            OLHeader("Lists")
            OLSearchLink { navigator.open(.find("")) }
                .padding(.top, OLMetrics.headerGap)
                .accessibilityIdentifier("lists.find")
            ListsViewPicker(selection: $mode)
                .padding(.top, 16)
            if mode == .tasks {
                ListsTasksView(selectedLists: $selectedLists)
            } else if env.awaitsFirstImport(library) {
                OLLoadingState("Getting your lists from iCloud…")
                    .padding(.top, 60)
            } else {
                OLListGrid {
                    ForEach(lists) { list in
                        card(list)
                    }
                    OLNewListCard {
                        newName = ""
                        namesList = true
                    }
                    .accessibilityIdentifier("lists.new")
                }
                .padding(.top, 16)
                if !library.labels.isEmpty {
                    let query = library.findQuery
                    OLGroup("Labels") {
                        OLFlowLayout {
                            ForEach(library.labels) { label in
                                let key = query.key(for: label)
                                OLChipButton(OLChip(key)) { navigator.open(.find(key)) }
                            }
                        }
                    }
                }
                if !archived.isEmpty {
                    OLFold("archived", count: archived.count, isExpanded: $showsArchived) {
                        OLListGrid {
                            ForEach(archived) { list in card(list) }
                        }
                    }
                }
            }
        }
        .alert("New list", isPresented: $namesList) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                if let list = env.actions.createList(named: newName) { navigator.open(.list(list.id)) }
            }
            .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func card(_ list: TaskList) -> some View {
        OLListCard(title: list.displayTitle, icon: list.icon, accent: list.accent, detail: library.cardDetail(for: list)) {
            env.navigator.open(.list(list.id))
        }
        .contextMenu { ListMenuItems(list: list) }
    }
}

extension NextLibrary {
    /// Archived lists whose parent isn't archived with them.
    var archivedRoots: [TaskList] {
        let ids = Set(archived.map(\.id))
        return archived.filter { list in list.parentListID.map { !ids.contains($0) } ?? true }
    }

    /// Find's language over this library: its lists, labels and "done".
    var findQuery: TaskQuery { TaskQuery(lists: lists, labels: labels, readsStatus: true) }

    /// A list card's line: "7 open", "All done" once its tasks are, or
    /// "Empty" with none at all.
    func cardDetail(for list: TaskList) -> String {
        let open = openCount(in: list.id)
        if open > 0 { return "\(open) open" }
        return tasks(in: list.id).isEmpty ? "Empty" : "All done"
    }

    /// Nothing in it yet but the Inbox every library starts with.
    var isEmptyLibrary: Bool { tasks.isEmpty && archived.isEmpty && lists.allSatisfy(\.isSystemInbox) }
}

extension PhoneEnvironment {
    /// The first iCloud import still on its way to a library with nothing in
    /// it yet. Screens say so rather than look empty, and offer nothing to
    /// make meanwhile, which would be there twice once the import lands.
    func awaitsFirstImport(_ library: NextLibrary) -> Bool {
        sync.state.isAwaitingFirstImport && library.isEmptyLibrary
    }
}
