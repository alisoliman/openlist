//
//  OutlinePolicy.swift
//  openlist
//

import Foundation

/// The editing rules an outline follows, the list document's from the
/// design. Only tasks and list items indent, two levels deep at most, and
/// never under a heading or text, though a line turned into one keeps what
/// was under it and takes a line indented after that; Return and Backspace
/// step a line out or convert it instead of merging; `> ` makes text; done
/// top-level tasks leave the document; and a line's whole edit, from the
/// caret arriving to it leaving, is one undo step. A line left empty is
/// removed.
enum OutlinePolicy {
    /// Kinds that nest under a line of their own family.
    static func nests(_ kind: BlockKind) -> Bool {
        kind == .task || kind == .bullet || kind == .numbered
    }

    /// Kinds whose lines, folded, hide the lines under them: only tasks, as
    /// in the design. A heading folds its section instead, and a list item
    /// or text line, which draws no caret, never folds, whatever an older
    /// list or a kind change left set on it.
    static func folds(_ kind: BlockKind) -> Bool {
        kind == .task
    }

    /// The deepest a line can be indented.
    static let maximumDepth = 2

    /// Whether a line takes lines dropped into it.
    static func holdsDrops(_ row: BlockRow) -> Bool {
        nests(row.block.kind) && row.depth < maximumDepth
    }
}
