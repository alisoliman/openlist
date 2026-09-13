import SwiftUI

struct CalendarMovePicker: View {
    let block: PlannedBlock
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date.now
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Move task").font(.headline)
            DatePicker("Start", selection: $date)
            Text("Move sets a flexible preference. Pin time keeps the requested time fixed and shows any conflicts.")
                .font(.caption).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Pin time") { env.calendar.move(block: block, to: date, isPinned: true); dismiss() }
                    .help("Keep this time fixed and flag conflicts")
                Button("Move") { env.calendar.move(block: block, to: date); dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(16).frame(width: 320).onAppear { date = block.start }
    }
}
