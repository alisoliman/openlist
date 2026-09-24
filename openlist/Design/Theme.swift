//
//  Theme.swift
//  openlist
//

import AppKit
import SwiftUI

/// Design tokens for the app: spacing, radii, typography and semantic colours.
///
/// The visual language mirrors Superlist's: a bright, low-chrome canvas, a
/// tinted sidebar, generous line height in documents, and a single violet
/// accent that carries selection and primary actions.
enum Theme {
    enum Motion {
        static let feedbackDuration = 0.14
        static let rearrangementDuration = 0.2

        static func allowsAnimation(reduceMotion: Bool, eventType: NSEvent.EventType?) -> Bool {
            guard !reduceMotion else { return false }
            switch eventType {
            case .leftMouseDown, .leftMouseUp, .leftMouseDragged,
                 .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp:
                return true
            default:
                return false
            }
        }

        @MainActor
        static func feedback(reduceMotion: Bool, duration: Double = feedbackDuration) -> Animation? {
            guard allowsAnimation(reduceMotion: reduceMotion, eventType: NSApp.currentEvent?.type) else { return nil }
            return .timingCurve(0.23, 1, 0.32, 1, duration: duration)
        }
    }

    // MARK: Spacing

    enum Spacing {
        /// Horizontal inset of document content from the window edge.
        static let documentGutter: CGFloat = 40
        /// Indent applied per nesting level in the editor.
        static let indentStep: CGFloat = 26
        static let rowVertical: CGFloat = 3
        static let sidebarRowHeight: CGFloat = 28
        static let sectionGap: CGFloat = 18
    }

    // MARK: Radii

    enum Radius {
        static let row: CGFloat = 7
        static let card: CGFloat = 12
        static let chip: CGFloat = 5
        static let panel: CGFloat = 14
        static let popover: CGFloat = 10
    }

    // MARK: Colours

    static let accent = ListAccent.violet.color

    /// Main document background.
    static var canvas: Color { Color(nsColor: .textBackgroundColor) }
    /// Sidebar and inspector background.
    static var chrome: Color { Color(nsColor: .windowBackgroundColor) }
    /// A quiet surface separating task content from the main document.
    static var inspector: Color { Color(nsColor: .controlBackgroundColor) }
    /// Hairline separators.
    static var separator: Color { Color(nsColor: .separatorColor) }
    /// Hover highlight on rows.
    static var rowHover: Color { Color.primary.opacity(0.045) }
    /// Selected row fill in documents.
    static var rowSelected: Color { accent.opacity(0.13) }
    /// Secondary text.
    static var secondaryText: Color { Color.secondary }
    /// Tertiary text — metadata, placeholders, counts.
    static var tertiaryText: Color { Color.secondary }
    /// Fill behind metadata chips.
    static var chipFill: Color { Color.primary.opacity(0.06) }

    // MARK: Typography

    enum Font {
        static let documentTitle = SwiftUI.Font.system(size: 28, weight: .bold, design: .default)
        static let inspectorTitle = SwiftUI.Font.system(size: 25, weight: .semibold)
        static let heading1 = SwiftUI.Font.system(size: 21, weight: .bold)
        static let heading2 = SwiftUI.Font.system(size: 17, weight: .semibold)
        static let heading3 = SwiftUI.Font.system(size: 15, weight: .semibold)
        static let body = SwiftUI.Font.system(size: 13.5, weight: .regular)
        static let sidebar = SwiftUI.Font.system(size: 13, weight: .medium)
        static let sectionHeader = SwiftUI.Font.system(size: 11, weight: .semibold)
        static let metadata = SwiftUI.Font.system(size: 11, weight: .medium)
        static let chip = SwiftUI.Font.system(size: 11, weight: .medium)
    }

    /// Font metrics and text colours used by the AppKit-backed block editor.
    /// Kept here so the SwiftUI chrome and the NSTextView content stay
    /// optically aligned.
    ///
    /// There is one editor typography for every renderer: stored rich text
    /// drops fonts that match these, so a renderer-specific face would be
    /// saved into the document. The values are the Next list document's.
    enum Editor {
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
        /// Space above and below a block's text, the default for
        /// `BlockTextView.verticalInset`. The legacy document's gutter controls
        /// are tuned to a single line padded to 20pt; a renderer drawing the
        /// design's line boxes passes ``lineBoxInset(for:)`` instead.
        static let textVerticalInset: CGFloat = 2

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

        /// Extra space above a block, used to give headings breathing room.
        static func topPadding(for kind: BlockKind) -> CGFloat {
            switch kind {
            case .heading1: 22
            case .heading2: 16
            case .heading3: 12
            case .divider: 8
            case .image: 6
            default: 0
            }
        }

        static func bottomPadding(for kind: BlockKind) -> CGFloat {
            switch kind {
            case .heading1: 6
            case .heading2: 4
            case .heading3: 2
            case .divider: 8
            case .image: 6
            default: 0
            }
        }

        // MARK: Colours

        // Next's ink at the strengths the editor uses, and its accents. These
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
}

// MARK: - Shared view helpers

struct InteractionMotion: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.transaction {
            if !Theme.Motion.allowsAnimation(reduceMotion: reduceMotion, eventType: NSApp.currentEvent?.type) {
                $0.animation = nil
                $0.disablesAnimations = true
            }
        }
    }
}

/// Native controls supply their own feedback; custom plain controls need a
/// small press response without animating keyboard or accessibility actions.
struct QuietButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let moves = Theme.Motion.allowsAnimation(reduceMotion: reduceMotion, eventType: NSApp.currentEvent?.type)
        configuration.label
            .contentShape(Rectangle())
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
            .scaleEffect(configuration.isPressed && moves ? 0.97 : 1)
            .animation(Theme.Motion.feedback(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

extension View {
    /// Standard chip styling used for due dates, labels and counts.
    func chipStyle(accent: Color? = nil) -> some View {
        self
            .font(Theme.Font.chip)
            .foregroundStyle(accent ?? Theme.secondaryText)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .fill(accent?.opacity(0.13) ?? Theme.chipFill)
            )
    }

    /// The selected/hover fill every list-like row shares, so identical-looking
    /// rows are never drawn at different corner radii.
    func rowBackground(isSelected: Bool = false, isHovering: Bool = false) -> some View {
        background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(isSelected ? Theme.rowSelected : (isHovering ? Theme.rowHover : Color.clear))
        )
    }
}

/// A quiet group heading for panels and popovers.
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Theme.Font.sectionHeader)
            .foregroundStyle(Theme.tertiaryText)
    }
}

/// A menu row that shows a tick when it is the active choice.
///
/// Menus across the app offer "pick one of these" lists; without this each one
/// hand-rolls the same `HStack { Text; if selected { checkmark } }`.
struct CheckmarkMenuItem: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    init(_ title: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                if isSelected { Image(systemName: "checkmark") }
            }
        }
    }
}
