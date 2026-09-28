//
//  MCPCalendarBridge.swift
//  openlist
//

import Foundation

/// The running calendar as the MCP calendar tools read it: the Mac's
/// calendars' busy times, and free slots found as Plan finds them.
@MainActor
final class MCPCalendarBridge: MCPCalendarAccess {
    private weak var calendar: CalendarCoordinator?
    private let settings: AppSettings

    init(calendar: CalendarCoordinator, settings: AppSettings) {
        self.calendar = calendar
        self.settings = settings
    }

    func busyTimes(in span: DateInterval) -> [FixedBusyTime] {
        calendar?.externalCalendars.busyTimes(in: span) ?? []
    }

    func freeSlot(for task: Block, minutes: Int) -> DateInterval? {
        guard case let .found(slot)? = calendar?.freeSlot(for: task, minutes: minutes, weekCalendar: settings.calendar) else { return nil }
        return slot
    }
}
