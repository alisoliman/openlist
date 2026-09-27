//
//  InboxScreen.swift
//  OpenlistiOS
//

import SwiftUI

/// The Inbox (mockup 07). The shell's stub: the Inbox feature lists the
/// captures with their ages.
struct InboxScreen: View {
    @Environment(PhoneEnvironment.self) private var env

    var body: some View {
        let navigator = env.navigator
        OLScreen(identifier: PhoneRoute.inbox.screenIdentifier) {
            OLTopBar { OLEyebrow("To triage", color: OL.infoText) }
        } content: {
            OLHeader("Inbox")
            Button("Triage one by one") { navigator.open(.triage) }
                .buttonStyle(.ol(.primary, block: true))
                .padding(.top, OLMetrics.headerGap)
            FeaturePlaceholder(summary: "The Inbox’s captures come with the Capture feature.",
                               links: FeaturePlaceholder.firstTask(in: env, listID: navigator.inboxListID))
        }
    }
}
