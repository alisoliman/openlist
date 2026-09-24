//
//  ActivityWidgetView.swift
//  OpenlistWidget
//

import SwiftUI
import WidgetKit

/// The Activity screen's heatmap: ten weeks at small size, twenty-one at medium.
struct ActivityWidgetView: View {
    let model: ActivityModel
    let size: WidgetSize
    @Environment(\.widgetPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 6) {
                WidgetSymbol(name: "square.grid.2x2.fill", size: 11, weight: .regular, color: palette.acc)
                    .frame(width: 13, height: 13)
                // One gap fewer than the design's spacer leaves: the system
                // face is wider than the browser's at this size. Neither text
                // is ever shortened; as in the design, a long streak runs
                // into the padding instead.
                Text("Activity")
                    .css(.sans(12, .bold), line: 1)
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(model.streak)-day streak")
                    .css(.sans(11, .semibold), line: 1)
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            heatmap.frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if size == .small {
                    stat(model.month, "in \(model.monthName)")
                } else {
                    stat(model.today, "today")
                    stat(model.week, "this week")
                    stat(model.month, "in \(model.monthName)")
                }
            }
            .lineLimit(1)
        }
    }

    private func stat(_ value: Int, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("\(value)")
                .css(.sans(11, .bold), line: 1)
                .foregroundStyle(palette.ink)
            Text(label)
                .css(.sans(10.5, .medium), line: 1)
                .foregroundStyle(palette.sub)
        }
        .fixedSize()
    }

    private var heatmap: some View {
        HStack(spacing: 3) {
            ForEach(model.weeks.indices, id: \.self) { week in
                VStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { day in
                        cell(model.weeks[week][day], isToday: week == model.weeks.count - 1 && day == model.todayIndex)
                    }
                }
            }
        }
    }

    @ViewBuilder private func cell(_ count: Int?, isToday: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 3)
        Group {
            if let count {
                if count > 0 {
                    // CSS fades the cell's today ring with the cell.
                    shape.fill(palette.acc)
                        .widgetAccentable()
                        .overlay { if isToday { shape.inset(by: -0.75).stroke(palette.ink, lineWidth: 1.5) } }
                        .opacity(ActivityModel.opacity(count))
                } else {
                    shape.fill(palette.track)
                        .overlay { if isToday { shape.inset(by: -0.75).stroke(palette.ink, lineWidth: 1.5) } }
                }
            } else {
                shape.strokeBorder(palette.line, lineWidth: 0.5)
            }
        }
        .frame(width: 10.5, height: 10.5)
    }
}
