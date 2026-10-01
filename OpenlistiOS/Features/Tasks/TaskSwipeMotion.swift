import Foundation

/// Distance, never flick velocity, decides between revealing shortcuts and
/// committing an action. Kept independent of gestures so boundaries are tested.
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

    static func result(translation: CGFloat, origin: CGFloat = 0, width: CGFloat,
                       allowsToday: Bool = true) -> Result {
        if allowsToday, translation >= todayDistance(width: width) { return .today }
        if translation <= -trashDistance(width: width) { return .trash }
        let offset = origin + translation
        if offset >= revealDistance { return .shortcuts }
        if offset <= -revealDistance { return .delete }
        return .closed
    }
}
