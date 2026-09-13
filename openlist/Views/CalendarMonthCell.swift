import SwiftUI

struct CalendarMonthCell: View {
    let day: Date
    let calendar: Calendar
    let belongsToMonth: Bool
    let height: CGFloat
    let onOpenDay: () -> Void
    @Environment(AppEnvironment.self) private var env
    @State private var selectedCompletion: PlannedBlock?
    private var end: Date { calendar.date(byAdding: .day, value: 1, to: day) ?? day }
    private var blocks: [PlannedBlock] {
        env.calendar.visibleBlocks.filter {
            $0.start < end && ($0.end > day || ($0.isCompleted && $0.start == $0.end && $0.start >= day))
        }
    }
    private var planned: [PlannedBlock] { blocks.filter { !$0.isCompleted } }
    private var completed: [PlannedBlock] { blocks.filter(\.isCompleted) }
    private var completionCount: Int { Set(completed.map(\.occurrenceID)).count }
    private var outside: Bool { day >= env.calendar.plan.end || end <= env.calendar.plan.start }
    private var preview: [PlannedBlock] {
        // Keep both accomplishments and upcoming work visible in a compact cell.
        if let next = planned.first, let done = completed.first { return [next, done] }
        return Array(blocks.prefix(2))
    }
    private var summary: String {
        if blocks.isEmpty { return outside ? "Outside plan" : "No tasks planned" }
        return "\(planned.count) planned · \(completionCount) completed"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button(action: onOpenDay) {
                HStack {
                    Text(day.formatted(.dateTime.day())).font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(calendar.isDateInToday(day) ? .white : (belongsToMonth ? Color.primary : Theme.tertiaryText))
                        .frame(width: 25, height: 25)
                        .background(calendar.isDateInToday(day) ? Theme.accent : .clear, in: Circle())
                    Spacer(minLength: 0)
                    if env.calendar.externalCalendars.busyTimes.contains(where: { $0.start < end && $0.end > day }) {
                        Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(Theme.secondaryText)
                    }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Open day, \(day.formatted(date: .complete, time: .omitted)), \(summary)")
            Text(summary).font(.system(size: 9)).foregroundStyle(Theme.tertiaryText).lineLimit(1)
                .help(summary + (outside && !blocks.isEmpty ? " · Outside planning horizon" : ""))
            ForEach(preview) { block in
                Button {
                    if block.isCompleted { selectedCompletion = block }
                    else { env.navigator.openTask(block.taskID) }
                } label: {
                    HStack(spacing: 4) {
                        if block.isCompleted { Image(systemName: "checkmark.circle.fill").font(.system(size: 9)) }
                        else { Circle().fill(block.conflicts.isEmpty ? Theme.accent : ListAccent.orange.color).frame(width: 4, height: 4) }
                        Text(block.titleSnapshot ?? env.store.block(id: block.taskID)?.displayTitle ?? "Task")
                            .strikethrough(block.isCompleted).lineLimit(1)
                    }
                    .foregroundStyle(block.isCompleted ? Theme.secondaryText : Color.primary)
                    .font(.system(size: 10, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain)
                .help(block.isCompleted ? "Completed · \(block.isTimeTracked ? "Actual work time" : "Time not tracked"). Open occurrence history." : "Open task details")
                .accessibilityLabel("\(block.titleSnapshot ?? env.store.block(id: block.taskID)?.displayTitle ?? "Task"), \(block.isCompleted ? "completed" : "planned")")
            }
            if blocks.count > preview.count {
                Button("+\(blocks.count - preview.count) more", action: onOpenDay)
                    .buttonStyle(.plain).font(.system(size: 9)).foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(8).frame(maxWidth: .infinity).frame(height: height, alignment: .topLeading)
        .background(belongsToMonth && !outside ? Theme.canvas : Theme.chrome.opacity(0.55))
        .overlay(Rectangle().stroke(Theme.separator.opacity(0.4), lineWidth: 0.5))
        .sheet(item: $selectedCompletion) { block in
            CalendarHistoryView(taskID: block.taskID, occurrenceID: block.occurrenceID)
        }
    }
}
