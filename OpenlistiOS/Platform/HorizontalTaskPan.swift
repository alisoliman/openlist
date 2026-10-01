import SwiftUI
import UIKit

/// Recognizes horizontal motion only. A vertical drag fails before beginning,
/// leaving the enclosing native scroll view and edge-back gesture in charge.
struct HorizontalTaskPan: UIGestureRecognizerRepresentable {
    let changed: (UIGestureRecognizer.State, CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.maximumNumberOfTouches = 1
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        changed(recognizer.state, recognizer.translation(in: recognizer.view).x)
    }

    /// UIKit asks after the finger has already moved. Recover the original
    /// window position so entering a row from the screen edge never takes
    /// over a back gesture, regardless of the row's margins or current offset.
    static func startsAtBackEdge(locationX: CGFloat, translationX: CGFloat, velocityX: CGFloat) -> Bool {
        velocityX > 0 && locationX - translationX <= 24
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            if let window = pan.view?.window,
               HorizontalTaskPan.startsAtBackEdge(locationX: pan.location(in: window).x - window.bounds.minX,
                                                   translationX: pan.translation(in: window).x, velocityX: velocity.x) {
                return false
            }
            return TaskSwipeMotion.isHorizontal(x: velocity.x, y: velocity.y)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            // Our task pan waits for the native edge recognizer to fail,
            // giving navigation priority before a row can start moving.
            otherGestureRecognizer is UIScreenEdgePanGestureRecognizer
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            // SwiftUI's gesture wrapper must not cancel an edge pop when
            // the moving navigation page crosses a task row. The origin
            // check above still prevents that touch from changing the task.
            otherGestureRecognizer is UIScreenEdgePanGestureRecognizer
        }
    }
}
