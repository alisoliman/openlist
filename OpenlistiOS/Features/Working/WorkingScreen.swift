//
//  WorkingScreen.swift
//  OpenlistiOS
//

import SwiftUI

/// Working (mockup 04), a full-screen cover: the task under way, minutes
/// left in its block, how far through it is, and Stop, Pause or Resume, and
/// Done. The Next card names what the day holds after it. The pause button
/// is its glyph alone; VoiceOver reads Pause or Resume.
struct WorkingScreen: View {
    @Environment(PhoneEnvironment.self) private var env

    var body: some View {
        TimelineView(.periodic(from: .now, by: 10)) { _ in
            WorkingPage(now: env.now)
        }
    }
}

private struct WorkingPage: View {
    let now: Date
    @Environment(PhoneEnvironment.self) private var env
    @Environment(\.phoneLibrary) private var library
    @Environment(\.olStyle) private var style
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var timerSize: CGFloat = 52

    var body: some View {
        let navigator = env.navigator
        let work = PhoneWork(env: env, now: now)
        OLScreen(identifier: PhoneRoute.working.screenIdentifier, scrolls: dynamicTypeSize.isAccessibilitySize) {
            OLTopBar {
                OLIconButton("chevron.down", label: "Close", kind: .bare, iconSize: 22) { navigator.dismissCover() }
                    .accessibilityIdentifier("working.close")
            } trailing: {
                if let task = work.task {
                    // Over the tab Working came from, as the Next card opens it.
                    OLIconButton("doc.text", label: "Task details", kind: .bare, iconSize: 22) {
                        navigator.open(.taskDetail(task.id))
                    }
                }
            }
        } content: {
            if let task = work.task {
                session(task, work: work)
                    .frame(maxHeight: dynamicTypeSize.isAccessibilitySize ? nil : .infinity)
                if let next = next(after: work) { nextCard(next) }
            } else {
                OLEmptyState(symbol: "timer", tint: OL.accentText, title: "Nothing on now",
                             message: "Start a task from Today or its page, and it runs here.",
                             actionTitle: "Back to Today") { navigator.dismissCover() }
                    .frame(maxHeight: .infinity)
            }
        }
    }

    private func session(_ task: Block, work: PhoneWork) -> some View {
        let list = env.store.list(id: task.listID)
        let paused = work.state != .working
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(paused ? OL.today : OL.success).frame(width: 8, height: 8)
                Text(work.state == .working ? "Working" : work.state == .paused ? "Paused" : "Up now")
            }
            .font(OLFont.eyebrow)
            .foregroundStyle(OL.accentText)
            .accessibilityElement(children: .combine)
            OLTitle(task.displayTitle)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
            if let list {
                HStack(spacing: 4) {
                    OLListGlyph(icon: list.icon, accent: list.accent.color, size: 13)
                    Text(list.displayTitle)
                }
                .font(OLFont.meta)
                .foregroundStyle(OL.muted)
                .padding(.top, 4)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(work.minutesLeft)")
                    .font(OLFont.timer(size: min(timerSize, 72)))
                    .tracking(OLFont.timerTracking)
                    .contentTransition(.numericText(countsDown: true))
                Text("min left")
                    .font(OLFont.eyebrow)
                    .foregroundStyle(OL.muted)
            }
            .padding(.top, 48)
            .accessibilityElement(children: .combine)
            OLProgressBar(value: work.progress(now: now))
                .frame(width: 220)
                .padding(.top, 14)
            if let start = work.start, let end = work.end {
                Text(OLFormat.range(start, end, calendar: env.settings.calendar))
                    .font(OLFont.mono)
                    .foregroundStyle(OL.muted)
                    .padding(.top, 10)
            }
            HStack(spacing: 24) {
                // Before it starts there's nothing to stop: ✕ closes.
                OLIconButton("xmark", label: work.state == .planned ? "Close" : "Stop", size: .large) {
                    if work.state == .planned { env.navigator.dismissCover() } else { stop(task) }
                }
                .accessibilityIdentifier("working.stop")
                OLIconButton(paused ? "play.fill" : "pause.fill",
                             label: work.state == .planned ? "Start working" : paused ? "Resume" : "Pause", kind: .accent,
                             size: .extraLarge) { togglePause(task, work: work) }
                    .accessibilityIdentifier("working.pause")
                OLIconButton("checkmark", label: "Mark done", kind: .success, size: .large) { finish(task) }
                    .accessibilityIdentifier("working.done")
            }
            .padding(.top, 48)
            .olFeedback(.impact, trigger: paused)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 24)
        .animation(style.animation(.snappy(duration: 0.25)), value: paused)
    }

    private func nextCard(_ next: OLTimelineItem) -> some View {
        Button {
            if let id = next.taskID { env.navigator.open(.taskDetail(id)) }
        } label: {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("Next").font(OLFont.meta.weight(.semibold)).foregroundStyle(OL.muted)
                            Spacer(minLength: 0)
                            Text(CompactText.clock(next.start, calendar: env.settings.calendar))
                                .font(OLFont.trailing)
                                .foregroundStyle(OL.accentText)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        Text(next.title)
                            .font(OLFont.note)
                            .foregroundStyle(OL.ink)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    HStack(spacing: 12) {
                        Text("Next").font(OLFont.meta.weight(.semibold)).foregroundStyle(OL.muted)
                        Text(next.title)
                            .font(OLFont.note)
                            .foregroundStyle(OL.ink)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(CompactText.clock(next.start, calendar: env.settings.calendar))
                            .font(OLFont.trailing)
                            .foregroundStyle(OL.accentText)
                    }
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .olCard()
            .contentShape(.rect)
        }
        .buttonStyle(OLRowPressStyle())
        .disabled(next.taskID == nil)
        .accessibilityLabel("Next, \(next.title), \(CompactText.clock(next.start, calendar: env.settings.calendar))")
        .accessibilityIdentifier("working.next")
    }

    /// What today holds after this work: the first slot, meeting or timed due
    /// task from the end of its block, or from now.
    private func next(after work: PhoneWork) -> OLTimelineItem? {
        let calendar = env.settings.calendar
        let schedule = TimelineSchedule(env: env, library: library, day: calendar.startOfDay(for: now), now: now)
        let from = max(work.end ?? now, now)
        return schedule.items
            .first { $0.kind != .done && $0.kind != .working && $0.start >= from.addingTimeInterval(-60)
                && ($0.taskID == nil || $0.taskID != work.task?.id) }
    }

    // MARK: Controls

    private func togglePause(_ task: Block, work: PhoneWork) {
        if work.state == .working {
            env.calendar.pause(now: env.now)
        } else {
            env.actions.startWork(task)
        }
    }

    /// Stops recording and lets the work go, as the Mac's ✕: what ran is kept.
    private func stop(_ task: Block) {
        let minutes = Int(env.calendar.trackedMinutes(for: task, now: env.now).rounded())
        env.calendar.stopWorking(now: env.now)
        env.calendar.dismissResume()
        env.tray.show("Stopped · \(minutes) min recorded", icon: "stop.circle", tone: .neutral, seconds: 4)
        env.haptics.play(.soft)
        env.navigator.dismissCover()
    }

    private func finish(_ task: Block) {
        env.actions.complete([task])
        env.navigator.dismissCover()
    }
}
