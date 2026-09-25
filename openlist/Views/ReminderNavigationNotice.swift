import SwiftUI

struct ReminderNavigationNotice: View {
    @Environment(AppEnvironment.self) private var env
    var body: some View {
        if let message = env.reminderNavigation.unavailableMessage {
            NXNoticeCard(icon: "bell.slash", message: message) {
                Button("Dismiss") { env.reminderNavigation.unavailableMessage = nil }
                    .buttonStyle(NXPanelButtonStyle(kind: .quiet))
            }
            .nxNoticePlacement()
        }
    }
}
