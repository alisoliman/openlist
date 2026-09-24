import SwiftUI

/// Owned by the shared Store and shown above every screen of the main window,
/// Settings included.
struct LabelMergeNotice: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = env.store.labelMaintenanceError {
                HStack(alignment: .top) {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .help(error)
                    Spacer(minLength: 8)
                    Button("Dismiss") { env.store.labelMaintenanceError = nil }
                        .fixedSize()
                }
            }
            if let plan = env.store.labelMergeUndo {
                let message = "Merged “\(plan.source.name)” into “\(plan.destination.name)”."
                HStack(alignment: .top) {
                    Text(message)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .help(message)
                    Spacer(minLength: 8)
                    Button("Undo merge") { env.store.undoLabelMerge() }
                        .fixedSize()
                        .accessibilityIdentifier("undo-label-merge")
                    Button("Dismiss", systemImage: "xmark") { env.store.labelMergeUndo = nil }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .help("Dismiss merge result")
                }
            }
        }
        .font(.callout)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ListAccent.blue.softBackground)
    }
}
