//
//  NextNoteGlyph.swift
//  openlist
//

import AppKit
import SwiftUI

/// The one sign a row gives of its task's note: a quiet glyph after the
/// title's last word. The note itself is read and written in the task's
/// details, never in the row. A note that's only a link shows the link
/// glyph, which opens it; any other note shows the note glyph, which opens
/// the details.
struct NXNoteGlyph: View {
    enum Kind: Equatable {
        case note
        case link(URL)
    }

    /// Where the glyph sits in the title's own space.
    struct Placement: Equatable {
        let x: CGFloat
        let y: CGFloat
        /// On a line of its own under the title, which makes room for it.
        let wraps: Bool
    }

    /// The glyph's box, 2pt under the baseline of the line it ends.
    static let box: CGFloat = 13
    /// The pitch of a title's lines.
    static let linePitch = (NXEditor.lineHeight(for: .task) * 2).rounded() / 2

    static func kind(of task: Block) -> Kind? {
        let note = task.note
        guard note.contains(where: { !$0.isWhitespace }) else { return nil }
        return NoteMarkdown.soleLink(in: note).map(Kind.link) ?? .note
    }

    /// After text laid out by TextKit, as a list document's line is: 7pt on
    /// from its last word, or at the start of a line of its own when the last
    /// line has no room left for it. `topInset` is the space above the
    /// first line's TextKit line.
    static func placement(after content: NSAttributedString, width: CGFloat, topInset: CGFloat) -> Placement {
        let end = NXTextMeasure.end(of: content, width: width)
        let y = topInset + end.baseline - (box - 2)
        guard width > 1, end.x + 7 + box > width else { return Placement(x: end.x + 7, y: y, wraps: false) }
        return Placement(x: 0, y: y + linePitch, wraps: true)
    }

    /// After a screen row's title, set as `NXStrikeText` sets it at 13.8.
    static func placement(afterTitle title: String, width: CGFloat) -> Placement {
        let size: CGFloat = 13.8
        let leading = max(0, size * 1.45 - NX.lineHeight(size))
        let oneLine = NXStrikeText.lineWidth(title, size: size)
        // SwiftUI's line puts the baseline at the rounded ascender.
        if width <= 1 || oneLine + 7 + box <= width {
            return Placement(x: oneLine + 7, y: leading / 2 + titleAscender - (box - 2), wraps: false)
        }
        let key = TitleKey(title: title, width: width)
        if let placement = titlePlacements[key] { return placement }
        if titlePlacements.count >= 1024 { titlePlacements.removeAll(keepingCapacity: true) }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = leading
        let content = NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: size), .paragraphStyle: paragraph])
        let placement = placement(after: content, width: width, topInset: leading / 2)
        titlePlacements[key] = placement
        return placement
    }

    private static let titleAscender = NSFont.systemFont(ofSize: 13.8).ascender.rounded()
    private struct TitleKey: Hashable {
        var title: String
        var width: CGFloat
    }
    private static var titlePlacements: [TitleKey: Placement] = [:]

    let kind: Kind
    let placement: Placement
    /// Opens the task's details, for the note glyph.
    let openDetails: () -> Void
    @Environment(\.openURL) private var openURL
    @State private var hovering = false

    var body: some View {
        Button {
            switch kind {
            case .note: openDetails()
            case let .link(url): openURL(url)
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(hovering ? NX.ink(0.62) : NX.ink(0.3))
                .frame(width: Self.box, height: Self.box)
                // A little more than the glyph to aim at, as a row's icons have.
                .contentShape(.interaction, Rectangle().inset(by: -4))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering = $0 }
        .pointerStyle(.link)
        .help(help)
        .accessibilityLabel(help)
        .offset(x: placement.x, y: placement.y)
    }

    private var symbol: String {
        if case .link = kind { "link" } else { "text.alignleft" }
    }

    private var help: String {
        switch kind {
        case .note: "Show note"
        case let .link(url): "Open \(NoteMarkdown.shortAddress(url))"
        }
    }
}
