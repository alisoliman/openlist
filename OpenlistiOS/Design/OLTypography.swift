//
//  OLTypography.swift
//  OpenlistiOS
//

import SwiftUI
import UIKit

/// The design's type roles (design-system.css), each anchored to the iOS text
/// style of the same size so it follows Dynamic Type. At the default size the
/// CSS sizes are the text styles' own: 17 body, 16 callout, 15 subheadline,
/// 13 footnote, 12 caption, 11 caption 2, 22 title 2.
enum OLFont {
    /// A screen title (`.vt`): Instrument Serif 36/40.
    static let display = OLSerif.font(size: 36, relativeTo: .largeTitle)
    /// The empty state's title: serif 28/32.
    static let displayMedium = OLSerif.font(size: 28, relativeTo: .title)

    /// 15/20 semibold: "Wednesday 23 September", "6 to triage".
    static let eyebrow = Font.subheadline.weight(.semibold)
    /// 17/22 medium: a back link, Cancel, Done (`.tlink`).
    static let link = Font.body.weight(.medium)
    static let linkStrong = Font.body.weight(.semibold)
    /// 15/20 semibold: "Starred", "Schedule" (`.gh`).
    static let groupHeader = Font.subheadline.weight(.semibold)
    /// 16/22: a row's title (`.tt`).
    static let rowTitle = Font.callout
    /// 17/22 bold: the Now card's title, a list card's name.
    static let rowTitleStrong = Font.body.weight(.bold)
    /// 13/18: `.lbl`, `.sub`, `.ts`.
    static let meta = Font.footnote
    /// 13/18 tabular: a row's trailing value (`.tr`).
    static let trailing = Font.footnote.monospacedDigit()
    /// 11/14 bold, tracked and upper-cased: "TRIAGE" (`.caps`).
    static let caps = Font.caption2.weight(.bold)
    /// 15/20 medium: a chip.
    static let chip = Font.subheadline.weight(.medium)
    /// 13 medium: a small chip.
    static let chipSmall = Font.footnote.weight(.medium)
    /// 16/20 semibold: a button.
    static let button = Font.callout.weight(.semibold)
    /// 17 semibold: Start working.
    static let buttonLarge = Font.body.weight(.semibold)
    /// 15 semibold: the capture sheet's Add, a tray's Undo.
    static let buttonSmall = Font.subheadline.weight(.semibold)
    /// 13 semibold: a segment.
    static let segment = Font.footnote.weight(.semibold)
    /// 11/18 bold: the dock's badge.
    static let badge = Font.caption2.weight(.bold)
    /// 13/18 monospaced: "10:00–11:30".
    static let mono = Font.footnote.monospaced()
    /// 11/14 monospaced: the timeline's hours.
    static let monoHour = Font.caption2.monospaced()
    /// 22/28 bold: Task detail's title.
    static let detailTitle = Font.title2.weight(.bold)
    /// 22/28: the triage card's title.
    static let triageTitle = Font.title2
    /// 20/28: the capture field.
    static let captureInput = Font.title3
    /// 15/21: a note, a tray message.
    static let note = Font.subheadline
    /// 12/16 semibold: a timeline block.
    static let timelineBlock = Font.caption.weight(.semibold)
    /// 13/18 bold: the working block's title.
    static let timelineBlockStrong = Font.footnote.weight(.bold)
    /// 11/14 semibold: a week strip's weekday.
    static let weekday = Font.caption2.weight(.semibold)
    /// 17/22 semibold: a week strip's date.
    static let weekDate = Font.body.weight(.semibold)

    /// The Working timer's minutes: 52/56 medium, tabular. `size` comes from a
    /// `@ScaledMetric` so it grows with Dynamic Type, capped by the caller.
    static func timer(size: CGFloat = 52) -> Font {
        .system(size: size, weight: .medium).monospacedDigit()
    }

    /// The tracking `.caps` asks for: 0.08 em of 11 pt.
    static let capsTracking: CGFloat = 0.88
    /// −0.02 em of the timer's 52 pt.
    static let timerTracking: CGFloat = -1.04

    /// How much taller than its CSS line box Instrument Serif lays out a
    /// single line at `size`: the face's ascent and descent run to about 1.3 em
    /// where the design's line is `lineHeight`. Half of it comes off above and
    /// below a one-line title, so the header's spacing matches the mockups.
    static func serifOverflow(size: CGFloat, lineHeight: CGFloat) -> CGFloat {
        guard OLSerif.isAvailable, let font = UIFont(name: OLSerif.fontName, size: size) else { return 0 }
        return max(0, (font.lineHeight - lineHeight) / 2)
    }
}

extension View {
    /// `.caps`: 11/14 bold, 0.08 em tracking, upper-cased.
    func olCaps() -> some View {
        font(OLFont.caps).tracking(OLFont.capsTracking).textCase(.uppercase)
    }
}
