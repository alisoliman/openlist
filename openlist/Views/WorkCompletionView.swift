import SwiftUI

struct WorkCompletionView: View {
    let summary: WorkCompletionSummary
    let chooseNext: () -> Void
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Occurrence complete", systemImage: "checkmark.circle").foregroundStyle(Theme.secondaryText)
            Text(summary.title).font(.title3.weight(.semibold))
            Text("\(summary.recordedMinutes.formatted(.number.precision(.fractionLength(0)))) minutes recorded. Nothing else has started.")
                .fixedSize(horizontal: false, vertical: true)
            if let date = summary.nextDate { Text("Repeats \(date.formatted(date: .abbreviated, time: .omitted))").foregroundStyle(Theme.secondaryText) }
            HStack {
                if summary.undoID != nil { Button("Undo completion") { env.calendar.undoWorkCompletion() } }
                Spacer()
                Button("Choose next task", action: chooseNext).buttonStyle(.borderedProminent)
            }
        }
    }
}
