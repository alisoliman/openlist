import SwiftData
import SwiftUI

struct CalendarHistoryView: View {
    var taskID: UUID? = nil
    var occurrenceID: UUID? = nil
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\WorkSession.startedAt, order: .reverse)]) private var allSessions: [WorkSession]
    @Query(sort: [SortDescriptor(\CompletionRecord.completedAt, order: .reverse)]) private var allCompletions: [CompletionRecord]
    @State private var tab = 0

    init(taskID: UUID? = nil, occurrenceID: UUID? = nil) {
        self.taskID = taskID
        self.occurrenceID = occurrenceID
        _tab = State(initialValue: occurrenceID == nil ? 0 : 1)
    }
    private var sessions: [WorkSession] { allSessions.filter { (taskID == nil || $0.taskID == taskID) && (occurrenceID == nil || $0.occurrenceID == occurrenceID) } }
    private var completions: [CompletionRecord] { allCompletions.filter { (taskID == nil || $0.taskID == taskID) && (occurrenceID == nil || $0.occurrenceID == occurrenceID) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(occurrenceID == nil ? "Work history" : "Completed occurrence").font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            Picker("History", selection: $tab) {
                Text("Work sessions").tag(0)
                Text("Completions").tag(1)
            }.pickerStyle(.segmented)
            if tab == 0 {
                Text("Only explicitly started work is recorded. Correct a finished session to improve remaining time and future duration suggestions.")
                    .font(.caption).foregroundStyle(Theme.secondaryText)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if sessions.isEmpty { Text("No work sessions recorded yet.").foregroundStyle(Theme.secondaryText).padding(.vertical, 20) }
                        ForEach(sessions) { session in
                            CalendarSessionRow(session: session)
                            Divider()
                        }
                    }
                }
            } else {
                Text(occurrenceID == nil ? "Each recurring occurrence has its own completion record." : "This history belongs to the completed occurrence, including its title and recorded work.")
                    .font(.caption).foregroundStyle(Theme.secondaryText)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if completions.isEmpty { Text("No completion history yet.").foregroundStyle(Theme.secondaryText).padding(.vertical, 20) }
                        ForEach(completions) { record in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(ListAccent.green.color)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(record.title).font(.body.weight(.medium))
                                    Text(record.completedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption).foregroundStyle(Theme.secondaryText)
                                    if record.wasRecurring { Label("Recurring occurrence", systemImage: "repeat").font(.caption).foregroundStyle(Theme.secondaryText) }
                                    if !record.plannedIntervals.isEmpty {
                                        DisclosureGroup("Originally planned") {
                                            ForEach(Array(record.plannedIntervals.enumerated()), id: \.offset) { _, interval in
                                                Text("\(interval.start.formatted(date: .abbreviated, time: .shortened)) – \(interval.end.formatted(date: .omitted, time: .shortened))")
                                                    .font(.caption).foregroundStyle(Theme.secondaryText)
                                            }
                                        }
                                        .font(.caption)
                                    }
                                }
                                Spacer(minLength: 0)
                                let recordedSessions = sessions.filter { $0.occurrenceID == record.occurrenceID && $0.endedAt != nil }
                                let minutes = recordedSessions.reduce(0) { $0 + env.calendar.recordedMinutes(for: $1) }
                                Text(recordedSessions.isEmpty ? "Time not tracked" : "\(minutes.formatted(.number.precision(.fractionLength(0)))) min worked")
                                    .font(.caption).foregroundStyle(Theme.secondaryText)
                            }
                            Divider()
                        }
                    }
                }
            }
        }.padding(24).frame(width: 580, height: 560)
    }
}
