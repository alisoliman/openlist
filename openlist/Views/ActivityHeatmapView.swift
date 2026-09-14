import SwiftUI

struct ActivityHeatmapView: View {
    let heatmap: ActivityHeatmap
    @State private var selectedDate: Date?

    private var selectedDay: ActivityHeatmapDay? {
        heatmap.days.first { $0.id == selectedDate } ?? heatmap.days.last
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sectionGap) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(heatmap.total) recorded completion\(heatmap.total == 1 ? "" : "s")")
                    .font(.title2).bold()
                    .accessibilityIdentifier("activity-total")
                Text("Last 12 weeks · \(heatmap.start.formatted(date: .abbreviated, time: .omitted)) – \(heatmap.end.formatted(date: .abbreviated, time: .omitted))")
                    .font(.callout).foregroundStyle(.secondary)
            }

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 6) {
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("Week").hidden().frame(height: 22)
                        ForEach(0..<7) { index in
                            Text(heatmap.calendar.shortWeekdaySymbols[(heatmap.calendar.firstWeekday - 1 + index) % 7])
                                .font(.callout).foregroundStyle(.secondary)
                                .frame(height: 30)
                        }
                    }
                    .accessibilityHidden(true)
                    ForEach(0..<12) { week in
                        VStack(spacing: 6) {
                            Text(heatmap.days[week * 7].id, format: .dateTime.month(.abbreviated).day())
                                .font(.caption).foregroundStyle(.secondary)
                                .frame(height: 22)
                                .accessibilityHidden(true)
                            ForEach(0..<7) { weekday in
                                let index = week * 7 + weekday
                                if index < heatmap.days.count {
                                    ActivityHeatmapCell(day: heatmap.days[index], isSelected: selectedDay?.id == heatmap.days[index].id) {
                                        selectedDate = heatmap.days[index].id
                                    }
                                } else {
                                    Color.clear.frame(width: 30, height: 30).accessibilityHidden(true)
                                }
                            }
                        }
                        .frame(width: 46)
                    }
                }
                .padding(4)
            }
            .accessibilityLabel("Daily recorded completions")
            ActivityHeatmapLegend()

            Text("A dash means history is unavailable, not zero completions.")
                .font(Theme.Font.metadata).foregroundStyle(.secondary)
            if heatmap.unclassifiedCount > 0 {
                Text("\(heatmap.unclassifiedCount) entries could not be counted because their history is incomplete or conflicting.")
                    .font(.callout).foregroundStyle(.secondary)
                    .accessibilityIdentifier("activity-incomplete")
            }
            if heatmap.total == 0 {
                ContentUnavailableView("No recorded completions", systemImage: "square.grid.3x3",
                    description: Text("Earlier or cleared history may be unavailable."))
            }
            Divider()
            if let selectedDay { ActivityDayDetail(day: selectedDay) }
            Divider()
            DisclosureGroup("About these counts") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Dates use \(heatmap.calendar.timeZone.identifier).")
                    Text("Each task counts once; repeating tasks and subtasks count once per recorded cycle. Reopening, Undo, and Redo do not add another completion.")
                    Text("Older or cleared history cannot be reconstructed, and older recurring subtasks may be undercounted. Clear History in Updates removes these records too.")
                }
                .padding(.top, 8)
            }
            .font(Theme.Font.metadata).foregroundStyle(.secondary)
        }
        .onChange(of: heatmap.start) { selectedDate = nil }
    }
}
