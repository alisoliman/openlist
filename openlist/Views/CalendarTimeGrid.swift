import SwiftUI

/// Owns high-frequency scrolling state so the screen header, coverage and
/// footer do not recompute for every pixel of scrolling.
struct CalendarTimeGrid: View {
    let dates: [Date]
    let calendar: Calendar
    let hourHeight: CGFloat
    let scrollRequest: Int
    let scrollTarget: Date?
    let onOpenDay: (Date) -> Void

    @Environment(AppEnvironment.self) private var env
    @State private var scrollOffset = CGPoint.zero
    @State private var scrollPosition = ScrollPosition(idType: Int.self)
    private let gutter: CGFloat = 62
    private var firstDay: Date { dates.first ?? calendar.startOfDay(for: .now) }

    private func minutes(_ time: Date) -> CGFloat {
        CGFloat(calendar.component(.hour, from: time) * 60 + calendar.component(.minute, from: time))
    }

    var body: some View {
        GeometryReader { geometry in
            let width = max(dates.count == 7 ? 112 : 155, (geometry.size.width - gutter) / CGFloat(max(1, dates.count)))
            let contentWidth = gutter + width * CGFloat(max(1, dates.count))
            let canvasHeight = 24 * hourHeight
            let viewportHeight = max(0, geometry.size.height - 68)
            let initialY = max(0, minutes(.now) / 60 * hourHeight - 80)
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text(calendar.timeZone.abbreviation(for: firstDay) ?? "Time")
                        .font(.system(size: 9, weight: .medium)).foregroundStyle(Theme.tertiaryText)
                        .frame(width: gutter, height: 68).background(Theme.canvas)
                        .offset(x: scrollOffset.x).zIndex(2)
                    ForEach(dates, id: \.self) { day in dayHeader(day, width: width) }
                }
                .frame(width: contentWidth, height: 68, alignment: .leading)
                .offset(x: -scrollOffset.x)
                .frame(width: geometry.size.width, height: 68, alignment: .leading).clipped()
                Divider()
                ScrollView([.horizontal, .vertical]) {
                    HStack(alignment: .top, spacing: 0) {
                        timeRuler
                            .frame(width: gutter, height: canvasHeight, alignment: .topLeading)
                            .background(Theme.canvas)
                            .offset(x: scrollOffset.x).zIndex(3)
                        ForEach(dates, id: \.self) { day in
                            CalendarDayColumn(day: day, width: width, hourHeight: hourHeight,
                                              onMove: { block, location in
                                let index = Int(floor((location.x - gutter) / width))
                                guard dates.indices.contains(index), location.y >= 0, location.y < canvasHeight else { return }
                                let minutes = min(1435, max(0, Int((location.y / hourHeight * 12).rounded()) * 5))
                                guard let start = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: dates[index]) else { return }
                                env.calendar.move(block: block, to: start)
                            })
                        }
                    }.frame(width: contentWidth, height: canvasHeight, alignment: .topLeading)
                        .coordinateSpace(name: "calendarTimeline")
                }
                .defaultScrollAnchor(UnitPoint(x: 0, y: min(1, initialY / max(1, canvasHeight - viewportHeight))), for: .initialOffset)
                .defaultScrollAnchor(.topLeading, for: .alignment)
                .scrollPosition($scrollPosition)
                .onChange(of: hourHeight) { oldHeight, newHeight in
                    guard oldHeight > 0 else { return }
                    let visibleHour = max(0, scrollOffset.y) / oldHeight
                    let targetY = min(max(0, 24 * newHeight - viewportHeight), visibleHour * newHeight)
                    // Zoom keeps the same hour at the viewport's top; the 80px
                    // breathing room is only for an explicit Now/date reveal.
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        scrollPosition.scrollTo(x: max(0, scrollOffset.x), y: targetY)
                    }
                }
                .onScrollGeometryChange(for: CGPoint.self) {
                    // NavigationSplitView contributes the sidebar as a leading
                    // safe-area inset. Use the content's logical origin so the
                    // fixed ruler and scrolling dates follow the same columns.
                    CGPoint(x: max(0, $0.contentOffset.x + $0.contentInsets.leading),
                            y: max(0, $0.contentOffset.y + $0.contentInsets.top))
                } action: { _, value in scrollOffset = value }
                .task(id: scrollRequest) {
                    guard let target = scrollTarget else { return }
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    let dayIndex = max(0, calendar.dateComponents([.day], from: firstDay, to: calendar.startOfDay(for: target)).day ?? 0)
                    let x = min(max(0, contentWidth - geometry.size.width), CGFloat(dayIndex) * width)
                    let y = min(max(0, canvasHeight - viewportHeight), max(0, minutes(target) / 60 * hourHeight - 80))
                    scrollPosition.scrollTo(x: x, y: y)
                }
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
    }
    private var timeRuler: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<24) { hour in
                Text(String(format: "%02d:00", hour))
                    .font(.system(size: 10, weight: .medium, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Theme.tertiaryText).frame(width: gutter - 12, alignment: .trailing)
                    .offset(y: CGFloat(hour) * hourHeight + 3)
            }
            if dates.contains(where: { calendar.isDateInToday($0) }) {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text(context.date.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 9, weight: .bold)).monospacedDigit().foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 3)
                        .background(ListAccent.red.color, in: Capsule())
                        .frame(width: gutter - 6, alignment: .trailing)
                        .offset(y: minutes(context.date) / 60 * hourHeight - 9)
                }.allowsHitTesting(false)
            }
        }
    }
    private func dayHeader(_ day: Date, width: CGFloat) -> some View {
        let today = calendar.isDateInToday(day)
        let planned = env.calendar.plan.blocks.filter { calendar.isDate($0.start, inSameDayAs: day) }
        let total = planned.reduce(0) { $0 + $1.durationMinutes }
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86400)
        let completed = env.calendar.visibleBlocks.filter {
            $0.isCompleted && $0.start < dayEnd
                && ($0.end > day || ($0.start == $0.end && $0.start >= day))
        }
        let completionCount = Set(completed.map(\.occurrenceID)).count
        let sessionSummary = "\(planned.count) planned · \(Int(total.rounded())) min"
        let outside = day >= env.calendar.plan.end || dayEnd <= env.calendar.plan.start
        return Button { onOpenDay(day) } label: {
            VStack(spacing: completionCount > 0 ? 2 : 5) {
                HStack(spacing: 6) {
                    Text(day.formatted(.dateTime.weekday(.abbreviated))).foregroundStyle(today ? Theme.accent : Theme.secondaryText)
                    Text(day.formatted(.dateTime.day())).fontWeight(.semibold)
                        .foregroundStyle(today ? .white : Color.primary)
                        .frame(width: 25, height: 25).background(today ? Theme.accent : .clear, in: Circle())
                }.font(.system(size: 12, weight: .medium))
                Text(outside ? "Outside plan" : (planned.isEmpty ? "" : sessionSummary))
                    .font(.system(size: 9)).foregroundStyle(Theme.tertiaryText).lineLimit(1)
                    .frame(height: 12)
                if completionCount > 0 {
                    Label("\(completionCount) completed", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 9)).foregroundStyle(Theme.secondaryText).lineLimit(1)
                }
            }.frame(width: width, height: 68).contentShape(Rectangle())
        }.buttonStyle(.plain).help("Open \(day.formatted(date: .complete, time: .omitted))")
        .accessibilityLabel("Open day, \(day.formatted(date: .complete, time: .omitted)), \(sessionSummary), \(completionCount) completed")
    }

}
