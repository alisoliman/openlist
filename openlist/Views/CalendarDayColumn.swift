import SwiftUI

struct CalendarDayColumn: View {
    let day: Date
    let width: CGFloat
    let hourHeight: CGFloat
    let onMove: (PlannedBlock, CGPoint) -> Void
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDragging = false
    private var calendar: Calendar { .current }
    private var end: Date { calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86400) }
    private var blocks: [PlannedBlock] {
        env.calendar.visibleBlocks.filter {
            $0.start < end && ($0.end > day || ($0.isCompleted && $0.start == $0.end && $0.start >= day))
        }
    }
    private var completedIDs: [String] { blocks.filter(\.isCompleted).map(\.id).sorted() }
    private var placements: [CalendarOverlapLayout.Placement] {
        CalendarOverlapLayout.arrange(blocks.map { block in
            let top = y(max(day, block.start))
            let minimum: CGFloat = block.isCompleted && block.durationMinutes == 0 ? 38 : 20
            let height = max(minimum, y(min(end, block.end)) - top - 1)
            // Keep late-night markers inside the canvas; their labels retain
            // the actual timestamp, and the rendered frame still gets a lane.
            return .init(id: block.id, top: Double(min(top, 24 * hourHeight - height)), height: Double(height))
        })
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            availabilityBackground(.work)
            availabilityBackground(.personal)
            ForEach(0..<24) { hour in
                Rectangle().fill(Theme.separator.opacity(0.48)).frame(height: 0.5).offset(y: CGFloat(hour) * hourHeight)
                Rectangle().fill(Theme.separator.opacity(0.18)).frame(height: 0.5).offset(y: (CGFloat(hour) + 0.5) * hourHeight)
            }
            ForEach(env.calendar.externalCalendars.busyTimes.filter { $0.start < end && $0.end > day }) { busy in
                VStack(alignment: .leading, spacing: 3) {
                    Label(busy.title, systemImage: "lock.fill").lineLimit(2)
                    Text("Busy · \(busy.start.formatted(date: .omitted, time: .shortened))").lineLimit(1)
                }
                .font(.system(size: 10)).foregroundStyle(Theme.secondaryText)
                .padding(5).frame(width: width - 8, height: max(3, y(min(end, busy.end)) - y(max(day, busy.start))), alignment: .topLeading)
                .clipped()
                .background(Theme.chipFill, in: RoundedRectangle(cornerRadius: 5))
                .offset(x: 4, y: y(max(day, busy.start)))
                .help("\(busy.title) · Fixed busy time from a connected calendar")
            }
            ForEach(placements, id: \.id) { placement in
                if let block = blocks.first(where: { $0.id == placement.id }) {
                    let height = CGFloat(placement.height)
                    let laneWidth = (width - 10) / CGFloat(placement.laneCount)
                    let task = env.store.block(id: block.taskID)
                    let listAccent = env.store.list(id: task?.listID)?.accent.color ?? Theme.accent
                    CalendarTaskBlock(block: block, height: height, task: task, listAccent: listAccent,
                                      onMove: { location, translation in
                                          // Preserve where the card was grabbed, so its final
                                          // placement matches the preview before five-minute snapping.
                                          onMove(block, CGPoint(x: location.x, y: y(max(day, block.start)) + translation.height))
                                      }, onDragging: { isDragging = $0 })
                        .frame(width: max(1, laneWidth - (placement.laneCount > 1 ? 3 : 0)), height: height)
                        .offset(x: 5 + CGFloat(placement.lane) * laneWidth, y: CGFloat(placement.top))
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97)))
                        .animation(Theme.Motion.feedback(reduceMotion: reduceMotion, duration: Theme.Motion.rearrangementDuration), value: block.start)
                        .animation(Theme.Motion.feedback(reduceMotion: reduceMotion, duration: Theme.Motion.rearrangementDuration), value: block.end)
                }
            }
            if calendar.isDateInToday(day) {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    HStack(spacing: 0) {
                        Circle().fill(ListAccent.red.color).frame(width: 6, height: 6)
                        Rectangle().fill(ListAccent.red.color.opacity(0.85)).frame(height: 1)
                    }.offset(y: y(context.date) - 3)
                }.allowsHitTesting(false)
            }
        }
        .frame(width: width, height: 24 * hourHeight, alignment: .topLeading)
        .background(Theme.chrome.opacity(0.22))
        .overlay(alignment: .leading) { Rectangle().fill(Theme.separator.opacity(0.45)).frame(width: 0.5) }
        .zIndex(isDragging ? 10 : 0)
        .animation(Theme.Motion.feedback(reduceMotion: reduceMotion, duration: Theme.Motion.rearrangementDuration), value: completedIDs)
    }
    private func availabilityBackground(_ category: AvailabilityCategory) -> some View {
        let windows = availableWindows(category)
        let color = category == .work ? ListAccent.blue.color : ListAccent.green.color
        return ForEach(Array(windows.enumerated()), id: \.offset) { _, window in
            Rectangle().fill(color.opacity(0.045))
                .frame(width: width, height: CGFloat(window.endMinute - window.startMinute) / 60 * hourHeight)
                .overlay(alignment: .leading) { Rectangle().fill(color.opacity(0.22)).frame(width: 2) }
                .offset(y: CGFloat(window.startMinute) / 60 * hourHeight)
                .allowsHitTesting(false)
        }
    }
    private func availableWindows(_ category: AvailabilityCategory) -> [AvailabilityWindow] {
        let profile = env.calendar.preferences.profile(for: category)
        let weekday = calendar.component(.weekday, from: day)
        let override = profile.overrides.last { calendar.isDate($0.date, inSameDayAs: day) }
        var windows = override?.windows ?? profile.weekly[weekday] ?? []
        let breaks = override?.breaks ?? profile.breaks[weekday] ?? []
        for pause in breaks {
            windows = windows.flatMap { window -> [AvailabilityWindow] in
                if pause.endMinute <= window.startMinute || pause.startMinute >= window.endMinute { return [window] }
                var pieces: [AvailabilityWindow] = []
                if pause.startMinute > window.startMinute { pieces.append(AvailabilityWindow(startMinute: window.startMinute, endMinute: pause.startMinute)) }
                if pause.endMinute < window.endMinute { pieces.append(AvailabilityWindow(startMinute: pause.endMinute, endMinute: window.endMinute)) }
                return pieces
            }
        }
        return windows.filter { $0.endMinute > $0.startMinute }
    }
    private func y(_ date: Date) -> CGFloat {
        if date >= end { return 24 * hourHeight }
        let values = calendar.dateComponents([.hour, .minute], from: date)
        return (CGFloat(values.hour ?? 0) + CGFloat(values.minute ?? 0) / 60) * hourHeight
    }
}
