//
//  EditorTypography.swift
//  OpenlistiOS
//

import UIKit

/// The iPhone twin of the Mac's `NXEditor` (openlist/Next/NextEditorTypography.swift):
/// the list document's text metrics and ink as UIKit fonts and colours, under
/// the same names, so the shared rich-text codec and Store compile unchanged.
///
/// The sizes are the Mac's on purpose. Stored rich text drops every font that
/// matches its block's base font here, so both devices must agree on what
/// "base" is: a run the iPhone saved in a face of its own would read as
/// styling on the Mac. The iPhone's screens set their own type on top.
enum NXEditor {
    /// Tasks, bullets and numbered items: 400 13.8/1.45.
    static let bodyPointSize: CGFloat = 13.8
    /// Text and quotes: 400 13.5/1.55.
    static let textPointSize: CGFloat = 13.5
    /// 700 20/1.3.
    nonisolated static let heading1PointSize: CGFloat = 20
    /// 600 15.5/1.35.
    static let heading2PointSize: CGFloat = 15.5
    /// 600 13.8/1.45.
    static let heading3PointSize: CGFloat = 13.8
    static let codePointSize: CGFloat = 12.5
    /// Heading 1's letter-spacing, −0.01em.
    static let heading1Kern: CGFloat = -0.2

    /// Named as on the Mac, where the codec calls it; a `UIFont` here.
    static func nsFont(for kind: BlockKind) -> UIFont {
        switch kind {
        case .heading1: .systemFont(ofSize: heading1PointSize, weight: .bold)
        case .heading2: .systemFont(ofSize: heading2PointSize, weight: .semibold)
        case .heading3: .systemFont(ofSize: heading3PointSize, weight: .semibold)
        case .code: .monospacedSystemFont(ofSize: codePointSize, weight: .regular)
        case .paragraph, .quote: .systemFont(ofSize: textPointSize, weight: .regular)
        default: .systemFont(ofSize: bodyPointSize, weight: .regular)
        }
    }

    /// The design's CSS `line-height` for a kind, as a multiple of its size.
    static func lineHeightMultiple(for kind: BlockKind) -> CGFloat {
        switch kind {
        case .paragraph, .quote: 1.55
        case .heading1: 1.3
        case .heading2: 1.35
        default: 1.45
        }
    }

    /// One line box, as CSS draws it: `size × line-height`.
    static func lineHeight(for kind: BlockKind) -> CGFloat {
        nsFont(for: kind).pointSize * lineHeightMultiple(for: kind)
    }

    /// Space between wrapped lines, so they fall on the design's line pitch,
    /// with none above the first line or below the last. Rounded to the half
    /// point, so wrapped text measures whole lines. UIKit's own line height
    /// for the font stands in for the Mac's TextKit measurement.
    static func lineSpacing(for kind: BlockKind) -> CGFloat {
        (max(0, lineHeight(for: kind) - nsFont(for: kind).lineHeight) * 2).rounded() / 2
    }

    /// The inset above and below a line that grows it into the design's line
    /// box, the spare height split evenly.
    static func lineBoxInset(for kind: BlockKind) -> CGFloat {
        max(0, lineHeight(for: kind) - nsFont(for: kind).lineHeight) / 2
    }

    /// The first baseline in a line of `kind`.
    static func baselineOffset(for kind: BlockKind) -> CGFloat { nsFont(for: kind).ascender }

    // MARK: Colours

    // `NX.ink` at the strengths the editor uses. Singletons, as on the Mac:
    // attributed strings compare dynamic colours by identity.

    nonisolated static let ink = inkColor(1)
    /// Text lines and quotes.
    nonisolated static let secondaryInk = inkColor(0.66)
    nonisolated static let placeholderInk = inkColor(0.36)
    /// Completed task text.
    nonisolated static let completedInk = inkColor(0.42)
    /// The strike through completed task text.
    nonisolated static let strikeInk = inkColor(0.36)

    /// `NX.ink` (#17161A, #F1EFEC in dark mode) at `alpha`.
    private nonisolated static func inkColor(_ alpha: CGFloat) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0xF1 / 255, green: 0xEF / 255, blue: 0xEC / 255, alpha: alpha)
                : UIColor(red: 0x17 / 255, green: 0x16 / 255, blue: 0x1A / 255, alpha: alpha)
        }
    }
}
