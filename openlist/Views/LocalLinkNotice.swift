import SwiftUI

struct LocalLinkNotice: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        if let error = env.localLinks.error {
            // A link that can't open is drawn as a reminder's that can't is, as
            // the two land alike: grey and untitled, the message saying why. A
            // library whose link identity can't be read is the app failing,
            // drawn red as its other failures are.
            let failed = error == .identityUnavailable
            NXNoticeCard(icon: failed ? "exclamationmark.triangle" : "exclamationmark.circle", tone: failed ? .error : .info,
                         message: error.localizedDescription) {
                Button("Dismiss") { env.localLinks.error = nil }
                    .buttonStyle(NXPanelButtonStyle(kind: .quiet))
            }
            .accessibilityIdentifier("local-link-error")
            .nxNoticePlacement()
        }
    }
}
