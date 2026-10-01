import Foundation

/// The two shortcuts revealed by a short right swipe. A long right swipe
/// always adds to Today, independently of these choices.
enum TaskSwipeAction: String, CaseIterable, Identifiable {
    case moveToList
    case star
    case tomorrow
    case startWorking
    case complete

    var id: String { rawValue }

    var title: String {
        switch self {
        case .moveToList: "Move to list"
        case .star: "Star"
        case .tomorrow: "Tomorrow"
        case .startWorking: "Start working"
        case .complete: "Complete"
        }
    }

    var symbol: String {
        switch self {
        case .moveToList: "folder"
        case .star: "star"
        case .tomorrow: "arrow.right"
        case .startWorking: "play"
        case .complete: "checkmark"
        }
    }
}
