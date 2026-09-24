// Checks NX.lineHeight against the line SwiftUI lays out, which the Next
// UI's CSS line boxes are fitted over: a label's (size − line) / 2 padding
// and a paragraph's size × line-height − line leading. Compiled against the
// real openlist/Next/NextTextLine.swift by Tools/run-logic-checks.sh.

import AppKit
import SwiftUI

/// The theme's namespace, which NextTextLine.swift extends.
enum NX {}

var failures = 0, checks = 0

@MainActor
func check(_ c: Bool, _ label: String, _ detail: @autoclosure () -> String = "") {
    checks += 1
    if !c { failures += 1; print("FAIL  \(label)\(detail().isEmpty ? "" : " — \(detail())")") }
}

/// How tall SwiftUI lays `view` out, rounded up to whole points as a
/// hosting view's fitting size is.
@MainActor
func height<V: View>(_ view: V) -> CGFloat {
    NSHostingView(rootView: view.fixedSize()).fittingSize.height
}

/// How tall SwiftUI lays `view` out, in fractions of a point.
@MainActor
func exactHeight<V: View>(_ view: V) -> CGFloat {
    NSHostingController(rootView: view.fixedSize()).sizeThatFits(in: CGSize(width: 1000, height: 1000)).height
}

func lines(_ count: Int) -> String { Array(repeating: "Hg", count: count).joined(separator: "\n") }

MainActor.assumeIsolated {
    // One line, at every half point the UI's text uses and the rows' 13.8,
    // in each weight and in SF Mono.
    let weights: [(Font.Weight, String)] = [(.regular, "regular"), (.medium, "medium"), (.semibold, "semibold"), (.bold, "bold")]
    for size in Array(stride(from: CGFloat(8), through: 23.5, by: 0.5)) + [13.8] {
        for (weight, name) in weights {
            let system = height(Text("Hg").font(.system(size: size, weight: weight)))
            check(system == NX.lineHeight(size), "\(size)pt \(name) line", "SwiftUI \(system), helper \(NX.lineHeight(size))")
            let mono = height(Text("Hg").font(.system(size: size, weight: weight, design: .monospaced)))
            check(mono == NX.lineHeight(size), "\(size)pt \(name) mono line", "SwiftUI \(mono), helper \(NX.lineHeight(size))")
        }
    }

    // The lines the design's boxes are fitted over, and the leading that gives.
    check(NX.lineHeight(9.5) == 12 && NX.lineHeight(10) == 13 && NX.lineHeight(10.5) == 13
          && NX.lineHeight(11) == 14 && NX.lineHeight(12) == 15 && NX.lineHeight(13) == 16
          && NX.lineHeight(16) == 19 && NX.lineHeight(22) == 26, "SwiftUI's whole-point lines")
    check(abs(22 * 1.3 - NX.lineHeight(22) - 2.6) < 0.001, "triage title 22/1.3 leads 2.6")
    check(abs(10.5 * 1.4 - NX.lineHeight(10.5) - 1.7) < 0.001, "triage hint 10.5/1.4 leads 1.7")
    check(abs(13 * 1.45 - NX.lineHeight(13) - 2.85) < 0.001, "triage summary 13/1.45 leads 2.85")
    check(abs(10.5 * 1.25 - NX.lineHeight(10.5) - 0.125) < 0.001, "block title 10.5/1.25 leads 0.125")
    check(abs(9.5 * 1.3 - NX.lineHeight(9.5) - 0.35) < 0.001, "block time 9.5/1.3 leads 0.35")

    // A line-height 1 label padded by (size − line) / 2 is its size tall.
    for size: CGFloat in [9.5, 10, 10.5, 11, 12, 12.5, 16, 17] {
        let box = height(Text("Hg").font(.system(size: size)).padding(.vertical, (size - NX.lineHeight(size)) / 2))
        check(box == size.rounded(.up), "\(size)/1 label box", "\(box)")
    }

    // A paragraph's leading goes between its lines only, so with half of it
    // above and below, n lines stack at the design's n × size × line-height.
    let paragraphs: [(CGFloat, CGFloat)] = [(10.5, 1.25), (9.5, 1.3), (22, 1.3), (10.5, 1.4), (13, 1.45),
                                            (11.5, 1.45), (12, 1.45), (12.5, 1.35)]
    for (size, lineHeight) in paragraphs {
        let leading = size * lineHeight - NX.lineHeight(size)
        for count in [1, 2, 3] {
            let text = height(Text(lines(count)).font(.system(size: size)).lineSpacing(leading))
            let stacked = CGFloat(count) * NX.lineHeight(size) + CGFloat(count - 1) * leading
            check(text == stacked.rounded(.up), "\(count) lines of \(size)/\(lineHeight)", "\(text) against \(stacked)")
        }
    }

    // Lists, Activity, Trash and Settings, boxed by the formulas their views
    // use (the helper and each box's padding, restated here, as the views
    // don't compile in this target): each is the design's CSS height, unrounded.
    let settingsLabel = 13 * 1.25 - NX.lineHeight(13), settingsHint = 11.5 * 1.35 - NX.lineHeight(11.5)
    let settingsRow = exactHeight(VStack(alignment: .leading, spacing: 3) {
        Text("Hg").font(.system(size: 13, weight: .medium)).lineSpacing(settingsLabel).padding(.vertical, settingsLabel / 2)
        Text("Hg").font(.system(size: 11.5)).lineSpacing(settingsHint).padding(.vertical, settingsHint / 2)
    }.padding(.vertical, 12))
    check(abs(settingsRow - (12 + 16.25 + 3 + 15.525 + 12)) < 0.001, "settings row 13/1.25 over 11.5/1.35", "\(settingsRow)")
    let caps = exactHeight(Text("HG").font(.system(size: 10.5, weight: .semibold)).kerning(0.735)
        .padding(.vertical, (10.5 - NX.lineHeight(10.5)) / 2))
    check(caps == 10.5, "caps title 600 10.5/1", "\(caps)")
    // A leading under SwiftUI's own line can't go in lineSpacing, which
    // can't be negative, so one line takes it as padding: a card name's one
    // line is 17.4, and two are 35.4 (IMPLEMENTATION.md's deviation).
    let closed = exactHeight(Text(lines(2)).font(.system(size: 14.5, weight: .semibold))
        .lineSpacing(14.5 * 1.2 - NX.lineHeight(14.5)))
    check(closed == 2 * NX.lineHeight(14.5), "a negative lineSpacing leaves 14.5pt lines 18 apart", "\(closed)")
    for (count, box) in [(1, 17.4), (2, 35.4)] {
        let cardName = exactHeight(Text(lines(count)).font(.system(size: 14.5, weight: .semibold))
            .padding(.vertical, (14.5 * 1.2 - NX.lineHeight(14.5)) / 2))
        check(abs(cardName - box) < 0.001, "\(count)-line card name 600 14.5/1.2", "\(cardName)")
    }
    let dayRow = exactHeight(HStack(spacing: 9) {
        Image(systemName: "checkmark.circle.fill").font(.system(size: 13))
        Text("Hg").font(.system(size: 12.5)).padding(.vertical, (12.5 * 1.3 - NX.lineHeight(12.5)) / 2)
        Text("09:41").font(.system(size: 10.5, weight: .medium, design: .monospaced))
    }.padding(.vertical, 7).padding(.top, 0.5))
    check(abs(dayRow - 30.75) < 0.001, "day panel row", "\(dayRow)")
    // Buttons with an icon box as their views give it, whatever the symbol's own height.
    @MainActor func button(_ icon: String?, symbol: CGFloat, box: CGFloat, label size: CGFloat, padding: CGFloat,
                           spacing: CGFloat = 5) -> CGFloat {
        exactHeight(HStack(spacing: spacing) {
            if let icon { Image(systemName: icon).font(.system(size: symbol)).frame(height: box) }
            Text("Hg").padding(.vertical, (size - NX.lineHeight(size)) / 2)
        }.font(.system(size: size, weight: .semibold)).padding(.vertical, padding))
    }
    check(button("trash.slash", symbol: 13.5, box: 14, label: 11.5, padding: 7) == 28, "Hold to empty Trash is 28")
    check(button("arrow.up.bin", symbol: 12, box: 13, label: 11, padding: 6, spacing: 4) == 25, "Restore is 25")
    check(button(nil, symbol: 0, box: 0, label: 11, padding: 6) == 23, "Hold to erase is 23")
    check(button(nil, symbol: 0, box: 0, label: 10.5, padding: 5) == 20.5, "Changes' Undo is 20.5")
}

print(failures == 0 ? "✅ \(checks) line-height checks passed" : "❌ \(failures)/\(checks) failed")
exit(failures == 0 ? 0 : 1)
