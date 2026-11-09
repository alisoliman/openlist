import SwiftUI
import UIKit

struct OLCaptureButton: UIViewRepresentable {
    let label: String
    @Binding var isPressed: Bool
    var sayTasks: (() -> Void)?
    let typeTask: () -> Void

    func makeUIView(context: Context) -> CaptureControl { CaptureControl() }

    func updateUIView(_ control: CaptureControl, context: Context) {
        control.accessibilityLabel = label
        control.accessibilityIdentifier = "dock.capture"
        control.accessibilityHint = sayTasks == nil ? "Opens a new task with the keyboard." :
            "Tap to type a new task. Touch and hold to say tasks. Recording continues when you lift your finger."
        control.pressing = { isPressed = $0 }
        control.perform = { action in
            switch action {
            case .typed: typeTask()
            case .voice: sayTasks?()
            }
        }
        if control.hold.isEnabled != (sayTasks != nil) { control.hold.isEnabled = sayTasks != nil }
        control.accessibilityCustomActions = sayTasks == nil ? [] : [
            UIAccessibilityCustomAction(name: "Say tasks", target: control, selector: #selector(CaptureControl.accessibilitySayTasks))
        ]
    }

    final class CaptureControl: UIControl {
        var pressing: (Bool) -> Void = { _ in }
        var perform: (CapturePress.Action) -> Void = { _ in }
        private var press = CapturePress()
        private(set) lazy var hold = UILongPressGestureRecognizer(target: self, action: #selector(held))
        /// Where and when, by the touch's own clock, the press went down, and
        /// whether the finger stayed within the hold's allowance since.
        private var touchStart: (time: TimeInterval, point: CGPoint)?
        private var stayedPut = false
        private var heldLongEnough = false

        init() {
            super.init(frame: .zero)
            isAccessibilityElement = true
            accessibilityTraits = .button
            isExclusiveTouch = true
            hold.minimumPressDuration = 0.45
            hold.allowableMovement = 16
            hold.cancelsTouchesInView = false
            addGestureRecognizer(hold)
            addTarget(self, action: #selector(began), for: .touchDown)
            addTarget(self, action: #selector(endedInside), for: .touchUpInside)
            addTarget(self, action: #selector(cancelled), for: [.touchUpOutside, .touchCancel, .touchDragExit])
        }

        required init?(coder: NSCoder) { nil }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            if let touch = touches.first {
                touchStart = (touch.timestamp, touch.location(in: self))
                stayedPut = true
                heldLongEnough = false
            }
            super.touchesBegan(touches, with: event)
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            if let touch = touches.first, let touchStart {
                let point = touch.location(in: self)
                if hypot(point.x - touchStart.point.x, point.y - touchStart.point.y) > hold.allowableMovement { stayedPut = false }
            }
            super.touchesMoved(touches, with: event)
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            // Before super, which sends Touch Up Inside.
            if let touch = touches.first, let touchStart {
                heldLongEnough = stayedPut && touch.timestamp - touchStart.time >= hold.minimumPressDuration
            }
            super.touchesEnded(touches, with: event)
        }

        @objc private func began() {
            press.begin()
            pressing(true)
        }

        @objc private func endedInside() {
            let action = press.end(inside: true, heldLongEnough: heldLongEnough)
            heldLongEnough = false
            pressing(false)
            if let action { perform(action) }
        }

        @objc private func cancelled() {
            press.cancel()
            pressing(false)
        }

        @objc private func held(_ recognizer: UILongPressGestureRecognizer) {
            switch recognizer.state {
            case .began:
                if let action = press.recognizeHold() { perform(action) }
            case .ended, .cancelled:
                cancelled()
            default: break
            }
        }

        override func accessibilityActivate() -> Bool {
            cancelled()
            perform(.typed)
            return true
        }

        @objc func accessibilitySayTasks() -> Bool {
            cancelled()
            perform(.voice)
            return true
        }
    }
}
