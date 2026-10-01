import SwiftUI

struct AppInformationSection: View {
    var body: some View {
        OLGroup("About") {
            VStack(spacing: 0) {
                if let url = URL(string: "https://github.com/alisoliman/openlist/blob/main/docs/PRIVACY.md") {
                    Link(destination: url) {
                        OLSettingsRow("Privacy policy", tile: .info("hand.raised")) {
                            OLRowValue(nil)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(OLRowPressStyle())
                    .accessibilityIdentifier("settings.privacyPolicy")
                }
                if let url = URL(string: "https://github.com/alisoliman/openlist/blob/main/docs/SUPPORT.md") {
                    Link(destination: url) {
                        OLSettingsRow("Help and support", tile: .info("questionmark.circle"), separator: .settings) {
                            OLRowValue(nil)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(OLRowPressStyle())
                    .accessibilityIdentifier("settings.support")
                }
            }
            .olCard()
        }
    }
}
