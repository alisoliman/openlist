//
//  SummaryWidget.swift
//  OpenlistWidget
//

import AppKit
import SwiftUI
import WidgetKit

/// Due, overdue, Inbox and done, plus this week's completions.
struct SummaryWidget: Widget {
    static let kind = WidgetKind.summary

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            WidgetEntryView(entry: entry) { family, style in
                SummaryWidgetView(entry: entry, family: family, style: style)
            }
            .widgetURL(WidgetLink.today.url)
        }
        .configurationDisplayName("Summary")
        .description("Due, overdue, Inbox and done, plus this week.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

/// The four counts in the display serif; medium adds this week's completions
/// as a bar per day.
struct SummaryWidgetView: View {
    let entry: SnapshotEntry
    let family: WidgetFamily
    let style: WidgetStyle

    var body: some View {
        if entry.isPlaceholder {
            OpenAppPrompt()
        } else if entry.state.isOutdated {
            // Counts days old would read as today's.
            OpenAppPrompt(isOutdated: true)
        } else if family == .systemSmall {
            // Small widgets are a single tap target, so the counts don't link
            // anywhere of their own; the widget opens Today.
            SummaryCounts(snapshot: entry.state.snapshot, numberSize: 30, linksCounts: false)
        } else {
            HStack(spacing: 16) {
                SummaryCounts(snapshot: entry.state.snapshot, numberSize: 32, linksCounts: true)
                    .frame(width: 140)
                SummaryWeekChart(state: entry.state)
            }
        }
    }
}

/// The app mark and the 2×2 grid of counts, settled at the bottom.
private struct SummaryCounts: View {
    let snapshot: WidgetSnapshot
    let numberSize: CGFloat
    let linksCounts: Bool
    @Environment(\.widgetStyle) private var style

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: 10)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    count(snapshot.dueTodayCount, "Due today", style.acc, link: .today)
                    count(snapshot.overdueCount, "Overdue", style.red, link: .today)
                }
                HStack(alignment: .top, spacing: 10) {
                    count(snapshot.inboxCount, "In Inbox", style.blue, link: .inbox)
                    count(snapshot.completedTodayCount, "Done", style.green, link: .today)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(style.acc)
                .widgetAccentable()
                .frame(width: 13, height: 13)
                .accessibilityHidden(true)
            Text("Openlist")
                .foregroundStyle(style.ink)
                .lineLimit(1)
                .textStyle(12, .bold, lineHeight: 1)
                .accessibilityAddTraits(.isHeader)
        }
    }

    @ViewBuilder
    private func count(_ value: Int, _ label: String, _ color: Color, link: WidgetLink) -> some View {
        let cell = SummaryCount(value: value, label: label, color: color, numberSize: numberSize)
        if linksCounts {
            AppLink(link) { cell }
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            cell
        }
    }
}

/// One count and its label.
private struct SummaryCount: View {
    let value: Int
    let label: String
    let color: Color
    let numberSize: CGFloat
    @Environment(\.widgetStyle) private var style

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value, format: .number)
                .monospacedDigit()
                .foregroundStyle(color)
                .contentTransition(.numericText(value: Double(value)))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .displayStyle(numberSize, lineHeight: 0.9, style: style)
            Text(label)
                .foregroundStyle(style.sub)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .textStyle(10, .medium, lineHeight: 1.1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // A zero steps back, so the counts that need attention read first.
        .opacity(value == 0 ? 0.35 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(Text(value, format: .number))
    }
}

/// "This week": a bar per day from the app's first weekday, today's in the
/// accent with its count above.
private struct SummaryWeekChart: View {
    let state: WidgetState
    @Environment(\.widgetStyle) private var style

    /// The design's tallest bar, which the week's best day reaches; the other
    /// days scale from it.
    private static let tallestBar: CGFloat = 70
    /// A day gone by never draws shorter than this, so an empty one still
    /// reads as a day rather than a gap.
    private static let shortestBar: CGFloat = 4
    /// Days still to come.
    private static let stubHeight: CGFloat = 3
    /// The count above a bar and the letter under it, with their gaps.
    private static let labelsHeight: CGFloat = 9.5 + 5 + 5 + 9.5

    var body: some View {
        let days = SummaryWeek.days(activity: state.snapshot.activity, now: state.now, calendar: state.calendar)
        let total = days.reduce(0) { $0 + ($1.count ?? 0) }
        let best = max(1, days.compactMap(\.count).max() ?? 0)
        AppLink(.activity) {
            HStack(spacing: 0) {
                Hairline(.vertical)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        CapsLabel("This week")
                        Spacer(minLength: 0)
                        Text("\(total) done")
                            .foregroundStyle(style.ink)
                            .lineLimit(1)
                            .textStyle(11, .semibold, lineHeight: 1)
                    }
                    GeometryReader { proxy in
                        // Shorter widgets than the design's keep the labels
                        // and shrink the bars.
                        let tallest = max(Self.shortestBar, min(Self.tallestBar, proxy.size.height - Self.labelsHeight))
                        HStack(alignment: .bottom, spacing: 6) {
                            ForEach(days) { day in
                                column(day, barHeight: barHeight(for: day, best: best, tallest: tallest))
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    }
                    .padding(.top, 8)
                }
                .padding(.leading, 16)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("This week, \(total) done")
            .accessibilityValue(accessibilityDays(days))
        }
    }

    private func column(_ day: SummaryDay, barHeight: CGFloat) -> some View {
        let labelColor = day.isToday ? style.acc : style.faint
        return VStack(spacing: 5) {
            if let count = day.count {
                Text(count, format: .number)
                    .monospacedDigit()
                    .foregroundStyle(labelColor)
                    .contentTransition(.numericText(value: Double(count)))
                    .lineLimit(1)
                    .fixedSize()
                    .textStyle(9.5, .semibold, lineHeight: 1)
            }
            bar(for: day, height: barHeight)
            Text(day.letter)
                .foregroundStyle(labelColor)
                .lineLimit(1)
                .fixedSize()
                .textStyle(9.5, .semibold, lineHeight: 1)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func bar(for day: SummaryDay, height: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: min(4, height / 2))
        Group {
            if day.count == nil {
                shape.fill(style.track)
            } else {
                // Bars are the chart's accentable part; in tinted and
                // in-background rendering they keep today's emphasis by
                // opacity alone.
                shape.fill(day.isToday ? style.acc : style.ink.opacity(0.2))
                    .widgetAccentable()
            }
        }
        .frame(maxWidth: 20)
        .frame(height: height)
    }

    private func barHeight(for day: SummaryDay, best: Int, tallest: CGFloat) -> CGFloat {
        guard let count = day.count else { return Self.stubHeight }
        return max(Self.shortestBar, tallest * CGFloat(count) / CGFloat(best))
    }

    /// "Monday 0, Tuesday 0, Wednesday 2": the days so far.
    private func accessibilityDays(_ days: [SummaryDay]) -> String {
        days.compactMap { day in
            day.count.map { "\(WidgetFormat.weekdayName(day.date, calendar: state.calendar)) \($0)" }
        }
        .joined(separator: ", ")
    }
}

#if RENDER_SUMMARY
extension SummaryWidget {
    static var renderCases: [RenderCase] {
        let view = { (entry: SnapshotEntry, family: WidgetFamily, style: WidgetStyle) in
            SummaryWidgetView(entry: entry, family: family, style: style)
        }
        let families: [WidgetFamily] = [.systemSmall, .systemMedium]
        return RenderCase.families("summary", families, view: view)
            // A task ticked in another widget, not yet applied by the app.
            + RenderCase.families("summary", families, state: "ticked", entry: .mockup(pending: [.completing("q4")]), view: view)
            // A quiet morning: nothing late, nothing done yet, Inbox empty.
            + RenderCase.families("summary", families, state: "zeros", entry: sample { snapshot in
                snapshot.overdueCount = 0
                snapshot.inboxCount = 0
                snapshot.completedTodayCount = 0
                snapshot.activity.days[snapshot.activity.days.count - 1].count = 0
            }, view: view)
            // Three-digit counts, and a busier start to the week.
            + RenderCase.families("summary", families, state: "busy", entry: sample { snapshot in
                snapshot.dueTodayCount = 12
                snapshot.overdueCount = 128
                snapshot.inboxCount = 47
                snapshot.completedTodayCount = 9
                let days = snapshot.activity.days.count
                snapshot.activity.days[days - 3].count = 14
                snapshot.activity.days[days - 2].count = 5
                snapshot.activity.days[days - 1].count = 9
            }, view: view)
            // The app's serif titles turned off.
            + RenderCase.families("summary", [.systemMedium], state: "sans", entry: sample { $0.serifTitles = false }, view: view)
            + RenderCase.families("summary", families, state: "placeholder", entry: placeholder, view: view)
    }

    /// The mockup's sample, edited.
    private static func sample(_ edit: (inout WidgetSnapshot) -> Void) -> SnapshotEntry {
        let calendar = RenderCalendar.current
        let now = WidgetSnapshot.mockupNow(calendar: calendar)
        var snapshot = WidgetSnapshot.sample(now: now, calendar: calendar)
        edit(&snapshot)
        return SnapshotEntry(date: now, snapshot: snapshot, calendar: calendar)
    }

    private static var placeholder: SnapshotEntry {
        let calendar = RenderCalendar.current
        return SnapshotEntry(date: WidgetSnapshot.mockupNow(calendar: calendar), snapshot: WidgetSnapshot(), isPlaceholder: true, calendar: calendar)
    }
}
#endif
