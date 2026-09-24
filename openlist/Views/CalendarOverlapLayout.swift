import Foundation

/// Assigns equal-width lanes to connected groups of calendar items. Items
/// collide over their times, as the design's lanes do, so one starting when
/// another ends keeps the full width and covers what a minimum height drew
/// past that end. An item can claim its whole drawn box instead, so a short
/// one that mustn't be covered stays readable. This never reserves time.
enum CalendarOverlapLayout {
    struct Item: Equatable {
        let id: String
        let top: Double
        let height: Double
        /// Where the item stops colliding with the ones after it: the end of
        /// its time, which may fall short of its drawn bottom, or be its top
        /// for an item with no length. Its drawn bottom when none is given.
        let end: Double
        /// A meeting, which goes before a block with the same times, as the
        /// design's list of meetings then blocks does.
        let isEvent: Bool
        var bottom: Double { top + height }

        init(id: String, top: Double, height: Double, end: Double? = nil, isEvent: Bool = false) {
            self.id = id
            self.top = top
            self.height = height
            self.end = end.flatMap { $0 >= top ? $0 : nil } ?? top + height
            self.isEvent = isEvent
        }

        /// A meeting, drawn at least 16pt tall, over its time.
        static func event(_ event: FixedBusyTime, y: (Date) -> Double) -> Item {
            Item(id: event.id, top: y(event.start) + 1, height: max(16, y(event.end) - y(event.start) - 2),
                 end: y(event.end) + 1, isEvent: true)
        }

        /// A block, drawn at least 18pt tall. One on a slot, planned, running
        /// there or done in it, collides over its time, as the design's
        /// placements do. Recorded work the design never draws, time tracked
        /// outside any slot or work running or paused with none, keeps its
        /// whole box, so a few minutes of it don't go under the next block.
        static func block(_ block: PlannedBlock, y: (Date) -> Double) -> Item {
            Item(id: block.id, top: y(block.start) + 1, height: max(18, y(block.end) - y(block.start) - 2),
                 end: block.placementID != nil || block.keepsSlot ? y(block.end) + 1 : nil)
        }
    }

    struct Placement: Equatable {
        let id: String
        let top: Double
        let height: Double
        let lane: Int
        let laneCount: Int
    }

    static func arrange(_ items: [Item]) -> [Placement] {
        let ordered = items.filter { $0.top.isFinite && $0.height.isFinite && $0.height > 0 && $0.end.isFinite }
            .sorted {
                if $0.top != $1.top { return $0.top < $1.top }
                if $0.end != $1.end { return $0.end > $1.end }
                if $0.isEvent != $1.isEvent { return $0.isEvent }
                if $0.height != $1.height { return $0.height > $1.height }
                return $0.id < $1.id
            }
        var result: [Placement] = []
        var group: [(item: Item, lane: Int)] = []
        var laneEnds: [Double] = []
        var groupEnd = -Double.infinity

        func flush() {
            result += group.map {
                Placement(id: $0.item.id, top: $0.item.top, height: $0.item.height,
                          lane: $0.lane, laneCount: laneEnds.count)
            }
            group.removeAll(keepingCapacity: true)
            laneEnds.removeAll(keepingCapacity: true)
        }

        for item in ordered {
            if item.top >= groupEnd {
                flush()
                groupEnd = item.end
            }
            let lane = laneEnds.firstIndex(where: { $0 <= item.top }) ?? laneEnds.count
            if lane == laneEnds.count { laneEnds.append(item.end) }
            else { laneEnds[lane] = item.end }
            group.append((item, lane))
            groupEnd = max(groupEnd, item.end)
        }
        flush()
        return result
    }
}

// MARK: - The day column's clock

extension CalendarOverlapLayout {
    /// `time`'s wall-clock hour on `day`, fractional, where the day column
    /// draws it against its hour labels and now line: 10:40 is 10.67 on a day
    /// the clocks change too, where the time since midnight is an hour more
    /// or less. Past midnight it goes on counting, 24 and up.
    static func hours(_ time: Date, on day: Date, calendar: Calendar) -> Double {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: day), to: calendar.startOfDay(for: time)).day ?? 0
        let parts = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: time)
        let seconds = Double(parts.second ?? 0) + Double(parts.nanosecond ?? 0) / 1_000_000_000
        return Double(24 * days + (parts.hour ?? 0)) + Double(parts.minute ?? 0) / 60 + seconds / 3600
    }

    /// The moment the clock reads `minute` after midnight on `day`, as the
    /// planner reads the work hours: a time the clocks skip is the next one
    /// there is, and 24:00 is the next midnight.
    static func time(minute: Int, on day: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: day)
        let next = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        let minute = min(max(minute, 0), 1440)
        guard minute < 1440 else { return next }
        return calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: start,
                             matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward) ?? next
    }
}
