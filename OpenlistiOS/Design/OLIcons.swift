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

    var path: Path {
        var path = Path()
        switch self {
        case .calendar:
            path.addRoundedRect(in: CGRect(x: 3.5, y: 5, width: 17, height: 15.5), cornerSize: CGSize(width: 2.5, height: 2.5))
            path.move(to: CGPoint(x: 3.5, y: 10)); path.addLine(to: CGPoint(x: 20.5, y: 10))
            path.move(to: CGPoint(x: 8, y: 3)); path.addLine(to: CGPoint(x: 8, y: 7))
            path.move(to: CGPoint(x: 16, y: 3)); path.addLine(to: CGPoint(x: 16, y: 7))
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
