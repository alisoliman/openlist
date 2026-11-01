//
//  LibraryFailureScreen.swift
//  OpenlistiOS
//

import SwiftUI

/// What the app shows when the library can't be opened. Never an empty
/// library in its place: one saved over it, or synced up, would lose the real
/// one. Try Again opens it afresh; restoring from a backup is on the Mac.
struct LibraryFailureScreen: View {
    let message: String
    /// How many times Try Again has failed, each felt and heard as it does.
    var failedRetries = 0
    /// Opens the library again, which takes this screen's place once it opens.
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            OLEmptyState(symbol: "exclamationmark.triangle", tint: OL.danger, title: "Openlist can’t open your library",
                         message: message.isEmpty ? "Something went wrong opening your lists." : message,
                         actionTitle: "Try Again", action: retry)
            Text("Your lists are untouched. If this keeps happening, quit Openlist and open it again, or restore a backup on your Mac.")
                .font(OLFont.meta)
                .foregroundStyle(OL.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            Spacer()
        }
        .padding(.horizontal, OLMetrics.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OL.canvas.ignoresSafeArea())
        .sensoryFeedback(.error, trigger: failedRetries)
        .onChange(of: failedRetries) {
            AccessibilityNotification.Announcement("Openlist still can’t open your library").post()
        }
        .accessibilityIdentifier("screen.libraryFailure")
    }
}
