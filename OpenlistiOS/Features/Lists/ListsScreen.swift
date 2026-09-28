//
//  ListsScreen.swift
//  OpenlistiOS
//

import SwiftUI

/// Lists (mockup 09): Find, every top-level list as a card with its open
/// count, New list, the labels, which open Find on them, and archived lists
/// folded away at the end.
struct ListsScreen: View {
    @Environment(PhoneEnvironment.self) private var env
    @Environment(\.phoneLibrary) private var library
    @State private var namesList = false
    @State private var newName = ""
    @State private var showsArchived = false

    var body: some View {
        let navigator = env.navigator
        let lists = library.lists.filter { !$0.isSystemInbox && library.hierarchy.parent(of: $0.id) == nil }
        let archived = library.archivedRoots
        OLScreen(identifier: PhoneRoute.lists.screenIdentifier) {
            OLTopBar {
                EmptyView()
            } trailing: {
                OLIconButton(icon: .settings, label: "Settings", kind: .bare, iconSize: 22) { navigator.open(.settings) }
                    .accessibilityIdentifier("lists.settings")
            }
        } content: {
            OLHeader("Lists")
            OLSearchLink { navigator.open(.find("")) }
                .padding(.top, OLMetrics.headerGap)
                .accessibilityIdentifier("lists.find")
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
            .padding(.top, OLMetrics.headerGap)
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
        .alert("New list", isPresented: $namesList) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                if let list = env.actions.createList(named: newName) { navigator.open(.list(list.id)) }
            }
        }
    }

    private func card(_ list: TaskList) -> some View {
        let open = library.openCount(in: list.id)
        return OLListCard(title: list.displayTitle, icon: list.icon, accent: list.accent,
                          detail: open == 0 ? "All done" : "\(open) open") {
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
}
