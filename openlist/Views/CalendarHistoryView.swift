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
            HStack(alignment: .center) {
                // One completion's history is titled by its task.
                NXPanelTitle(occurrenceID == nil ? "Work history" : completions.first?.title ?? "Work history")
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(NXPanelButtonStyle(kind: .primary))
                    // Esc closes it too, as it does every Next sheet, while
                    // Done keeps Return.
                    .background {
                        Button("Close") { dismiss() }
                            .keyboardShortcut(.cancelAction)
                            .opacity(0)
                            .frame(width: 0, height: 0)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
            }
            NXSegmented(options: [(0, "Work sessions"), (1, "Completions")], selection: tab) { tab = $0 }
                .accessibilityRepresentation {
                    Picker("History", selection: $tab) {
                        Text("Work sessions").tag(0)
                        Text("Completions").tag(1)
                    }
                    .pickerStyle(.segmented)
                }
            if tab == 0 {
                Text("Only explicitly started work is recorded. Correct a finished session to improve remaining time and future duration suggestions.")
                    .font(.system(size: 11.5)).foregroundStyle(NX.ink(0.5))
                    .fixedSize(horizontal: false, vertical: true)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if sessions.isEmpty { NXDashedEmpty(text: "No work sessions recorded yet.") }
                        ForEach(sessions) { session in
                            CalendarSessionRow(session: session)
                            hairline
                        }
                    }
                }
            } else {
                Text(occurrenceID == nil ? "Every completion is listed on its own, so a repeating task shows each time it was done." : "What was recorded when this task was done, under the title it had then.")
                    .font(.system(size: 11.5)).foregroundStyle(NX.ink(0.5))
                    .fixedSize(horizontal: false, vertical: true)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if completions.isEmpty { NXDashedEmpty(text: "No completion history yet.") }
                        ForEach(completions) { record in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(NX.green)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(record.title).font(.system(size: 13, weight: .medium)).foregroundStyle(NX.ink)
                                    Group {
                                        Text(NXFormat.moment(record.completedAt))
                                        if record.wasRecurring {
                                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                                Image(systemName: "repeat").font(.system(size: 10.5, weight: .medium))
                                                    .accessibilityHidden(true)
                                                Text("Repeating task")
                                            }
                                        }
                                    }
                                    .font(.system(size: 11.5)).foregroundStyle(NX.ink(0.5))
                                    if !record.plannedIntervals.isEmpty {
                                        PlannedIntervalsDisclosure(intervals: record.plannedIntervals)
                                    }
                                }
                                Spacer(minLength: 0)
                                let recordedSessions = sessions.filter { $0.occurrenceID == record.occurrenceID && $0.endedAt != nil }
                                let minutes = recordedSessions.reduce(0) { $0 + env.calendar.recordedMinutes(for: $1) }
                                Text(recordedSessions.isEmpty ? "Time not tracked" : "\(minutes.formatted(.number.precision(.fractionLength(0)))) min worked")
                                    .font(.system(size: 11.5, weight: .medium)).monospacedDigit().foregroundStyle(NX.ink(0.5))
                            }
                            hairline
                        }
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 580, height: 560)
        .presentationBackground(NX.card)
        .tint(env.workbench.style.accent)
        .environment(\.nextStyle, env.workbench.style)
    }

    private var hairline: some View {
        Rectangle().fill(NX.ink(0.07)).frame(height: 0.5)
    }
}

/// Where a completed occurrence was planned, folded under the quiet chevron
/// the inspector's disclosures use.
private struct PlannedIntervalsDisclosure: View {
    let intervals: [CompletionCalendarInterval]
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            NXDisclosureButton("Originally planned", isExpanded: $isExpanded)
            if isExpanded {
                ForEach(Array(intervals.enumerated()), id: \.offset) { _, interval in
                    Text("\(NXFormat.moment(interval.start))–\(NXFormat.clock(interval.end))")
                        .font(.system(size: 11.5)).foregroundStyle(NX.ink(0.5))
                }
                .transition(.opacity)
            }
        }
    }
}
