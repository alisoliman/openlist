import Testing
import UIKit
@testable import OpenlistiOS

@MainActor
struct HorizontalTaskPanTests {
    @Test func backEdgeUsesTouchOriginRatherThanTheFingerAfterItMoved() {
        #expect(HorizontalTaskPan.startsAtBackEdge(locationX: 260, translationX: 255, velocityX: 500))
        #expect(HorizontalTaskPan.startsAtBackEdge(locationX: 44, translationX: 20, velocityX: 500))
        #expect(!HorizontalTaskPan.startsAtBackEdge(locationX: 45, translationX: 20, velocityX: 500))
        #expect(!HorizontalTaskPan.startsAtBackEdge(locationX: 210, translationX: 94, velocityX: 500))
        #expect(!HorizontalTaskPan.startsAtBackEdge(locationX: 4, translationX: -10, velocityX: -500))
    }

    @Test func taskPanWaitsForNativeBackButNotTheScrollViewPan() {
        let coordinator = HorizontalTaskPan.Coordinator()
        let taskPan = UIPanGestureRecognizer()
        let back = UIScreenEdgePanGestureRecognizer()
        back.edges = .left
        #expect(coordinator.gestureRecognizer(taskPan, shouldRequireFailureOf: back))
        #expect(!coordinator.gestureRecognizer(taskPan, shouldRequireFailureOf: UIPanGestureRecognizer()))
        #expect(coordinator.gestureRecognizer(taskPan, shouldRecognizeSimultaneouslyWith: back))
        #expect(!coordinator.gestureRecognizer(taskPan, shouldRecognizeSimultaneouslyWith: UIPanGestureRecognizer()))
    }
}
