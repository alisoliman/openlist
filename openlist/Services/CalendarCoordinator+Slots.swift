//
//  CalendarCoordinator+Slots.swift
//  openlist
//

import Foundation

extension CalendarCoordinator {
    /// The earliest free slot `minutes` long for `task` inside its list's
    /// hours, avoiding busy time and whatever the calendar shows for other
    /// tasks (their placements, running work and done blocks): in the week
    /// around today, or the next once this one has no hours left long
    /// enough, or in the week from a deferral past it. `weekCalendar` sets
    /// where a week starts.
    func freeSlot(for task: Block, minutes: Int, weekCalendar: Calendar, now: Date = .now) -> PlanSlot {
        let category = store.list(id: task.listID).flatMap { AvailabilityCategory(rawValue: $0.availabilityCategoryRaw) } ?? .work
        let busy = externalCalendars.busyTimes.map { DateInterval(start: $0.start, end: $0.end) }
            + visibleBlocks.filter { $0.taskID != task.id && $0.end > $0.start }.map { DateInterval(start: $0.start, end: $0.end) }
        return CalendarWeek.slot(duration: TimeInterval(minutes * 60), deferredUntil: task.deferredUntil, category: category,
                                 preferences: preferences, busy: busy, now: now, calendar: weekCalendar)
    }
}
