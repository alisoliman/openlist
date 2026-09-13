import Foundation

/// Assigns equal-width lanes to connected groups of rendered time intervals.
/// Rendering height participates in collisions, so short completion markers
/// remain readable without covering the next task. This never reserves time.
enum CalendarOverlapLayout {
    struct Item: Equatable {
        let id: String
        let top: Double
        let height: Double
        var bottom: Double { top + height }
    }

    struct Placement: Equatable {
        let id: String
        let top: Double
        let height: Double
        let lane: Int
        let laneCount: Int
    }

    static func arrange(_ items: [Item]) -> [Placement] {
        let ordered = items.filter { $0.top.isFinite && $0.height.isFinite && $0.height > 0 }
            .sorted {
                if $0.top != $1.top { return $0.top < $1.top }
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
                groupEnd = item.bottom
            }
            let lane = laneEnds.firstIndex(where: { $0 <= item.top }) ?? laneEnds.count
            if lane == laneEnds.count { laneEnds.append(item.bottom) }
            else { laneEnds[lane] = item.bottom }
            group.append((item, lane))
            groupEnd = max(groupEnd, item.bottom)
        }
        flush()
        return result
    }
}
