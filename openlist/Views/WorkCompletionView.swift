import SwiftUI

struct WorkCompletionView: View {
    let summary: WorkCompletionSummary
    let chooseNext: () -> Void
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label {
                Text("Occurrence complete")
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
            Text("\(summary.recordedMinutes.formatted(.number.precision(.fractionLength(0)))) minutes recorded. Nothing else has started.")
                .font(.system(size: 12.5))
                .foregroundStyle(NX.ink(0.62))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            if let date = summary.nextDate {
                Text("Repeats \(date.formatted(date: .abbreviated, time: .omitted))")
                    .font(.system(size: 11.5))
                    .foregroundStyle(NX.ink(0.45))
                    .padding(.top, 4)
            }
            HStack(spacing: 8) {
                if summary.undoID != nil { NXWorkButton("Undo completion") { env.calendar.undoWorkCompletion() } }
                Spacer(minLength: 8)
                NXWorkButton("Choose next task", prominent: true, action: chooseNext)
            }
            .padding(.top, 14)
        }
    }
}
