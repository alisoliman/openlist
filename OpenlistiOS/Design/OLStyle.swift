//
//  OLStyle.swift
//  OpenlistiOS
//

import SwiftUI

/// The per-device settings every component reads while it draws, set once at
/// the root from `AppSettings` and the system's accessibility settings.
struct OLStyle: Equatable {
    /// The in-app Reduce motion toggle or the system's: either drops slides,
    /// springs and scale, keeping state changes as fades.
    var reduceMotion = false
    /// The Haptics toggle.
    var haptics = true
    /// The undo window: how long a ticked task dwells before it's written, 2–8 s.
    var dwell: Double = 5

    /// `animation`, or none under Reduce motion.
    func animation(_ animation: Animation) -> Animation? { reduceMotion ? nil : animation }

    /// `animation`, or a short fade under Reduce motion, for changes that
    /// should still be seen to happen.
    func fading(_ animation: Animation) -> Animation { reduceMotion ? .easeOut(duration: 0.15) : animation }

    /// The design's curves (design-system.css).
    static let checkbox = Animation.easeOut(duration: 0.2)
    static let progress = Animation.timingCurve(0.2, 0.9, 0.2, 1, duration: 0.56)
    static let fold = Animation.easeOut(duration: 0.16)
    static let press = Animation.snappy(duration: 0.15)
}

extension EnvironmentValues {
    @Entry var olStyle = OLStyle()
}

extension View {
    /// Plays `feedback` when `trigger` changes, if the Haptics setting is on.
    func olFeedback<T: Equatable>(_ feedback: SensoryFeedback, trigger: T) -> some View {
        modifier(OLFeedback(feedback: feedback, trigger: trigger, condition: nil))
    }

    /// Plays `feedback` when `trigger` changes and `condition` holds for the
    /// old and new values, if the Haptics setting is on.
    func olFeedback<T: Equatable>(_ feedback: SensoryFeedback, trigger: T,
                                  condition: @escaping (T, T) -> Bool) -> some View {
        modifier(OLFeedback(feedback: feedback, trigger: trigger, condition: condition))
    }

    /// `animation` tied to `value`, dropped under Reduce motion.
    func olAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(OLAnimation(animation: animation, value: value))
    }
}

private struct OLFeedback<T: Equatable>: ViewModifier {
    let feedback: SensoryFeedback
    let trigger: T
    let condition: ((T, T) -> Bool)?
    @Environment(\.olStyle) private var style

    func body(content: Content) -> some View {
        content.sensoryFeedback(feedback, trigger: trigger) { old, new in
            style.haptics && (condition?(old, new) ?? true)
        }
    }
}

private struct OLAnimation<V: Equatable>: ViewModifier {
    let animation: Animation
    let value: V
    @Environment(\.olStyle) private var style

    func body(content: Content) -> some View {
        content.animation(style.animation(animation), value: value)
    }
}
