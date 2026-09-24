import SwiftUI

/// The same named command is available in pointer and keyboard/VoiceOver menus.
/// It takes its symbol only in a menu whose items all carry one, as the task
/// menu's do; a list's menus are words only.
struct CopyItemLinkButton: View {
    let target: LocalLink.Target
    var iconed = false
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Group {
            if iconed {
                Button("Copy Link", systemImage: "link") { env.copyLink(to: target) }
            } else {
                Button("Copy Link") { env.copyLink(to: target) }
            }
        }
        .help("Copy a link to this item in this Mac’s Openlist library")
    }
}
