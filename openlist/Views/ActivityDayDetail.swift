import SwiftUI

struct ActivityDayDetail: View {
    let day: ActivityHeatmapDay

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(day.id, format: .dateTime.weekday(.wide).month(.wide).day().year())
                .font(.headline)
            Text(day.countDescription).font(.callout).foregroundStyle(.secondary)
            if day.completions.isEmpty {
                Text("There are no countable completion records for this date. The available history does not establish a zero.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if day.unclassifiedCount > 0 {
                Text("\(day.unclassifiedCount) completion entries have missing or conflicting details and cannot be counted reliably.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(day.completions) { completion in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: completion.wasRecurring == true ? "repeat" : "checkmark.circle")
                        .foregroundStyle(Theme.accent).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(completion.title.isEmpty ? "Untitled task" : completion.title)
                            .font(.body)
                        Text(completion.wasRecurring == true ? "Recurring occurrence" : "Task")
                            .font(.callout).foregroundStyle(.secondary)
                        if !completion.listTitle.isEmpty {
                            Text(completion.listTitle).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    Text(completion.date, format: .dateTime.hour().minute())
                        .font(.callout).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .textSelection(.enabled)
            }
            if !day.completions.isEmpty {
                Text("Titles and lists are snapshots from completion time, including tasks now in Trash or permanently deleted.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("activity-day-detail")
    }
}
