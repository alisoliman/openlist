import SwiftUI

/// The same named command is available in pointer and keyboard/VoiceOver menus.
struct CopyItemLinkButton: View {
    let target: LocalLink.Target
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Button("Copy Link", systemImage: "link") { env.copyLink(to: target) }
            .help("Copy a link to this item in this Mac’s Openlist library")
    }
}
