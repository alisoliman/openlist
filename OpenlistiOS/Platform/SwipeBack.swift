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
        // leaves the stack frozen.
        gestureRecognizer !== interactivePopGestureRecognizer || (viewControllers.count > 1 && transitionCoordinator == nil)
    }
}
