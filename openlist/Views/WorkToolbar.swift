import SwiftUI

/// A suggestion never takes space from the current document. A recording session
/// always retains a labeled Stop action, including at the compact window width.
struct WorkToolbar: View {
    @Environment(AppEnvironment.self) private var env
    @FocusState private var triggerFocused: Bool

    var body: some View {
        @Bindable var calendar = env.calendar
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(spacing: 6) {
                Button(action: toggleWork) {
                    HStack(spacing: 6) {
                        Image(systemName: calendar.activeSession == nil ? "timer" : "play.circle.fill")
                            .foregroundStyle(calendar.activeSession == nil ? Theme.secondaryText : Theme.accent)
                            .accessibilityHidden(true)
                        if let session = calendar.activeSession {
                            ViewThatFits(in: .horizontal) {
                                Text(session.title).lineLimit(1).frame(maxWidth: 130)
                                Text("Working")
                            }
                            Text("\(calendar.recordedMinutes(for: session, now: context.date).formatted(.number.precision(.fractionLength(0)))) min")
                                .monospacedDigit().fixedSize()
                        } else {
                            Text(idleTitle).fixedSize()
                        }
                    }
                }
                .focused($triggerFocused)
                .help("Show work — start, stop, or review your planned session")
                .accessibilityLabel(accessibilityTitle(now: context.date))
                .accessibilityIdentifier("work.toolbar")
                .popover(isPresented: $calendar.isWorkPanelPresented, arrowEdge: .bottom) {
                    WorkPopover().environment(env)
                }

                if calendar.activeSession != nil {
                    Button("Stop", action: stop)
                        .help("Stop recording time and keep the task open")
                        .accessibilityLabel("Stop working")
                        .accessibilityIdentifier("work.stop")
                }
            }
        }
        .onChange(of: calendar.isWorkPanelPresented) { wasOpen, isOpen in
            if wasOpen && !isOpen { triggerFocused = true }
        }
        .onChange(of: recordingAnnouncement) { _, announcement in
            guard let announcement else { return }
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                userInfo: [.announcement: announcement, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        }
    }

    private var idleTitle: String {
        if env.calendar.notice != nil { return "Work · Notice" }
        if env.calendar.overrunNudge?.needsConfirmation == true || env.calendar.resumableTask != nil { return "Work · Paused" }
        if env.calendar.workCompletion != nil { return "Work · Saved" }
        if env.calendar.startNudge != nil { return "Work · Ready" }
        return "Work"
    }

    private func accessibilityTitle(now: Date) -> String {
        guard let session = env.calendar.activeSession else { return "\(idleTitle). Show work details." }
        return "Working on \(session.title), \(env.calendar.recordedMinutes(for: session, now: now).formatted(.number.precision(.fractionLength(0)))) minutes recorded. Show work details."
    }

    /// Only meaningful transitions announce; timer ticks and suggestions do not.
    private var recordingAnnouncement: String? {
        if let notice = env.calendar.notice { return notice }
        if let session = env.calendar.activeSession { return "Recording work on \(session.title)." }
        if env.calendar.overrunNudge?.needsConfirmation == true { return "Recording paused. Review the plan before continuing." }
        if let summary = env.calendar.workCompletion { return "Completed \(summary.title). Recording stopped." }
        if let task = env.calendar.resumableTask { return "Recording stopped for \(task.displayTitle). The task is still open." }
        return nil
    }

    private func toggleWork() {
        if env.calendar.isWorkPanelPresented { env.calendar.isWorkPanelPresented = false }
        else { env.calendar.showWork() }
    }

    private func stop() { env.calendar.stopWorking(); env.calendar.showWork() }
}
