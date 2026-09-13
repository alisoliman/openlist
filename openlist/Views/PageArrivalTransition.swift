import SwiftUI

/// Animate only the arriving page's presentation. Keeping its structural
/// identity avoids resetting editors, focus, and scroll just to animate a route.
struct PageArrivalTransition: ViewModifier {
    let route: AppRoute
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: CGFloat.zero, trigger: route) { view, amount in
            view
                .opacity(reduceMotion ? 1 : 1 - amount * 0.08)
                .offset(y: reduceMotion ? 0 : amount * 5)
        } keyframes: { _ in
            MoveKeyframe(1)
            CubicKeyframe(0, duration: 0.2)
        }
    }
}
