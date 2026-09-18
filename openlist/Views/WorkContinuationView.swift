import SwiftUI

struct WorkContinuationView: View {
    @Environment(AppEnvironment.self) private var env
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Time stopped", systemImage: "pause.circle").foregroundStyle(Theme.secondaryText)
            if let nudge = env.calendar.overrunNudge {
                Text(env.store.block(id: nudge.taskID)?.displayTitle ?? "Paused task").font(.title3.weight(.semibold))
                Text("Recording paused at \(nudge.estimatedEnd.formatted(date: .omitted, time: .shortened)).")
                if let proposal = env.calendar.continuationProposal {
                    Text(proposal.changes.isEmpty ? "You can continue in free time." : "Continuing would move \(proposal.changes.count) \(proposal.changes.count == 1 ? "task" : "tasks").")
                    if !proposal.changes.isEmpty {
                        ScrollView { WorkPlanChangesView(changes: proposal.changes) }.frame(maxHeight: 180)
                    }
                    Text("Continue until \(proposal.proposedEnd.formatted(date: .omitted, time: .shortened)); fixed busy time stays protected.")
                        .font(.caption).foregroundStyle(Theme.secondaryText)
                    HStack {
                        Button("Keep paused") { env.calendar.keepWorkPaused() }
                        Spacer()
                        Button("Continue working") { env.calendar.confirmContinuation(proposal) }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    Text("This time is unavailable. Your remaining work is still in the plan.")
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Check availability") { env.calendar.refreshContinuation() }
                    Button("Keep paused") { env.calendar.keepWorkPaused() }
                }
                Divider()
                HStack {
                    Button("Complete task", action: complete).buttonStyle(.link)
                    Spacer()
                    Button("View plan", action: viewPlan).buttonStyle(.link)
                }
            }
        }
    }
    private func complete() {
        guard let nudge = env.calendar.overrunNudge, let task = env.store.block(id: nudge.taskID), task.occurrenceID == nudge.occurrenceID else { return }
        env.calendar.complete(task: task)
    }
    private func viewPlan() { env.calendar.isWorkPanelPresented = false; env.navigator.go(to: .calendar) }
}
