import SwiftUI

/// A stable, compact work bar: ordinary timing changes update its caption,
/// rather than presenting a modal or repeatedly shifting the calendar.
struct CalendarWorkBanner: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsRescheduleDetails = false

    var body: some View {
        VStack(spacing: 0) {
            if let nudge = env.calendar.overrunNudge, nudge.needsConfirmation,
               let task = env.store.block(id: nudge.taskID) {
                HStack(spacing: 10) {
                    Image(systemName: "pause.circle.fill").foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.displayTitle).font(.callout.weight(.semibold)).lineLimit(1)
                        Text("More time would move other tasks.")
                            .font(.caption).foregroundStyle(Theme.secondaryText)
                    }
                    Spacer(minLength: 4)
                    Button("Done") { env.calendar.complete(task: task) }
                    Button("Keep going · \(extensionMinutes(nudge)) min") { env.calendar.acceptMoreTime() }
                        .buttonStyle(.borderedProminent).tint(Theme.accent)
                }
                .padding(.horizontal, 12).frame(minHeight: 54)
                .background(Theme.rowSelected)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Confirm more work time")
            } else if let session = env.calendar.activeSession {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    HStack(spacing: 10) {
                        Image(systemName: "play.circle.fill").foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.title).font(.callout.weight(.semibold)).lineLimit(1)
                            if let nudge = env.calendar.overrunNudge, nudge.taskID == session.taskID {
                                Text("Still working? I’ll allow \(extensionMinutes(nudge)) more minutes.")
                                    .font(.caption).foregroundStyle(Theme.secondaryText)
                            } else {
                                Text("Working · \(env.calendar.recordedMinutes(for: session, now: context.date).formatted(.number.precision(.fractionLength(0)))) min this session")
                                    .font(.caption).foregroundStyle(Theme.secondaryText)
                            }
                        }
                        Spacer(minLength: 4)
                        Button("Pause") { env.calendar.pause(reason: "Paused") }
                        if let task = env.store.block(id: session.taskID) {
                            Button("Done") { env.calendar.complete(task: task) }
                                .buttonStyle(.borderedProminent).tint(Theme.accent)
                        }
                    }
                }
                .padding(.horizontal, 12).frame(minHeight: 54)
                .background(Theme.rowSelected)
            } else if let id = env.calendar.resumeTaskID {
                HStack(spacing: 10) {
                    Label("Resume \(env.store.block(id: id)?.displayTitle ?? "your task")?", systemImage: "pause.circle")
                        .font(.callout).lineLimit(2)
                    Spacer(minLength: 4)
                    Button("Later") { env.calendar.dismissResume() }
                    Button("Resume") { env.calendar.resume() }
                        .buttonStyle(.borderedProminent).tint(Theme.accent)
                }
                .padding(.horizontal, 12).frame(minHeight: 54)
                .background(Theme.rowSelected)
            } else if let nudge = env.calendar.startNudge,
                      let task = env.store.block(id: nudge.taskID) {
                HStack(spacing: 10) {
                    Image(systemName: "clock").foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Up next: \(task.displayTitle)").font(.callout.weight(.medium)).lineLimit(1)
                        Text("Your time starts when you do.")
                            .font(.caption).foregroundStyle(Theme.secondaryText)
                    }
                    Spacer(minLength: 4)
                    Button("Start") { _ = env.calendar.start(task: task) }
                        .buttonStyle(.borderedProminent).tint(Theme.accent)
                }
                .padding(.horizontal, 12).frame(minHeight: 54)
                .background(Theme.rowSelected)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Ready to start")
            }

            if let summary = env.calendar.rescheduleSummary, env.navigator.route == .calendar {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath").accessibilityHidden(true)
                    Text(summary.message).lineLimit(1)
                    Spacer(minLength: 4)
                    Button("Review") { showsRescheduleDetails = true }
                        .buttonStyle(.link)
                    Button("Dismiss rescheduling notice", systemImage: "xmark") {
                        env.calendar.dismissRescheduleSummary()
                    }.labelStyle(.iconOnly).buttonStyle(.plain)
                }
                .font(.caption).foregroundStyle(Theme.secondaryText)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Theme.chrome.opacity(0.5))
                .popover(isPresented: $showsRescheduleDetails) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(summary.message).font(.headline)
                        ForEach(summary.taskIDs, id: \.self) { id in
                            if let task = env.store.block(id: id) {
                                Button(task.displayTitle) {
                                    showsRescheduleDetails = false
                                    env.navigator.openTask(id)
                                }.buttonStyle(.link)
                            }
                        }
                        Button("Done") {
                            showsRescheduleDetails = false
                            env.calendar.dismissRescheduleSummary()
                        }
                    }.padding(16).frame(width: 300, alignment: .leading)
                }
            }

            if let notice = env.calendar.notice {
                HStack(alignment: .top, spacing: 12) {
                    Label(notice, systemImage: "info.circle").font(.callout)
                    Spacer(minLength: 4)
                    Button("Dismiss") { env.calendar.notice = nil }
                }.padding(12).background(ListAccent.blue.softBackground)
            }
        }
        .animation(Theme.Motion.feedback(reduceMotion: reduceMotion), value: env.calendar.startNudge?.taskID)
    }

    private func extensionMinutes(_ nudge: CalendarOverrunNudge) -> Int {
        max(1, Int(ceil(nudge.proposedEnd.timeIntervalSince(nudge.estimatedEnd) / 60)))
    }
}
