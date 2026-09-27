//
//  ListsScreen.swift
//  OpenlistiOS
//

import SwiftUI

/// Lists (mockup 09). The shell's stub: the Lists feature adds live counts,
/// labels, archived and nested lists and New list.
struct ListsScreen: View {
    @Environment(PhoneEnvironment.self) private var env

    var body: some View {
        let navigator = env.navigator
        OLScreen(identifier: PhoneRoute.lists.screenIdentifier) {
            OLTopBar {
                EmptyView()
            } trailing: {
                OLIconButton("gearshape", label: "Settings", kind: .bare, iconSize: 22) { navigator.open(.settings) }
                    .accessibilityIdentifier("lists.settings")
            }
        } content: {
            OLHeader("Lists")
            OLSearchLink { navigator.open(.find("")) }
                .padding(.top, OLMetrics.headerGap)
            OLListGrid {
                ForEach(env.store.allLists().filter { !$0.isSystemInbox && $0.parentListID == nil }) { list in
                    OLListCard(title: list.displayTitle, icon: list.icon, accent: list.accent) {
                        navigator.open(.list(list.id))
                    }
                }
                OLNewListCard {}
            }
            .padding(.top, OLMetrics.headerGap)
        }
    }
}
