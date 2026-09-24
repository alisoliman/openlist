//
//  SummaryWidgetView.swift
//  OpenlistWidget
//

import SwiftUI
import WidgetKit

/// The four counts in the display serif; medium adds this week's completions.
struct SummaryWidgetView: View {
    let model: SummaryModel
    let size: WidgetSize
    @Environment(\.widgetPalette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            main
                .frame(width: size == .medium ? 140 : nil)
                .frame(maxWidth: size == .medium ? nil : .infinity, maxHeight: .infinity, alignment: .topLeading)
            if size == .medium {
                HStack(alignment: .top, spacing: 0) {
                    Hairline()
                    week.padding(.leading, 16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var main: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 6) {
                WidgetSymbol(name: "checkmark.circle.fill", size: 11.5, weight: .regular, color: palette.acc)
                    .frame(width: 13, height: 13)
                Text("Openlist")
                    .css(.sans(12, .bold), line: 1)
                    .foregroundStyle(palette.ink)
            }
            Spacer(minLength: 0)
            Grid(alignment: .topLeading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    stat("Due today", model.due, palette.acc)
                    stat("Overdue", model.overdue, palette.red)
                }
                GridRow {
                    stat("In Inbox", model.inbox, palette.blue)
                    stat("Done", model.done, palette.green)
                }
            }
        }
    }

    /// Zero fades, so the count that matters stands out.
    private func stat(_ label: String, _ value: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(value)")
                .monospacedDigit()
                .css(.serif(size == .small ? 30 : 32), line: 0.9)
                .foregroundStyle(value > 0 ? color : palette.faint)
                .lineLimit(1)
            Text(label)
                .css(.sans(10, .medium), line: 1.1)
                .foregroundStyle(palette.sub)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var week: some View {
        let most = max(1, model.week.compactMap(\.count).max() ?? 0)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Eyebrow(title: "This week", color: palette.faint)
                Spacer(minLength: 0)
                Text("\(model.weekTotal) done")
                    .css(.sans(11, .semibold), line: 1)
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                    .fixedSize()
            }
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(model.week) { bar in
                    VStack(spacing: 5) {
                        Spacer(minLength: 0)
                        Text(bar.count.map(String.init) ?? "")
                            .monospacedDigit()
                            .css(.sans(9.5, .semibold), line: 1)
                            .foregroundStyle(bar.isToday ? palette.acc : palette.faint)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(bar.isToday ? palette.acc : bar.count == nil ? palette.track : palette.ink)
                            .opacity(bar.isToday || bar.count == nil ? 1 : 0.2)
                            .widgetAccentable(bar.isToday)
                            .frame(maxWidth: 20)
                            .frame(height: bar.count.map { max(4, (Double($0) / Double(most) * 70).rounded()) } ?? 3)
                        Text(bar.day)
                            .css(.sans(9.5, .semibold), line: 1)
                            .foregroundStyle(bar.isToday ? palette.acc : palette.faint)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(.top, 8)
            .frame(maxHeight: .infinity)
        }
    }
}
