//
//  OLCalendarViews.swift
//  OpenlistiOS
//

import SwiftUI

// MARK: - C29 Week strip

/// Seven days, Monday or the week-start setting's day first: the picked one
/// in the accent, today in the Today colour.
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
            .foregroundStyle(isSelected ? OL.onAccent : isToday ? OL.todayText : OL.ink)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background {
                if isSelected { RoundedRectangle(cornerRadius: 16, style: .continuous).fill(OL.accent) }
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
        /// Done today: greyed and struck through.
        case done
        /// The work on now: the accent, as tall as it runs.
        case working
        /// A task placed on the plan: `accentSoft` with its estimate.
        case planned
        /// Someone's calendar: an outline, as tall as it runs.
        case event
        /// Due at a time with no slot: `dangerSoft`, "Due".
        case due
    }

    let id: String
    var kind: Kind
    var title: String
    var start: Date
    var end: Date
    /// "20m" on a planned block, "Now · 50 min left" on the working one,
    /// "Calendar event" on an event.
    var detail: String?
    /// The task it is, for opening it; nil for a meeting.
    var taskID: UUID?
    /// The slot it draws, when it is one.
    var placementID: UUID?
    /// It can be dragged, or moved by a quarter hour, to another time.
    var movable = false
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

/// A block's look, sized by the caller.
struct OLTimelineBlock: View {
    let item: OLTimelineItem

    var body: some View {
        switch item.kind {
        case .done:
            Text(item.title)
                .font(OLFont.timelineBlock)
                .strikethrough(color: OL.muted)
                .foregroundStyle(OL.muted)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(OL.sunken, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        case .working:
            VStack(alignment: .leading) {
                Text(item.title).font(OLFont.timelineBlockStrong).lineLimit(1)
                Spacer(minLength: 0)
                if let detail = item.detail { Text(detail).font(.caption).opacity(0.9).lineLimit(1) }
            }
            .foregroundStyle(OL.onAccent)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(OL.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        case .planned, .due:
            HStack {
                Text(item.title).foregroundStyle(OL.ink).lineLimit(1)
                Spacer(minLength: 4)
                Text(item.kind == .due ? "Due" : item.detail ?? "")
                    .fontWeight(.medium)
                    .foregroundStyle(item.kind == .due ? OL.danger : OL.accentText)
            }
            .font(OLFont.timelineBlock)
            .padding(.horizontal, 8)
            // A slot longer than its line keeps the line at its top.
            .frame(maxWidth: .infinity, minHeight: 22)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(item.kind == .due ? OL.dangerSoft : OL.accentSoft,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        case .event:
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title).font(OLFont.timelineBlock).foregroundStyle(OL.ink).lineLimit(1)
                Text(item.detail ?? "Calendar event").font(.caption).foregroundStyle(OL.muted).lineLimit(1)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(OL.line, lineWidth: 1)
            }
        }
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
/// chip), side by side where they overlap, and the now-line. 44 pt an hour,
/// blocks from 58 pt to 10 pt short of the edge, 10 pt inside the card top
/// and bottom. With `drag`, a planned or due block lifts to be dropped at
/// another time; `ghost` draws where a drop would land.
struct OLTimeline: View {
    let items: [OLTimelineItem]
    var hours: ClosedRange<Int> = 8...19
    var now: Date?
    var hourHeight: CGFloat = 44
    var calendar: Calendar = .current
    /// The day drawn, so a block running to midnight ends at 24:00.
    var day: Date?
    /// Where a dragged task would land, drawn dashed.
    var ghost: OLTimelineItem?
    /// The task being dragged, faded where it was.
    var dragging: UUID?
    var drag: ((OLTimelineItem) -> NSItemProvider)?
    /// Moves a movable block by that many minutes, VoiceOver's way to drag.
    var nudge: ((OLTimelineItem, Int) -> Void)?
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
            if let now, let y = nowOffset(now) {
                OLNowLine(now: now).offset(y: y - 1)
            }
        }
    }

    private func placed(_ item: OLTimelineItem, frame: OLTimelineFrame, width: CGFloat) -> some View {
        let column = (width + 2) / CGFloat(frame.count)
        let faded = item.taskID != nil && item.taskID == dragging
        return block(item)
            .frame(width: max(0, column - 2), height: frame.height)
            .opacity(faded ? 0.35 : 1)
            .offset(x: Self.leading + CGFloat(frame.index) * column, y: frame.top)
    }

    @ViewBuilder private func block(_ item: OLTimelineItem) -> some View {
        let button = Button { open(item) } label: {
            OLTimelineBlock(item: item)
        }
        .buttonStyle(OLRowPressStyle())
        .disabled(item.kind == .done || item.kind == .event)
        .accessibilityLabel(Self.spoken(item, calendar: calendar))
        if let drag, item.movable {
            button
                .onDrag { drag(item) } preview: {
                    OLTimelineBlock(item: item).frame(width: 220, height: 22)
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

    /// Each block's top, height and column among those it overlaps: a run of
    /// blocks that touch shares the width, each in the first column free.
    static func frames(_ items: [OLTimelineItem], top: (Date) -> CGFloat, minimum: CGFloat) -> [String: OLTimelineFrame] {
        var spans: [OLTimelineFrame] = []
        for item in items {
            let y = top(item.start)
            let length: CGFloat = item.kind == .due ? 0 : top(item.end) - y
            spans.append(OLTimelineFrame(id: item.id, top: y, height: max(minimum, length)))
        }
        spans.sort { $0.top == $1.top ? $0.height > $1.height : $0.top < $1.top }
        var result: [String: OLTimelineFrame] = [:]
        var run: [OLTimelineFrame] = []
        var bottoms: [CGFloat] = []
        func close() {
            for var member in run {
                member.count = bottoms.count
                result[member.id] = member
            }
            run = []
            bottoms = []
        }
        for var span in spans {
            if let end = bottoms.max(), span.top >= end - 0.5 { close() }
            let index = bottoms.firstIndex { $0 <= span.top + 0.5 } ?? bottoms.count
            if index == bottoms.count { bottoms.append(0) }
            bottoms[index] = span.top + span.height
            span.index = index
            run.append(span)
        }
        close()
        return result
    }

    /// "Pay the ryokan deposit, Due, 18:00", "Design sync, Calendar event,
    /// 14:00 to 15:00".
    static func spoken(_ item: OLTimelineItem, calendar: Calendar = .current) -> String {
        let detail: String? = switch item.kind {
        case .due: "Due"
        case .done: "Done"
        default: item.detail
        }
        let start = CompactText.clock(item.start, calendar: calendar)
        let time = item.kind == .working || item.kind == .event
            ? "\(start) to \(CompactText.clock(item.end, calendar: calendar))" : start
        return [item.title, detail, time].compactMap(\.self).joined(separator: ", ")
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
