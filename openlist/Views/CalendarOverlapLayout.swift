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
        /// its time, which may fall short of its drawn bottom. Its drawn bottom
        /// when none is given, and for an item with no time of its own.
        let end: Double
        var bottom: Double { top + height }

        init(id: String, top: Double, height: Double, end: Double? = nil) {
            self.id = id
            self.top = top
            self.height = height
            self.end = end.flatMap { $0 > top ? $0 : nil } ?? top + height
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
