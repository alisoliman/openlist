import SwiftUI

/// Anchors the popup to the editable text, including indentation and row padding.
struct EditorTextBoundsKey: PreferenceKey {
    static let defaultValue: [UUID: Anchor<CGRect>] = [:]
    static func reduce(value: inout [UUID: Anchor<CGRect>], nextValue: () -> [UUID: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

enum SlashMenuLayout {
    /// Both inputs use native text-view coordinates. Clip to the visible editor,
    /// choosing above the caret when there is more space there.
    static func frame(caret: CGRect, viewport: CGRect, preferredHeight: CGFloat) -> CGRect? {
        let bounds = viewport.insetBy(dx: 8, dy: 8)
        guard bounds.width > 0, bounds.height > 0, viewport.intersects(caret) else { return nil }
        let below = max(0, bounds.maxY - caret.maxY - 4)
        let above = max(0, caret.minY - bounds.minY - 4)
        let useBelow = below >= preferredHeight || below >= above
        let height = min(preferredHeight, useBelow ? below : above)
        guard height >= 32 else { return nil }
        let width = min(260, bounds.width)
        return CGRect(
            x: min(max(caret.minX, bounds.minX), bounds.maxX - width),
            y: useBelow ? caret.maxY + 4 : caret.minY - 4 - height,
            width: width,
            height: height
        )
    }
}
