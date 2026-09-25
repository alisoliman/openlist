//
//  UpNextWidget.swift
//  OpenlistWidget
//

import AppIntents
import SwiftUI
import WidgetKit

/// The block to be on now, with Start, Pause and Done sharing the app's
/// toolbar timer.
struct UpNextWidget: Widget {
    static let kind = WidgetKind.upNext

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: UpNextProvider()) { entry in
            WidgetEntryView(entry: entry) { family, style in
                UpNextWidgetView(entry: entry, family: family, style: style)
            }
            .widgetURL(WidgetLink.calendar.url)
        }
        .configurationDisplayName("Up Next")
        .description("The block you should be on now, with Start, Pause and Done.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

/// The current session on the left; medium adds the rest of today's calendar
/// beside it.
struct UpNextWidgetView: View {
    let entry: SnapshotEntry
    let family: WidgetFamily
    let style: WidgetStyle

    var body: some View {
        if entry.isPlaceholder {
            OpenAppPrompt()
        } else {
            let upNext = entry.state.upNext
            GeometryReader { proxy in
                HStack(alignment: .top, spacing: 14) {
                    SessionColumn(upNext: upNext, now: entry.date, doneToday: entry.state.snapshot.completedTodayCount)
                        // Sized from the widget, not from what "Later today"
                        // holds, so the session always sits in the same place.
                        .frame(width: family == .systemSmall ? nil : Self.sessionWidth(in: proxy.size.width))
                        .frame(maxHeight: .infinity, alignment: .top)
                    if family != .systemSmall {
                        LaterColumn(rows: Array(upNext.later.prefix(4)))
                    }
                }
            }
        }
    }

    /// The design gives the session 168 of a 358-point widget's 326 points
    /// of content. Current Macs draw medium widgets 344 points wide, and the
    /// session has room to spare where "Later today" has none, so it gives
    /// up the first 14 points: down to 154, which still fits "WORKING" with
    /// its range and an hours clock beside both buttons. Any narrower, the
    /// two columns share the rest in the design's proportion.
    private static func sessionWidth(in width: CGFloat) -> CGFloat {
        let shortfall = max(0, 326 - width)
        let fromSession = min(14, shortfall)
        return (168 - fromSession - (shortfall - fromSession) * 168 / 326).rounded()
    }
}

// MARK: - Session

/// Phase and time, the block's title and list, then the clock (or what is
/// left of the block) above its progress, beside the work controls.
private struct SessionColumn: View {
    let upNext: UpNext
    let now: Date
    /// Closes an empty day in place of the session controls.
    let doneToday: Int
    @Environment(\.widgetStyle) private var style

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                header
                Text(upNext.title)
                    .foregroundStyle(style.ink)
                    .lineLimit(3)
                    .textStyle(15, .semibold, lineHeight: 1.25)
                    .padding(.top, 10)
                if !listLine.isEmpty {
                    Text(listLine)
                        .foregroundStyle(style.sub)
                        // "Next: Board prep at 14:00" keeps its time on a
                        // second line rather than truncating it away.
                        .lineLimit(upNext.phase == .none ? 2 : 1)
                        .textStyle(10.5, .medium, lineHeight: 1.2)
                        .padding(.top, 4)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            if upNext.phase != .none {
                footer
            } else if doneToday > 0 {
                doneLine
            }
        }
    }

    private var listLine: String { upNext.listLine(includesIcon: !style.isVibrant) }

    /// Drops the time range rather than cut the phase short when both do
    /// not fit, as in a narrow small widget.
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            headerRow(showsRange: !upNext.rangeText.isEmpty)
            headerRow(showsRange: false)
        }
    }

    private func headerRow(showsRange: Bool) -> some View {
        HStack(spacing: 0) {
            Circle()
                .fill(dotColor)
                .widgetAccentable(upNext.phase != .none)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            CapsLabel(upNext.phaseLabel, color: upNext.phase == .none ? style.faint : style.acc)
                .invalidatableContent()
                .padding(.leading, 6)
            // The design keeps 12 points here, which "WORKING" and a range
            // overrun in the small family, so the gap gives way first.
            Spacer(minLength: 4)
            if showsRange {
                Text(upNext.rangeText)
                    .foregroundStyle(style.sub)
                    .lineLimit(1)
                    .fixedSize()
                    .textStyle(10, .medium, lineHeight: 1, monospaced: true)
            }
        }
    }

    /// Paused work is amber, so it reads as waiting at a glance; an empty
    /// day has nothing live to mark.
    private var dotColor: Color {
        switch upNext.phase {
        case .paused: style.amber
        case .none: style.faint
        case .working, .now, .next: style.acc
        }
    }

    /// The row's parts are bottom-aligned, so the progress bar sits level
    /// with the foot of the buttons.
    private var footer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                if upNext.isRecording {
                    WorkClock(upNext: upNext, now: now)
                        .foregroundStyle(style.acc)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .textStyle(19, .semibold, lineHeight: 1, monospaced: true)
                        .invalidatableContent()
                } else if !upNext.note.isEmpty {
                    Text(upNext.note)
                        .foregroundStyle(style.sub)
                        .lineLimit(1)
                        .textStyle(11, .medium, lineHeight: 1)
                        .contentTransition(.numericText())
                        .invalidatableContent()
                }
                // The timeline steps every minute through a session, which
                // is as often as this bar visibly moves.
                ProgressLine(fraction: upNext.progress)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            controls
        }
    }

    private var doneLine: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(style.green)
                .widgetAccentable()
            Text("\(doneToday) done today")
                .foregroundStyle(style.sub)
                .lineLimit(1)
                .textStyle(11, .medium, lineHeight: 1)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var controls: some View {
        if let taskID = upNext.taskID, let occurrenceID = upNext.occurrenceID {
            switch upNext.phase {
            case .working, .paused:
                HStack(spacing: 5) {
                    // Every button names the session it was drawn for, so a
                    // tap on a widget that has not caught up with the app
                    // changes nothing rather than pausing or resuming other work.
                    if upNext.phase == .working {
                        RoundIconButton("Pause", systemImage: "pause.fill", role: .secondary,
                                        intent: PauseWorkIntent(taskID: taskID, occurrenceID: occurrenceID))
                    } else {
                        RoundIconButton("Resume", systemImage: "play.fill", role: .secondary,
                                        intent: ResumeWorkIntent(taskID: taskID, occurrenceID: occurrenceID))
                    }
                    RoundIconButton("Done", systemImage: "checkmark", role: .confirm,
                                    intent: FinishWorkIntent(taskID: taskID, occurrenceID: occurrenceID))
                }
            case .now, .next:
                RoundIconButton("Start", systemImage: "play.fill",
                                intent: StartWorkIntent(taskID: taskID, occurrenceID: occurrenceID))
            case .none:
                EmptyView()
            }
        }
    }
}

// MARK: - Later today

/// The rest of today's calendar after the current block: planned work in
/// its list's colour, meetings quieter.
private struct LaterColumn: View {
    let rows: [UpNext.Later]
    @Environment(\.widgetStyle) private var style

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            CapsLabel("Later today")
            if rows.isEmpty {
                Text("Nothing more today")
                    .foregroundStyle(style.faint)
                    .lineLimit(2)
                    .textStyle(11.5, .medium, lineHeight: 1.2)
            }
            ForEach(rows) { row in
                LaterRow(row: row)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.leading, 14)
        .overlay(alignment: .leading) {
            Hairline(.vertical)
        }
    }
}

private struct LaterRow: View {
    let row: UpNext.Later
    @Environment(\.widgetStyle) private var style

    var body: some View {
        HStack(spacing: 8) {
            Text(row.time)
                .foregroundStyle(style.sub)
                .lineLimit(1)
                .fixedSize()
                .textStyle(10, .medium, lineHeight: 1, monospaced: true)
                .frame(width: 32, alignment: .leading)
            bar
            Text(row.title)
                .foregroundStyle(row.isMeeting ? style.sub : style.ink)
                .lineLimit(1)
                .textStyle(11.5, .medium, lineHeight: 1.2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.isMeeting ? "\(row.time), \(row.title), meeting" : "\(row.time), \(row.title)")
    }

    @ViewBuilder
    private var bar: some View {
        let shape = RoundedRectangle(cornerRadius: 1.5, style: .continuous)
        if let hex = row.accentHex {
            shape.fill(style.listColor(hex))
                .widgetAccentable()
                .frame(width: 3, height: 15)
        } else {
            shape.fill(style.track)
                .frame(width: 3, height: 15)
        }
    }
}

#if RENDER_UPNEXT
extension UpNextWidget {
    static var renderCases: [RenderCase] {
        let families: [WidgetFamily] = [.systemSmall, .systemMedium]
        let view = { (entry: SnapshotEntry, family: WidgetFamily, style: WidgetStyle) in
            UpNextWidgetView(entry: entry, family: family, style: style)
        }
        let mockupNow = WidgetSnapshot.mockupNow(calendar: RenderCalendar.current)
        func later(_ minutes: Double) -> SnapshotEntry {
            SnapshotEntry.mockup().at(mockupNow.addingTimeInterval(minutes * 60))
        }
        return RenderCase.families("upnext", families, view: view)
            + RenderCase.families("upnext", families, state: "working", entry: .mockup(work: .working), view: view)
            + RenderCase.families("upnext", families, state: "paused", entry: .mockup(work: .paused), view: view)
            // 11:35: a longer title, with the interview feedback under way.
            + RenderCase.families("upnext", families, state: "long", entry: later(55), view: view)
            // 11:55: nothing under way, the scorecard at 13:00 is next.
            + RenderCase.families("upnext", families, state: "next", entry: later(75), view: view)
            // 18:30: the day's plan is done.
            + RenderCase.families("upnext", families, state: "none", entry: later(470), view: view)
            // An hour and a quarter into a session, so the clock shows hours.
            + RenderCase.families("upnext", families, state: "hours", entry: SnapshotEntry.mockup(work: .working).at(mockupNow.addingTimeInterval(75 * 60)), view: view)
            + RenderCase.families("upnext", families, state: "wordy", entry: wordy(at: mockupNow), view: view)
            + RenderCase.families("upnext", families, state: "placeholder",
                                  entry: SnapshotEntry(date: mockupNow, snapshot: WidgetSnapshot(), isPlaceholder: true), view: view)
    }

    /// The current block with a title and list long enough to be clamped.
    private static func wordy(at now: Date) -> SnapshotEntry {
        let calendar = RenderCalendar.current
        var snapshot = WidgetSnapshot.sample(now: now, calendar: calendar)
        if let index = snapshot.agenda.firstIndex(where: { $0.id == "block-q1" }) {
            snapshot.agenda[index].title = "Draft the Q3 objectives and key results for the platform and growth teams"
            snapshot.agenda[index].listName = "Quarterly planning and company objectives"
        }
        return SnapshotEntry(date: now, snapshot: snapshot, calendar: calendar)
    }
}
#endif
