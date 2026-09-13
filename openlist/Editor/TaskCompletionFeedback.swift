import SwiftUI

/// A small, silent acknowledgement. Only transforms/opacity animate, so the
/// checkbox never changes the row's layout while its task moves.
struct TaskCompletionFeedback: ViewModifier {
    let trigger: Int
    let accent: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Values {
        var scale: CGFloat = 1
        var ringScale: CGFloat = 1
        var ringOpacity: Double = 0
    }

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: Values(), trigger: trigger) { view, value in
            view
                .scaleEffect(reduceMotion ? 1 : value.scale)
                .overlay {
                    Circle()
                        .strokeBorder(accent, lineWidth: 1)
                        .frame(width: 18, height: 18)
                        .scaleEffect(value.ringScale)
                        .opacity(reduceMotion ? 0 : value.ringOpacity)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
        } keyframes: { _ in
            KeyframeTrack(\.scale) {
                CubicKeyframe(0.9, duration: 0.06)
                SpringKeyframe(1.16, duration: 0.15, spring: .bouncy)
                SpringKeyframe(1, duration: 0.23, spring: .smooth)
            }
            KeyframeTrack(\.ringScale) {
                LinearKeyframe(1, duration: 0.06)
                CubicKeyframe(1.7, duration: 0.32)
            }
            KeyframeTrack(\.ringOpacity) {
                LinearKeyframe(0.38, duration: 0.06)
                CubicKeyframe(0, duration: 0.32)
            }
        }
    }
}
