import SwiftUI

/// A failed Trash change, which stays until dismissed. It shows with the
/// window's other notices under the toolbar (`NextNotices`), clear of the
/// sidebar and an open inspector, including at narrow window widths.
struct TrashNotice: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        if let message = env.store.trashError {
            NXNoticeCard(icon: "exclamationmark.triangle", tone: .error, message: message) {
                if env.navigator.route != .trash {
                    Button("Open Trash") { env.navigator.go(to: .trash) }
                        .buttonStyle(NXPanelButtonStyle(kind: .link))
                }
                Button("Dismiss") { env.store.trashError = nil }
                    .buttonStyle(NXPanelButtonStyle(kind: .quiet))
            }
            .nxNoticePlacement()
        }
    }
}
