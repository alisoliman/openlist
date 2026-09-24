import SwiftUI

/// Reserves space inside the detail column so recovery feedback never covers
/// the sidebar or an open inspector, including at narrow window widths.
struct TrashNotice: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        if let message = env.store.trashError ?? env.store.trashNotice {
            let failed = env.store.trashError != nil
            NXNoticeCard(icon: failed ? "exclamationmark.triangle" : "arrow.uturn.backward",
                         tone: failed ? .error : .info, message: message) {
                if env.navigator.route != .trash {
                    Button("Open Trash") { env.navigator.go(to: .trash) }
                        .buttonStyle(NXPanelButtonStyle(kind: .link))
                }
                Button("Dismiss") { env.store.trashError = nil; env.store.trashNotice = nil }
                    .buttonStyle(NXPanelButtonStyle(kind: .quiet))
            }
            .nxNoticePlacement()
        }
    }
}
