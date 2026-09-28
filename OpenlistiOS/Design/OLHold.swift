//
//  OLHold.swift
//  OpenlistiOS
//

import SwiftUI

// MARK: - C38 Hold to confirm

/// What can't be undone asks for a hold rather than a tap: the fill runs
/// across the control for `duration`, and letting go early stops it. VoiceOver
/// activates at once, after its hint says what happens.
struct OLHoldModifier<Fill: Shape>: ViewModifier {
    var duration: Double = 0.9
    let fill: Fill
    var tint: Color = OL.danger
    let action: () -> Void
    @State private var progress: CGFloat = 0
    @Environment(\.olStyle) private var style

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    fill.fill(tint.opacity(0.18))
                        .frame(width: proxy.size.width * progress)
                }
                .clipShape(fill)
                .allowsHitTesting(false)
            }
            .onLongPressGesture(minimumDuration: duration, maximumDistance: 30) {
                progress = 0
                action()
            } onPressingChanged: { pressing in
                if pressing {
                    withAnimation(.linear(duration: duration)) { progress = 1 }
                } else {
                    withAnimation(style.fading(.easeOut(duration: 0.2))) { progress = 0 }
                }
            }
            .olFeedback(.impact, trigger: progress > 0)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }
}

extension View {
    /// Runs `action` once the view has been held for `duration`, drawing the
    /// hold as a fill across `shape`.
    func olHold<S: Shape>(_ shape: S, duration: Double = 0.9, tint: Color = OL.danger,
                          action: @escaping () -> Void) -> some View {
        modifier(OLHoldModifier(duration: duration, fill: shape, tint: tint, action: action))
    }
}
