import Foundation

/// Distance, never flick velocity, decides between revealing shortcuts and
/// committing an action: a commit needs the finger to travel its distance
/// and the row to get there. A release's velocity only picks where an
/// uncommitted row comes to rest. Kept independent of gestures so
/// boundaries are tested.
nonisolated enum TaskSwipeMotion {
    enum Result: Equatable {
        case closed, shortcuts, delete, today, trash
    }

    static let shortcutsWidth: CGFloat = 108
    static let deleteWidth: CGFloat = 64
    static let revealDistance: CGFloat = 38

    static func todayDistance(width: CGFloat) -> CGFloat { max(180, width * 0.58) }
    static func trashDistance(width: CGFloat) -> CGFloat { max(148, width * 0.5) }

    static func isHorizontal(x: CGFloat, y: CGFloat) -> Bool { abs(x) > abs(y) * 1.3 }

    /// How much further a release at `velocity`, in points a second, carries
    /// the row: where a scroll view slowing at UIKit's fast rate would stop
    /// (WWDC18's `project`).
    static func projection(of velocity: CGFloat) -> CGFloat {
        let rate: CGFloat = 0.99
        return velocity / 1000 * rate / (1 - rate)
    }

    static func result(translation: CGFloat, origin: CGFloat = 0, width: CGFloat,
                       allowsToday: Bool = true, velocity: CGFloat = 0) -> Result {
        let offset = origin + translation
        let today = todayDistance(width: width), trash = trashDistance(width: width)
        if allowsToday, translation >= today, offset >= today { return .today }
        if translation <= -trash, offset <= -trash { return .trash }
        // A flick back closes a row open on one side, rather than swinging it
        // open on the other.
        var resting = offset + projection(of: velocity)
        if offset * resting < 0 { resting = 0 }
        if resting >= revealDistance { return .shortcuts }
        if resting <= -revealDistance { return .delete }
        return .closed
    }
}
