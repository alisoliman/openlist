//
//  NextTextLine.swift
//  openlist
//

import AppKit

extension NX {
    /// The height SwiftUI gives one line of the system font at `size`, SF
    /// Mono's too, which the design's CSS line boxes are fitted over: whole
    /// points, the ascender rounded and the descender rounded up (12pt → 15,
    /// 10.5 → 13), not the font's fractional ascent and descent. Measured to
    /// match from 8 to 23.5pt, 21.25 aside, and at the header title's 27;
    /// from 24pt it otherwise comes out a point over. The one line helper:
    /// Tools/LineHeightChecks keeps it to SwiftUI's own line.
    static func lineHeight(_ size: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: size)
        return font.ascender.rounded() + (-font.descender).rounded(.up)
    }

    /// The height SwiftUI gives one line of Instrument Serif, the serif
    /// titles' face, at `size`: whole points again, its ascender and
    /// descender each rounded (22pt → 29, 34 → 45), not their fractional sum
    /// (28.6, 44.2). Measured to match at every whole point from 10 to 48,
    /// the sizes the titles use; half points come out a point or two over.
    /// Nil while the face isn't registered.
    static func serifLineHeight(_ size: CGFloat) -> CGFloat? {
        guard let font = NSFont(name: "InstrumentSerif-Regular", size: size) else { return nil }
        return font.ascender.rounded() + (-font.descender).rounded()
    }
}
