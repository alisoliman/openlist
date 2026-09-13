import SwiftUI

struct ContentRevealNotice: View {
    let request: ContentReveal
    let finish: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(message)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Button("Finish", action: finish)
                .accessibilityLabel("Finish revealing content")
        }
        .font(.callout)
        .padding(10)
        .background(Theme.accent.opacity(0.08), in: .rect(cornerRadius: 8))
        .accessibilityIdentifier("content-reveal-notice")
    }

    private var message: String {
        let title = request.source == .localLink ? "Opened from local link" :
            (request.query.isEmpty ? "Content revealed" : "Search result for “\(request.query)”")
        return request.isArchived ? title + ". This list is archived." : title
    }
}
