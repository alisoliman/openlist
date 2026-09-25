//
//  ActivityWidget.swift
//  OpenlistWidget
//

import SwiftUI
import WidgetKit

/// The completion heatmap from the Activity screen.
struct ActivityWidget: Widget {
    static let kind = WidgetKind.activity

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            WidgetEntryView(entry: entry) { family, style in
                ActivityWidgetView(entry: entry, family: family, style: style)
            }
            .widgetURL(WidgetLink.activity.url)
        }
        .configurationDisplayName("Activity")
        .description("Your completion streak as a heatmap.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

/// The streak, the last 10 (small) or 21 (medium) weeks of completions, and
/// the running totals underneath.
struct ActivityWidgetView: View {
    let entry: SnapshotEntry
    let family: WidgetFamily
    let style: WidgetStyle

    var body: some View {
        if entry.isPlaceholder {
            OpenAppPrompt()
        } else {
            let state = entry.state
            let activity = state.snapshot.activity
            let stats = ActivityStats(activity: activity, now: state.now, calendar: state.calendar)
            let weeks = ActivityGrid.weeks(family == .systemSmall ? 10 : 21, activity: activity, now: state.now, calendar: state.calendar)
            VStack(alignment: .leading, spacing: 0) {
                ActivityHeader(streak: stats.streak)
                ActivityHeatmap(weeks: weeks)
                ActivityTotals(stats: stats, showsWeek: family != .systemSmall)
            }
        }
    }
}

/// The grid icon, "Activity" and the streak.
private struct ActivityHeader: View {
    let streak: Int
    @Environment(\.widgetStyle) private var style

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 10))
                .foregroundStyle(style.acc)
                .widgetAccentable()
                .frame(width: 13, height: 13)
                .padding(.trailing, 6)
                .accessibilityHidden(true)
            Text("Activity")
                .foregroundStyle(style.ink)
                .lineLimit(1)
                .textStyle(12, .bold, lineHeight: 1)
                .layoutPriority(1)
            // The design keeps 12 points between title and streak; the small
            // widget only fits "1-day streak" beside the title with a little
            // less.
            Spacer(minLength: 8)
            streakLabel
        }
        .accessibilityElement(children: .combine)
    }

    /// The smallest the design's label shrinks to before it gives way.
    private static let minimumScale: CGFloat = 0.75

    /// "143-day streak", down to three quarters of its size where room is
    /// short, then "143 days": three-digit streaks on a 164-point small
    /// widget. `ViewThatFits` compares ideal widths, which ignore
    /// `minimumScaleFactor`, so the long label is measured at its smallest
    /// size and drawn over that as large as the room allows.
    private var streakLabel: some View {
        let long: LocalizedStringKey = "\(streak)-day streak"
        return ViewThatFits(in: .horizontal) {
            Text(long)
                .textStyle(11 * Self.minimumScale, .semibold, lineHeight: 1 / Self.minimumScale)
                .hidden()
                .frame(maxWidth: .infinity, alignment: .trailing)
                .overlay(alignment: .trailing) { streakText(long) }
            streakText(streak == 1 ? "1 day" : "\(streak) days")
        }
        .accessibilityLabel(Text(long))
    }

    private func streakText(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .foregroundStyle(streak > 0 ? style.ink : style.sub)
            .lineLimit(1)
            .minimumScaleFactor(Self.minimumScale)
            .textStyle(11, .semibold, lineHeight: 1)
            .contentTransition(.numericText(value: Double(streak)))
    }
}

/// Seven rows from the app's first weekday, one column per week, oldest on
/// the left and this week on the right.
private struct ActivityHeatmap: View {
    let weeks: [[ActivityCell]]

    /// The design's cell and gap.
    private static let side: CGFloat = 10.5
    private static let gap: CGFloat = 3

    var body: some View {
        GeometryReader { proxy in
            let side = Self.side(fitting: proxy.size, columns: weeks.count)
            HStack(spacing: Self.gap) {
                ForEach(weeks, id: \.first?.id) { week in
                    VStack(spacing: Self.gap) {
                        ForEach(week) { cell in
                            HeatCell(cell: cell, side: side)
                        }
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityElement()
        .accessibilityLabel("Completions over the last \(weeks.count) weeks")
    }

    /// The design's cell size, shrunk only when a widget comes out smaller
    /// than the design's (sizes vary with the display), so every week fits.
    private static func side(fitting size: CGSize, columns: Int) -> CGFloat {
        guard columns > 0 else { return side }
        let across = (size.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let down = (size.height - gap * 6) / 7
        return max(0, min(side, across, down))
    }
}

/// One day: an empty outline for days still to come, `track` for none, then
/// the accent at the band's strength, with a ring around today.
private struct HeatCell: View {
    let cell: ActivityCell
    let side: CGFloat
    @Environment(\.widgetStyle) private var style

    var body: some View {
        let radius = side * 3 / 10.5
        let shape = RoundedRectangle(cornerRadius: radius)
        Group {
            if cell.isFuture {
                shape.strokeBorder(style.line, lineWidth: 0.5)
            } else if cell.band == 0 {
                shape.fill(style.track)
            } else {
                shape.fill(style.acc).widgetAccentable()
            }
        }
        .frame(width: side, height: side)
        .overlay {
            if cell.isToday {
                RoundedRectangle(cornerRadius: radius + 1.5)
                    .strokeBorder(style.ink, lineWidth: 1.5)
                    .padding(-1.5)
            }
        }
        // The band's strength fades today's ring along with the fill, as the
        // design does, so a quiet day doesn't get a heavy outline.
        .opacity(cell.band == 0 ? 1 : WidgetStyle.heatOpacities[cell.band])
    }
}

/// "2 today  2 this week  49 in September"; the small widget has room for
/// the month only.
private struct ActivityTotals: View {
    let stats: ActivityStats
    let showsWeek: Bool

    var body: some View {
        HStack(spacing: 12) {
            if showsWeek {
                ActivityFigure(value: stats.today, label: "today")
                ActivityFigure(value: stats.week, label: "this week")
            }
            ActivityFigure(value: stats.month, label: "in \(stats.monthName)")
        }
        .accessibilityElement(children: .combine)
    }
}

/// A bold count and its quieter label, sharing a baseline.
private struct ActivityFigure: View {
    let value: Int
    let label: LocalizedStringKey
    @Environment(\.widgetStyle) private var style

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value, format: .number)
                .foregroundStyle(style.ink)
                .textStyle(11, .bold, lineHeight: 1)
                .contentTransition(.numericText(value: Double(value)))
            Text(label)
                .foregroundStyle(style.sub)
                .textStyle(10.5, .medium, lineHeight: 1)
        }
        .lineLimit(1)
        .fixedSize()
    }
}

#if RENDER_ACTIVITY
extension ActivityWidget {
    static var renderCases: [RenderCase] {
        let families: [WidgetFamily] = [.systemSmall, .systemMedium]
        let base = SnapshotEntry.mockup()
        func entry(_ edit: (inout WidgetSnapshot) -> Void) -> SnapshotEntry {
            var snapshot = base.snapshot
            edit(&snapshot)
            return SnapshotEntry(date: base.date, snapshot: snapshot, calendar: RenderCalendar.current)
        }
        let states: [(String?, SnapshotEntry)] = [
            (nil, base),
            // A tick in another widget, still waiting for the app: the design's crops.
            ("ticked", .mockup(pending: [.completing("q4")])),
            // A new library: every past day empty, no streak.
            ("empty", entry { $0.activity = WidgetSnapshot.Activity(days: $0.activity.days.map { .init(date: $0.date, count: 0) }) }),
            // Something done every day of the history: a three-digit streak.
            ("streak", entry { $0.activity.days = $0.activity.days.map { .init(date: $0.date, count: max(1, $0.count)) } }),
            // Two digits: the full label, a little smaller on a 164-point widget.
            ("streak45", entry { snapshot in
                let days = snapshot.activity.days
                snapshot.activity.days = days.enumerated().map { index, day in
                    .init(date: day.date, count: index >= days.count - 45 ? max(1, day.count) : 0)
                }
            }),
            // Weeks starting on Sunday move today down a row.
            ("sunday", entry { $0.firstWeekday = 1 }),
            ("placeholder", SnapshotEntry(date: base.date, snapshot: WidgetSnapshot(), isPlaceholder: true, calendar: RenderCalendar.current)),
        ]
        return states.flatMap { state, entry in
            RenderCase.families("activity", families, state: state, entry: entry) { entry, family, style in
                ActivityWidgetView(entry: entry, family: family, style: style)
            }
        }
    }
}
#endif
