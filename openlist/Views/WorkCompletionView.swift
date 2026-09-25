import SwiftUI

/// The Work panel after its task is done, in the design's words for the
/// same event: "Done", or for a repeat when it rolls to next.
struct WorkCompletionView: View {
    let summary: WorkCompletionSummary
    let chooseNext: () -> Void
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label {
                Text("Done")
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(NX.green)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(NX.ink(0.55))
            Text(summary.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(NX.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            Text("\(summary.recordedMinutes.formatted(.number.precision(.fractionLength(0)))) min recorded. Recording stopped.")
                .font(.system(size: 12.5))
                .foregroundStyle(NX.ink(0.62))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            if let date = summary.nextDate {
                // As the tray's "“…” rolls to Wed 30".
                Text("Rolls to \(NXFormat.dueLabel(date))")
                    .font(.system(size: 11.5))
                    .foregroundStyle(NX.ink(0.45))
                    .padding(.top, 4)
            }
            HStack(spacing: 8) {
                if summary.undoID != nil {
                    Button("Undo completion") { env.calendar.undoWorkCompletion() }
                        .buttonStyle(NXPanelButtonStyle())
                        .fixedSize()
                }
                Spacer(minLength: 8)
                Button("Choose next task", action: chooseNext)
                    .buttonStyle(NXPanelButtonStyle(kind: .primary))
                    .fixedSize()
            }
            .padding(.top, 14)
        }
    }
}
