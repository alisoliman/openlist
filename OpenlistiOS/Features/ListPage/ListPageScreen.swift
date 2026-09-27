//
//  ListPageScreen.swift
//  OpenlistiOS
//

import SwiftUI

/// A list's page (mockup 10). The shell's stub: the Lists feature adds its
/// rows, fold, add row and menu.
struct ListPageScreen: View {
    let listID: UUID
    @Environment(PhoneEnvironment.self) private var env
    @State private var isSelecting = false

    var body: some View {
        let navigator = env.navigator
        let list = env.store.list(id: listID)
        OLScreen(identifier: PhoneRoute.list(listID).screenIdentifier) {
            OLListHeaderBand(icon: list?.icon ?? "📋", accent: list?.accent ?? .graphite,
                             isInbox: list?.isSystemInbox == true) {
                OLTopBar {
                    OLBackButton(env.backTitle(for: .list(listID))) { navigator.pop() }
                } trailing: {
                    OLIconButton("checkmark.circle", label: "Select tasks", kind: .bare, iconSize: 22) { isSelecting = true }
                    OLIconButton("ellipsis", label: "List options", kind: .bare, iconSize: 22) {}
                }
            }
        } content: {
            OLHeader(list?.displayTitle ?? "List", topSpacing: 14)
            FeaturePlaceholder(summary: "The list’s tasks come with the Lists feature.",
                               links: FeaturePlaceholder.firstTask(in: env, listID: listID))
        }
        .modifier(SelectMode(isSelecting: $isSelecting, listTitle: list?.displayTitle ?? ""))
    }
}
