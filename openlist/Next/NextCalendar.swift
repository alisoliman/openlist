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
            // overnight moves to the new day with its header.
            TimelineView(.everyMinute) { context in
                let dates = Self.dates(count: days, from: context.date)
                VStack(alignment: .leading, spacing: 0) {
                    NXScreenHeader(tile: .icon("calendar"), color: style.accent, title: "Calendar", subtitle: Self.rangeText(dates)) {
                        NXSegmented(options: [(1, "Day"), (3, "3 days"), (7, "Week")], selection: days) { value in
                            withAnimation(style.ease(260)) { workbench.calendarDays = value }
                        }
                    }
                    NXCalendarBody(dates: dates, now: context.date)
                }
            }
        }
    }

    /// The week starts two days back so yesterday's misses stay in view.
    static func dates(count: Int, from now: Date = .now) -> [Date] {
        let first = NXFormat.day(offset: count == 7 ? -2 : 0, now: now)
        return (0..<count).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: first) }
    }

    static func rangeText(_ dates: [Date]) -> String {
        guard let first = dates.first, let last = dates.last else { return "" }
        if dates.count == 1 { return first.formatted(.dateTime.weekday(.wide).day().month(.wide)) }
        let cal = Calendar.current
        if cal.isDate(first, equalTo: last, toGranularity: .month) {
            return "\(cal.component(.day, from: first)) – \(last.formatted(.dateTime.day().month(.wide)))"
        }
        return "\(first.formatted(.dateTime.day().month(.wide))) – \(last.formatted(.dateTime.day().month(.wide)))"
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

    var body: some View {
        let range = hourRange
        VStack(alignment: .leading, spacing: 12) {
            if let current = plannedNow, let task = env.store.block(id: current.taskID) {
                banner(current, task: task)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    grid(range).frame(minWidth: max(640, NXCal.gutter + CGFloat(dates.count) * NXCal.minColumn))
                    NXUnplannedColumn(now: now).frame(width: 236)
                }
                VStack(alignment: .leading, spacing: 16) {
                    grid(range)
                    NXUnplannedColumn(now: now)
                }
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

    private var events: [FixedBusyTime] {
        guard let span else { return [] }
        return env.calendar.externalCalendars.busyTimes.filter {
            $0.end > span.start && $0.start < span.end && $0.end.timeIntervalSince($0.start) < 20 * 3600
        }
    }

    private var plannedNow: PlannedBlock? {
        guard env.calendar.activeSession == nil else { return nil }
        let paused = env.calendar.resumableTask?.id
        return env.calendar.visibleBlocks.first { block in
            guard !block.isCompleted, block.start <= now, now < block.end, block.taskID != paused,
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
            .buttonStyle(NXHoverButtonStyle(hover: style.accent.mix(with: .black, by: 0.1), radius: 8,
                                            padding: EdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 12),
                                            foreground: .white, hoverForeground: .white))
            .background(style.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 12))
        .background(style.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(style.accent.opacity(0.2), lineWidth: 1))
        .modifier(NXLiftIn())
    }

    private func grid(_ range: ClosedRange<Int>) -> some View {
        let height = CGFloat(range.upperBound - range.lowerBound) * NXCal.hourHeight
        let cal = Calendar.current
        let blocksByDay = Dictionary(grouping: blocks) { cal.startOfDay(for: $0.start) }
        let eventsByDay = Dictionary(grouping: events) { cal.startOfDay(for: $0.start) }
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: NXCal.gutter, height: 1)
                ForEach(dates, id: \.self) { date in
                    let day = cal.startOfDay(for: date)
                    NXDayHead(date: date, now: now, load: Self.hours(blocksByDay[day] ?? [], eventsByDay[day] ?? []))
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
        .background(NX.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(NX.ink(0.12), lineWidth: 0.5))
    }

    /// Booked hours in one day's blocks and events.
    private static func hours(_ blocks: [PlannedBlock], _ events: [FixedBusyTime]) -> Double {
        let seconds = blocks.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
            + events.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
        return seconds / 3600
    }
}

private struct NXDayHead: View {
    @Environment(\.nextStyle) private var style
    let date: Date
    let now: Date
    let load: Double

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
                if load > 0.01 {
                    let rounded = (load * 2).rounded() / 2
                    Text(rounded.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(rounded))h" : String(format: "%.1fh", rounded))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(NX.ink(0.36))
                        .lineLimit(1)
                }
            }
        }
        .padding(EdgeInsets(top: 9, leading: 9, bottom: 8, trailing: 9))
        .frame(minWidth: NXCal.minColumn, maxWidth: .infinity, alignment: .leading)
        .background(isToday ? style.accent.opacity(0.04) : .clear)
        .overlay(alignment: .leading) { Rectangle().fill(NX.ink(0.07)).frame(width: 0.5) }
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

    private func top(_ time: Date) -> CGFloat {
        let start = Calendar.current.startOfDay(for: date)
        let hours = time.timeIntervalSince(start) / 3600
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
                } else if isToday, let y = Self.offset(of: now, range: range) {
                    NX.ink(0.022).frame(height: y)
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
            .animation(style.ease(420), value: layout.mapValues { [$0.top, $0.height, Double($0.lane), Double($0.laneCount)] })
        }
        .overlay(alignment: .leading) { Rectangle().fill(NX.ink(0.07)).frame(width: 0.5) }
    }

    private func x(_ slot: CalendarOverlapLayout.Placement, _ width: CGFloat) -> CGFloat {
        slot.laneCount > 1 ? width * CGFloat(slot.lane) / CGFloat(slot.laneCount) + 2 : 3
    }

    private func width(_ slot: CalendarOverlapLayout.Placement, _ width: CGFloat) -> CGFloat {
        max(0, slot.laneCount > 1 ? width / CGFloat(slot.laneCount) - 4 : width - 6)
    }

    private func arrange() -> [String: CalendarOverlapLayout.Placement] {
        var items = events.map { event in
            CalendarOverlapLayout.Item(id: event.id, top: Double(top(event.start) + 1),
                                       height: Double(max(16, top(event.end) - top(event.start) - 2)))
        }
        items += blocks.map { block in
            CalendarOverlapLayout.Item(id: block.id, top: Double(top(block.start) + 1),
                                       height: Double(max(18, top(block.end) - top(block.start) - 2)))
        }
        let placements = CalendarOverlapLayout.arrange(items)
        return Dictionary(placements.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Break windows (lunch) from the work hours profile.
    private var breaks: [(start: Date, end: Date)] {
        let day = Calendar.current.startOfDay(for: date)
        let weekday = Calendar.current.component(.weekday, from: date)
        return (env.calendar.preferences.profile(for: .work).breaks[weekday] ?? []).map {
            (day.addingTimeInterval(TimeInterval($0.startMinute * 60)), day.addingTimeInterval(TimeInterval($0.endMinute * 60)))
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
    }
}

/// The 135° stripes used for breaks.
private nonisolated struct NXHatch: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step: CGFloat = 8
        var x = -rect.height
        while x < rect.width {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            path.addLine(to: CGPoint(x: x + rect.height + 4, y: rect.minY))
            path.addLine(to: CGPoint(x: x + 4, y: rect.maxY))
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
    @State private var popped = true

    var body: some View {
        let workbench = env.workbench
        let task = env.store.block(id: block.taskID)
        let color = library.list(task?.listID)?.nxColor ?? style.accent
        let closing = workbench.closing[block.taskID] != nil
        let done = block.isCompleted || task?.isCompleted == true || closing
        let missed = (isPastDay || (isToday && block.end <= now)) && !done
        let working = !block.isCompleted && task != nil && env.calendar.activeSession?.taskID == block.taskID
        let isNow = isToday && block.start <= now && now < block.end
        let focused = env.navigator.openTaskID == block.taskID
        let fg: Color = working ? .white : done ? NX.ink(0.5) : NX.ink
        let background: Color = working ? color : done ? NX.green.opacity(0.1) : missed ? NX.card.opacity(0.7) : color.opacity(0.12)
        let ring: Color = working ? .clear : done ? NX.green.opacity(0.28) : missed ? NX.red.opacity(0.35) : color.opacity(0.25)
        let fresh = workbench.freshBlockTaskID == block.taskID

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
                .onTapGesture { if !block.isCompleted { workbench.toggle(block.taskID) } }
                Text(task?.displayTitle ?? block.titleSnapshot ?? "Task")
                    .font(.system(size: 10.5, weight: .semibold))
                    .strikethrough(done)
                    .foregroundStyle(fg)
                    .lineLimit(height < 30 ? 1 : nil)
                    .truncationMode(.tail)
            }
            if height >= 34 {
                Text(meta(missed: missed, working: working, isNow: isNow))
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(working ? .white.opacity(0.8) : missed ? NX.redText : NX.ink(0.5))
                    .lineLimit(1)
                    .padding(.leading, 17)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(background, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(ring, lineWidth: 1))
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
        .scaleEffect(popped ? 1 : 0.96)
        .opacity(popped ? 1 : 0.4)
        .contentShape(Rectangle())
        .onTapGesture {
            workbench.focusID = nil
            env.navigator.openTask(block.taskID)
        }
        .animation(.easeOut(duration: 0.24), value: done)
        .animation(.easeOut(duration: 0.24), value: working)
        .onChange(of: fresh, initial: true) { _, isFresh in
            guard isFresh else { return }
            popped = false
            // A planned block usually arrives already fresh. Animating back on
            // the next update keeps both changes from merging into one.
            Task { @MainActor in withAnimation(style.ease(380)) { popped = true } }
        }
        .help(task?.displayTitle ?? "")
    }

    private func meta(missed: Bool, working: Bool, isNow: Bool) -> String {
        var text = "\(NXFormat.clock(block.start))–\(NXFormat.clock(block.end))"
        if missed { text += " · carried forward" }
        else if working { text += block.conflicts.first.map { " · runs into \($0)" } ?? " · working" }
        else if isNow { text += " · now" }
        let calendar = env.calendar
        if let extended = calendar.workExtension, extended.occurrenceID == block.occurrenceID {
            text += " · extended"
        } else if calendar.workExtension?.movedTaskIDs.contains(block.taskID) == true
                    || calendar.rescheduleSummary?.taskIDs.contains(block.taskID) == true {
            text += " · rescheduled"
        }
        return text
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
                card(task)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 8)), removal: .opacity.combined(with: .scale(scale: 0.96))))
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
        .animation(style.ease(220), value: tasks.map(\.id))
    }

    private var unplanned: [Block] {
        let workbench = env.workbench
        let placed = Set(env.calendar.visibleBlocks.filter { !$0.isCompleted }.map(\.taskID))
        return library.open.filter { task in
            guard !placed.contains(task.id), workbench.closing[task.id] == nil else { return false }
            if let due = task.dueDate, (-7...4).contains(NXFormat.dayOffset(due, now: now)) { return true }
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
                .buttonStyle(NXHoverButtonStyle(hover: style.accent.opacity(0.18), radius: 6,
                                                padding: EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8),
                                                foreground: style.accent))
                .background(style.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 11)
        .background(NX.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(NX.ink(0.12), lineWidth: 0.5))
        .contentShape(Rectangle())
        .onTapGesture { env.workbench.inspect(task.id) }
    }
}
