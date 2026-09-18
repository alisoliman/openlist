import SwiftUI

struct WorkPopover: View {
    @Environment(AppEnvironment.self) private var env
    @State private var choosingTask = false
    @State private var movingBlock: PlannedBlock?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(choosingTask ? "Choose a task" : "Work").font(.headline)
                Spacer()
                Button("Close work details", systemImage: "xmark", action: close)
                    .labelStyle(.iconOnly).buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
            }
            if let notice = env.calendar.notice {
                VStack(alignment: .leading, spacing: 6) {
                    Label(notice, systemImage: "info.circle")
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                    Button("Dismiss notice") { env.calendar.notice = nil }.buttonStyle(.link)
                }
                .accessibilityElement(children: .contain)
            }
            if choosingTask {
                WorkTaskChooser { reference in
                    env.calendar.selectWork(reference)
                    choosingTask = false
                }
            } else if let pending = env.calendar.pendingWorkStart {
                WorkSwitchConfirmation(reference: pending)
            } else if let summary = env.calendar.workCompletion {
                WorkCompletionView(summary: summary, chooseNext: chooseTask)
            } else if env.calendar.overrunNudge?.needsConfirmation == true {
                WorkContinuationView()
            } else if let task = env.calendar.selectedWorkTask {
                WorkSessionCard(task: task, chooseTask: chooseTask, move: { movingBlock = $0 })
            } else {
                ContentUnavailableView {
                    Label("What would you like to work on?", systemImage: "timer")
                } description: {
                    Text("No task is planned for now. Start a session whenever it helps.")
                } actions: {
                    Button("Choose a task", action: chooseTask).buttonStyle(.borderedProminent)
                    Button("Open calendar", action: openCalendar)
                }
            }

            if let summary = env.calendar.rescheduleSummary {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Label(summary.message, systemImage: "calendar.badge.clock").font(.callout)
                    if let reason = summary.reason { Text(reason).font(.caption).foregroundStyle(Theme.secondaryText) }
                    HStack {
                        Button("Review plan", action: openCalendar).buttonStyle(.link)
                        Spacer()
                        Button("Dismiss update") { env.calendar.dismissRescheduleSummary() }.buttonStyle(.link)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .tint(Theme.accent)
        .sheet(item: $movingBlock) { WorkMovePicker(block: $0).environment(env) }
        .onChange(of: env.calendar.workSelection) { _, _ in movingBlock = nil }
        .onChange(of: env.calendar.overrunNudge?.needsConfirmation) { _, needsConfirmation in
            if needsConfirmation == true { env.calendar.refreshContinuation() }
        }
        .onAppear { env.calendar.refreshContinuation() }
    }

    private func close() { env.calendar.isWorkPanelPresented = false }
    private func chooseTask() { env.calendar.dismissWorkCompletion(); choosingTask = true }
    private func openCalendar() { close(); env.navigator.go(to: .calendar) }
}
