//
//  WidgetCalendarFeed.swift
//  openlist
//

import Foundation

/// What the Up Next and Agenda widgets need from the calendar: the work on the
/// toolbar's timer, and each day of the week with its meetings and slots.
@MainActor
final class WidgetCalendarFeed {
    private let store: Store
    private let calendar: CalendarCoordinator
    private let settingsCalendar: () -> Calendar
    private var meetingsCache: (key: [Double], busy: [FixedBusyTime])?

    init(store: Store, calendar: CalendarCoordinator, settingsCalendar: @escaping () -> Calendar) {
        self.store = store
        self.calendar = calendar
        self.settingsCalendar = settingsCalendar
    }

    func callAsFunction(_ now: Date) -> (work: WidgetSnapshot.Work?, agenda: [WidgetSnapshot.AgendaDay]) {
        (work(now: now), agenda(now: now))
    }

    // MARK: Work

    private func work(now: Date) -> WidgetSnapshot.Work? {
        if let session = calendar.activeSession, session.endedAt == nil,
           let task = store.block(id: session.taskID), task.occurrenceID == session.occurrenceID, !task.isCompleted {
            // Stable while the work runs: the clock reads now minus this, so the
            // snapshot doesn't change, and the widget doesn't reload, each second.
            let earlier = store.workSessions(taskID: task.id)
                .filter { $0.occurrenceID == task.occurrenceID && $0.id != session.id }
                .reduce(0) { $0 + calendar.recordedMinutes(for: $1, now: now) * 60 }
            let anchor = Date(timeIntervalSinceReferenceDate: (session.startedAt.timeIntervalSinceReferenceDate - earlier).rounded())
            let slot = calendar.visibleBlocks.first { $0.isActive && $0.occurrenceID == task.occurrenceID }
            return work(task, isRunning: true, anchor: anchor, elapsed: 0,
                        slot: slot.map { ($0.start, Self.quarter(after: $0.end)) })
        }
        guard let task = calendar.resumableTask else { return nil }
        let slot = calendar.visibleBlocks.first {
            $0.occurrenceID == task.occurrenceID && !$0.isCompleted && $0.start <= now && now < $0.end
        }
        return work(task, isRunning: false, anchor: Date(timeIntervalSinceReferenceDate: 0),
                    elapsed: (calendar.trackedMinutes(for: task, now: now) * 60).rounded(.down),
                    slot: slot.map { ($0.start, $0.end) })
    }

    private func work(_ task: Block, isRunning: Bool, anchor: Date, elapsed: Double, slot: (Date, Date)?) -> WidgetSnapshot.Work {
        let list = store.list(id: task.listID)
        return WidgetSnapshot.Work(taskID: task.id, occurrenceID: task.occurrenceID, title: task.displayTitle,
                                   listName: list?.displayTitle ?? "", listIcon: list?.glyph ?? "",
                                   accent: list?.widgetAccent ?? ListAccent.graphite.rawValue, isRunning: isRunning,
                                   elapsedAnchor: anchor, pausedElapsed: elapsed, slotStart: slot?.0, slotEnd: slot?.1,
                                   estimateMinutes: calendar.estimatedMinutes(for: task))
    }

    /// The running block's end grows with the work; rounding it up to the
    /// quarter hour keeps each minute's growth from reloading the widget.
    static func quarter(after date: Date) -> Date {
        let quarter: TimeInterval = 15 * 60
        return Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / quarter).rounded(.up) * quarter)
    }

    // MARK: Agenda

    /// The settings week around today, and tomorrow when the week ends today,
    /// so entries after midnight still have a day to draw.
    private func agenda(now: Date) -> [WidgetSnapshot.AgendaDay] {
        let calendar = settingsCalendar()
        let today = calendar.startOfDay(for: now)
        let offset = (calendar.component(.weekday, from: today) - calendar.firstWeekday + 7) % 7
        guard let weekStart = calendar.date(byAdding: .day, value: -offset, to: today) else { return [] }
        let count = offset == 6 ? 8 : 7
        let days = (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
        guard let first = days.first, let last = days.last,
              let end = calendar.date(byAdding: .day, value: 1, to: last) else { return [] }
        let meetings = busyTimes(in: DateInterval(start: first, end: end))
        let placed = Set(self.calendar.visibleBlocks.compactMap(\.placementID))
        let flexible = self.calendar.plan.blocks.filter {
            !$0.isActive && $0.end > $0.start && $0.placementID.map(placed.contains) != true && $0.end > now
        }
        return days.map { day in
            let next = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            func overlaps(_ start: Date, _ end: Date) -> Bool { end > day && start < next }
            var items = meetings.filter { overlaps($0.start, $0.end) }.map { meeting in
                WidgetSnapshot.AgendaItem(id: "\(meeting.id)-\(Int(day.timeIntervalSinceReferenceDate))", kind: .meeting,
                                          title: meeting.title, start: meeting.start, end: meeting.end,
                                          isCompleted: false, isActive: false, isFlexible: false)
            }
            items += self.calendar.visibleBlocks.filter { overlaps($0.start, $0.end) }.compactMap { block(for: $0, isFlexible: false, now: now) }
            if day == today {
                items += flexible.filter { overlaps($0.start, $0.end) }.compactMap { block(for: $0, isFlexible: true, now: now) }
            }
            return WidgetSnapshot.AgendaDay(day: day, items: items.sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start })
        }
    }

    private func block(for block: PlannedBlock, isFlexible: Bool, now: Date) -> WidgetSnapshot.AgendaItem? {
        let task = store.block(id: block.taskID)
        guard let title = block.isCompleted ? block.titleSnapshot ?? task?.displayTitle : task?.displayTitle else { return nil }
        let list = store.list(id: task?.listID)
        // Work running past what the plan allows ends now, and now moves on
        // with every heartbeat: rounded, as the timer's slot is.
        let end = block.isActive ? Self.quarter(after: max(block.end, now)) : block.end
        return WidgetSnapshot.AgendaItem(id: block.id, kind: .task, title: title, start: block.start, end: end,
                                         taskID: block.taskID, occurrenceID: block.occurrenceID, listIcon: list?.glyph,
                                         listName: list?.displayTitle, accent: list?.widgetAccent ?? ListAccent.graphite.rawValue,
                                         isCompleted: block.isCompleted, isActive: block.isActive, isFlexible: isFlexible)
    }

    /// Meetings, read again only when the week or the calendars change. Events
    /// of twenty hours or more are all-day holds, not meetings, as on Calendar.
    private func busyTimes(in interval: DateInterval) -> [FixedBusyTime] {
        let source = calendar.externalCalendars
        let key = [interval.start.timeIntervalSinceReferenceDate, interval.end.timeIntervalSinceReferenceDate, Double(source.revision)]
        if let meetingsCache, meetingsCache.key == key { return meetingsCache.busy }
        let busy = source.busyTimes(in: interval).filter { $0.end.timeIntervalSince($0.start) < 20 * 3600 }
        meetingsCache = (key, busy)
        return busy
    }
}
