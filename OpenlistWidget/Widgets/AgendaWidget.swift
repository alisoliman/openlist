//
//  AgendaWidget.swift
//  OpenlistWidget
//

import SwiftUI
import WidgetKit

/// Today's plan around the meetings, or the whole week.
struct AgendaWidget: Widget {
    static let kind = WidgetKind.agenda

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: AgendaProvider()) { entry in
            WidgetEntryView(entry: entry) { family, style in
                AgendaWidgetView(entry: entry, family: family, style: style)
            }
            .widgetURL(WidgetLink.calendar.url)
        }
        .configurationDisplayName("Agenda")
        .description("Today’s plan around your meetings, or the whole week.")
        .supportedFamilies([.systemLarge, .systemExtraLarge])
        .contentMarginsDisabled()
    }
}

/// Large draws today on an hour grid, meetings and planned blocks side by
/// side with a line at the current time. Extra Large draws the week as seven
/// such columns on one shared grid.
struct AgendaWidgetView: View {
    let entry: SnapshotEntry
    let family: WidgetFamily
    let style: WidgetStyle

    var body: some View {
        if entry.isPlaceholder {
            OpenAppPrompt()
        } else {
            let state = entry.state
            let isWeek = family == .systemExtraLarge
            let days = isWeek
                ? AgendaLayout.week(snapshot: state.snapshot, now: state.now, calendar: state.calendar)
                : [AgendaLayout.day(state.now, snapshot: state.snapshot, now: state.now, calendar: state.calendar)]
            VStack(alignment: .leading, spacing: 0) {
                AgendaHeader(
                    title: isWeek ? "This week" : "Today",
                    detail: isWeek
                        ? WidgetFormat.weekRange(from: days.first?.date ?? state.now, calendar: state.calendar)
                        : AgendaLayout.summary(for: days[0])
                )
                .padding(.bottom, 10)
                AgendaGrid(days: days, state: state, metrics: isWeek ? .week : .day)
            }
        }
    }
}

/// What differs between the day and the week: the week's columns are a
/// quarter of the width, so blocks sit tighter and drop their times.
private struct AgendaMetrics {
    var blockInset: CGFloat
    var titleSize: CGFloat
    /// The current block shows "10:00–11:30" under its title.
    var showsCurrentRange: Bool
    var showsDayHeaders: Bool

    static let day = AgendaMetrics(blockInset: 5, titleSize: 10.5, showsCurrentRange: true, showsDayHeaders: false)
    static let week = AgendaMetrics(blockInset: 2, titleSize: 9, showsCurrentRange: false, showsDayHeaders: true)

    /// The hour labels' column.
    static let gutter: CGFloat = 30
    /// Hour labels end this far short of the grid.
    static let labelTrailing: CGFloat = 7
    /// The week's "MON 21" row and the air under it.
    static let dayHeaderHeight: CGFloat = 9.5
    static let dayHeaderGap: CGFloat = 6
    /// One line of title, so even a ten-minute block can be read.
    static let minimumBlockHeight: CGFloat = 13
    /// How short the block below may cut a one-line block before the two
    /// move side by side instead: the title's capitals still fit, and only
    /// its descenders clip.
    static let shortestBlockHeight: CGFloat = 9
    /// Air above and below every block, so back-to-back events stay apart.
    static let blockGap: CGFloat = 1
    /// Between blocks that overlap and so share a slot side by side.
    static let columnGap: CGFloat = 2
}

/// The serif title with the day's counts, or the week's dates, beside it.
private struct AgendaHeader: View {
    let title: LocalizedStringKey
    let detail: String
    @Environment(\.widgetStyle) private var style

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(style.display(23))
                .foregroundStyle(style.ink)
                .lineLimit(1)
                .fixedSize()
            Text(detail)
                .foregroundStyle(style.sub)
                .lineLimit(1)
                .textStyle(10.5, .medium, lineHeight: 1)
        }
        // The design sets the title solid (line-height 1), so the serif's tall
        // ascent and descent overhang a 23-point line evenly, as CSS does.
        .frame(height: 23)
        .accessibilityElement(children: .combine)
    }
}

/// The hour gutter and one column per day, filling the rest of the widget.
private struct AgendaGrid: View {
    let days: [AgendaDay]
    let state: WidgetState
    let metrics: AgendaMetrics
    @Environment(\.widgetStyle) private var style

    /// The grid widens to show the now line early in the morning or late in
    /// the evening, but not in the small hours, when that would squeeze the
    /// whole day into the top of the widget.
    private static let nowLineHours = 7.0...22.0

    var body: some View {
        let events = days.flatMap(\.events)
        let nowHour = AgendaLayout.hourOfDay(state.now, calendar: state.calendar)
        let window = AgendaLayout.window(
            for: events,
            including: Self.nowLineHours.contains(nowHour) ? state.now : nil,
            calendar: state.calendar
        )
        GeometryReader { proxy in
            let headerHeight = metrics.showsDayHeaders ? AgendaMetrics.dayHeaderHeight + AgendaMetrics.dayHeaderGap : 0
            let hourHeight = window.hourHeight(in: proxy.size.height - headerHeight)
            let columnWidth = max(0, (proxy.size.width - AgendaMetrics.gutter) / CGFloat(max(1, days.count)))
            VStack(alignment: .leading, spacing: 0) {
                if metrics.showsDayHeaders {
                    dayHeaders(columnWidth: columnWidth)
                        .frame(height: AgendaMetrics.dayHeaderHeight, alignment: .topLeading)
                        .padding(.bottom, AgendaMetrics.dayHeaderGap)
                }
                HStack(alignment: .top, spacing: 0) {
                    HourLabels(window: window, hourHeight: hourHeight)
                        .frame(width: AgendaMetrics.gutter)
                    ForEach(days) { day in
                        DayColumn(day: day, window: window, hourHeight: hourHeight, width: columnWidth, metrics: metrics, state: state)
                    }
                }
                .frame(height: hourHeight * CGFloat(window.hours), alignment: .topLeading)
                .overlay {
                    if events.isEmpty { EmptyAgenda(isWeek: metrics.showsDayHeaders) }
                }
            }
        }
    }

    private func dayHeaders(columnWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: AgendaMetrics.gutter)
            ForEach(days) { day in
                CapsLabel(day.label, color: day.isToday ? style.acc : style.faint, size: 9.5, tracking: 0.05, weight: .semibold)
                    .widgetAccentable(day.isToday)
                    .padding(.leading, 4)
                    .frame(width: columnWidth, alignment: .leading)
            }
        }
        // Each column already carries its day for VoiceOver.
        .accessibilityHidden(true)
    }
}

/// "10", "12", "14": every other hour, centred on its hairline.
private struct HourLabels: View {
    let window: AgendaWindow
    let hourHeight: CGFloat
    @Environment(\.widgetStyle) private var style

    var body: some View {
        let width = AgendaMetrics.gutter - AgendaMetrics.labelTrailing
        ZStack(alignment: .topLeading) {
            ForEach(window.labelHours(step: 2), id: \.self) { hour in
                Text(String(format: "%02d", hour))
                    .font(style.mono(9))
                    .foregroundStyle(style.faint)
                    .lineLimit(1)
                    .frame(width: width, alignment: .trailing)
                    // The design's 9-point line box sits half a point above
                    // the hairline's centre.
                    .position(x: width / 2, y: CGFloat(hour - window.startHour) * hourHeight - 0.5)
            }
        }
        .frame(maxHeight: .infinity)
        .accessibilityHidden(true)
    }
}

/// One day: hairlines every hour, its meetings and blocks, and the now line
/// when it is today. The week tints today's column.
private struct DayColumn: View {
    let day: AgendaDay
    let window: AgendaWindow
    let hourHeight: CGFloat
    let width: CGFloat
    let metrics: AgendaMetrics
    let state: WidgetState
    @Environment(\.widgetStyle) private var style

    /// The column's left rule; blocks and the now line are placed inside it.
    private static let rule: CGFloat = 0.5

    var body: some View {
        let height = hourHeight * CGFloat(window.hours)
        ZStack(alignment: .topLeading) {
            if metrics.showsDayHeaders, day.isToday {
                Rectangle().fill(style.chip)
            }
            HourRules(hours: window.hours, hourHeight: hourHeight)
                .fill(style.line)
            Rectangle()
                .fill(style.line)
                .frame(width: Self.rule)
            ForEach(placedBlocks) { block in
                AgendaBlock(event: block.event, size: block.rect.size, metrics: metrics, state: state)
                    .padding(.leading, Self.rule + block.rect.minX)
                    .padding(.top, block.rect.minY)
            }
            if day.isToday, let offset = window.nowOffset(state.now, hourHeight: hourHeight, calendar: state.calendar) {
                NowLine(width: width - Self.rule)
                    .padding(.leading, Self.rule)
                    .padding(.top, offset - NowLine.dotOverhang)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(day.isToday ? "\(day.label), today" : day.label)
    }

    /// Each event's rectangle inside the column, right of its rule. Events
    /// that overlap share the width side by side; a short block that runs
    /// into the next one stops at its top, and only moves aside when that
    /// would leave too little of its title (see `AgendaWindow.blocks`).
    private var placedBlocks: [AgendaPlacement] {
        window.blocks(
            for: day.events, hourHeight: hourHeight, width: width - Self.rule, inset: metrics.blockInset,
            minimumHeight: AgendaMetrics.minimumBlockHeight, shortestHeight: AgendaMetrics.shortestBlockHeight,
            gap: AgendaMetrics.blockGap, columnGap: AgendaMetrics.columnGap, calendar: state.calendar
        )
    }
}

/// A 0.5-point rule at the top of every hour.
private nonisolated struct HourRules: Shape {
    let hours: Int
    let hourHeight: CGFloat

    func path(in rect: CGRect) -> Path {
        Path { path in
            for hour in 0..<max(0, hours) {
                path.addRect(CGRect(x: rect.minX, y: rect.minY + CGFloat(hour) * hourHeight, width: rect.width, height: 0.5))
            }
        }
    }
}

/// The current time: a red rule across the day with a dot on the column's
/// edge. Red collapses to white in vibrant rendering like every accent.
private struct NowLine: View {
    let width: CGFloat
    @Environment(\.widgetStyle) private var style

    private static let thickness: CGFloat = 1.5
    private static let dot: CGFloat = 6
    /// How far the dot reaches above the rule's top edge.
    static let dotOverhang = (dot - thickness) / 2

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(style.red)
                .frame(width: width, height: Self.thickness)
            Circle()
                .fill(style.red)
                .frame(width: Self.dot, height: Self.dot)
                .offset(x: -Self.dot / 2)
        }
        .widgetAccentable()
        .accessibilityHidden(true)
    }
}

/// A meeting or a planned block. Meetings are quiet grey; planned blocks wear
/// their list's colour with a bar down the left, and open the task.
private struct AgendaBlock: View {
    let event: WidgetSnapshot.AgendaEvent
    let size: CGSize
    let metrics: AgendaMetrics
    let state: WidgetState
    @Environment(\.widgetStyle) private var style

    private static let radius: CGFloat = 5

    var body: some View {
        if event.kind == .task, let taskID = event.taskID {
            AppLink(.task(taskID)) { block }
        } else {
            block
        }
    }

    private var block: some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius)
        return VStack(alignment: .leading, spacing: 1) {
            Text(event.title)
                .foregroundStyle(titleColor)
                .strikethrough(isDone, color: style.sub)
                .lineLimit(1)
                .truncationMode(.tail)
                .textStyle(metrics.titleSize, .semibold, lineHeight: 1.2)
            if showsRange {
                Text(range)
                    .foregroundStyle(style.faint)
                    .lineLimit(1)
                    .textStyle(9.5, .medium, lineHeight: 1.2, monospaced: true)
            }
        }
        .padding(padding)
        .frame(width: size.width, height: size.height, alignment: isCutShort ? .leading : .topLeading)
        .background {
            shape.fill(fill)
            // The block being recorded lays its tint on twice, which reads
            // stronger in every appearance without a colour of its own.
            if isTask, !isDone, event.isActive { shape.fill(fill) }
        }
        .overlay {
            if let barColor {
                BlockBar(width: event.isActive ? 3 : 2.5, radius: Self.radius)
                    .fill(barColor)
                    .widgetAccentable(!isDone)
            }
        }
        .clipShape(shape)
        .contentShape(shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var isTask: Bool { event.kind == .task }
    private var isDone: Bool { isTask && event.isCompleted }
    private var isCurrent: Bool { event.start <= state.now && state.now < event.end }

    private var titleHeight: CGFloat { metrics.titleSize * 1.2 }

    /// Short blocks tuck the title up against their top edge; anything with
    /// room for a line of air gets the design's roomier padding.
    private var isRoomy: Bool { size.height >= titleHeight + 6 }

    /// Cut shorter than a line by the block below it, on a long day. Tucked
    /// to the top the title would lose its baseline; centred, the clip takes
    /// only the air above its capitals and its descenders.
    private var isCutShort: Bool { size.height < AgendaMetrics.minimumBlockHeight }

    /// Blocks squeezed side by side into a week column keep what little
    /// width they have for the title.
    private var padding: EdgeInsets {
        let vertical: CGFloat = isCutShort ? 0 : isRoomy ? 3 : 1
        if size.width < 44 { return EdgeInsets(top: vertical, leading: 4, bottom: vertical, trailing: 2) }
        let horizontal: CGFloat = isRoomy ? 6 : 5
        return EdgeInsets(top: vertical, leading: horizontal, bottom: vertical, trailing: horizontal)
    }

    /// The block you should be on shows its times, when it has room for them.
    private var showsRange: Bool {
        metrics.showsCurrentRange && isTask && !isDone && (isCurrent || event.isActive)
            && size.height >= 3 + titleHeight + 1 + 9.5 * 1.2 + 3
    }

    private var range: String {
        WidgetFormat.range(event.start, event.end, calendar: state.calendar)
    }

    private var titleColor: Color {
        isTask && !isDone ? style.ink : style.sub
    }

    private var fill: Color {
        guard isTask else { return style.meet }
        return isDone ? style.chip : style.listTint(event.accentHex ?? state.snapshot.accentHex)
    }

    private var barColor: Color? {
        guard isTask else { return nil }
        return isDone ? style.track : style.listColor(event.accentHex ?? state.snapshot.accentHex)
    }

    private var accessibilityText: String {
        var parts = [event.title, WidgetFormat.range(event.start, event.end, calendar: state.calendar)]
        if isTask {
            if !event.listName.isEmpty { parts.append(event.listName) }
            if isDone { parts.append("done") } else if event.isActive { parts.append("in progress") }
        } else {
            parts.append("meeting")
        }
        return parts.joined(separator: ", ")
    }
}

/// The accent down a block's left edge, curving with its corners the way the
/// design's inset shadow does.
private nonisolated struct BlockBar: Shape {
    let width: CGFloat
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let outline = RoundedRectangle(cornerRadius: radius).path(in: rect)
        return outline.subtracting(RoundedRectangle(cornerRadius: radius).path(in: rect.offsetBy(dx: width, dy: 0)))
    }
}

/// Shown over the empty grid, which still carries the hours and the now line.
private struct EmptyAgenda: View {
    let isWeek: Bool
    @Environment(\.widgetStyle) private var style

    var body: some View {
        VStack(spacing: 3) {
            Text(isWeek ? "Your week is clear" : "Your day is clear")
                .foregroundStyle(style.ink)
                .textStyle(12, .semibold, lineHeight: 1.3)
            Text("Meetings and planned tasks show up here.")
                .foregroundStyle(style.sub)
                .multilineTextAlignment(.center)
                .textStyle(10.5, .medium, lineHeight: 1.3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(style.bg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.leading, AgendaMetrics.gutter)
        .accessibilityElement(children: .combine)
    }
}

#if RENDER_AGENDA
extension AgendaWidget {
    static var renderCases: [RenderCase] {
        let families: [WidgetFamily] = [.systemLarge, .systemExtraLarge]
        let view = { (entry: SnapshotEntry, family: WidgetFamily, style: WidgetStyle) in
            AgendaWidgetView(entry: entry, family: family, style: style)
        }
        // The design's crops were taken with Close out Q2 retro actions
        // ticked off, so Tuesday's block is struck through.
        return RenderCase.families("agenda", families, entry: .mockup(pending: [.completing("q4")]), view: view)
            + RenderCase.families("agenda", families, state: "working", entry: .mockup(work: .working), view: view)
            + RenderCase.families("agenda", families, state: "done", entry: .mockup(pending: [.completing("q1")]), view: view)
            + RenderCase.families("agenda", families, state: "busy", entry: busy, view: view)
            + RenderCase.families("agenda", families, state: "long", entry: long, view: view)
            + RenderCase.families("agenda", families, state: "empty", entry: empty, view: view)
    }

    /// A 07:00 gym session and a 19:00 dinner stretch the grid to thirteen
    /// hours, so a half-hour is shorter than a line of title. The day's
    /// back-to-back half-hours must still keep the full width.
    private static var long: SnapshotEntry {
        let base = SnapshotEntry.mockup()
        let calendar = base.state.calendar
        var snapshot = base.snapshot
        func at(_ hour: Int) -> Date {
            calendar.date(bySettingHour: hour, minute: 0, second: 0, of: base.date) ?? base.date
        }
        snapshot.agenda += [
            .init(id: "long-1", kind: .meeting, title: "Gym", start: at(7), end: at(8)),
            .init(id: "long-2", kind: .meeting, title: "Dinner with Jun", start: at(19), end: at(20)),
        ]
        snapshot.agenda.sort { $0.start < $1.start }
        return SnapshotEntry(date: base.date, snapshot: snapshot, calendar: RenderCalendar.current)
    }

    /// Overlapping events, back-to-back ten-minute blocks and an evening
    /// meeting that stretches the grid.
    private static var busy: SnapshotEntry {
        let base = SnapshotEntry.mockup()
        let calendar = base.state.calendar
        var snapshot = base.snapshot
        func at(_ hour: Int, _ minute: Int, days: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: days, to: base.date) ?? base.date
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        let tasks = snapshot.agenda.filter { $0.kind == .task }
        let blue = tasks.first { $0.title == "Draft Q3 OKRs" }?.accentHex
        let green = tasks.first { $0.title == "Order new water filters" }?.accentHex
        snapshot.agenda += [
            .init(id: "busy-1", kind: .meeting, title: "Call with Mika about the trip", start: at(10, 30), end: at(11, 15)),
            .init(id: "busy-2", kind: .task, title: "Book the boiler service", start: at(16, 40), end: at(16, 50), taskID: UUID(), accentHex: green),
            .init(id: "busy-3", kind: .task, title: "Pick up the dry cleaning", start: at(16, 50), end: at(17, 0), taskID: UUID(), accentHex: green),
            .init(id: "busy-4", kind: .meeting, title: "Dinner with Jun", start: at(19, 30), end: at(21, 0)),
            .init(id: "busy-5", kind: .meeting, title: "Leadership sync", start: at(13, 0, days: 1), end: at(14, 0, days: 1)),
            .init(id: "busy-6", kind: .task, title: "Outline the offsite agenda", start: at(13, 15, days: 1), end: at(14, 30, days: 1), taskID: UUID(), accentHex: blue),
        ]
        snapshot.agenda.sort { $0.start < $1.start }
        return SnapshotEntry(date: base.date, snapshot: snapshot, calendar: RenderCalendar.current)
    }

    private static var empty: SnapshotEntry {
        let base = SnapshotEntry.mockup()
        var snapshot = base.snapshot
        snapshot.agenda = []
        return SnapshotEntry(date: base.date, snapshot: snapshot, calendar: RenderCalendar.current)
    }
}
#endif
