//
//  Typography.swift
//  OpenlistWidget
//

import AppKit
import SwiftUI

extension View {
    /// CSS `line-height` for system text: pads a line to `size × multiple`
    /// and spaces wrapped lines to match, so rows measure what the design
    /// does. A multiple below the font's own height (the design's `/ 1`
    /// labels) tightens the box instead.
    func lineHeight(_ multiple: CGFloat, fontSize size: CGFloat, monospaced: Bool = false) -> some View {
        let extra = size * multiple - WidgetFonts.naturalLineHeight(size, monospaced: monospaced)
        return lineSpacing(max(0, extra)).padding(.vertical, extra / 2)
    }

    /// The design's `font: <weight> <size>px / <lineHeight> SF` in one call;
    /// `monospaced` for its `ui-monospace` times.
    func textStyle(_ size: CGFloat, _ weight: Font.Weight = .regular, lineHeight: CGFloat = 1.2, monospaced: Bool = false) -> some View {
        font(.system(size: size, weight: weight, design: monospaced ? .monospaced : .default))
            .lineHeight(lineHeight, fontSize: size, monospaced: monospaced)
    }
}

extension View {
    /// The design's `font: <size>px / <lineHeight> SERIF` for text set in
    /// `style.display`. `textStyle` only knows the system face's line
    /// heights; Instrument Serif's are much taller (1.3 em), so without this
    /// titles and big numbers would stand apart by far more than the design's.
    /// With serif titles off the face is smaller bold SF, and the box keeps
    /// the design's height so layouts do not shift.
    func displayStyle(_ size: CGFloat, lineHeight multiple: CGFloat, style: WidgetStyle) -> some View {
        let extra = size * multiple - WidgetFonts.naturalDisplayLineHeight(size, serifTitles: style.serifTitles)
        return font(style.display(size)).padding(.vertical, extra / 2)
    }
}

/// The small uppercase labels: "OVERDUE", "LATER TODAY", "WEDNESDAY".
struct CapsLabel: View {
    let text: String
    /// Defaults to `faint`.
    var color: Color?
    var size: CGFloat = 10
    /// The design's letter-spacing, in ems.
    var tracking: CGFloat = 0.08
    var weight: Font.Weight = .bold
    @Environment(\.widgetStyle) private var style

    init(_ text: String, color: Color? = nil, size: CGFloat = 10, tracking: CGFloat = 0.08, weight: Font.Weight = .bold) {
        self.text = text
        self.color = color
        self.size = size
        self.tracking = tracking
        self.weight = weight
    }

    var body: some View {
        Text(text)
            .textCase(.uppercase)
            .tracking(size * tracking)
            .foregroundStyle(color ?? style.faint)
            .lineLimit(1)
            .textStyle(size, weight, lineHeight: 1)
    }
}
