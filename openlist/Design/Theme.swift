//
//  Theme.swift
//  openlist
//

import SwiftUI

/// Design tokens for the app: spacing, radii, typography and semantic colours.
///
/// The visual language mirrors Superlist's: a bright, low-chrome canvas, a
/// tinted sidebar, generous line height in documents, and a single violet
/// accent that carries selection and primary actions.
enum Theme {
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
        static let heading1 = SwiftUI.Font.system(size: 21, weight: .bold)
        static let heading2 = SwiftUI.Font.system(size: 17, weight: .semibold)
        static let heading3 = SwiftUI.Font.system(size: 15, weight: .semibold)
        static let body = SwiftUI.Font.system(size: 13.5, weight: .regular)
        static let sidebar = SwiftUI.Font.system(size: 13, weight: .medium)
        static let sectionHeader = SwiftUI.Font.system(size: 11, weight: .semibold)
        static let metadata = SwiftUI.Font.system(size: 11, weight: .medium)
        static let chip = SwiftUI.Font.system(size: 11, weight: .medium)
    }

    /// Font metrics used by the AppKit-backed block editor. Kept here so the
    /// SwiftUI chrome and the NSTextView content stay optically aligned.
    enum Editor {
        static let bodyPointSize: CGFloat = 13.5
        static let heading1PointSize: CGFloat = 21
        static let heading2PointSize: CGFloat = 17
        static let heading3PointSize: CGFloat = 15
        static let codePointSize: CGFloat = 12.5
        static let lineHeightMultiple: CGFloat = 1.28

        static func nsFont(for kind: BlockKind) -> NSFont {
            switch kind {
            case .heading1: .systemFont(ofSize: heading1PointSize, weight: .bold)
            case .heading2: .systemFont(ofSize: heading2PointSize, weight: .semibold)
            case .heading3: .systemFont(ofSize: heading3PointSize, weight: .semibold)
            case .code: .monospacedSystemFont(ofSize: codePointSize, weight: .regular)
            case .quote: .systemFont(ofSize: bodyPointSize, weight: .regular)
            default: .systemFont(ofSize: bodyPointSize, weight: .regular)
            }
        }

        /// Extra space above a block, used to give headings breathing room.
        static func topPadding(for kind: BlockKind) -> CGFloat {
            switch kind {
            case .heading1: 18
            case .heading2: 14
            case .heading3: 10
            case .divider: 8
            case .image: 6
            default: 0
            }
        }

        static func bottomPadding(for kind: BlockKind) -> CGFloat {
            switch kind {
            case .heading1: 4
            case .heading2: 3
            case .heading3: 2
            case .divider: 8
            case .image: 6
            default: 0
            }
        }
    }
}

// MARK: - Shared view helpers

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

/// An uppercase group heading, used above sections in panels and popovers.
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Theme.Font.sectionHeader)
            .textCase(.uppercase)
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


extension EnvironmentValues {
    /// Supplied by the page's available width, so row layout responds to an
    /// inspector/sidebar opening as well as direct window resizing.
    @Entry var compactTaskRows = false
}
