//
//  OLIcons.swift
//  OpenlistiOS
//

import SwiftUI

/// The mockups' own glyphs where the SF Symbol reads differently: stroked
/// on a 24-unit square at 1.8, with round caps (design-system.css `.i`).
nonisolated enum OLIcon: Sendable {
    /// The timeline toggle's calendar: an outline with two rings, where
    /// SF Symbols' `calendar` is a solid page of dots.
    case calendar
    /// Lists' Settings button: a small ring and eight short rays.
    case settings
    /// Reduce motion's tile: one sine wave.
    case wave
    /// Plan hours' tile and the work tile: a stopwatch.
    case stopwatch

    var path: Path {
        var path = Path()
        func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) {
            path.move(to: CGPoint(x: x1, y: y1)); path.addLine(to: CGPoint(x: x2, y: y2))
        }
        switch self {
        case .calendar:
            path.addRoundedRect(in: CGRect(x: 3.5, y: 5, width: 17, height: 15.5), cornerSize: CGSize(width: 2.5, height: 2.5))
            line(3.5, 10, 20.5, 10)
            line(8, 3, 8, 7)
            line(16, 3, 16, 7)
        case .settings:
            path.addEllipse(in: CGRect(x: 9, y: 9, width: 6, height: 6))
            line(12, 2.5, 12, 5.5); line(12, 18.5, 12, 21.5); line(2.5, 12, 5.5, 12); line(18.5, 12, 21.5, 12)
            line(5.3, 5.3, 7.4, 7.4); line(16.6, 16.6, 18.7, 18.7); line(5.3, 18.7, 7.4, 16.6); line(16.6, 7.4, 18.7, 5.3)
        case .wave:
            path.move(to: CGPoint(x: 4, y: 12))
            path.addCurve(to: CGPoint(x: 12, y: 12), control1: CGPoint(x: 7, y: 6), control2: CGPoint(x: 9, y: 6))
            path.addCurve(to: CGPoint(x: 20, y: 12), control1: CGPoint(x: 15, y: 18), control2: CGPoint(x: 17, y: 18))
        case .stopwatch:
            path.addEllipse(in: CGRect(x: 4, y: 5, width: 16, height: 16))
            path.move(to: CGPoint(x: 12, y: 9)); path.addLine(to: CGPoint(x: 12, y: 13)); path.addLine(to: CGPoint(x: 14.5, y: 15.5))
            line(9.5, 2.5, 14.5, 2.5)
        }
        return path
    }
}

/// An `OLIcon` at `size`, in the foreground style.
struct OLIconView: View {
    let icon: OLIcon
    var size: CGFloat = 22

    var body: some View {
        OLIconShape(icon: icon)
            .stroke(style: StrokeStyle(lineWidth: 1.8 * size / 24, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

nonisolated private struct OLIconShape: Shape {
    let icon: OLIcon

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        return icon.path
            .applying(CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: rect.minX / scale, y: rect.minY / scale))
    }
}
