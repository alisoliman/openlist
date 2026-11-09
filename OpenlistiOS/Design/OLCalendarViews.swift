//
//  OLCalendarViews.swift
//  OpenlistiOS
//

import SwiftUI

// MARK: - C29 Week strip

/// Seven days, Monday or the week-start setting's day first: the picked one
/// in the accent, today on a grey fill.
struct OLWeekStrip: View {
    let days: [Date]
    @Binding var selection: Date
    var today: Date
    var calendar: Calendar = .current
    @Environment(\.olStyle) private var style

    /// The week holding `date`, from `calendar.firstWeekday`.
    static func week(containing date: Date, calendar: Calendar) -> [Date] {
        let day = calendar.startOfDay(for: date)
        let offset = (calendar.component(.weekday, from: day) - calendar.firstWeekday + 7) % 7
        guard let start = calendar.date(byAdding: .day, value: -offset, to: day) else { return [day] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(days, id: \.self) { day in
                dayButton(day)
            }
        }
        .olFeedback(.selection, trigger: selection)
    }

    private func dayButton(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selection)
        let isToday = calendar.isDate(day, inSameDayAs: today)
        return Button {
            withAnimation(style.animation(.snappy(duration: 0.22))) { selection = day }
        } label: {
            VStack(spacing: 2) {
                Text(day.formatted(.dateTime.weekday(.abbreviated)))
                    .font(OLFont.weekday)
                    .opacity(0.75)
                Text(day.formatted(.dateTime.day()))
                    .font(OLFont.weekDate)
                    .monospacedDigit()
            }
            .foregroundStyle(isSelected ? OL.onAccent : OL.ink)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background {
                if isSelected || isToday {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(isSelected ? OL.accent : OL.accentSoft)
                }
            }
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(OLPressStyle(scale: 0.95))
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - C30 Timeline

/// One block on the timeline card.
struct OLTimelineItem: Identifiable, Equatable {
    enum Kind: Equatable {
        /// Done: a green tint, struck through, its checkbox ticked.
        case done
        /// The work on now: solid ink, as tall as it runs.
        case working
        /// A task's slot: a grey card with its checkbox in its list's colour.
        case planned
        /// A slot gone by without work: dashed red, carried forward.
        case missed
        /// A meeting: a quiet grey block, as tall as it runs.
        case event
        /// Due at a time with no slot: a card at that time, "Due" in red.
        case due
    }

    /// What's under way now and what comes next today, a step heavier.
    enum Emphasis: Equatable { case none, now, next }

    let id: String
    var kind: Kind
    var title: String
    var start: Date
    var end: Date
    /// A note after its time: "Now · 50 min left" on the working block,
    /// "25 min left" on a slot on now.
    var detail: String?
    /// The task it is, for opening it; nil for a meeting.
    var taskID: UUID?
    /// The slot it draws, when it is one.
    var placementID: UUID?
    /// It can be dragged, or moved by a quarter hour, to another time.
    var movable = false
    var emphasis: Emphasis = .none
    /// The task's list colour, which its checkbox wears.
    var listColor: Color?
    /// Over: a meeting gone by is drawn lighter.
    var isPast = false
    /// A meeting's place and calendar, for its details.
    var location: String?
    var calendarTitle: String?
}

/// Where a block sits: its top and height, and its column `index` of
/// `count` among the blocks it overlaps.
struct OLTimelineFrame: Equatable {
    let id: String
    var top: CGFloat
    var height: CGFloat
    var index = 0
    var count = 1
}

/// The hour grid: a rule every hour from 52 pt, the hour in mono beside it.
struct OLTimelineGrid: View {
    let hours: ClosedRange<Int>
    var hourHeight: CGFloat = 44

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(hours), id: \.self) { hour in
                let y = CGFloat(hour - hours.lowerBound) * hourHeight
                Rectangle()
                    .fill(OL.line)
                    .frame(height: 1)
                    .padding(.leading, 52)
                    .offset(y: y)
                Text(String(format: "%02d:00", hour))
                    .font(OLFont.monoHour)
                    .foregroundStyle(OL.muted)
                    .offset(x: 10, y: y - 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

/// The colours a task's block wears, as the Mac's Calendar and Today draw a
/// session (`NXSessionLook`): a grey card with its checkbox in its list's
/// colour, work under way solid ink, done a green tint, a slot gone by
/// without work dashed red. What's on now, and next, is outlined a step heavier.
struct OLSessionLook {
    let kind: OLTimelineItem.Kind
    var emphasis: OLTimelineItem.Emphasis = .none
    var listColor: Color?

    private var working: Bool { kind == .working }
    private var done: Bool { kind == .done }
    private var missed: Bool { kind == .missed }
    /// Open and on time: the plain card the emphasis outlines.
    private var plain: Bool { !working && !done && !missed }

    var foreground: Color { working ? OL.onAccent : done ? OL.muted : OL.ink }
    var fill: Color { working ? OL.accent : done ? OL.success.opacity(0.1) : OL.surface }
    var ring: Color {
        if working || missed { return .clear }
        if done { return OL.success.opacity(0.28) }
        return switch emphasis {
        case .now: OL.ink.opacity(0.6)
        case .next: OL.ink.opacity(0.3)
        case .none: OL.ink.opacity(0.12)
        }
    }
    var ringWidth: CGFloat { plain && emphasis == .now ? 1.5 : 1 }
    /// The checkbox's ring while the task is open.
    var circle: Color { working ? OL.onAccent : listColor ?? OL.muted }
    /// The time and note under the title.
    var detail: Color { working ? OL.onAccent.opacity(0.8) : missed ? OL.danger : OL.muted }
    /// The dashes around a slot gone by.
    static let missedDash = OL.danger.opacity(0.5)
}

/// A block's look, sized by the caller: a meeting a quiet grey block, its
/// title darker while it's on; a task's block a card with its checkbox
/// (`OLSessionLook`). One line holds the title and its start; from
/// `twoLines` tall, the time goes under the title.
struct OLTimelineBlock: View {
    let item: OLTimelineItem
    /// How tall it's drawn.
    var height: CGFloat = 22
    /// How wide its lane is: a narrow one keeps its room for the title.
    var width: CGFloat = .infinity
    var calendar: Calendar = .current
    /// Ticks the task from its checkbox; nil draws the checkbox alone.
    var check: (() -> Void)?

    /// Tall enough for the time on a line of its own.
    static let twoLines: CGFloat = 38
    /// Wide enough for a start time after the title on one line.
    static let trailingRoom: CGFloat = 150

    var body: some View {
        if item.kind == .event { meeting } else { session }
    }

    private func clock(_ date: Date) -> String { CompactText.clock(date, calendar: calendar) }

    private var range: String { OLFormat.range(item.start, item.end, calendar: calendar) }

    // MARK: Meeting

    private var meeting: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        let on = item.emphasis == .now
        let twoLines = height >= Self.twoLines
        return VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(item.title)
                    .font(OLFont.timelineBlock.weight(on ? .semibold : .medium))
                    .foregroundStyle(item.isPast && !on ? OL.muted : OL.ink)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !twoLines, width >= Self.trailingRoom { time(clock(item.start), color: OL.muted, fixed: true) }
            }
            if twoLines { time(range, color: OL.muted) }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(OL.ink.opacity(on ? 0.085 : item.isPast ? 0.035 : 0.055), in: shape)
        // Solid, so the grid's lines and the now line pass under it.
        .background(OL.surface, in: shape)
        .clipShape(shape)
    }

    // MARK: Session

    private var session: some View {
        let look = OLSessionLook(kind: item.kind, emphasis: item.emphasis, listColor: item.listColor)
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        let missed = item.kind == .missed
        let twoLines = height >= Self.twoLines && item.kind != .due
        return VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                checkbox(look)
                Text(item.title)
                    .font(OLFont.timelineBlock)
                    .strikethrough(item.kind == .done, color: OL.muted)
                    .foregroundStyle(look.foreground)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !twoLines, let trailing, width >= Self.trailingRoom || item.kind == .due {
                    time(trailing, color: item.kind == .due ? OL.danger : look.detail, fixed: true)
                }
            }
            if twoLines {
                time([item.kind == .working ? nil : range, note].compactMap(\.self).joined(separator: " · "),
                     color: look.detail)
                    .padding(.leading, 19)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(look.fill, in: shape)
        // Solid underneath a tint, so the grid and the now-line pass under it.
        .background(OL.surface, in: shape)
        .overlay {
            if missed {
                shape.strokeBorder(OLSessionLook.missedDash, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            } else {
                shape.strokeBorder(look.ring, lineWidth: look.ringWidth)
            }
        }
        .clipShape(shape)
    }

    /// What follows the title on one line: its start, the working block's
    /// note, or "Due".
    private var trailing: String? {
        switch item.kind {
        case .due: "Due"
        case .working: item.detail
        default: clock(item.start)
        }
    }

    /// What follows the time on the second line.
    private var note: String? {
        switch item.kind {
        case .missed: "carried forward"
        case .done, .due, .event: nil
        case .working, .planned: item.detail
        }
    }

    /// A time or note: `fixed` after a title, which gives way first.
    private func time(_ text: String, color: Color, fixed: Bool = false) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize(horizontal: fixed, vertical: false)
    }

    /// The task's checkbox in its list's colour, ticked green once done. A
    /// tap on it, and a little around it, ticks the task.
    @ViewBuilder private func checkbox(_ look: OLSessionLook) -> some View {
        let circle = ZStack {
            if item.kind == .done {
                Circle().fill(OL.success)
                Image(systemName: "checkmark").font(.system(size: 7, weight: .bold)).foregroundStyle(.white)
            } else {
                Circle().strokeBorder(look.circle, lineWidth: 1.4)
            }
        }
        .frame(width: 13, height: 13)
        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
        if let check, item.kind != .done {
            circle
                // Only taps take the wider target: a drag lifted there still
                // carries the block's own shape (`.interaction`).
                .contentShape(.interaction, Circle().inset(by: -10))
                .onTapGesture(perform: check)
        } else {
            circle
        }
    }
}

/// A meeting's details, as a long press on it shows them: its title, its
/// time and length, how far off it is, and where and on which calendar.
struct OLMeetingDetails: View {
    let title: String
    let start: Date
    let end: Date
    var location: String?
    var calendarTitle: String?
    let now: Date
    var calendar: Calendar = .current

    init(_ item: OLTimelineItem, now: Date, calendar: Calendar = .current) {
        self.init(title: item.title, start: item.start, end: item.end, location: item.location,
                  calendarTitle: item.calendarTitle, now: now, calendar: calendar)
    }

    init(title: String, start: Date, end: Date, location: String? = nil, calendarTitle: String? = nil, now: Date,
         calendar: Calendar = .current) {
        self.title = title
        self.start = start
        self.end = end
        self.location = location
        self.calendarTitle = calendarTitle
        self.now = now
        self.calendar = calendar
    }

    var body: some View {
        let minutes = Int((end.timeIntervalSince(start) / 60).rounded())
        VStack(alignment: .leading, spacing: 10) {
            Text(title.isEmpty ? "Busy" : title)
                .font(OLFont.rowTitleStrong)
                .foregroundStyle(OL.ink)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(OLFormat.range(start, end, calendar: calendar)) · \(OLFormat.span(minutes))")
                    .font(OLFont.note.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(OL.ink)
                Text(Self.when(start: start, end: end, now: now, calendar: calendar))
                    .font(OLFont.meta)
                    .foregroundStyle(OL.muted)
            }
            if location != nil || calendarTitle != nil {
                VStack(alignment: .leading, spacing: 6) {
                    if let location { detail("mappin.and.ellipse", location) }
                    if let calendarTitle { detail("calendar", calendarTitle) }
                }
            }
        }
        .padding(16)
        .frame(width: 300, alignment: .leading)
        .background(OL.surface)
        .accessibilityElement(children: .combine)
    }

    private func detail(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .font(OLFont.meta)
                .foregroundStyle(OL.muted)
                .frame(width: 16)
            Text(text)
                .font(OLFont.meta)
                .foregroundStyle(OL.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "In 40 min", "Now · 25 min left", "Ended 10 min ago"; on another
    /// day, the day: "Tomorrow", "Fri".
    static func when(start: Date, end: Date, now: Date, calendar: Calendar = .current) -> String {
        if !calendar.isDate(start, inSameDayAs: now), !calendar.isDate(end, inSameDayAs: now) || end <= now {
            return CompactText.day(start, now: now, calendar: calendar)
        }
        if start > now { return "In \(OLFormat.span(OLFormat.minutes(from: now, to: start)))" }
        if end > now { return "Now · \(OLFormat.span(OLFormat.minutes(from: now, to: end))) left" }
        return "Ended " + NXFormat.relative(end, now: now)
    }

    /// The details as VoiceOver reads them with the meeting: "14:00 to
    /// 15:00, Studio, 3rd floor, Work calendar".
    static func spoken(start: Date, end: Date, location: String?, calendarTitle: String?,
                       calendar: Calendar = .current) -> String {
        ["\(CompactText.clock(start, calendar: calendar)) to \(CompactText.clock(end, calendar: calendar))", location,
         calendarTitle.map { "\($0) calendar" }].compactMap(\.self).joined(separator: ", ")
    }
}

/// Where a dragged task would land: its time and title in a dashed accent
/// outline, as long as the slot it would get.
struct OLTimelineGhost: View {
    let item: OLTimelineItem

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        HStack(alignment: .top, spacing: 6) {
            if let detail = item.detail {
                Text(detail).fontWeight(.semibold).monospacedDigit().foregroundStyle(OL.accentText)
            }
            Text(item.title).foregroundStyle(OL.ink).lineLimit(1)
            Spacer(minLength: 0)
        }
        .font(OLFont.timelineBlock)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(OL.accentSoft.opacity(0.7), in: shape)
        .overlay { shape.strokeBorder(OL.accent, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])) }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The red now-line: 2 pt from 52 pt, with an 8 pt dot on its start.
struct OLNowLine: View {
    let now: Date

    var body: some View {
        Rectangle()
            .fill(OL.danger)
            .frame(height: 2)
            .overlay(alignment: .leading) {
                Circle().fill(OL.danger).frame(width: 8, height: 8).offset(x: -5)
            }
            .padding(.leading, 52)
            .accessibilityElement()
            .accessibilityLabel("Now, \(now.formatted(date: .omitted, time: .shortened))")
    }
}

/// The timeline card's canvas: the grid for `hours`, blocks where their times
/// fall and as tall as they run (at least 22 pt; a due time is a 22 pt
/// card), side by side where they overlap, in the lanes the Mac's calendar
/// lays out (`CalendarOverlapLayout`), and the now-line. 44 pt an hour,
/// blocks from 58 pt to 10 pt short of the edge, 10 pt inside the card top
/// and bottom. With `drag`, a planned or due block lifts to be dropped at
/// another time; `ghost` draws where a drop would land. A planned block's
/// long-press menu moves it a quarter hour or takes it off the calendar; a
/// meeting's shows its details.
struct OLTimeline: View {
    let items: [OLTimelineItem]
    var hours: ClosedRange<Int> = 8...19
    /// Where the now-line goes: today's time, nil on another day.
    var now: Date?
    var hourHeight: CGFloat = 44
    var calendar: Calendar = .current
    /// The day drawn, so a block running to midnight ends at 24:00.
    var day: Date?
    /// The time a meeting's details count from ("In 40 min"), on any day.
    var moment: Date?
    /// Where a dragged task would land, drawn dashed.
    var ghost: OLTimelineItem?
    /// The task being dragged, faded where it was.
    var dragging: UUID?
    var drag: ((OLTimelineItem) -> NSItemProvider)?
    /// Moves a movable block by that many minutes, VoiceOver's way to drag,
    /// and the block's long-press menu's.
    var nudge: ((OLTimelineItem, Int) -> Void)?
    /// Takes a placed block's task off the calendar, from the same menu.
    var unplace: ((OLTimelineItem) -> Void)?
    /// Ticks a block's task, from its checkbox.
    var check: ((OLTimelineItem) -> Void)?
    /// Opens a meeting where it lives, from its long-press menu.
    var openMeeting: ((OLTimelineItem) -> Void)?
    var open: (OLTimelineItem) -> Void = { _ in }

    static let inset: CGFloat = 10
    static let leading: CGFloat = 58
    static let trailing: CGFloat = 10

    var body: some View {
        let height = CGFloat(hours.count - 1) * hourHeight
        GeometryReader { proxy in
            canvas(width: max(0, proxy.size.width - Self.leading - Self.trailing))
        }
        .frame(height: height, alignment: .topLeading)
        .padding(.vertical, Self.inset)
    }

    private func canvas(width: CGFloat) -> some View {
        let frames = Self.frames(items, top: offset(of:), minimum: 22)
        return ZStack(alignment: .topLeading) {
            OLTimelineGrid(hours: hours, hourHeight: hourHeight)
            // The now-line runs between the blocks, not through their words,
            // as the Mac's does; its dot sits in the gutter, clear of them.
            if let now, let y = nowOffset(now) {
                OLNowLine(now: now).offset(y: y - 1)
            }
            ForEach(items) { item in
                if let frame = frames[item.id] {
                    placed(item, frame: frame, width: width)
                }
            }
            if let ghost {
                OLTimelineGhost(item: ghost)
                    .frame(width: width, height: max(22, offset(of: ghost.end) - offset(of: ghost.start)))
                    .offset(x: Self.leading, y: offset(of: ghost.start))
            }
        }
    }

    private func placed(_ item: OLTimelineItem, frame: OLTimelineFrame, width: CGFloat) -> some View {
        let column = (width + 2) / CGFloat(frame.count)
        let faded = item.taskID != nil && item.taskID == dragging
        return block(item, height: frame.height, width: max(0, column - 2))
            .frame(width: max(0, column - 2), height: frame.height)
            .opacity(faded ? 0.35 : 1)
            .offset(x: Self.leading + CGFloat(frame.index) * column, y: frame.top)
    }

    @ViewBuilder private func block(_ item: OLTimelineItem, height: CGFloat, width: CGFloat) -> some View {
        let tick: (() -> Void)? = item.taskID == nil ? nil : check.map { check in { check(item) } }
        let drawn = OLTimelineBlock(item: item, height: height, width: width, calendar: calendar, check: tick)
        switch item.kind {
        case .event:
            // A meeting opens nothing: a long press shows its details.
            let meeting = drawn
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Self.spoken(item, calendar: calendar))
            if let openMeeting {
                meeting
                    .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .contextMenu {
                        Button("Open in Calendar", systemImage: "calendar") { openMeeting(item) }
                    } preview: {
                        OLMeetingDetails(item, now: moment ?? now ?? item.start, calendar: calendar)
                    }
                    .accessibilityAction(named: "Open in Calendar") { openMeeting(item) }
            } else {
                meeting
            }
        case .done:
            // Done work opens nothing either, so it's drawn, not a button.
            drawn
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Self.spoken(item, calendar: calendar))
        default:
            let button = Button { open(item) } label: { drawn }
                .buttonStyle(OLRowPressStyle())
                .accessibilityLabel(Self.spoken(item, calendar: calendar))
                .accessibilityActions {
                    if let tick { Button("Complete", action: tick) }
                }
            if let drag, item.movable {
                button
                    .onDrag { drag(item) } preview: {
                        OLTimelineBlock(item: item, calendar: calendar).frame(width: 220, height: 22)
                    }
                    // Another time without a drag: a quarter hour either way,
                    // or off the calendar.
                    .contextMenu {
                        if item.placementID != nil {
                            if let nudge {
                                Button("Move 15 minutes earlier", systemImage: "arrow.up") { nudge(item, -15) }
                                Button("Move 15 minutes later", systemImage: "arrow.down") { nudge(item, 15) }
                            }
                            if let unplace {
                                Button("Take off the calendar", systemImage: "calendar.badge.minus") { unplace(item) }
                            }
                        }
                    }
                    .accessibilityHint("Drag to another time")
                    .accessibilityActions {
                        if let nudge, item.placementID != nil {
                            Button("Move 15 minutes earlier") { nudge(item, -15) }
                            Button("Move 15 minutes later") { nudge(item, 15) }
                        }
                    }
            } else {
                button
            }
        }
    }

    /// Each block's top, height and lane among those it overlaps, as the
    /// Mac's calendar arranges them (`CalendarOverlapLayout`): a run of blocks
    /// that touch shares the width, each in the first lane free, a meeting
    /// first at the same time. Each claims its whole drawn box, so a short
    /// block's one line is never drawn over by the next.
    static func frames(_ items: [OLTimelineItem], top: (Date) -> CGFloat, minimum: CGFloat) -> [String: OLTimelineFrame] {
        let laid = items.map { item -> CalendarOverlapLayout.Item in
            let y = top(item.start)
            let length: CGFloat = item.kind == .due ? 0 : top(item.end) - y
            let height = max(minimum, length)
            // Half a point short, so blocks that only touch don't share.
            return CalendarOverlapLayout.Item(id: item.id, top: Double(y), height: Double(height),
                                              end: Double(y + height - 0.5), isEvent: item.kind == .event)
        }
        return Dictionary(CalendarOverlapLayout.arrange(laid).map {
            ($0.id, OLTimelineFrame(id: $0.id, top: CGFloat($0.top), height: CGFloat($0.height), index: $0.lane,
                                    count: $0.laneCount))
        }, uniquingKeysWith: { first, _ in first })
    }

    /// What VoiceOver reads for a block: "Write interview feedback for Priya,
    /// 11:30 to 11:50, next", "Design sync, meeting, 14:00 to 15:00, Studio,
    /// Work calendar", "Pay the ryokan deposit, Due, 18:00".
    static func spoken(_ item: OLTimelineItem, calendar: Calendar = .current) -> String {
        let start = CompactText.clock(item.start, calendar: calendar)
        let range = "\(start) to \(CompactText.clock(item.end, calendar: calendar))"
        let emphasis: String? = switch item.emphasis {
        case .now: "now"
        case .next: "next"
        case .none: nil
        }
        let parts: [String?] = switch item.kind {
        case .due: [item.title, "Due", start]
        case .done: [item.title, "Done", range]
        case .working: [item.title, item.detail, range]
        case .missed: [item.title, "missed, carried forward", range]
        case .planned: [item.title, range, emphasis, item.detail]
        case .event: [item.title, "meeting", OLMeetingDetails.spoken(start: item.start, end: item.end, location: item.location,
                                                                     calendarTitle: item.calendarTitle, calendar: calendar),
                      emphasis]
        }
        return parts.compactMap(\.self).joined(separator: ", ")
    }

    /// Wall-clock hours down the grid; with `day`, anything before it at
    /// 00:00 and anything after it at 24:00.
    private func offset(of date: Date) -> CGFloat {
        let hour: Double
        if let day, date <= day {
            hour = 0
        } else if let day, !calendar.isDate(date, inSameDayAs: day) {
            hour = 24
        } else {
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            hour = Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60
        }
        return CGFloat(hour - Double(hours.lowerBound)) * hourHeight
    }

    private func nowOffset(_ now: Date) -> CGFloat? {
        let y = offset(of: now)
        return y >= 0 && y <= CGFloat(hours.count - 1) * hourHeight ? y : nil
    }
}
