import SwiftUI
import SwiftData

struct WorkSessionCard: View {
    let task: Block
    let chooseTask: () -> Void
    let move: (PlannedBlock) -> Void
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        if task.modelContext != nil, !task.isDeleted {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let reference = WorkTaskReference(task)
            let session = env.calendar.activeSession.flatMap { $0.occurrenceID == reference.occurrenceID ? $0 : nil }
            let paused = env.calendar.resumableTask?.occurrenceID == reference.occurrenceID
            let plan = env.calendar.plannedWork(reference, now: context.date)
            let quiet = env.calendar.quietUntil[reference.occurrenceID.uuidString].map(Date.init(timeIntervalSince1970:))
            VStack(alignment: .leading, spacing: 14) {
                Text(session != nil ? "Working now" : paused ? "Session stopped" : plan.map { $0.start > context.date ? "Planned for later" : "Ready when you are" } ?? "Ready when you are")
                    .font(.callout).foregroundStyle(Theme.secondaryText)
                Text(task.displayTitle).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                Text(env.store.list(id: task.listID)?.displayTitle ?? "Task").font(.callout).foregroundStyle(Theme.secondaryText)

                if let session {
                    Text("\(env.calendar.recordedMinutes(for: session, now: context.date).formatted(.number.precision(.fractionLength(0)))) min")
                        .font(.largeTitle).monospacedDigit()
                    Text("Recorded this session · \(env.calendar.estimatedMinutes(for: task).formatted(.number.precision(.fractionLength(0)))) min estimated")
                        .font(.caption).foregroundStyle(Theme.secondaryText)
                    if env.calendar.overrunNudge?.kind == .headsUp {
                        Text("Estimate almost reached. Recording will pause if more time would move other tasks.")
                            .font(.callout).fixedSize(horizontal: false, vertical: true)
                    } else if env.calendar.trackedMinutes(for: task, now: context.date) >= env.calendar.estimatedMinutes(for: task) {
                        Text("Estimate reached; still recording in free time.").font(.callout)
                    }
                    HStack {
                        Button("Stop working", action: stop)
                        Spacer(minLength: 8)
                        Button("Complete task", action: complete).buttonStyle(.borderedProminent)
                    }
                } else {
                    if paused, let previous = env.store.workSessions(taskID: task.id).first(where: { $0.occurrenceID == reference.occurrenceID && $0.endedAt != nil }) {
                        Label(previous.pauseReason == "Stopped working" ? "Task still open. No time is being recorded." : "Paused: \(previous.pauseReason ?? "Session ended"). No time is being recorded.", systemImage: "pause.circle")
                            .font(.callout).fixedSize(horizontal: false, vertical: true)
                        Text("\(env.calendar.recordedMinutes(for: previous).formatted(.number.precision(.fractionLength(0)))) min recorded in the last session")
                            .font(.caption).foregroundStyle(Theme.secondaryText)
                    }
                    if let plan {
                        Label("\(plan.start.formatted(date: .abbreviated, time: .shortened))–\(plan.end.formatted(date: .omitted, time: .shortened)) · \(Int(plan.durationMinutes)) min", systemImage: "calendar")
                            .font(.callout).fixedSize(horizontal: false, vertical: true)
                        Text(env.calendar.workPlanSource(task)).font(.caption).foregroundStyle(Theme.secondaryText)
                    } else {
                        Text("\(env.calendar.estimatedMinutes(for: task).formatted(.number.precision(.fractionLength(0)))) min estimated")
                            .font(.callout).foregroundStyle(Theme.secondaryText)
                    }
                    if let due = task.dueDate {
                        Text("Due \(due.formatted(date: .abbreviated, time: task.includesTime ? .shortened : .omitted))")
                            .font(.caption).foregroundStyle(Theme.secondaryText)
                    }
                    if !env.calendar.canStartWork(reference, now: context.date) {
                        Text("Outside available hours or during fixed busy time. Choose an available slot in your plan.")
                            .font(.callout).fixedSize(horizontal: false, vertical: true)
                    } else if !paused {
                        Text("Time is recorded only after you start.").font(.caption).foregroundStyle(Theme.secondaryText)
                    }
                    if let quiet, quiet > context.date {
                        HStack {
                            Text("Reminder quiet until \(quiet.formatted(date: .omitted, time: .shortened))").font(.caption)
                            Button("Undo") { env.calendar.undoQuietWork(reference) }.buttonStyle(.link)
                        }
                    }
                    HStack {
                        Button(paused ? "Resume working" : plan.map { $0.start > context.date } == true ? "Start now" : "Start working", action: start)
                            .buttonStyle(.borderedProminent)
                            .disabled(!env.calendar.canStartWork(reference, now: context.date))
                            .accessibilityIdentifier("work.start")
                        Spacer(minLength: 8)
                        if paused { Button("Complete task", action: complete) }
                        else {
                            Menu("Later…") {
                                Button("Remind in 15 minutes") { env.calendar.quietWork(reference) }
                                if let plan { Button("Move planned time…") { move(plan) } }
                            }.fixedSize()
                        }
                    }
                }
                Divider()
                HStack {
                    Button(session == nil ? "Choose another task" : "Switch task…", action: chooseTask).buttonStyle(.link)
                    Spacer()
                    Button(session == nil ? "View plan" : "Task details", action: openContext).buttonStyle(.link)
                }
                if paused {
                    Button("Dismiss stopped session") { env.calendar.dismissResume(); env.calendar.isWorkPanelPresented = false }
                        .buttonStyle(.link).font(.caption)
                }
            }
        }
        }
    }

    private func start() { env.calendar.requestWork(WorkTaskReference(task)) }
    private func stop() { env.calendar.stopWorking() }
    private func complete() { env.calendar.complete(task: task) }
    private func openContext() {
        env.calendar.isWorkPanelPresented = false
        if env.calendar.activeSession?.taskID == task.id { env.navigator.openTask(task.id) }
        else { env.navigator.go(to: .calendar) }
    }
}
