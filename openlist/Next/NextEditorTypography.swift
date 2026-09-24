//
//  NextEditorTypography.swift
//  openlist
//

import AppKit

/// The Next tokens for the list document's AppKit-backed text: font metrics
/// and `NX.ink` as NSColors, so its NSTextViews and the SwiftUI rows around
/// them stay optically aligned. It stands apart from `NX`, so the rich-text
/// codec, and the checks that build it, need none of the SwiftUI tokens.
///
/// There is one editor typography for every block: stored rich text drops
/// fonts that match these, so a face of the renderer's own would be saved
/// into the document.
enum NXEditor {
    /// Tasks, bullets and numbered items: 400 13.8/1.45, the size
    /// `NXStrikeText` sets a Next row's title in.
    static let bodyPointSize: CGFloat = 13.8
    /// Text and quotes: 400 13.5/1.55.
    static let textPointSize: CGFloat = 13.5
    /// 700 20/1.3.
    nonisolated static let heading1PointSize: CGFloat = 20
    /// 600 15.5/1.35.
    static let heading2PointSize: CGFloat = 15.5
    /// 600 13.8/1.45, a Next extra the design has no line for.
    static let heading3PointSize: CGFloat = 13.8
    static let codePointSize: CGFloat = 12.5
    /// Heading 1's letter-spacing, −0.01em.
    static let heading1Kern: CGFloat = -0.2

    static func nsFont(for kind: BlockKind) -> NSFont {
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

    /// Space between wrapped lines, so they fall on the design's line
    /// pitch. Like SwiftUI's `lineSpacing` on the Next rows, none is added
    /// above the first line or below the last, so a single line keeps
    /// TextKit's own height and never sits low in its selection highlight.
    /// Rounded to the half point, so wrapped text measures whole lines.
    static func lineSpacing(for kind: BlockKind) -> CGFloat {
        (max(0, lineHeight(for: kind) - metrics(for: kind).lineHeight) * 2).rounded() / 2
    }

    /// The inset above and below a text view's lines that grows its first
    /// line into the design's line box, the spare height split evenly as
    /// SwiftUI splits it for `NXStrikeText`. A task's first baseline then
    /// sits where a Next row's title does.
    static func lineBoxInset(for kind: BlockKind) -> CGFloat {
        max(0, lineHeight(for: kind) - metrics(for: kind).lineHeight) / 2
    }

    /// TextKit's first baseline in a line of `kind`.
    static func baselineOffset(for kind: BlockKind) -> CGFloat { metrics(for: kind).baseline }

    /// TextKit's own line height and first baseline for each kind's font,
    /// measured once.
    private static let lineMetrics: [BlockKind: (lineHeight: CGFloat, baseline: CGFloat)] = {
        let layout = NSLayoutManager()
        return Dictionary(uniqueKeysWithValues: BlockKind.allCases.map { kind in
            let font = nsFont(for: kind)
            return (kind, (layout.defaultLineHeight(for: font), layout.defaultBaselineOffset(for: font)))
        })
    }()

    private static func metrics(for kind: BlockKind) -> (lineHeight: CGFloat, baseline: CGFloat) {
        lineMetrics[kind] ?? (16, 13)
    }

    // MARK: Colours

    // `NX.ink` at the strengths the editor uses, and the accents. These
    // must stay singletons: attributed strings compare dynamic colours by
    // identity, so a colour made per call would fail every content
    // signature and restyle the text view on each update, resetting the
    // caret and IME.

    nonisolated static let ink = inkColor(1)
    /// Text lines and quotes.
    nonisolated static let secondaryInk = inkColor(0.66)
    nonisolated static let placeholderInk = inkColor(0.36)
    /// Completed task text.
    nonisolated static let completedInk = inkColor(0.42)
    /// The strike through completed task text.
    nonisolated static let strikeInk = inkColor(0.36)

    /// Next's accents, for `BlockTextView.strikeColor` while a task closes.
    /// `NextAccent.editorColor` picks the one the settings choose.
    nonisolated static let accentViolet = NSColor(srgbRed: 0x7C / 255, green: 0x4D / 255, blue: 0xF0 / 255, alpha: 1)
    nonisolated static let accentBlue = NSColor(srgbRed: 0x2F / 255, green: 0x6F / 255, blue: 0xE0 / 255, alpha: 1)
    nonisolated static let accentGreen = NSColor(srgbRed: 0x1F / 255, green: 0x8A / 255, blue: 0x6D / 255, alpha: 1)
    nonisolated static let accentOrange = NSColor(srgbRed: 0xC2 / 255, green: 0x53 / 255, blue: 0x2B / 255, alpha: 1)
    /// Links take Next's default accent.
    nonisolated static let link = accentViolet

    /// `NX.ink` (#17161A, #F1EFEC in dark mode) at `alpha`.
    private nonisolated static func inkColor(_ alpha: CGFloat) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(srgbRed: 0xF1 / 255, green: 0xEF / 255, blue: 0xEC / 255, alpha: alpha)
                : NSColor(srgbRed: 0x17 / 255, green: 0x16 / 255, blue: 0x1A / 255, alpha: alpha)
        }
    }
}
