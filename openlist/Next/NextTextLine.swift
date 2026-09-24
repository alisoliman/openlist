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
}
