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
                NXPanelTitle(occurrenceID == nil ? "Work history" : "Completed occurrence")
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(NXPanelButtonStyle(kind: .primary))
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
                Text(occurrenceID == nil ? "Each recurring occurrence has its own completion record." : "This history belongs to the completed occurrence, including its title and recorded work.")
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
                                        Text(record.completedAt.formatted(date: .abbreviated, time: .shortened))
                                        if record.wasRecurring { Label("Recurring occurrence", systemImage: "repeat") }
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

/// Where a completed occurrence was planned, folded under a quiet chevron
/// as the inspector's disclosures are.
private struct PlannedIntervalsDisclosure: View {
    @Environment(\.nextStyle) private var style
    let intervals: [CompletionCalendarInterval]
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { withAnimation(style.ease(220)) { isExpanded.toggle() } } label: {
                HStack(spacing: 5) {
                    Text("Originally planned")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8.5, weight: .bold))
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
            }
            .buttonStyle(NXPanelButtonStyle(kind: .quiet, size: .small))
            .padding(.leading, -5)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            if isExpanded {
                ForEach(Array(intervals.enumerated()), id: \.offset) { _, interval in
                    Text("\(interval.start.formatted(date: .abbreviated, time: .shortened)) – \(interval.end.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 11.5)).foregroundStyle(NX.ink(0.5))
                }
                .transition(.opacity)
            }
        }
    }
}
