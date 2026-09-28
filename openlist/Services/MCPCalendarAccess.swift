//
//  MCPCalendarAccess.swift
//  openlist
//

import Foundation

/// What the calendar tools read of the running calendar: the busy times of
/// the Mac's calendars, and a free slot for a task. The app's calendar
/// provides it; without one, as in the store checks, those tools say so.
@MainActor
protocol MCPCalendarAccess: AnyObject {
    func busyTimes(in span: DateInterval) -> [FixedBusyTime]
    /// The next free slot `minutes` long for `task`, as Plan finds one: around
    /// busy times and other planned work, inside its list's hours, this week
    /// or next. Nil when there's none.
    func freeSlot(for task: Block, minutes: Int) -> DateInterval?
}
