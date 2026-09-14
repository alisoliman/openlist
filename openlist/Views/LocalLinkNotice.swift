import SwiftUI

struct LocalLinkNotice: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        if let error = env.localLinks.error {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Link unavailable", systemImage: "exclamationmark.circle")
                        .font(.headline)
                    Text(error.localizedDescription)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button("Dismiss") { env.localLinks.error = nil }
            }
            .font(.callout)
            .padding(12)
            .background(ListAccent.orange.softBackground)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("local-link-error")
        }
    }
}
