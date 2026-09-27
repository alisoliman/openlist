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
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
/// fall (at least 22 pt tall), and the now-line. 44 pt an hour, blocks from
/// 58 pt to 10 pt short of the edge, 10 pt inside the card top and bottom.
struct OLTimeline: View {
    let items: [OLTimelineItem]
    var hours: ClosedRange<Int> = 8...19
    var now: Date?
    var hourHeight: CGFloat = 44
    var calendar: Calendar = .current
    var open: (OLTimelineItem) -> Void = { _ in }

    var body: some View {
        let height = CGFloat(hours.count - 1) * hourHeight
        ZStack(alignment: .topLeading) {
            OLTimelineGrid(hours: hours, hourHeight: hourHeight)
            ForEach(items) { item in
                let top = offset(of: item.start)
                let blockHeight = item.kind == .working || item.kind == .event
                    ? max(22, offset(of: item.end) - top) : 22
                Button { open(item) } label: {
                    OLTimelineBlock(item: item)
                }
                .buttonStyle(OLRowPressStyle())
                .disabled(item.kind == .done || item.kind == .event)
                .frame(height: blockHeight)
                .padding(.leading, 58)
                .padding(.trailing, 10)
                .offset(y: top)
                .accessibilityLabel([item.title, item.detail].compactMap(\.self).joined(separator: ", "))
            }
            if let now, let y = nowOffset(now) {
                OLNowLine(now: now).offset(y: y - 1)
            }
        }
        .frame(height: height, alignment: .topLeading)
        .padding(.vertical, 10)
    }

    private func offset(of date: Date) -> CGFloat {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hours = Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60 - Double(self.hours.lowerBound)
        return CGFloat(hours) * hourHeight
    }

    private func nowOffset(_ now: Date) -> CGFloat? {
        let y = offset(of: now)
        return y >= 0 && y <= CGFloat(hours.count - 1) * hourHeight ? y : nil
    }
}
