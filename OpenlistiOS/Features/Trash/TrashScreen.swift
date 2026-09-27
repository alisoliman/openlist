//
//  TrashScreen.swift
//  OpenlistiOS
//

import SwiftUI

/// Trash (mockup 16), pushed inside Settings. The shell's stub: the Settings
/// feature adds the entries, restore and the holds to erase.
struct TrashScreen: View {
    @Environment(PhoneEnvironment.self) private var env

    var body: some View {
        let navigator = env.navigator
        OLScreen(identifier: PhoneRoute.trash.screenIdentifier) {
            OLTopBar { OLBackButton(env.backTitle(for: .trash)) { navigator.pop() } }
        } content: {
            OLHeader("Trash")
            FeaturePlaceholder(summary: "Trash’s entries come with the Settings feature.")
        }
    }
}
