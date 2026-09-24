import SwiftUI

struct LocalLinkNotice: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        if let error = env.localLinks.error {
            NXNoticeCard(icon: "exclamationmark.circle", tone: .warning, title: "Link unavailable",
                         message: error.localizedDescription) {
                Button("Dismiss") { env.localLinks.error = nil }
                    .buttonStyle(NXPanelButtonStyle(kind: .quiet))
            }
            .accessibilityIdentifier("local-link-error")
            .nxNoticePlacement()
        }
    }
}
