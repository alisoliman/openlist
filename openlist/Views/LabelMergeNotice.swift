import SwiftUI

/// Owned by the shared Store and shown above every screen of the main window,
/// Settings included.
struct LabelMergeNotice: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = env.store.labelMaintenanceError {
                NXNoticeCard(icon: "exclamationmark.triangle", tone: .error, message: error, lineLimit: 3) {
                    Button("Dismiss") { env.store.labelMaintenanceError = nil }
                        .buttonStyle(NXPanelButtonStyle(kind: .quiet))
                }
            }
            if let plan = env.store.labelMergeUndo {
                NXNoticeCard(icon: "arrow.triangle.merge", tone: .accent,
                             message: "Merged “\(plan.source.name)” into “\(plan.destination.name)”.", lineLimit: 3) {
                    Button("Undo merge") { env.store.undoLabelMerge() }
                        .buttonStyle(NXPanelButtonStyle(kind: .link))
                        .accessibilityIdentifier("undo-label-merge")
                    Button { env.store.labelMergeUndo = nil } label: {
                        Image(systemName: "xmark").font(.system(size: 10.5, weight: .semibold)).frame(width: 14, height: 14)
                    }
                    .buttonStyle(NXPanelButtonStyle(kind: .quiet, size: .icon))
                    .accessibilityLabel("Dismiss")
                    .help("Dismiss merge result")
                }
            }
        }
        .nxNoticePlacement()
        // The Settings window shows it too, outside the Next shell's style.
        .environment(\.nextStyle, env.workbench.style)
    }
}
