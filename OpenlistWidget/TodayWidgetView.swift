//
//  TodayWidgetView.swift
//  OpenlistWidget
//

import SwiftUI
import WidgetKit

/// What's due and overdue. Small shows two rows, medium adds the day and
/// progress on the left, large splits Overdue from Due today above a footer.
struct TodayWidgetView: View {
    let model: TodayModel
    let size: WidgetSize
    let libraryID: UUID?
    @Environment(\.widgetPalette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if size == .medium { side }
            VStack(alignment: .leading, spacing: 0) {
                if size != .medium { head }
                if model.rows.isEmpty {
                    AllClearView(subtitle: size == .small ? "Nothing due" : "Nothing due or overdue today")
                } else {
                    rows
                        .padding(.top, size == .medium ? 0 : 11)
                        .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
                        .clipped()
                }
                if size == .large {
                    WidgetFooter(addLabel: "New task", addURL: WidgetRoute.capture(listID: nil, forToday: true).url,
                                 note: "\(model.done) done today")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var lateText: String { model.late > 0 ? "\(model.late) late" : size == .medium ? "On track" : "" }

    private var lateLabel: some View {
        Text(lateText)
            .css(.sans(10.5, .semibold), line: 1)
            .foregroundStyle(model.late > 0 ? palette.red : palette.green)
            .lineLimit(1)
            .fixedSize()
    }

    /// Medium's left column: the weekday, the date and the day's progress.
    private var side: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow(title: model.weekday, color: palette.orange)
                Text(model.dayNumber)
                    .css(.serif(50), line: 0.9)
                    .foregroundStyle(palette.ink)
                    .padding(.top, 8)
                Spacer(minLength: 0)
                HStack(alignment: .center, spacing: 8) {
                    ProgressRing(progress: model.progress, diameter: 26, stroke: 3)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(model.done) of \(model.total) done")
                            .css(.sans(11, .semibold), line: 1)
                            .foregroundStyle(palette.ink)
                            .lineLimit(1)
                            .fixedSize()
                        lateLabel
                    }
                }
            }
            .frame(width: 98, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.trailing, 14)
            Hairline()
        }
        .padding(.trailing, 14)
    }

    /// Small and large: the sun, the title, the late count and the ring.
    private var head: some View {
        HStack(alignment: .center, spacing: 6) {
            WidgetSymbol(name: "sun.max.fill", size: 12, weight: .regular, color: palette.orange)
                .frame(width: 14, height: 14)
            if size == .large {
                Text("Today").css(.serif(23), line: 1).foregroundStyle(palette.ink)
            } else {
                Text("Today").css(.sans(13, .bold), line: 1).foregroundStyle(palette.ink)
            }
            Spacer(minLength: 0)
            lateLabel
            ProgressRing(progress: model.progress, diameter: 20, stroke: 3.2)
        }
    }

    @ViewBuilder private var rows: some View {
        let link = { (row: WidgetRow) in size == .small ? nil : WidgetRoute.taskURL(libraryID: libraryID, taskID: row.id) }
        VStack(alignment: .leading, spacing: size == .small ? 8 : 7) {
            if size == .large {
                let late = Array(model.lateRows.prefix(3))
                let due = Array(model.dueRows.prefix(max(0, 5 - late.count)))
                if !late.isEmpty {
                    SectionHead(title: "Overdue", color: palette.red, isFirst: true)
                    ForEach(late) { TaskRowView(row: $0, link: link($0)) }
                }
                if !model.dueRows.isEmpty {
                    SectionHead(title: "Due today", color: palette.faint, isFirst: late.isEmpty)
                    ForEach(due) { TaskRowView(row: $0, link: link($0)) }
                }
                if model.itemCount > late.count + due.count { MoreLine(count: model.itemCount - late.count - due.count) }
            } else {
                let shown = Array(model.rows.prefix(size == .small ? 2 : 3))
                ForEach(shown) { TaskRowView(row: $0, compact: size == .small, link: link($0)) }
                if model.itemCount > shown.count { MoreLine(count: model.itemCount - shown.count) }
            }
        }
    }
}
