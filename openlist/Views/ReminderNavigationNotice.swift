import SwiftUI

struct ReminderNavigationNotice: View {
    @Environment(AppEnvironment.self) private var env
    var body: some View {
        if let message = env.reminderNavigation.unavailableMessage {
            HStack(alignment: .top, spacing: 10) {
                Label(message, systemImage: "bell.slash")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Dismiss") { env.reminderNavigation.unavailableMessage = nil }
            }
            .font(Theme.Font.metadata)
            .padding(12)
            .background(Theme.accent.opacity(0.08))
        }
    }
}
