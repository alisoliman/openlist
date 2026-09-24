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
}

print(failures == 0 ? "✅ \(checks) line-height checks passed" : "❌ \(failures)/\(checks) failed")
exit(failures == 0 ? 0 : 1)
