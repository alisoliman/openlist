import SwiftUI

/// The Work panel the notch, the Work menu and notifications open: the task in
/// hand or up next, and what the plan did around it, drawn like the rest of Next.
struct WorkPopover: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    @State private var choosingTask = false
    @State private var movingBlock: PlannedBlock?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text(choosingTask ? "Choose a task" : "Work")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NX.ink)
                Spacer(minLength: 8)
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 10.5, weight: .semibold)).frame(width: 14, height: 14)
                }
                .buttonStyle(NXHoverButtonStyle(radius: 6, padding: EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4),
                                                foreground: NX.ink(0.45), hoverForeground: NX.ink))
                .keyboardShortcut(.cancelAction)
                .help("Close")
                .accessibilityLabel("Close work details")
            }
            if let notice = env.calendar.notice {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "info.circle").font(.system(size: 11.5)).foregroundStyle(NX.ink(0.45))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(notice)
                            .font(.system(size: 12))
                            .foregroundStyle(NX.ink(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                        NXWorkLink("Dismiss notice") { env.calendar.notice = nil }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NX.ink(0.04), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityElement(children: .contain)
            }
            if choosingTask {
                WorkTaskChooser { reference in
                    env.calendar.selectWork(reference)
                    choosingTask = false
                }
            } else if let summary = env.calendar.workCompletion {
                WorkCompletionView(summary: summary, chooseNext: chooseTask)
            } else if let task = env.calendar.selectedWorkTask {
                WorkSessionCard(task: task, chooseTask: chooseTask, move: { movingBlock = $0 })
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Image(systemName: "timer")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(style.accent)
                        .frame(width: 36, height: 36)
                        .background(style.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Text("What would you like to work on?")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(NX.ink)
                        .padding(.top, 12)
                    Text("No task is planned for now. Start a session whenever it helps.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(NX.ink(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                    HStack(spacing: 8) {
                        NXWorkButton("Choose a task", prominent: true, action: chooseTask)
                        NXWorkButton("Open calendar", action: openCalendar)
                    }
                    .padding(.top, 14)
                }
            }

            if let summary = env.calendar.rescheduleSummary {
                Rectangle().fill(NX.ink(0.08)).frame(height: 0.5)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "calendar.badge.clock").font(.system(size: 11.5)).foregroundStyle(NX.ink(0.45))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(summary.message).font(.system(size: 12, weight: .medium)).foregroundStyle(NX.ink(0.72))
                        if let reason = summary.reason {
                            Text(reason).font(.system(size: 11.5)).foregroundStyle(NX.ink(0.45))
                        }
                        HStack(spacing: 14) {
                            NXWorkLink("Review plan", action: openCalendar)
                            NXWorkLink("Dismiss update") { env.calendar.dismissRescheduleSummary() }
                        }
                        .padding(.top, 2)
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
        .presentationBackground(NX.card)
        .tint(style.accent)
        .sheet(item: $movingBlock) { WorkMovePicker(block: $0).environment(env).environment(\.nextStyle, style) }
        .onChange(of: env.calendar.workSelection) { _, _ in movingBlock = nil }
    }

    private func close() { env.calendar.isWorkPanelPresented = false }
    private func chooseTask() { env.calendar.dismissWorkCompletion(); choosingTask = true }
    private func openCalendar() { close(); env.navigator.go(to: .calendar) }
}

/// A Work panel button: filled with the accent for the main action, grey otherwise.
struct NXWorkButton: View {
    @Environment(\.nextStyle) private var style
    let title: String
    var prominent = false
    let action: () -> Void

    init(_ title: String, prominent: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.prominent = prominent
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
        }
        .buttonStyle(NXHoverButtonStyle(hover: prominent ? style.accent.opacity(0.86) : NX.ink(0.1),
                                        rest: prominent ? style.accent : NX.ink(0.05), radius: 8,
                                        padding: EdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 12),
                                        foreground: prominent ? .white : NX.ink(0.72),
                                        hoverForeground: prominent ? .white : NX.ink))
        .fixedSize()
    }
}

/// A quiet text action in the accent, for the Work panel's secondary choices.
struct NXWorkLink: View {
    @Environment(\.nextStyle) private var style
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
        }
        .buttonStyle(NXHoverButtonStyle(hover: style.accent.opacity(0.1), radius: 6,
                                        padding: EdgeInsets(top: 3, leading: 5, bottom: 3, trailing: 5),
                                        foreground: style.accent))
        // The text lines up with the copy above; the hover fill reaches past it.
        .padding(.horizontal, -5)
        .fixedSize()
    }
}
