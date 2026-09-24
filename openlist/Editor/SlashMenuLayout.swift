import SwiftUI

/// Anchors the Turn into card to the editable text, including indentation and row padding.
struct EditorTextBoundsKey: PreferenceKey {
    static let defaultValue: [UUID: Anchor<CGRect>] = [:]
    static func reduce(value: inout [UUID: Anchor<CGRect>], nextValue: () -> [UUID: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

enum SlashMenuLayout {
    /// Whether the list document's Turn into card, `height` tall, opens
    /// above its line rather than 6pt below it, where the design puts it.
    /// Below whenever it fits on the visible page, else above when it fits
    /// there, else on the side with more room. `line` and `viewport` share
    /// one coordinate space.
    static func cardOpensAbove(line: CGRect, height: CGFloat, viewport: CGRect) -> Bool {
        guard !viewport.isNull, !viewport.isEmpty else { return false }
        let below = viewport.maxY - line.maxY - 6
        guard below < height else { return false }
        let above = line.minY - viewport.minY - 6
        return above >= height || above > below
    }
}
