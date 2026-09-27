//
//  TriageScreen.swift
//  OpenlistiOS
//

import SwiftUI

/// Triage (mockup 08), a full-screen cover. The shell's stub: the Capture
/// feature deals the Inbox one card at a time.
struct TriageScreen: View {
    @Environment(PhoneEnvironment.self) private var env

    var body: some View {
        let navigator = env.navigator
        OLScreen(identifier: PhoneRoute.triage.screenIdentifier, scrolls: false) {
            OLTopBar {
                OLIconButton("xmark", label: "Close", kind: .bare, iconSize: 22) { navigator.dismissCover() }
            }
        } content: {
            OLProgressBar(value: 0, tint: OL.info).padding(.top, 6)
            FeaturePlaceholder(summary: "Triage’s cards come with the Capture feature.")
        }
    }
}
