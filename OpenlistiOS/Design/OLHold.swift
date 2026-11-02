//
//  OLHold.swift
//  OpenlistiOS
//

import SwiftUI

// MARK: - C38 Hold to confirm

/// What can't be undone asks for a hold rather than a tap: the fill runs
/// across the control for `duration`, and letting go early stops it.
/// VoiceOver and Voice Control, which activate rather than hold, ask in a
/// dialog instead, its destructive button beside the system's Cancel; with
/// `asksOnTap`, a plain tap asks there too.
struct OLHoldModifier<Fill: Shape>: ViewModifier {
    var duration: Double = 0.9
    let fill: Fill
    var tint: Color = OL.danger
    /// The dialog's question and its button: "Erase “Q3 notes” for good?",
    /// "Erase".
    let confirmation: String
    let confirmTitle: String
    var asksOnTap = false
    let action: () -> Void
    @State private var progress: CGFloat = 0
    @State private var confirming = false
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
            // After the hold, so it fires only once a press has let go early.
            .gesture(TapGesture().onEnded { confirming = true }, including: asksOnTap ? .all : .subviews)
            .olFeedback(.impact, trigger: progress > 0)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { confirming = true }
            .confirmationDialog(confirmation, isPresented: $confirming, titleVisibility: .visible) {
                Button(confirmTitle, role: .destructive, action: action)
            }
    }
}

extension View {
    /// Runs `action` once the view has been held for `duration`, drawing the
    /// hold as a fill across `shape`, or once `confirmation` is answered
    /// with `confirmTitle` where a hold can't be made.
    func olHold<S: Shape>(_ shape: S, duration: Double = 0.9, tint: Color = OL.danger, confirmation: String,
                          confirmTitle: String, asksOnTap: Bool = false, action: @escaping () -> Void) -> some View {
        modifier(OLHoldModifier(duration: duration, fill: shape, tint: tint, confirmation: confirmation,
                                confirmTitle: confirmTitle, asksOnTap: asksOnTap, action: action))
    }
}
