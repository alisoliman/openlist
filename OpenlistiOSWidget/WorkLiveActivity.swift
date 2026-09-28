//
//  WorkLiveActivity.swift
//  OpenlistiOSWidget
//

import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Work under way on the Lock Screen and in the Dynamic Island (mockup 05),
/// on the dark palette in either appearance: Working or Paused, the task, the
/// minutes left counting down on their own, the bar, and Pause or Resume and
/// Done, which act in the app.
struct WorkLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkActivityAttributes.self) { context in
            WorkLockScreen(context: context)
                .activityBackgroundTint(OLPalette.dark.color(OLColorPair(0x151417)))
                .activitySystemActionForegroundColor(OLPalette.dark.ink)
        } dynamicIsland: { context in
            let palette = OLPalette.dark
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    WorkTile(palette: palette).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    MinutesLeft(state: context.state, palette: palette, size: 26).padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    WorkHeadline(state: context.state, palette: palette)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 10) {
                        WorkBar(state: context.state, palette: palette)
                        WorkButtons(context: context, palette: palette)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: "stopwatch")
                    .foregroundStyle(palette.accentText)
            } compactTrailing: {
                CompactMinutes(state: context.state)
                    .foregroundStyle(context.state.isPaused ? palette.todayText : palette.accentText)
            } minimal: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "stopwatch")
                    .foregroundStyle(palette.accentText)
            }
            .widgetURL(WidgetLink.working.url)
            .keylineTint(palette.accent)
        }
    }
}

private struct WorkLockScreen: View {
    let context: ActivityViewContext<WorkActivityAttributes>

    var body: some View {
        let palette = OLPalette.dark
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                WorkTile(palette: palette)
                WorkHeadline(state: context.state, palette: palette)
                    .frame(maxWidth: .infinity, alignment: .leading)
                MinutesLeft(state: context.state, palette: palette, size: 30)
            }
            WorkBar(state: context.state, palette: palette)
            WorkButtons(context: context, palette: palette)
        }
        .padding(16)
        .widgetURL(WidgetLink.working.url)
    }
}

private struct WorkTile: View {
    let palette: OLPalette

    var body: some View {
        Image(systemName: "stopwatch")
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(palette.accentText)
            .frame(width: 40, height: 40)
            .background(palette.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityHidden(true)
    }
}

private struct WorkHeadline: View {
    let state: WorkActivityAttributes.ContentState
    let palette: OLPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Circle().fill(state.isPaused ? palette.today : palette.success).frame(width: 7, height: 7)
                Text(state.isPaused ? "Paused" : "Working")
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(state.isPaused ? palette.todayText : palette.successText)
            Text(state.title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
        }
    }
}

/// "49:58 / left", counting down on the activity's own clock while it
/// runs; "50 / min left", still, while paused.
private struct MinutesLeft: View {
    let state: WorkActivityAttributes.ContentState
    let palette: OLPalette
    let size: CGFloat

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Group {
                if let paused = state.pausedMinutesLeft {
                    Text("\(paused)")
                } else if state.endsAt > .now {
                    // Counting down on the activity's own clock.
                    Text(timerInterval: Date.now...state.endsAt, countsDown: true, showsHours: false)
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                } else {
                    Text("0")
                }
            }
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(palette.ink)
            Text(state.pausedMinutesLeft == nil && state.endsAt > .now ? "left" : "min left")
                .font(.system(size: 12))
                .foregroundStyle(palette.muted)
        }
        .frame(minWidth: 64, alignment: .trailing)
    }
}

private struct CompactMinutes: View {
    let state: WorkActivityAttributes.ContentState

    var body: some View {
        if let paused = state.pausedMinutesLeft {
            Text("\(paused)m")
        } else {
            Text(timerInterval: Date.now...max(Date.now, state.endsAt), countsDown: true, showsHours: false)
                .monospacedDigit()
                .frame(maxWidth: 44)
        }
    }
}

private struct WorkBar: View {
    let state: WorkActivityAttributes.ContentState
    let palette: OLPalette

    var body: some View {
        if state.isPaused || state.endsAt <= .now || state.startedAt >= state.endsAt {
            WidgetBar(value: state.progress(at: .now), palette: palette)
        } else {
            ProgressView(timerInterval: state.startedAt...state.endsAt, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.linear)
            .tint(palette.accent)
            .labelsHidden()
        }
    }
}

private struct WorkButtons: View {
    let context: ActivityViewContext<WorkActivityAttributes>
    let palette: OLPalette

    var body: some View {
        let taskID = UUID(uuidString: context.attributes.taskID) ?? UUID()
        let occurrenceID = UUID(uuidString: context.attributes.occurrenceID) ?? UUID()
        HStack(spacing: 8) {
            if context.state.isPaused {
                Button(intent: ResumeWorkIntent(taskID: taskID, occurrenceID: occurrenceID)) {
                    Label("Resume", systemImage: "play.fill")
                }
                .buttonStyle(WorkButtonStyle(fill: palette.sunken, ink: palette.ink))
            } else {
                Button(intent: PauseWorkIntent(taskID: taskID, occurrenceID: occurrenceID)) {
                    Label("Pause", systemImage: "pause.fill")
                }
                .buttonStyle(WorkButtonStyle(fill: palette.sunken, ink: palette.ink))
            }
            Button(intent: FinishWorkIntent(taskID: taskID, occurrenceID: occurrenceID)) {
                Label("Done", systemImage: "checkmark")
            }
            .buttonStyle(WorkButtonStyle(fill: palette.success, ink: .white))
        }
    }
}

/// The Live Activity's buttons (mockup 05): 38 pt capsules sharing the row,
/// filled with the tint, 16 pt semibold.
private struct WorkButtonStyle: ButtonStyle {
    let fill: Color
    let ink: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(fill, in: .capsule)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
