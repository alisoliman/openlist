import SwiftUI

struct ContentRevealNotice: View {
    let request: ContentReveal
    let finish: () -> Void

    var body: some View {
        NXNoticeCard(icon: icon, tone: .accent, message: message) {
            Button("Finish", action: finish)
                .buttonStyle(NXPanelButtonStyle(kind: .link))
                .accessibilityLabel("Finish revealing content")
        }
        .accessibilityIdentifier("content-reveal-notice")
    }

    private var icon: String {
        request.source == .localLink ? "link" : request.query.isEmpty ? "eye" : "magnifyingglass"
    }

    private var message: String {
        let title = request.source == .localLink ? "Opened from local link" :
            (request.query.isEmpty ? "Content revealed" : "Search result for “\(request.query)”")
        return request.isArchived ? title + ". This list is archived." : title
    }
}
