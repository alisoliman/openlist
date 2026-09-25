//
//  AgendaWidgetView.swift
//  OpenlistWidget
//

import SwiftUI
import WidgetKit

/// Today's plan around your meetings at large size, the whole week at extra
/// large, 09:00 to 19:00 with a line at the entry's time.
struct AgendaWidgetView: View {
    let model: AgendaModel
    let size: WidgetSize
    @Environment(\.widgetPalette) private var palette

    private var isWeek: Bool { size == .xl }
    /// Points per hour.
    private var pxh: CGFloat { isWeek ? 27 : 29 }
    private var days: [AgendaModel.Day] { isWeek ? model.week : [model.today] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(isWeek ? "This week" : "Today")
                    .css(.serif(23), line: 1)
                    .foregroundStyle(palette.ink)
                Text(isWeek ? model.range : model.daySubtitle)
                    .css(.sans(10.5, .medium), line: 1)
                    .foregroundStyle(palette.sub)
                    .lineLimit(1)
            }
            .padding(.bottom, 10)
            if isWeek {
                HStack(spacing: 0) {
                    Color.clear.frame(width: 30, height: 1)
                    ForEach(days) { day in
                        Text(day.label.uppercased())
                            .tracking(9.5 * 0.05)
                            .css(.sans(9.5, .semibold), line: 1)
                            .foregroundStyle(day.isToday ? palette.acc : palette.faint)
                            .lineLimit(1)
                            .padding(.leading, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.bottom, 6)
            }
            grid
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var grid: some View {
        HStack(alignment: .top, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                ForEach([10, 12, 14, 16, 18], id: \.self) { hour in
                    Text(String(format: "%02d", hour))
                        .css(.mono(9, .medium), line: 1)
                        .foregroundStyle(palette.faint)
                        .fixedSize()
                        .offset(y: (CGFloat(hour) - 9) * pxh - 5)
                }
                .padding(.trailing, 7)
            }
            .frame(width: 30, alignment: .topTrailing)
            .frame(maxHeight: .infinity, alignment: .top)
            ForEach(days) { day in column(day) }
        }
        .frame(height: CGFloat(AgendaModel.lastHour - AgendaModel.firstHour) * pxh)
    }

    private func column(_ day: AgendaModel.Day) -> some View {
        HStack(spacing: 0) {
            Hairline()
            ZStack(alignment: .topLeading) {
                if isWeek && day.isToday { palette.chip }
                ForEach(0..<Int(AgendaModel.lastHour - AgendaModel.firstHour), id: \.self) { hour in
                    palette.line.frame(height: 0.5).offset(y: CGFloat(hour) * pxh)
                }
                ForEach(day.items.filter { $0.end > AgendaModel.firstHour && $0.start < AgendaModel.lastHour }) { item in
                    block(item)
                }
                if day.isToday, let offset = AgendaModel.nowOffset(model.nowHour, pxh: pxh) {
                    palette.red.frame(height: 1.5)
                        .overlay(alignment: .topLeading) {
                            Circle().fill(palette.red).frame(width: 6, height: 6).offset(x: -3, y: -2.25)
                        }
                        .widgetAccentable()
                        .offset(y: offset)
                        .zIndex(3)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity)
    }

    private func block(_ item: AgendaModel.Item) -> some View {
        let frame = AgendaModel.frame(start: item.start, end: item.end, pxh: pxh)
        let height = CGFloat(frame.height)
        let shape = RoundedRectangle(cornerRadius: 5)
        let showsTime = !isWeek && height >= 28
        return VStack(alignment: .leading, spacing: 1) {
            Text(item.title)
                .strikethrough(item.isDone)
                .css(.sans(isWeek ? 9 : 10.5, .semibold), line: 1.2)
                .foregroundStyle(item.isMeeting || item.isDone ? palette.sub : palette.ink)
                .lineLimit(1)
                .truncationMode(.tail)
            if showsTime {
                Text(item.timeText)
                    .css(.mono(9.5, .medium), line: 1.2)
                    .foregroundStyle(palette.faint)
                    .lineLimit(1)
            }
        }
        .padding(height < 18 ? EdgeInsets(top: 1, leading: 5, bottom: 1, trailing: 5) : EdgeInsets(top: 3, leading: 6, bottom: 3, trailing: 6))
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: height, alignment: .topLeading)
        .background {
            if item.isMeeting {
                shape.fill(palette.meet)
            } else {
                shape.fill(item.isDone ? palette.chip : palette.tint(item.accent))
                    .overlay(alignment: .leading) {
                        (item.isDone ? palette.track : palette.col(item.accent))
                            .frame(width: 2.5)
                            .widgetAccentable()
                    }
                    .clipShape(shape)
            }
        }
        .clipShape(shape)
        .padding(.horizontal, isWeek ? 2 : 5)
        .offset(y: CGFloat(frame.top))
        .zIndex(item.layer)
    }
}
