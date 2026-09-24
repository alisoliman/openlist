//
//  NextCalendar.swift
//  openlist
//

import SwiftUI

struct NextCalendarScreen: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style

    var body: some View {
        let workbench = env.workbench
        let days = workbench.calendarDays
        NXPage(wide: true) {
            // The range comes from the timeline's date, so a screen left open
            // overnight moves to the new day with its header, from whatever
            // range it was stepped or planned to the day before.
            TimelineView(.everyMinute) { context in
                // Week is the settings week around today, as Plan searches it,
                // or around the day stepped to or planned on.
                let calendar = env.settings.calendar
                let dates = CalendarWeek.days(count: days, from: workbench.calendarStart(now: context.date), calendar: calendar)
                let controls = HStack(spacing: 10) {
                    NXCalendarStepper(dates: dates, now: context.date, calendar: calendar)
                    NXSegmented(options: [(1, "Day"), (3, "3 days"), (7, "Week")], selection: days) { value in
                        withAnimation(style.ease(260)) { workbench.calendarDays = value }
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    // The range control trails the title, wrapping under it as
                    // every header's controls do.
                    header(dates) { controls }
                    NXCalendarBody(dates: dates, now: context.date)
                        .padding(.top, 18)
                }
            }
        }
    }

    private func header<Trailing: View>(_ dates: [Date], @ViewBuilder trailing: @escaping () -> Trailing) -> some View {
        NXScreenHeader(tile: .icon("calendar"), color: style.accent, title: "Calendar", subtitle: Self.rangeText(dates), trailing: trailing)
    }

    static func rangeText(_ dates: [Date]) -> String {
        guard let first = dates.first, let last = dates.last else { return "" }
        if dates.count == 1 { return first.formatted(.dateTime.weekday(.wide).day().month(.wide)) }
        // The locale orders day and month, and drops a shared month once. The
        // dash gets the design's plain spaces, not the formatter's thin ones.
        return (first..<last).formatted(.interval.day().month(.wide)).replacingOccurrences(of: "\u{2009}", with: " ")
    }
}

/// Steps the Calendar's range on or back a day, three days or a week at a
/// time, and back to the one around today. A native extra: Plan goes on into
/// the next week once this one has no hours left, which the design's week,
/// always around a Wednesday, never needs.
private struct NXCalendarStepper: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    let dates: [Date]
    let now: Date
    let calendar: Calendar

    var body: some View {
        let showsToday = dates.contains { calendar.isDate($0, inSameDayAs: now) }
        HStack(spacing: 2) {
            step(-1)
            if !showsToday {
                Button { move(to: nil) } label: {
                    Text("Today").font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(buttonStyle(horizontal: 9))
                .transition(.opacity)
            }
            step(1)
        }
        .padding(2)
        .background(NX.ink(0.06), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .animation(style.ease(140), value: showsToday)
    }

    private func step(_ direction: Int) -> some View {
        let label = (direction < 0 ? "Previous " : "Next ") + (dates.count == 7 ? "week" : dates.count == 3 ? "3 days" : "day")
        return Button { move(to: CalendarWeek.anchor(stepping: dates, by: direction, now: now, calendar: calendar)) } label: {
            Image(systemName: direction < 0 ? "chevron.left" : "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 12, height: 15)
        }
        .buttonStyle(buttonStyle(horizontal: 6))
        .help(label)
        .accessibilityLabel(label)
    }

    private func buttonStyle(horizontal: CGFloat) -> NXHoverButtonStyle {
        NXHoverButtonStyle(hover: NX.ink(0.08), radius: 7, padding: EdgeInsets(top: 6, leading: horizontal, bottom: 6, trailing: horizontal),
                           foreground: NX.ink(0.55), hoverForeground: NX.ink)
    }

    private func move(to anchor: Date?) {
        withAnimation(style.ease(260)) { env.workbench.calendarAnchor = anchor }
    }
}

private enum NXCal {
    static let hourHeight: CGFloat = 40
    static let gutter: CGFloat = 52
    static let minColumn: CGFloat = 92
}

private struct NXCalendarBody: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    @Environment(\.nextLibrary) private var library
    let dates: [Date]
    let now: Date
    @State private var meetings = NXCalendarMeetings()

    var body: some View {
        let range = hourRange
        VStack(alignment: .leading, spacing: 12) {
            if let current = plannedNow, let task = env.store.block(id: current.taskID) {
                banner(current, task: task)
            }
            NXCalendarColumns {
                grid(range)
                NXUnplannedColumn(now: now)
            }
        }
    }

    /// 8–21 by default, stretched to fit anything scheduled outside it.
    private var hourRange: ClosedRange<Int> {
        let cal = Calendar.current
        var low = 8
        var high = 21
        let visible = blocks.map { ($0.start, $0.end) } + events.map { ($0.start, $0.end) }
        for (start, end) in visible {
            low = min(low, cal.component(.hour, from: start))
            let endHour = cal.component(.hour, from: end) + (cal.component(.minute, from: end) > 0 ? 1 : 0)
            high = max(high, cal.isDate(end, inSameDayAs: start) ? endHour : 24)
        }
        return max(0, low)...min(24, max(high, low + 1))
    }

    private var span: DateInterval? {
        guard let first = dates.first, let last = dates.last,
              let end = Calendar.current.date(byAdding: .day, value: 1, to: last) else { return nil }
        return DateInterval(start: first, end: end)
    }

    private var blocks: [PlannedBlock] {
        guard let span else { return [] }
        return env.calendar.visibleBlocks.filter { $0.end > span.start && $0.start < span.end }
    }

    /// Busy time in the days shown, earlier ones and weeks stepped to
    /// included, where the planner's own range, from today, doesn't reach.
    private var busy: [FixedBusyTime] {
        guard let span else { return [] }
        return meetings.busyTimes(in: span, from: env.calendar.externalCalendars)
    }

    private var events: [FixedBusyTime] {
        busy.filter { $0.end.timeIntervalSince($0.start) < 20 * 3600 }
    }

    /// Holds of 20 hours or more, like Out of office: no meeting to draw, but
    /// Plan keeps clear of them, so the day's header names them.
    private var holds: [FixedBusyTime] {
        busy.filter { $0.end.timeIntervalSince($0.start) >= 20 * 3600 }
    }

    /// The slot running now, with nothing to work on in hand: the design's
    /// banner hides while there's work, running or paused.
    private var plannedNow: PlannedBlock? {
        guard env.workbench.workTask == nil else { return nil }
        return env.calendar.visibleBlocks.first { block in
            guard !block.isCompleted, block.start <= now, now < block.end,
                  let task = env.store.block(id: block.taskID) else { return false }
            return !task.isCompleted && task.trashID == nil && env.workbench.closing[task.id] == nil
        }
    }

    private func banner(_ block: PlannedBlock, task: Block) -> some View {
        HStack(spacing: 12) {
            NXBreathingDot(color: style.accent, size: 8)
            Text("Planned now")
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.66)
                .textCase(.uppercase)
                .foregroundStyle(style.accent)
            Text(task.displayTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NX.ink)
                .lineLimit(1)
            Text("\(NXFormat.clock(block.start))–\(NXFormat.clock(block.end))")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NX.ink(0.5))
            Spacer(minLength: 8)
            Button { env.workbench.startWork(task.id) } label: {
                HStack(spacing: 5) {
                    Image(systemName: "play.fill").font(.system(size: 11))
                    Text("Start").font(.system(size: 12, weight: .semibold))
                }
            }
            .buttonStyle(NXHoverButtonStyle(hover: style.accent.mix(with: .black, by: 0.1), rest: style.accent, radius: 8,
                                            padding: EdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 12),
                                            foreground: .white, hoverForeground: .white))
        }
        .padding(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 12))
        .background(style.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(style.accent.opacity(0.2), lineWidth: 1))
        .modifier(NXLiftIn(animation: NX.cssEase(260)))
    }

    private func grid(_ range: ClosedRange<Int>) -> some View {
        let minWidth = NXCal.gutter + CGFloat(dates.count) * NXCal.minColumn
        return ScrollView(.horizontal) {
            // Days share the card's width down to their minimum, then the card scrolls.
            columns(range).containerRelativeFrame(.horizontal) { length, _ in max(length, minWidth) }
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .background(NX.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(NX.ink(0.12), lineWidth: 0.5))
    }

    private func columns(_ range: ClosedRange<Int>) -> some View {
        let height = CGFloat(range.upperBound - range.lowerBound) * NXCal.hourHeight
        let cal = Calendar.current
        let blocksByDay = Dictionary(grouping: blocks) { cal.startOfDay(for: $0.start) }
        let eventsByDay = Dictionary(grouping: events) { cal.startOfDay(for: $0.start) }
        let holds = self.holds
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: NXCal.gutter, height: 1)
                ForEach(dates, id: \.self) { date in
                    let day = cal.startOfDay(for: date)
                    let next = cal.date(byAdding: .day, value: 1, to: day) ?? day
                    NXDayHead(date: date, now: now, load: Self.hours(blocksByDay[day] ?? [], eventsByDay[day] ?? []),
                              holds: holds.filter { $0.end > day && $0.start < next }, reservesHold: !holds.isEmpty)
                }
            }
            .overlay(alignment: .bottom) { Rectangle().fill(NX.ink(0.09)).frame(height: 0.5) }
            HStack(alignment: .top, spacing: 0) {
                NXHourGutter(range: range, now: now, showsNow: dates.contains { cal.isDate($0, inSameDayAs: now) })
                    .frame(width: NXCal.gutter, height: height)
                ForEach(dates, id: \.self) { date in
                    let day = cal.startOfDay(for: date)
                    NXDayColumn(date: date, now: now, range: range,
                                blocks: blocksByDay[day] ?? [], events: eventsByDay[day] ?? [])
                        .frame(minWidth: NXCal.minColumn, maxWidth: .infinity)
                        .frame(height: height)
                }
            }
        }
    }

    /// Booked hours in one day's blocks and events.
    private static func hours(_ blocks: [PlannedBlock], _ events: [FixedBusyTime]) -> Double {
        let seconds = blocks.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
            + events.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
        return seconds / 3600
    }
}

/// The days' busy time, read again only when the days or the calendars change.
private final class NXCalendarMeetings {
    private var key: [Double] = []
    private var busy: [FixedBusyTime] = []

    func busyTimes(in span: DateInterval, from source: ExternalCalendarSource) -> [FixedBusyTime] {
        let key = [span.start.timeIntervalSinceReferenceDate, span.end.timeIntervalSinceReferenceDate, Double(source.revision)]
        if key != self.key {
            self.key = key
            busy = source.busyTimes(in: span)
        }
        return busy
    }
}

/// The grid (basis 640) and the tray (basis 236) side by side, sharing any
/// extra width equally; once both don't fit, each takes a full-width line.
private struct NXCalendarColumns: Layout {
    private let grid: CGFloat = 640
    private let tray: CGFloat = 236
    private let spacing: CGFloat = 16

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let frames = frames(width: proposal.width, subviews: subviews)
        return CGSize(width: frames.map(\.maxX).max() ?? 0, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, frames(width: bounds.width, subviews: subviews)) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }

    private func frames(width: CGFloat?, subviews: Subviews) -> [CGRect] {
        guard subviews.count == 2 else { return [] }
        let width = width.flatMap { $0.isFinite ? $0 : nil } ?? grid + spacing + tray
        func height(_ index: Int, _ width: CGFloat) -> CGFloat {
            subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        }
        if width >= grid + spacing + tray {
            let extra = (width - grid - spacing - tray) / 2
            return [CGRect(x: 0, y: 0, width: grid + extra, height: height(0, grid + extra)),
                    CGRect(x: grid + extra + spacing, y: 0, width: tray + extra, height: height(1, tray + extra))]
        }
        let top = height(0, width)
        return [CGRect(x: 0, y: 0, width: width, height: top),
                CGRect(x: 0, y: top + spacing, width: width, height: height(1, width))]
    }
}

private struct NXDayHead: View {
    @Environment(\.nextStyle) private var style
    let date: Date
    let now: Date
    let load: Double
    /// The day's all-day holds, and whether any day shown has one, so every
    /// header keeps the same height.
    let holds: [FixedBusyTime]
    let reservesHold: Bool

    var body: some View {
        let cal = Calendar.current
        let isToday = cal.isDate(date, inSameDayAs: now)
        let weekend = cal.isDateInWeekend(date)
        VStack(alignment: .leading, spacing: 4) {
            Text(isToday ? "Today" : date.formatted(.dateTime.weekday(.abbreviated)))
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.4)
                .textCase(.uppercase)
                .foregroundStyle(isToday ? style.accent : NX.ink(0.45))
                .lineLimit(1)
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text("\(cal.component(.day, from: date))")
                    .font(.system(size: 17, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(isToday ? style.accent : weekend ? NX.ink(0.5) : NX.ink)
                Spacer(minLength: 0)
                if load > 0 {
                    // Whole hours plain, anything else to a tenth, and never 0h
                    // for a day that has something in it.
                    let fractional = abs(load - load.rounded()) > 0.001
                    Text(fractional ? String(format: "%.1fh", max(0.1, (load * 10).rounded() / 10)) : "\(Int(load.rounded()))h")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(NX.ink(0.36))
                        .lineLimit(1)
                }
            }
            if reservesHold {
                hold.frame(height: 16)
            }
        }
        .padding(EdgeInsets(top: 9, leading: 9, bottom: 8, trailing: 9))
        .frame(minWidth: NXCal.minColumn, maxWidth: .infinity, alignment: .leading)
        .background(isToday ? style.accent.opacity(0.04) : .clear)
        .overlay(alignment: .leading) { Rectangle().fill(NX.ink(0.07)).frame(width: 0.5) }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var hold: some View {
        let names = holds.map { $0.title.isEmpty ? "Busy" : $0.title }
        if let first = names.first {
            Text(names.count > 1 ? "\(first) +\(names.count - 1)" : first)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(NX.ink(0.55))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(NX.ink(0.06), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                .help(names.joined(separator: ", "))
                .accessibilityLabel(names.joined(separator: ", ") + ", all day")
        } else {
            Color.clear
        }
    }
}

private struct NXHourGutter: View {
    let range: ClosedRange<Int>
    let now: Date
    let showsNow: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ForEach(Array(range.dropFirst().dropLast()), id: \.self) { hour in
                Text(String(format: "%02d:00", hour))
                    .font(NX.mono(10))
                    .foregroundStyle(NX.ink(0.36))
                    .padding(.trailing, 8)
                    .offset(y: CGFloat(hour - range.lowerBound) * NXCal.hourHeight - 6)
            }
            if showsNow, let y = NXDayColumn.offset(of: now, range: range) {
                Text(NXFormat.clock(now))
                    .font(NX.mono(9.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.vertical, 2)
                    .padding(.horizontal, 4)
                    .background(NX.red, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .padding(.trailing, 4)
                    .offset(y: y - 7)
                    .zIndex(6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }
}

private struct NXDayColumn: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    let date: Date
    let now: Date
    let range: ClosedRange<Int>
    let blocks: [PlannedBlock]
    let events: [FixedBusyTime]

    static func offset(of time: Date, range: ClosedRange<Int>) -> CGFloat? {
        let cal = Calendar.current
        let hours = Double(cal.component(.hour, from: time)) + Double(cal.component(.minute, from: time)) / 60
        guard hours >= Double(range.lowerBound), hours <= Double(range.upperBound) else { return nil }
        return CGFloat(hours - Double(range.lowerBound)) * NXCal.hourHeight
    }

    /// Where `time` falls, by the clock as the hour labels and the now line
    /// are, so nothing drifts an hour off them on a day the clocks change.
    private func top(_ time: Date) -> CGFloat {
        let hours = CalendarOverlapLayout.hours(time, on: date, calendar: .current)
        return CGFloat(min(max(hours, Double(range.lowerBound)), Double(range.upperBound)) - Double(range.lowerBound)) * NXCal.hourHeight
    }

    var body: some View {
        let cal = Calendar.current
        let isToday = cal.isDate(date, inSameDayAs: now)
        let isPast = date < cal.startOfDay(for: now)
        let weekend = cal.isDateInWeekend(date)
        let layout = arrange()
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                (isToday ? style.accent.opacity(0.024) : weekend ? NX.ink(0.015) : Color.clear)
                ForEach(1..<(range.upperBound - range.lowerBound), id: \.self) { index in
                    Rectangle().fill(NX.ink(0.06))
                        .frame(height: 0.5)
                        .offset(y: CGFloat(index) * NXCal.hourHeight - 0.5)
                }
                ForEach(Array(breaks.enumerated()), id: \.offset) { _, window in
                    NXHatch()
                        .fill(NX.ink(0.035))
                        .frame(height: max(0, top(window.end) - top(window.start)))
                        .clipped()
                        .offset(y: top(window.start))
                }
                if isPast {
                    NX.ink(0.022)
                } else if isToday {
                    // After the last hour, the whole of today has gone by.
                    NX.ink(0.022).frame(height: Self.offset(of: now, range: range)
                        ?? (cal.component(.hour, from: now) >= range.upperBound ? geo.size.height : 0))
                }

                ForEach(events) { event in
                    if let slot = layout[event.id] {
                        eventView(event)
                            .frame(width: width(slot, geo.size.width), height: slot.height)
                            .offset(x: x(slot, geo.size.width), y: slot.top)
                    }
                }
                ForEach(blocks) { block in
                    if let slot = layout[block.id] {
                        NXCalendarBlock(block: block, now: now, height: slot.height, isToday: isToday, isPastDay: isPast)
                            .frame(width: width(slot, geo.size.width), height: slot.height)
                            .offset(x: x(slot, geo.size.width), y: slot.top)
                            .zIndex(2)
                    }
                }

                if isToday, let y = Self.offset(of: now, range: range) {
                    Rectangle().fill(NX.red)
                        .frame(height: 2)
                        .overlay(alignment: .leading) {
                            Circle().fill(NX.red).frame(width: 8, height: 8).offset(x: -4)
                        }
                        .offset(y: y - 1)
                        .allowsHitTesting(false)
                        .zIndex(5)
                }
            }
            // The design's 420ms top and height, whatever the Motion setting.
            .animation(NX.ease(420), value: layout.mapValues { [$0.top, $0.height, Double($0.lane), Double($0.laneCount)] })
        }
        .overlay(alignment: .leading) { Rectangle().fill(NX.ink(0.07)).frame(width: 0.5) }
    }

    private func x(_ slot: CalendarOverlapLayout.Placement, _ width: CGFloat) -> CGFloat {
        slot.laneCount > 1 ? width * CGFloat(slot.lane) / CGFloat(slot.laneCount) + 2 : 3
    }

    private func width(_ slot: CalendarOverlapLayout.Placement, _ width: CGFloat) -> CGFloat {
        max(0, slot.laneCount > 1 ? width / CGFloat(slot.laneCount) - 4 : width - 6)
    }

    /// Lanes over the items' times, as the design's: one starting when another
    /// ends keeps the full width, drawn over what a minimum height put past
    /// that end. Recorded work away from any slot keeps its whole box.
    private func arrange() -> [String: CalendarOverlapLayout.Placement] {
        let y = { (time: Date) in Double(top(time)) }
        let items = events.map { CalendarOverlapLayout.Item.event($0, y: y) }
            + blocks.map { CalendarOverlapLayout.Item.block($0, y: y) }
        let placements = CalendarOverlapLayout.arrange(items)
        return Dictionary(placements.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Break windows (lunch) from the work hours, where the planner has them:
    /// a date override's when it sets them, else the weekday's. On the clock,
    /// as the planner keeps clear of them.
    private var breaks: [(start: Date, end: Date)] {
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)
        return env.calendar.preferences.profile(for: .work).breaks(on: day, calendar: cal).map {
            (CalendarOverlapLayout.time(minute: $0.startMinute, on: day, calendar: cal),
             CalendarOverlapLayout.time(minute: $0.endMinute, on: day, calendar: cal))
        }
    }

    private func eventView(_ event: FixedBusyTime) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(event.title).font(.system(size: 10.5, weight: .semibold))
            Text("\(NXFormat.clock(event.start))–\(NXFormat.clock(event.end))")
                .font(.system(size: 9.5, weight: .medium))
                .opacity(0.7)
        }
        .foregroundStyle(NX.ink(0.62))
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(NX.ink(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .help(event.title)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(event.title.isEmpty ? "Busy" : event.title)
        .accessibilityValue("\(NXFormat.clock(event.start)) to \(NXFormat.clock(event.end))")
    }
}

/// The 135° stripes used for breaks: 4pt wide and 8pt apart measured across
/// them, as the design's repeating gradient runs.
private nonisolated struct NXHatch: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Measured along the rows, the stripes are √2 times wider and further apart.
        let step: CGFloat = 8 * 2.squareRoot()
        let width: CGFloat = 4 * 2.squareRoot()
        var x = -rect.height
        while x < rect.width {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            path.addLine(to: CGPoint(x: x + rect.height + width, y: rect.minY))
            path.addLine(to: CGPoint(x: x + width, y: rect.maxY))
            path.closeSubpath()
            x += step
        }
        return path
    }
}

private struct NXCalendarBlock: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    @Environment(\.nextLibrary) private var library
    let block: PlannedBlock
    let now: Date
    let height: CGFloat
    let isToday: Bool
    let isPastDay: Bool
    @State private var entered = true
    @State private var hovering = false
    /// Briefly true after running work pushed this block to a new time.
    @State private var shifted = false
    @State private var shifts = 0

    var body: some View {
        let workbench = env.workbench
        let task = env.store.block(id: block.taskID)
        let color = library.list(task?.listID)?.nxColor ?? style.accent
        let closing = workbench.closing[block.taskID] != nil
        let done = block.isCompleted || task?.isCompleted == true || closing
        let running = block.isActive
        // Paused work keeps its block drawn as the work, as the design's does.
        let paused = env.calendar.pausedBlockID == block.id
        let working = running || paused
        // Work still running is never carried forward.
        let missed = !running && (isPastDay || (isToday && block.end <= now)) && !done
        let isNow = isToday && block.start <= now && now < block.end
        let meta = note(missed: missed, running: running, working: working, isNow: isNow)
        let focused = env.navigator.openTaskID == block.taskID
        let fg: Color = working ? .white : done ? NX.ink(0.5) : NX.ink
        let background: Color = working ? color : done ? NX.green.opacity(0.1) : missed ? NX.card.opacity(0.7) : color.opacity(0.12)
        let ring: Color = working ? .clear : done ? NX.green.opacity(0.28) : missed ? NX.red.opacity(0.35) : color.opacity(0.25)
        let fresh = workbench.freshBlockTaskID == block.taskID
        let title = task?.displayTitle ?? block.titleSnapshot ?? "Task"

        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .top, spacing: 5) {
                ZStack {
                    if done {
                        Circle().fill(closing ? style.accent : NX.green)
                        Image(systemName: "checkmark").font(.system(size: 7, weight: .bold)).foregroundStyle(.white)
                    } else {
                        Circle().strokeBorder(working ? .white : color, lineWidth: 1.3)
                    }
                }
                .frame(width: 12, height: 12)
                .padding(.top, 1)
                .contentShape(Circle())
                .onTapGesture(perform: check)
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .strikethrough(done)
                    .foregroundStyle(fg)
                    .lineLimit(height < 30 ? 1 : nil)
                    .truncationMode(.tail)
            }
            // The title keeps all its lines, as the design's, whose row never
            // shrinks; the time and state wrap into what's left under it, and
            // the block's edge cuts off what doesn't fit.
            .fixedSize(horizontal: false, vertical: true)
            if height >= 34 {
                Text(time + (meta.map { " · " + $0 } ?? ""))
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(working ? .white.opacity(0.8) : missed ? NX.redText : NX.ink(0.5))
                    .padding(.leading, 17)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        // A missed block's content keeps inside its dashed border, as the design's does.
        .padding(missed ? 1 : 0)
        // No taller than its slot, so what overflows is cut at the bottom
        // instead of the block growing past its hours.
        .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        .background(background, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        // The design's inset ring, which a missed block's border keeps inside
        // it: a solid line within the dashes, the fill showing between them.
        .overlay(RoundedRectangle(cornerRadius: missed ? 6 : 7, style: .continuous)
            .strokeBorder(ring, lineWidth: 1)
            .padding(missed ? 1 : 0))
        .overlay {
            if missed {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(NX.red.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            if focused {
                RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(style.accent, lineWidth: 2).padding(-2)
            }
        }
        .shadow(color: working ? color.opacity(0.33) : .clear, radius: 8, y: 6)
        .brightness(hovering ? -0.03 : 0)
        // The design's rowIn entrance.
        .offset(y: entered ? 0 : -8)
        .scaleEffect(entered ? 1 : 0.99)
        .opacity(entered ? 1 : 0)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: open)
        .animation(.easeOut(duration: 0.24), value: done)
        .animation(.easeOut(duration: 0.24), value: working)
        .onChange(of: fresh, initial: true) { _, isFresh in
            if isFresh { enter() }
        }
        .onChange(of: block.start) { _, _ in
            guard env.calendar.workExtension?.movedTaskIDs.contains(block.taskID) == true else { return }
            shifted = true
            shifts += 1
            enter()
        }
        .task(id: shifts) {
            guard shifted else { return }
            try? await Task.sleep(for: .milliseconds(1400))
            if !Task.isCancelled { shifted = false }
        }
        .help(task?.displayTitle ?? "")
        // One element: the title, its time and state, opened by default, with its check as an action.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(spokenState(done: done, missed: missed, paused: paused, note: meta))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, open)
        .accessibilityAction(named: done ? "Reopen" : "Complete", check)
    }

    private var time: String { "\(NXFormat.clock(block.start))–\(NXFormat.clock(block.end))" }

    private func open() {
        env.workbench.focusID = nil
        env.navigator.openTask(block.taskID)
    }

    /// A done block reopens its task where it was, unless a repeat has moved on since.
    private func check() {
        if block.isCompleted { env.workbench.reopen(block: block) } else { env.workbench.toggle(block.taskID) }
    }

    private func enter() {
        entered = false
        // A planned block usually arrives already fresh. Animating back on
        // the next update keeps both changes from merging into one. The
        // design's rowIn takes 380ms here whatever the Motion setting.
        Task { @MainActor in withAnimation(NX.ease(380)) { entered = true } }
    }

    /// The note after the slot, in the design's order of precedence. Work that
    /// can grow no further runs into what stopped it for as long as it runs,
    /// and paused work reads as it did when it paused.
    private func note(missed: Bool, running: Bool, working: Bool, isNow: Bool) -> String? {
        if missed { return "carried forward" }
        if working {
            let calendar = env.calendar
            let paused = running ? nil : calendar.pausedWorkNote
            if let conflict = running ? calendar.workConflict : paused?.conflict, conflict.occurrenceID == block.occurrenceID {
                return "runs into " + env.workbench.conflictName(conflict)
            }
            let extended = running ? calendar.workExtension?.occurrenceID == block.occurrenceID : paused?.extended == true
            return extended ? "extended" : "working"
        }
        if shifted { return "rescheduled" }
        return isNow ? "now" : nil
    }

    private func spokenState(done: Bool, missed: Bool, paused: Bool, note: String?) -> String {
        let time = "\(NXFormat.clock(block.start)) to \(NXFormat.clock(block.end))"
        // Paused work says so, then what it ran into or that it was extended.
        let pausedState = ["paused", note == "working" ? nil : note].compactMap { $0 }.joined(separator: ", ")
        let state = done ? "done" : missed ? "missed, carried forward" : paused ? pausedState : note
        return [time, state].compactMap { $0 }.joined(separator: ", ")
    }
}

/// Open tasks due soon or picked for today that have no block yet.
private struct NXUnplannedColumn: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    @Environment(\.nextLibrary) private var library
    let now: Date

    var body: some View {
        let tasks = unplanned
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Not planned yet").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(NX.ink)
                Text("\(tasks.count)").font(.system(size: 11, weight: .medium)).foregroundStyle(NX.ink(0.4))
            }
            .padding(EdgeInsets(top: 4, leading: 2, bottom: 2, trailing: 2))
            Text("Due soon or picked for today. Plan finds the next free slot around meetings and your hours.")
                .font(.system(size: 11.5))
                .foregroundStyle(NX.ink(0.5))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(EdgeInsets(top: 0, leading: 2, bottom: 4, trailing: 2))
            ForEach(tasks) { task in
                // Each card plays the design's liftIn as it appears, the Calendar opening too.
                card(task)
                    .modifier(NXLiftIn(animation: NX.cssEase(220)))
                    .transition(.asymmetric(insertion: .identity, removal: .opacity.combined(with: .scale(scale: 0.96))))
            }
            if tasks.isEmpty {
                Text("Everything due this week has a slot.")
                    .font(.system(size: 12))
                    .foregroundStyle(NX.ink(0.45))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(NX.ink(0.16), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            }
        }
        .animation(NX.ease(220), value: tasks.map(\.id))
    }

    private var unplanned: [Block] {
        let workbench = env.workbench
        // A block on the calendar keeps a task out, as Today's Fit into calendar counts it:
        // running or paused work, or a slot this week or later.
        let placed = workbench.placedTaskIDs(now: now)
        return library.open.filter { task in
            guard !placed.contains(task.id), workbench.closing[task.id] == nil else { return false }
            if let due = task.dueDate, CalendarWeek.isDueSoon(due, now: now, calendar: env.settings.calendar) { return true }
            return workbench.isPlanned(task)
        }
        .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    private func card(_ task: Block) -> some View {
        let overdue = task.dueDate.map { NXFormat.dayOffset($0, now: now) < 0 } ?? false
        let minutes = task.schedulingEstimateMinutes > 0 ? task.schedulingEstimateMinutes : env.workbench.defaultEstimate
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 7) {
                if let list = library.list(task.listID) { NXListGlyph(list: list, size: 12) }
                Text(task.displayTitle)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(NX.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 6) {
                Text(task.dueDate.map { NXFormat.dueLabel($0) } ?? "Picked for today")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(overdue ? NX.redText : style.accent)
                    .padding(.vertical, 3)
                    .padding(.horizontal, 6)
                    .background(overdue ? NX.red.opacity(0.12) : style.accent.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                Text("\(minutes) min").font(.system(size: 10.5, weight: .medium)).foregroundStyle(NX.ink(0.45))
                Spacer(minLength: 4)
                Button { env.workbench.fit(task.id) } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "sparkles").font(.system(size: 11))
                        Text("Plan").font(.system(size: 11, weight: .semibold))
                    }
                }
                .buttonStyle(NXHoverButtonStyle(hover: style.accent.opacity(0.18), rest: style.accent.opacity(0.1), radius: 6,
                                                padding: EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8),
                                                foreground: style.accent))
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 11)
        .background(NX.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(NX.ink(0.12), lineWidth: 0.5))
        .contentShape(Rectangle())
        .onTapGesture { env.workbench.inspect(task.id) }
        // Keeps the Plan button its own element under the card's tap target.
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Open details") { env.workbench.inspect(task.id) }
    }
}
