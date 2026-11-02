//
//  SwipeBack.swift
//  OpenlistiOS
//

import UIKit

/// Screens draw the design's own top bar and hide the navigation bar, which
/// turns off UIKit's edge swipe back. This keeps it on for every pushed
/// screen, as a native back button would have it.
///
/// Both methods are a category's, so they would replace UIKit's own if
/// UINavigationController ever gained them; `NavigationTests` fails first.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // Not mid-push or mid-pop: a swipe that starts during a transition
        // leaves the stack frozen. Nor while a mode over the page is up,
        // which a swipe would take away with the page under it.
        gestureRecognizer !== interactivePopGestureRecognizer
            || (viewControllers.count > 1 && transitionCoordinator == nil && SwipeBack.suspensions.isEmpty)
    }
}

/// Modes drawn over a pushed page (Select's), during which swiping back is
/// off: their own Done ends them, and only then does the page go back.
@MainActor
enum SwipeBack {
    private(set) static var suspensions: Set<UUID> = []

    static func suspend(_ suspended: Bool, for token: UUID) {
        if suspended { suspensions.insert(token) } else { suspensions.remove(token) }
    }
}
