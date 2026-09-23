import SwiftUI
import SwiftData

/// The Work panel's task: its timer while it runs, else when it is planned and
/// how to start. Stop and Complete go through the workbench, as the notch does.
struct WorkSessionCard: View {
    let task: Block
    let chooseTask: () -> Void
    let move: (PlannedBlock) -> Void
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style

    var body: some View {
        if task.modelContext != nil, !task.isDeleted {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let reference = WorkTaskReference(task)
            let session = env.calendar.activeSession.flatMap { $0.occurrenceID == reference.occurrenceID ? $0 : nil }
            let paused = env.calendar.resumableTask?.occurrenceID == reference.occurrenceID
            let plan = env.calendar.plannedWork(reference, now: context.date)
            let quiet = env.calendar.quietUntil[reference.occurrenceID.uuidString].map(Date.init(timeIntervalSince1970:))
            let estimate = env.calendar.estimatedMinutes(for: task)
            VStack(alignment: .leading, spacing: 0) {
                Text(session != nil ? "Working now" : paused ? "Session stopped" : plan.map { $0.start > context.date ? "Planned for later" : "Ready when you are" } ?? "Ready when you are")
                    .font(.system(size: 10.5, weight: .semibold))
                    .kerning(0.74)
                    .textCase(.uppercase)
                    .foregroundStyle(NX.ink(0.36))
                Text(task.displayTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NX.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                Text(env.store.list(id: task.listID)?.displayTitle ?? "Task")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NX.ink(0.5))
                    .padding(.top, 2)

                if session != nil {
                    // Only the running timer needs every second.
                    TimelineView(.periodic(from: .now, by: 1)) { tick in
                        let elapsed = env.calendar.trackedMinutes(for: task, now: tick.date) * 60
                        VStack(alignment: .leading, spacing: 0) {
                            Text(NXFormat.mmss(elapsed))
                                .font(NX.mono(28, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(elapsed > estimate * 60 ? NX.amberText : style.accent)
                                .padding(.top, 14)
                            Text("Recorded · \(minutes(estimate)) estimated")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(NX.ink(0.45))
                                .padding(.top, 3)
                            Group {
                                if let conflict = env.calendar.workConflict, conflict.occurrenceID == reference.occurrenceID {
                                    Text("Running into \(env.workbench.conflictLabel(conflict, inSentence: true)). Still recording.")
                                        .foregroundStyle(NX.redText)
                                } else if env.calendar.overrunNudge?.occurrenceID == reference.occurrenceID {
                                    Text("Estimate almost reached. Recording continues and the plan makes room.")
                                        .foregroundStyle(NX.ink(0.62))
                                } else if elapsed >= estimate * 60 {
                                    Text("Past the estimate. Still recording.").foregroundStyle(NX.ink(0.62))
                                }
                            }
                            .font(.system(size: 12))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 10)
                        }
                    }
                    HStack(spacing: 8) {
                        NXWorkButton("Stop working", action: stop)
                        Spacer(minLength: 8)
                        NXWorkButton("Complete task", prominent: true, action: complete)
                    }
                    .padding(.top, 14)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        if paused, let previous = env.store.workSessions(taskID: task.id).first(where: { $0.occurrenceID == reference.occurrenceID && $0.endedAt != nil }) {
                            detail(previous.pauseReason == "Stopped working" ? "Task still open. No time is being recorded." : "Paused: \(previous.pauseReason ?? "Session ended"). No time is being recorded.",
                                   icon: "pause.circle")
                            caption("\(minutes(env.calendar.recordedMinutes(for: previous))) recorded in the last session")
                        }
                        if let plan {
                            detail("\(plan.start.formatted(date: .abbreviated, time: .shortened))–\(plan.end.formatted(date: .omitted, time: .shortened)) · \(Int(plan.durationMinutes)) min",
                                   icon: "calendar")
                            caption(env.calendar.workPlanSource(task))
                        } else {
                            caption("\(minutes(estimate)) estimated")
                        }
                        if let due = task.dueDate {
                            caption("Due \(due.formatted(date: .abbreviated, time: task.includesTime ? .shortened : .omitted))")
                        }
                        // Hours and busy time shape the plan; they never stop you starting.
                        if !env.calendar.isWithinAvailability(reference, now: context.date) {
                            caption("Outside the list’s hours or during busy time. Time is still recorded.")
                        } else if !paused {
                            caption("Time is recorded only after you start.")
                        }
                        if let quiet, quiet > context.date {
                            HStack(spacing: 10) {
                                caption("Reminder quiet until \(quiet.formatted(date: .omitted, time: .shortened))")
                                NXWorkLink("Undo") { env.calendar.undoQuietWork(reference) }
                            }
                        }
                    }
                    .padding(.top, 12)
                    HStack(spacing: 8) {
                        NXWorkButton(paused ? "Resume working" : plan.map { $0.start > context.date } == true ? "Start now" : "Start working",
                                     prominent: true, action: start)
                            .accessibilityIdentifier("work.start")
                        Spacer(minLength: 8)
                        if paused {
                            NXWorkButton("Complete task", action: complete)
                        } else {
                            Menu {
                                Button("Remind in 15 minutes") { env.calendar.quietWork(reference) }
                                if let plan { Button("Move planned time…") { move(plan) } }
                            } label: {
                                Text("Later…").font(.system(size: 12, weight: .semibold))
                            }
                            .menuStyle(.button)
                            .buttonStyle(NXHoverButtonStyle(hover: NX.ink(0.1), rest: NX.ink(0.05), radius: 8,
                                                            padding: EdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 12),
                                                            foreground: NX.ink(0.72), hoverForeground: NX.ink))
                            .menuIndicator(.hidden)
                            .fixedSize()
                        }
                    }
                    .padding(.top, 14)
                }
                Rectangle().fill(NX.ink(0.08)).frame(height: 0.5).padding(.top, 16)
                HStack(spacing: 14) {
                    NXWorkLink(session == nil ? "Choose another task" : "Switch task…", action: chooseTask)
                    Spacer(minLength: 8)
                    NXWorkLink(session == nil ? "View plan" : "Task details", action: openContext)
                }
                .padding(.top, 10)
                if paused {
                    NXWorkLink("Dismiss stopped session") { env.calendar.dismissResume(); env.calendar.isWorkPanelPresented = false }
                        .padding(.top, 6)
                }
            }
        }
        }
    }

    private func detail(_ text: String, icon: String) -> some View {
        Label {
            Text(text).font(.system(size: 12.5)).foregroundStyle(NX.ink(0.72)).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon).font(.system(size: 11.5)).foregroundStyle(NX.ink(0.45))
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.system(size: 11.5)).foregroundStyle(NX.ink(0.45)).fixedSize(horizontal: false, vertical: true)
    }

    private func minutes(_ value: Double) -> String { "\(value.formatted(.number.precision(.fractionLength(0)))) min" }

    private func start() { env.calendar.requestWork(WorkTaskReference(task)) }

    /// As the notch's ✕: ends the session with its "Stopped" tray, and the panel goes with it.
    private func stop() {
        env.calendar.isWorkPanelPresented = false
        env.workbench.stopWork()
    }

    /// As the notch's ✓ for the task it shows; any other task completes as its row would.
    private func complete() {
        env.calendar.isWorkPanelPresented = false
        if env.workbench.workTask?.id == task.id { env.workbench.finishWork() } else { env.workbench.complete([task.id]) }
    }

    private func openContext() {
        env.calendar.isWorkPanelPresented = false
        if env.calendar.activeSession?.taskID == task.id { env.navigator.openTask(task.id) }
        else { env.navigator.go(to: .calendar) }
    }
}
