//
//  NextWordWrap.swift
//  openlist
//

import AppKit
import SwiftUI

extension NX {
    /// The width of `text`'s widest word in the system font at `size` and
    /// `weight`: its CSS min-content, the narrowest it wraps to without
    /// breaking inside a word. A word ends at a space or after a dash, where
    /// CSS and SwiftUI both break a line. Pass `text` as it's drawn, in
    /// capitals for a caps label. Tools/LineHeightChecks keeps it to SwiftUI's.
    static func wordFloor(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, kerning: CGFloat = 0) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .kern: kerning]
        var words: [String] = [], word = ""
        for character in text {
            if character.isWhitespace {
                words.append(word)
                word = ""
            } else {
                word.append(character)
                if "-–—".contains(character) {
                    words.append(word)
                    word = ""
                }
            }
        }
        words.append(word)
        return words.map { NSAttributedString(string: $0, attributes: attributes).size().width.rounded(.up) }.max() ?? 0
    }
}

/// A text's word floor, for `NXFlexRow`; nil for an item that keeps its width.
private nonisolated struct NXWordFloorKey: LayoutValueKey {
    static let defaultValue: CGFloat? = nil
}

extension View {
    /// Wraps at words, as the design's CSS does, down to `floor`, the text's
    /// widest word (`NX.wordFloor`). Offered less than that, it keeps to one
    /// truncated line rather than breaking inside a word. An `NXFlexRow`
    /// reads the floor.
    func nxWordFloor(_ floor: CGFloat) -> some View {
        ViewThatFits(in: .horizontal) {
            // Ideally only as wide as the floor, so it's chosen whenever that fits.
            fixedSize(horizontal: false, vertical: true).frame(idealWidth: floor)
            lineLimit(1)
        }
        .layoutValue(key: NXWordFloorKey.self, value: floor)
    }
}

/// The design's flex row with a `flex: 1` spacer before its last item, as
/// the Calendar's Planned now banner is: items side by side, centred on the
/// row, the last at the trailing edge, two gaps past the rest at least.
/// Short of room, the texts with a word floor give way, the lowest
/// `layoutPriority` first, each wrapping down to its floor; only once all are
/// there does the lowest go under its own and truncate, so no text breaks
/// inside a word and the row never runs past its width.
struct NXFlexRow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let widths = widths(proposal.width, subviews)
        let height = subviews.indices.map { subviews[$0].sizeThatFits(ProposedViewSize(width: widths[$0], height: nil)).height }.max() ?? 0
        let natural = widths.reduce(0, +) + gaps(subviews)
        return CGSize(width: proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? natural, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let widths = widths(bounds.width, subviews)
        var x = bounds.minX
        for index in subviews.indices {
            // The spacer's own gap, and whatever the row has spare, go before the last.
            if index > 0, index == subviews.count - 1 { x = max(x + spacing, bounds.maxX - widths[index]) }
            let height = subviews[index].sizeThatFits(ProposedViewSize(width: widths[index], height: nil)).height
            subviews[index].place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading,
                                  proposal: ProposedViewSize(width: widths[index], height: height))
            x += widths[index] + spacing
        }
    }

    /// The gaps between the items, and the spacer's second one.
    private func gaps(_ subviews: Subviews) -> CGFloat {
        subviews.count > 1 ? spacing * CGFloat(subviews.count) : 0
    }

    /// Each item's width in a row `width` wide: its own one line, or, short of
    /// room, what the texts give way to, as `NXFlexRow` describes.
    private func widths(_ width: CGFloat?, _ subviews: Subviews) -> [CGFloat] {
        let floors = subviews.map { $0[NXWordFloorKey.self] }
        // A floored text's ideal is its floor, so its one line is measured unbounded.
        let full = subviews.indices.map { index in
            subviews[index].sizeThatFits(floors[index] == nil ? .unspecified : ProposedViewSize(width: .infinity, height: nil)).width
        }
        guard let width, width.isFinite else { return full }
        var widths = full
        var excess = full.reduce(0, +) + gaps(subviews) - width
        let groups = Dictionary(grouping: subviews.indices.filter { floors[$0] != nil }, by: { subviews[$0].priority })
            .sorted { $0.key < $1.key }.map(\.value)
        // Down to the floors, the lowest priority first, texts of one priority
        // alike; then, only if the row is still short, under them.
        for underFloor in [false, true] {
            for group in groups where excess > 0 {
                let targets = group.map { underFloor ? 0 : min(widths[$0], floors[$0] ?? 0) }
                let room = group.indices.map { widths[group[$0]] - targets[$0] }
                let total = room.reduce(0, +)
                guard total > 0 else { continue }
                let take = min(excess, total)
                for (offset, index) in group.enumerated() {
                    widths[index] = max(targets[offset], widths[index] - take * room[offset] / total)
                }
                excess -= take
            }
        }
        // A wrapped text is only as wide as its widest line; what it leaves
        // goes back to the lowest priority, which gave the most. It keeps
        // its floor, which its measured words can come in just under.
        var spare: CGFloat = 0
        for index in widths.indices where widths[index] < full[index] {
            guard let floor = floors[index] else { continue }
            let used = max(subviews[index].sizeThatFits(ProposedViewSize(width: widths[index], height: nil)).width,
                           min(widths[index], floor))
            spare += max(0, widths[index] - used)
            widths[index] = min(widths[index], used)
        }
        for group in groups {
            for index in group where spare > 0 && widths[index] < full[index] {
                let give = min(spare, full[index] - widths[index])
                widths[index] += give
                spare -= give
            }
        }
        return widths
    }
}
