//
//  EmojiSize.swift
//  Shared between the app and the widget extension.
//

import CoreGraphics

/// The point size a list's colour emoji takes to draw as large as the design
/// draws it at a CSS size.
nonisolated enum EmojiSize {
    /// Core Text draws small colour emoji a few points larger than the design's
    /// browser does at the same size (12pt comes out 15pt wide, not 13), and the
    /// two agree again from 24pt. Measured pairs, interpolated.
    static func points(forDesign size: CGFloat) -> CGFloat {
        let table: [(design: CGFloat, native: CGFloat)] = [(11, 9.3), (12, 10), (13, 11), (16, 13.5), (20, 16), (24, 24)]
        guard size < 24 else { return size }
        guard let upper = table.firstIndex(where: { $0.design >= size }), upper > 0 else {
            return size - (table[0].design - table[0].native)
        }
        let (a, b) = (table[upper - 1], table[upper])
        return a.native + (size - a.design) / (b.design - a.design) * (b.native - a.native)
    }
}
