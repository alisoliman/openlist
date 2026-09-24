import SwiftUI

struct LocalLinkNotice: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        if let error = env.localLinks.error {
            // Drawn as a reminder's that can't open is, as the two land alike:
            // grey and untitled, the message saying why.
            NXNoticeCard(icon: "exclamationmark.circle", message: error.localizedDescription) {
                Button("Dismiss") { env.localLinks.error = nil }
                    .buttonStyle(NXPanelButtonStyle(kind: .quiet))
            }
            .accessibilityIdentifier("local-link-error")
            .nxNoticePlacement()
        }
    }
}
