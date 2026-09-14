import SwiftUI

/// Reserves space inside the detail column so recovery feedback never covers
/// the sidebar or an open inspector, including at narrow window widths.
struct TrashNotice: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        if let message = env.store.trashError ?? env.store.trashNotice {
            HStack(alignment: .top, spacing: 12) {
                Label(message, systemImage: env.store.trashError == nil ? "arrow.uturn.backward" : "exclamationmark.triangle")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if env.navigator.route != .trash {
                    Button("Open Trash") { env.navigator.go(to: .trash) }.fixedSize()
                }
                Button("Dismiss") { env.store.trashError = nil; env.store.trashNotice = nil }.fixedSize()
            }
            .padding(12)
            .background(Theme.canvas)
            .overlay(alignment: .bottom) { Divider() }
        }
    }
}
