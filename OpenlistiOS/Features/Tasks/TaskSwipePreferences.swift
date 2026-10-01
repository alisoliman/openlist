import Foundation
import Observation

/// Device preferences, isolated with the rest of a review session's defaults.
@Observable
@MainActor
final class TaskSwipePreferences {
    enum Slot: String, CaseIterable {
        case first, second

        var title: String { self == .first ? "First action" : "Second action" }
    }

    private(set) var first: TaskSwipeAction
    private(set) var second: TaskSwipeAction
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = ReviewSession.defaults) {
        self.defaults = defaults
        let savedFirst = defaults.string(forKey: "phone.swipe.first").flatMap(TaskSwipeAction.init(rawValue:)) ?? .moveToList
        let savedSecond = defaults.string(forKey: "phone.swipe.second").flatMap(TaskSwipeAction.init(rawValue:)) ?? .star
        first = savedFirst
        second = savedSecond == savedFirst ? (savedFirst == .star ? .moveToList : .star) : savedSecond
    }

    func action(for slot: Slot) -> TaskSwipeAction { slot == .first ? first : second }

    /// Picking the other shortcut exchanges the slots, keeping two useful,
    /// distinct actions while preserving the user's existing choice.
    func set(_ action: TaskSwipeAction, for slot: Slot) {
        switch slot {
        case .first:
            if second == action { second = first }
            first = action
        case .second:
            if first == action { first = second }
            second = action
        }
        defaults.set(first.rawValue, forKey: "phone.swipe.first")
        defaults.set(second.rawValue, forKey: "phone.swipe.second")
    }
}
