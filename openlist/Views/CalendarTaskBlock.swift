import SwiftUI

struct CalendarTaskBlock: View {
    let block: PlannedBlock
    let height: CGFloat
    let task: Block?
    let listAccent: Color
    let onMove: (CGPoint, CGSize) -> Void
    let onDragging: (Bool) -> Void
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    @State private var showsMove = false
    @State private var showsDeferral = false
    @State private var showsHistory = false
    @GestureState private var dragOffset = CGSize.zero
    private var title: String { block.titleSnapshot ?? task?.displayTitle ?? "Task" }
    private var accent: Color {
        if block.isCompleted { return Theme.secondaryText }
        return !block.conflicts.isEmpty ? ListAccent.orange.color : listAccent
    }
    private var duration: String { block.durationMinutes.formatted(.number.precision(.fractionLength(0))) }
    private var timeSummary: String {
        let start = block.start.formatted(date: .omitted, time: .shortened)
        if block.isCompleted {
            return block.isTimeTracked ? "\(start) · \(duration) min worked" : "\(start) · Time not tracked"
        }
        return "\(start) · \(duration) min"
    }
    private var status: String {
        if block.isCompleted { return block.isTimeTracked ? "Completed, actual work time" : "Completed, time not tracked" }
        return block.isActive ? "Working" : "Not started"
    }

    var body: some View {
        Button(action: openDetails) {
            Group {
                if height < 36 {
                    HStack(spacing: 3) {
                        if height >= 12 {
                            statusIcons
                            Text(title).strikethrough(block.isCompleted).lineLimit(1)
                            if !block.conflicts.isEmpty { Image(systemName: "exclamationmark.triangle.fill") }
                        }
                    }
                    .font(.system(size: min(11, max(8, height - 3)), weight: .medium))
                    .padding(.horizontal, 5)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .top, spacing: 3) {
                            statusIcons
                            Text(title).strikethrough(block.isCompleted)
                                .lineLimit(max(1, min(3, Int((height - 25) / 13))))
                            Spacer(minLength: 0)
                            if !block.conflicts.isEmpty { Image(systemName: "exclamationmark.triangle.fill") }
                        }
                        Text(timeSummary)
                            .font(.system(size: 10)).foregroundStyle(Theme.secondaryText).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 8).padding(.vertical, 5)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: height < 36 ? .leading : .topLeading)
            .contentShape(Rectangle())
            .clipped()
            .foregroundStyle(block.isCompleted ? Theme.secondaryText : Color.primary)
            .background(accent.opacity(block.isActive ? 0.23 : (isHovering ? 0.18 : (block.isCompleted ? 0.07 : 0.10))), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(accent.opacity(isHovering ? 0.45 : 0.12), lineWidth: 0.5))
            .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(accent.opacity(block.isCompleted ? 0.55 : 1)).frame(width: 3) }
            .shadow(color: .black.opacity(isHovering ? 0.09 : 0), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .offset(dragOffset)
        .zIndex(dragOffset == .zero ? 0 : 10)
        .highPriorityGesture(
            DragGesture(minimumDistance: 6, coordinateSpace: .named("calendarTimeline"))
                .updating($dragOffset) { value, state, _ in
                    if !block.isActive && !block.isCompleted { state = value.translation }
                }
                .onEnded { value in
                    if !block.isActive && !block.isCompleted { onMove(value.location, value.translation) }
                },
            including: block.isCompleted ? .none : .all
        )
        .onChange(of: dragOffset) { _, value in onDragging(value != .zero) }
        .onHover { isHovering = $0 }
        .animation(Theme.Motion.feedback(reduceMotion: reduceMotion), value: block.isCompleted)
        .help(([title, status, timeSummary] + block.conflicts).joined(separator: "\n"))
        .accessibilityLabel("\(title), \(block.start.formatted(date: .abbreviated, time: .shortened)), \(block.isCompleted && !block.isTimeTracked ? "time not tracked" : duration + " minutes")\(block.isPinned ? ", pinned" : "")")
        .accessibilityValue(([status] + block.conflicts).joined(separator: ". "))
        .accessibilityHint(block.isCompleted ? "Open history for this completed occurrence." : "Open task details. Drag to move, or use the context menu to start, move or pin this session.")
        .contextMenu {
            if block.isCompleted {
                Button("Occurrence history", systemImage: "clock.arrow.circlepath") { showsHistory = true }
            } else if let task {
                if block.isActive {
                    Button("Pause") { env.calendar.pause(reason: "Paused") }
                } else { Button("Start working") { _ = env.calendar.start(task: task) } }
                Button("Complete task") { env.calendar.complete(task: task) }
                Divider()
                Button("Move time…") { showsMove = true }.disabled(block.isActive)
                Button(block.isPinned ? "Unpin time" : "Pin time") {
                    if block.isPinned { env.calendar.unpin(block: block) } else { env.calendar.pin(block: block) }
                }.disabled(block.isActive)
                Button("Defer to another day…") { showsDeferral = true }
                Divider()
                Button("Task details") { env.navigator.openTask(task.id) }
            }
        }
        .popover(isPresented: $showsMove) { CalendarMovePicker(block: block) }
        .popover(isPresented: $showsDeferral) { if let task { TaskDeferralPicker(block: task) } }
        .sheet(isPresented: $showsHistory) { CalendarHistoryView(taskID: block.taskID, occurrenceID: block.occurrenceID) }
    }

    @ViewBuilder private var statusIcons: some View {
        if block.isCompleted {
            Image(systemName: "checkmark.circle.fill")
        } else {
            if block.isActive { Image(systemName: "play.fill") }
            if block.isPinned { Image(systemName: "pin.fill") }
        }
    }

    private func openDetails() {
        if block.isCompleted { showsHistory = true }
        else { env.navigator.openTask(block.taskID) }
    }
}
