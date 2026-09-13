//
//  ProgressBar.swift
//  Shared between the app and the widget extension.
//

import SwiftUI

/// A slim completion bar in a list's own colour.
///
/// `ProgressView(.linear)` ignores `.tint` on macOS, so every list's bar came
/// out the same grey. Drawing it directly keeps the accent, and keeps the app
/// and the widget looking like one product.
struct ProgressBar: View {
    let done: Int
    let total: Int
    let accent: ListAccent
    var height: CGFloat = 4
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(done) / Double(total)))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                // A finished list reads green regardless of its own colour.
                Capsule()
                    .fill(fraction >= 1 ? ListAccent.green.color : accent.color)
                    // Keep a visible nub once any progress exists.
                    .frame(width: fraction > 0 ? max(height, proxy.size.width * fraction) : 0)
            }
        }
        .frame(height: height)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: fraction)
        .accessibilityLabel("\(done) of \(total) done")
    }
}
