#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Foundation

// Rich text both devices write and read through `Block.richData`. Built and
// described with the codec's own API only, so the Mac suite and the iPhone
// fixture tool share every sample and every expectation.

enum ParityStyle: Equatable {
    case bold, italic, code, strike
    case link(String)
}

struct ParitySample {
    let name: String
    let kind: BlockKind
    let text: String
    /// Applied in order, each to the first occurrence of its substring.
    let styles: [(ParityStyle, String)]
    /// Built on a completed task, whose drawn strike must never be stored.
    var completed = false
    /// The text after an edit on the other device.
    let edited: String
}

/// A run of decoded text, in terms both platforms share. A trait counts only
/// where the block's own font lacks it: a heading is bold on its own.
struct ParityRun: Equatable, CustomStringConvertible {
    var text: String
    var bold = false
    var italic = false
    var code = false
    var link: String?
    var strike = false

    var description: String {
        let flags = [bold ? "bold" : nil, italic ? "italic" : nil, code ? "code" : nil,
                     strike ? "strike" : nil, link.map { "link=\($0)" }].compactMap { $0 }
        return "[\(text)]\(flags.isEmpty ? "" : " " + flags.joined(separator: " "))"
    }

    func sameStyle(as other: ParityRun) -> Bool {
        bold == other.bold && italic == other.italic && code == other.code && link == other.link && strike == other.strike
    }
}

enum Parity {
    static let samples: [ParitySample] = [
        ParitySample(name: "task-styles", kind: .task, text: "Bold ital code link strike end",
                     styles: [(.bold, "Bold"), (.italic, "ital"), (.code, "code"),
                              (.link("https://example.com/a?b=1&c=%C3%A9"), "link"), (.strike, "strike")],
                     edited: "Bolder ital code link strike end"),
        ParitySample(name: "task-combined", kind: .task, text: "Both bold code 🇯🇵 Café 東京 — “quoted” · end",
                     styles: [(.bold, "Both"), (.italic, "Both"), (.code, "bold code"), (.bold, "bold code"),
                              (.strike, "Café"), (.link("openlist://v1/7C9A3C0E-8C51-4A9B-9E0B-1B8F3F9F6D21/task/3D5B2F1E-2A7C-4E0B-9C1D-5B6A7E8F9A0B"), "東京"),
                              (.italic, "“quoted”")],
                     edited: "Both bold code 🇯🇵 Café 東京 — “quoted” · end, from the iPhone"),
        ParitySample(name: "heading", kind: .heading1, text: "Trip plan for Kyoto",
                     styles: [(.italic, "Kyoto"), (.code, "plan"), (.strike, "for")],
                     edited: "Trip plan for Kyoto and Nara"),
        ParitySample(name: "text", kind: .paragraph, text: "Notes with a link and bold italic words",
                     styles: [(.link("https://example.com/notes"), "a link"), (.bold, "bold italic"), (.italic, "bold italic")],
                     edited: "Notes with a link and bold italic words here"),
        ParitySample(name: "completed-task", kind: .task, text: "Done with one struck word",
                     styles: [(.strike, "struck"), (.bold, "Done")], completed: true,
                     edited: "Done with one struck word today"),
    ]

    /// The sample's text styled through the codec's editing API, as either
    /// device's editor styles it.
    static func build(_ sample: ParitySample) -> NSMutableAttributedString {
        let text = NSMutableAttributedString(attributedString: RichTextCodec.decode(
            nil, plainText: sample.text, kind: sample.kind, isCompleted: sample.completed))
        for (style, substring) in sample.styles {
            let range = (sample.text as NSString).range(of: substring)
            precondition(range.location != NSNotFound, "\(sample.name): no \(substring)")
            switch style {
            case .bold: RichTextCodec.toggleTrait(RichTextCodec.boldTrait, in: text, range: range, kind: sample.kind)
            case .italic: RichTextCodec.toggleTrait(RichTextCodec.italicTrait, in: text, range: range, kind: sample.kind)
            case .code: RichTextCodec.toggleInlineCode(in: text, range: range, kind: sample.kind)
            case .strike: RichTextCodec.toggleStrikethrough(in: text, range: range)
            case let .link(url): RichTextCodec.setLink(URL(string: url)!, in: text, range: range)
            }
        }
        return text
    }

    /// What the sample means, worked out from its styles alone.
    static func intended(_ sample: ParitySample) -> [ParityRun] {
        let length = (sample.text as NSString).length
        var characters = [ParityRun](repeating: ParityRun(text: ""), count: length)
        for (style, substring) in sample.styles {
            let range = (sample.text as NSString).range(of: substring)
            for index in range.location..<NSMaxRange(range) {
                switch style {
                case .bold: characters[index].bold.toggle()
                case .italic: characters[index].italic.toggle()
                case .code: characters[index].code.toggle()
                case .strike: characters[index].strike.toggle()
                case let .link(url): characters[index].link = url
                }
            }
        }
        let base = RichTextCodec.fontTraits(of: NXEditor.nsFont(for: sample.kind))
        // Group UTF-16 units first, so a run never splits a surrogate pair.
        var runs: [(style: ParityRun, range: NSRange)] = []
        for (index, var style) in characters.enumerated() {
            if base.bold { style.bold = false }
            if base.italic { style.italic = false }
            if let last = runs.last, last.style.sameStyle(as: style) {
                runs[runs.count - 1].range.length += 1
            } else {
                runs.append((style, NSRange(location: index, length: 1)))
            }
        }
        return runs.map { run in
            var style = run.style
            style.text = (sample.text as NSString).substring(with: run.range)
            return style
        }
    }

    /// The runs `text` draws, decoded for `kind`.
    static func describe(_ text: NSAttributedString, kind: BlockKind) -> [ParityRun] {
        let base = RichTextCodec.fontTraits(of: NXEditor.nsFont(for: kind))
        var runs: [ParityRun] = []
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, range, _ in
            let traits = RichTextCodec.fontTraits(of: attributes[.font])
            let link = (attributes[.link] as? URL)?.absoluteString ?? attributes[.link] as? String
            runs.append(ParityRun(
                text: (text.string as NSString).substring(with: range),
                bold: traits.bold && !base.bold,
                italic: traits.italic && !base.italic,
                code: (attributes[.openlistInlineCode] as? Bool) == true,
                link: link,
                strike: (attributes[.openlistStrikethrough] as? Bool) == true
                    && (attributes[.strikethroughStyle] as? Int ?? 0) != 0
            ))
        }
        return merge(runs)
    }

    private static func merge(_ runs: [ParityRun]) -> [ParityRun] {
        var merged: [ParityRun] = []
        for run in runs {
            if let last = merged.last, last.sameStyle(as: run) {
                merged[merged.count - 1].text += run.text
            } else {
                merged.append(run)
            }
        }
        return merged
    }

    /// What an archive decodes to, stored for `sample`'s kind.
    static func decoded(_ data: Data?, text: String, for sample: ParitySample) -> [ParityRun] {
        describe(RichTextCodec.decode(data, plainText: text, kind: sample.kind), kind: sample.kind)
    }

    /// The archive an edit writes: the other device's archive decoded, its
    /// text replaced as a title field replaces it, and encoded again.
    static func editing(_ data: Data?, for sample: ParitySample) -> Data? {
        let decoded = RichTextCodec.decode(data, plainText: sample.text, kind: sample.kind)
        return RichTextCodec.encode(RichTextCodec.replacingText(in: decoded, with: sample.edited), kind: sample.kind)
    }

    /// Point sizes of the fonts an archive names, read at the Mac's scale.
    static func storedPointSizes(_ data: Data) -> Set<Double> {
        #if os(macOS)
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [.documentType: NSAttributedString.DocumentType.rtf]
        #else
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.rtf, .targetTextScaling: NSTextScalingType.standard.rawValue,
        ]
        #endif
        guard let text = try? NSAttributedString(data: data, options: options, documentAttributes: nil) else { return [] }
        var sizes = Set<Double>()
        text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            if let font = value as? RichTextCodec.PlatformFont { sizes.insert((Double(font.pointSize) * 100).rounded() / 100) }
        }
        return sizes
    }
}
