//
//  LibraryFailureScreen.swift
//  OpenlistiOS
//

import SwiftUI

/// What the app shows when the library can't be opened. Never an empty
/// library in its place: one saved over it, or synced up, would lose the real
/// one. Restoring from a backup is on the Mac.
struct LibraryFailureScreen: View {
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            OLEmptyState(symbol: "exclamationmark.triangle", tint: OL.danger, title: "Openlist can’t open your library",
                         message: message.isEmpty ? "Something went wrong opening your lists." : message)
            Text("Your lists are untouched. Quit Openlist and open it again; if this keeps happening, restore a backup on your Mac.")
                .font(OLFont.meta)
                .foregroundStyle(OL.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            Spacer()
        }
        .padding(.horizontal, OLMetrics.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OL.canvas.ignoresSafeArea())
        .accessibilityIdentifier("screen.libraryFailure")
    }
}
