import SwiftUI

struct CalendarCoverageView: View {
    @Environment(AppEnvironment.self) private var env
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Deadline coverage").font(.headline)
            Text("Required time includes remaining work. Coverage counts conflict-free time before the deadline.")
                .font(.caption).foregroundStyle(Theme.secondaryText)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if env.calendar.plan.assessments.isEmpty {
                        Text("Select a task for today or add a due date to bring it into the plan.").foregroundStyle(Theme.secondaryText)
                    }
                    ForEach(env.calendar.plan.assessments.sorted { $0.status.rawValue < $1.status.rawValue }) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Button(env.store.block(id: item.taskID)?.displayTitle ?? "Task") { env.navigator.openTask(item.taskID) }
                                .buttonStyle(.plain).font(.body.weight(.medium))
                            Text(item.conflicts.isEmpty ? item.status.title : "Pinned time needs attention").font(.caption.weight(.semibold))
                                .foregroundStyle(item.status == .cannotFitBeforeDeadline || !item.conflicts.isEmpty ? ListAccent.orange.color : Theme.accent)
                            Text("\(Int(item.beforeDeadlineMinutes.rounded())) of \(Int(item.requiredMinutes.rounded())) min covered · \(Int(item.scheduledMinutes.rounded())) min scheduled")
                                .font(.caption).foregroundStyle(Theme.secondaryText)
                            Text(item.reason).font(.caption).foregroundStyle(Theme.secondaryText)
                            ForEach(item.conflicts, id: \.self) { conflict in
                                Label(conflict, systemImage: "pin.slash").font(.caption).foregroundStyle(ListAccent.orange.color)
                            }
                        }
                        Divider()
                    }
                }
            }
        }.padding(20)
    }
}
