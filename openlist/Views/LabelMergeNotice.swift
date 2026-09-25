import SwiftUI

/// A label rename, merge or merge Undo that failed, owned by the shared Store
/// and shown above every screen of the main window, Settings included. A merge
/// that worked reports in the tray, with Undo there and on ⌘Z.
struct LabelMergeNotice: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        if let error = env.store.labelMaintenanceError {
            NXNoticeCard(icon: "exclamationmark.triangle", tone: .error, message: error, lineLimit: 3) {
                Button("Dismiss") { env.store.labelMaintenanceError = nil }
                    .buttonStyle(NXPanelButtonStyle(kind: .quiet))
            }
            .nxNoticePlacement()
        }
    }
}
