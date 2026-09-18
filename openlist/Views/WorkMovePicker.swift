import SwiftUI

struct WorkMovePicker: View {
    let block: PlannedBlock
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date.now
    @State private var changes: [WorkPlanChange] = []
    @State private var feedback: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Move planned work").font(.headline)
            Text(env.store.block(id: block.taskID)?.displayTitle ?? "Task").font(.title3)
            DatePicker("Start", selection: $date, in: Date.now...)
            Text("This changes your preferred work time, not your deadline.").font(.callout).foregroundStyle(Theme.secondaryText)
            if !changes.isEmpty {
                Text("Other planned work would move:").font(.callout)
                ScrollView { WorkPlanChangesView(changes: changes) }
                    .frame(maxHeight: 200)
            }
            if let feedback { Text(feedback).font(.callout) }
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button(changes.isEmpty ? "Move" : "Move and update plan", action: confirm)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20).frame(width: 400)
        .onAppear { date = max(.now, block.start); refresh() }
        .onChange(of: date) { _, _ in refresh() }
    }
    private func refresh() { changes = env.calendar.previewMove(block, to: date); feedback = nil }
    private func confirm() {
        let current = env.calendar.previewMove(block, to: date)
        guard current == changes else { changes = current; feedback = "The plan changed. Review these times before moving."; return }
        env.calendar.move(block: block, to: date)
        if env.store.persistenceError == nil { dismiss() }
        else { feedback = env.store.persistenceError }
    }
}
