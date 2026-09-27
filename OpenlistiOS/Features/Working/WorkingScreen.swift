//
//  WorkingScreen.swift
//  OpenlistiOS
//

import SwiftUI

/// Working (mockup 04), a full-screen cover. The shell's stub: the Work
/// feature draws the timer, its controls and the Next card.
struct WorkingScreen: View {
    @Environment(PhoneEnvironment.self) private var env

    var body: some View {
        let navigator = env.navigator
        OLScreen(identifier: PhoneRoute.working.screenIdentifier, scrolls: false) {
            OLTopBar {
                OLIconButton("chevron.down", label: "Close", kind: .bare, iconSize: 22) { navigator.dismissCover() }
            } trailing: {
                if let session = env.calendar.activeSession {
                    OLIconButton("doc.text", label: "Task details", kind: .bare, iconSize: 22) {
                        navigator.open(.taskDetail(session.taskID))
                    }
                }
            }
        } content: {
            OLHeader(env.calendar.activeSession?.title ?? "Working")
            FeaturePlaceholder(summary: "The timer, Pause and Done come with the Work feature.")
        }
    }
}
