// Checks NX.lineHeight and NX.serifLineHeight against the line SwiftUI lays
// out, which the Next UI's CSS line boxes are fitted over: a label's
// (size − line) / 2 padding, a paragraph's size × line-height − line leading,
// and the exact lines of a text whose CSS line is under SwiftUI's. Compiled
// against the real openlist/Next/NextTextLine.swift by Tools/run-logic-checks.sh.

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

/// How tall SwiftUI lays `view` out, to the fraction.
@MainActor
func exactHeight<V: View>(_ view: V) -> CGFloat {
    NSHostingController(rootView: view.fixedSize()).sizeThatFits(in: CGSize(width: 2000, height: 2000)).height
}

func lines(_ count: Int) -> String { Array(repeating: "Hg", count: count).joined(separator: "\n") }

/// The first and last rows `view` inks, in quarter points, drawn at 4x over white.
@MainActor
func ink<V: View>(_ view: V) -> ClosedRange<Double>? {
    let renderer = ImageRenderer(content: view.fixedSize().background(Color.white))
    renderer.scale = 4
    guard let image = renderer.cgImage,
          let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                  bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
    let rows = (0..<image.height).filter { y in
        (0..<image.width).contains { x in data[(y * image.width + x) * 4 + 3] > 200 && data[(y * image.width + x) * 4] < 128 }
    }
    guard let first = rows.first, let last = rows.last else { return nil }
    return Double(first) / 4...Double(last + 1) / 4
}

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
    // The screen header's sans title, bold 27, past the half points above.
    let header = height(Text("Hg").font(.system(size: 27, weight: .bold)))
    check(header == NX.lineHeight(27) && header == 32, "27pt bold header line", "SwiftUI \(header), helper \(NX.lineHeight(27))")
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

    // A fitting size is rounded up, which hides a line off by a fraction of
    // a point, so ten of each box are stacked and measured to the fraction:
    // the rows' titles and notes, their chips, the empty text, add row, pills
    // and tabs, and the sans header title and subtitle, each padded to the
    // design's size × line-height.
    let boxes: [(size: CGFloat, lineHeight: CGFloat, weight: Font.Weight, name: String)] = [
        (13.8, 1.45, .regular, "row title"), (12, 1.4, .regular, "row note"), (11, 1.2, .semibold, "chip"),
        (11.5, 1.2, .medium, "quiet chip"), (12.5, 1.4, .regular, "empty text"), (13, 1.45, .regular, "Today is clear text"),
        (13.5, 1.3, .regular, "add row"), (12, 1, .medium, "query pill"), (11, 1, .semibold, "group action"),
        (13.5, 1, .semibold, "tab"), (9.5, 1, .semibold, "pill caption"), (10.5, 1.3, .medium, "pill footer"),
        (27, 1.1, .bold, "sans header title"), (12, 1.2, .medium, "header subtitle"),
    ]
    for box in boxes {
        let pad = (box.size * box.lineHeight - NX.lineHeight(box.size)) / 2
        let stack = exactHeight(VStack(spacing: 0) {
            ForEach(0..<10, id: \.self) { _ in Text("Hg").font(.system(size: box.size, weight: box.weight)).padding(.vertical, pad) }
        })
        let design = 10 * box.size * box.lineHeight
        check(abs(stack - design) < 0.01, "\(box.name) ×10 at \(box.size)/\(box.lineHeight)", "\(stack) against \(design)")
    }

    // Instrument Serif, the serif titles' face, from the app's bundle copy:
    // its line at every whole point, and the titles' boxes over it (the
    // Changes and day titles' 22/1.1, Today is clear's and the sheets' 26/1.1,
    // the screen header's 34/1.05), ten stacked.
    let serifURL = URL(fileURLWithPath: "Shared/Fonts/InstrumentSerif-Regular.ttf")
    check(CTFontManagerRegisterFontsForURL(serifURL as CFURL, .process, nil), "Instrument Serif registers")
    for size in stride(from: CGFloat(10), through: 48, by: 1) {
        let line = exactHeight(Text("Hg").font(.custom("InstrumentSerif-Regular", size: size)))
        check(line == NX.serifLineHeight(size), "\(size)pt serif line", "SwiftUI \(line), helper \(NX.serifLineHeight(size).map { "\($0)" } ?? "none")")
    }
    for (size, lineHeight) in [(CGFloat(22), CGFloat(1.1)), (26, 1.1), (34, 1.05)] {
        let pad = (size * lineHeight - (NX.serifLineHeight(size) ?? 0)) / 2
        let stack = exactHeight(VStack(spacing: 0) {
            ForEach(0..<10, id: \.self) { _ in Text("Hg").font(.custom("InstrumentSerif-Regular", size: size)).padding(.vertical, pad) }
        })
        check(abs(stack - 10 * size * lineHeight) < 0.01, "serif title ×10 at \(size)/\(lineHeight)", "\(stack) against \(10 * size * lineHeight)")
    }
    // The add row's N: SF Mono 10/1 inside 2 pt padding, 14 pt.
    let keys = height(VStack(spacing: 0) {
        ForEach(0..<10, id: \.self) { _ in
            Text("N").font(.system(size: 10, weight: .medium, design: .monospaced)).padding(.vertical, 2 + (10 - NX.lineHeight(10)) / 2)
        }
    })
    check(keys == 140, "key cap ×10 at 10/1", "\(keys)")

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

    // A wrapping text whose CSS line is under SwiftUI's, as the triage card's
    // list names (13/1) and caps titles (10.5/1) and the Planned now title
    // (13/1.2), label (11/1) and time (12/1) are, takes exact lines, so n of
    // them stack at the design's n × size × line-height.
    for (size, lineHeight) in [(CGFloat(13), CGFloat(1)), (13, 1.2), (10.5, 1), (11, 1), (12, 1)] {
        for count in [1, 2, 3] {
            let text = height(Text(lines(count)).font(.system(size: size, weight: .medium))
                .lineHeight(.exact(points: size * lineHeight)))
            let stacked = CGFloat(count) * size * lineHeight
            check(text == stacked.rounded(.up), "\(count) exact lines of \(size)/\(lineHeight)", "\(text) against \(stacked)")
        }
    }
    // An exact line trims SwiftUI's from below, so raised by half the trim its
    // ink sits where a label padded by (size − line) / 2 has it, centred.
    for size in [CGFloat(11), 12, 13] {
        let exact = ink(Text("H").font(.system(size: size, weight: .semibold))
            .lineHeight(.exact(points: size)).offset(y: (size - NX.lineHeight(size)) / 2))
        let padded = ink(Text("H").font(.system(size: size, weight: .semibold)).padding(.vertical, (size - NX.lineHeight(size)) / 2))
        check(exact != nil && exact == padded, "a raised exact \(size)pt line centres its ink", "\(String(describing: exact)) against \(String(describing: padded))")
    }
    // At a half-point size an exact line sets the baseline at the size, half
    // a point under SwiftUI's own, which it rounds down to a whole point, so
    // a one-line caps title (NXCapsTitle, 10.5) raised that much more keeps
    // the box and ink the padded one had.
    for size in [CGFloat(9.5), 10.5, 11.5, 12.5] {
        let exact = ink(Text("H").font(.system(size: size, weight: .semibold)).lineHeight(.exact(points: size)))
        let own = ink(Text("H").font(.system(size: size, weight: .semibold)))
        check(exact != nil && exact?.upperBound == own.map { $0.upperBound + 0.5 }, "an exact \(size)pt line sets its baseline half a point lower",
              "\(String(describing: exact)) against \(String(describing: own))")
    }
    let capsExact = Text("File into").font(.system(size: 10.5, weight: .semibold)).kerning(0.735).textCase(.uppercase)
        .lineHeight(.exact(points: 10.5)).offset(y: (10.5 - NX.lineHeight(10.5)) / 2 - 0.5)
    let capsPadded = Text("File into").font(.system(size: 10.5, weight: .semibold)).kerning(0.735).textCase(.uppercase)
        .padding(.vertical, (10.5 - NX.lineHeight(10.5)) / 2)
    check(height(capsExact) == height(capsPadded) && ink(capsExact) == ink(capsPadded), "a caps title's exact line is its padded one",
          "\(height(capsExact)) against \(height(capsPadded))")

    // A word floor is the widest word, ending at a space or after a dash, as
    // SwiftUI breaks: that word keeps to a line at the floor, which is never
    // more than a point or two over where SwiftUI would break inside it.
    for (text, word, size, semibold, kerning) in [("Weekend in Kyoto", "Weekend", CGFloat(13), false, CGFloat(0)),
                                                  ("Board presentation", "presentation", 13, true, 0),
                                                  ("10:00–10:30", "10:00–", 12, false, 0),
                                                  ("PLANNED NOW", "PLANNED", 11, true, 0.66)] {
        let weight: NSFont.Weight = semibold ? .semibold : .medium
        let floor = NX.wordFloor(text, size: size, weight: weight, kerning: kerning)
        @MainActor func wordLines(_ width: CGFloat) -> CGFloat {
            height(Text(word).font(.system(size: size, weight: semibold ? .semibold : .medium)).kerning(kerning)
                .lineHeight(.exact(points: size)).frame(width: width).fixedSize(horizontal: false, vertical: true)) / size
        }
        check(floor == NX.wordFloor(word, size: size, weight: weight, kerning: kerning) && floor < NX.wordFloor(text.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "–", with: ""), size: size, weight: weight, kerning: kerning),
              "\(text)'s floor is \(word)'s", "\(floor)")
        check(wordLines(floor).rounded() == 1 && wordLines(floor - 2.5).rounded() == 2, "\(word) keeps to a line at its floor, and just under it breaks",
              "\(wordLines(floor)) and \(wordLines(floor - 2.5)) lines at \(floor)")
    }
    // Under its floor a text keeps to one truncated line; at it, it wraps at words.
    let kyoto = NX.wordFloor("Weekend in Kyoto", size: 13, weight: .medium)
    @MainActor func name(_ width: CGFloat) -> CGFloat {
        height(Text("Weekend in Kyoto").font(.system(size: 13, weight: .medium)).lineHeight(.exact(points: 13))
            .nxWordFloor(kyoto).frame(width: width))
    }
    check(name(kyoto) == 26 && name(kyoto - 1) == 13 && name(400) == 13, "a floored name wraps at words, and truncates under its floor",
          "\(name(kyoto)), \(name(kyoto - 1)) and \(name(400))")

    // A symbol in the design's icon box beside a line-height 1 label, as the
    // Calendar's Start (a 14pt box, 12/1, 7pt padding) and Plan (13pt, 11/1,
    // 5pt) are: the box, not the symbol's own height, sets the button's.
    let start = height(HStack(spacing: 5) {
        Image(systemName: "play.fill").font(.system(size: 11)).frame(height: 14)
        Text("Start").font(.system(size: 12, weight: .semibold)).padding(.vertical, (12 - NX.lineHeight(12)) / 2)
    }.padding(.vertical, 7))
    check(start == 28, "Start's 7 + 14 + 7 box", "\(start)")
    let plan = height(HStack(spacing: 3) {
        Image(systemName: "sparkles").font(.system(size: 11)).frame(height: 13)
        Text("Plan").font(.system(size: 11, weight: .semibold)).padding(.vertical, (11 - NX.lineHeight(11)) / 2)
    }.padding(.vertical, 5))
    check(plan == 23, "Plan's 5 + 13 + 5 box", "\(plan)")

    // The Planned now banner's row, as NextCalendar lays it out: squeezed,
    // the title wraps first, then the label and time, none inside a word,
    // so even the 324pt page of the narrowest window keeps it a few lines
    // tall; at its widest it's the design's 48pt, 10 + 28 + 10.
    @MainActor func banner(_ title: String, width: CGFloat) -> CGFloat {
        let titleLine = 13 * 1.2
        return height(NXFlexRow(spacing: 12) {
            Circle().frame(width: 8, height: 8)
            Text("Planned now").font(.system(size: 11, weight: .semibold)).kerning(0.66).textCase(.uppercase)
                .lineHeight(.exact(points: 11)).offset(y: (11 - NX.lineHeight(11)) / 2)
                .nxWordFloor(NX.wordFloor("PLANNED NOW", size: 11, weight: .semibold, kerning: 0.66))
                .layoutPriority(1)
            Text(title).font(.system(size: 13, weight: .semibold))
                .lineHeight(.exact(points: titleLine)).offset(y: (titleLine - NX.lineHeight(13)) / 2)
                .nxWordFloor(NX.wordFloor(title, size: 13, weight: .semibold))
            Text("10:00–10:30").font(.system(size: 12, weight: .medium))
                .lineHeight(.exact(points: 12)).offset(y: (12 - NX.lineHeight(12)) / 2)
                .nxWordFloor(NX.wordFloor("10:00–10:30", size: 12, weight: .medium))
                .layoutPriority(1)
            HStack(spacing: 5) {
                Image(systemName: "play.fill").font(.system(size: 11)).frame(height: 14)
                Text("Start").font(.system(size: 12, weight: .semibold)).padding(.vertical, (12 - NX.lineHeight(12)) / 2)
            }
            .padding(EdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 12))
        }
        .padding(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 12))
        .frame(width: width))
    }
    let long = "Prepare the quarterly board presentation and speaker notes"
    for width in [CGFloat(324), 384, 450, 520, 640] {
        let tall = banner(long, width: width)
        check(tall >= 48 && tall <= (20 + 4 * 13 * 1.2).rounded(.up), "a long Planned now title keeps the banner a few lines tall at \(width)pt", "\(tall)")
    }
    check(banner(long, width: 800) == 48 && banner("Draft Q3 OKRs", width: 450) == 48, "a Planned now title that fits keeps the banner 48pt")
    check(banner("Reimplementation of the importer", width: 324) == 48, "a word too wide for the narrowest banner truncates the title rather than breaking it")
}

print(failures == 0 ? "✅ \(checks) line-height checks passed" : "❌ \(failures)/\(checks) failed")
exit(failures == 0 ? 0 : 1)
