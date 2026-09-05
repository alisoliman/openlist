import AppKit
import Foundation

/// Serializes stored inline formatting independently of the editor's heading,
/// completion and theme styling. Formatting that crosses another run is split
/// into balanced spans, and code delimiters are chosen from the actual text.
enum InlineMarkdown {
    private struct CharacterStyle {
        var text: String
        var link: String?
        var bold: Bool
        var italic: Bool
        var struck: Bool
        var code: Bool

        func value(at level: Int) -> String? {
            switch level {
            case 0: link
            case 1: bold ? "**" : nil
            case 2: italic ? "*" : nil
            case 3: struck ? "~~" : nil
            case 4: code ? "`" : nil
            default: nil
            }
        }
    }

    static func string(from attributed: NSAttributedString) -> String {
        var characters: [CharacterStyle] = []
        var offset = 0
        for character in attributed.string {
            let text = String(character)
            let attributes = attributed.attributes(at: offset, effectiveRange: nil)
            let traits = (attributes[.font] as? NSFont).map { NSFontManager.shared.traits(of: $0) } ?? []
            let link = (attributes[.link] as? URL)?.absoluteString ?? attributes[.link] as? String
            characters.append(CharacterStyle(
                text: text,
                link: link,
                bold: traits.contains(.boldFontMask),
                italic: traits.contains(.italicFontMask),
                struck: (attributes[.openlistStrikethrough] as? Bool) == true,
                code: (attributes[.openlistInlineCode] as? Bool) == true
            ))
            offset += text.utf16.count
        }
        return render(characters[...], level: 0)
    }

    static func escape(_ text: String) -> String {
        let punctuation = Set("\\`*_{}[]<>()#+-.!|~")
        return text.map { punctuation.contains($0) ? "\\\($0)" : String($0) }.joined()
    }

    /// Angle-delimited destinations allow literal parentheses. Encode characters
    /// that could terminate the destination or turn into HTML/control syntax.
    static func destination(_ value: String) -> String {
        var allowed = CharacterSet.urlFragmentAllowed
        allowed.remove(charactersIn: "<>\\\"\n\r\t ")
        allowed.insert(charactersIn: "%#")
        return "<\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)>"
    }

    static func codeFence(for text: String) -> String {
        String(repeating: "`", count: max(3, longestBacktickRun(in: text) + 1))
    }

    private static func render(_ characters: ArraySlice<CharacterStyle>, level: Int) -> String {
        guard !characters.isEmpty else { return "" }
        guard level <= 4 else { return escape(characters.map(\.text).joined()) }
        var output = ""
        var start = characters.startIndex
        while start < characters.endIndex {
            let value = characters[start].value(at: level)
            var end = start + 1
            while end < characters.endIndex, characters[end].value(at: level) == value { end += 1 }
            let run = characters[start..<end]
            guard let value else {
                output += render(run, level: level + 1)
                start = end
                continue
            }

            if level == 4 {
                let text = run.map(\.text).joined()
                let fence = String(repeating: "`", count: longestBacktickRun(in: text) + 1)
                let needsPadding = text.hasPrefix("`") || text.hasSuffix("`")
                    || (text.hasPrefix(" ") && text.hasSuffix(" ") && !text.allSatisfy { $0 == " " })
                let padding = needsPadding ? " " : ""
                output += fence + padding + text + padding + fence
            } else {
                // Markdown emphasis cannot open/close on whitespace. Leave it
                // outside the delimiters, retaining its other inline styles.
                var first = run.startIndex
                var last = run.endIndex
                while first < last, run[first].text.allSatisfy(\.isWhitespace) { first += 1 }
                while last > first, run[last - 1].text.allSatisfy(\.isWhitespace) { last -= 1 }
                output += render(run[..<first], level: level + 1)
                if first < last {
                    let content = render(run[first..<last], level: level + 1)
                    if level == 0 {
                        output += "[\(content)](\(destination(value)))"
                    } else if needsHTMLSpan(characters, first: first, last: last)
                        || (level == 1 && ambiguousEmphasisNesting(run[first..<last])) {
                        // Punctuation within a word and partially overlapping
                        // emphasis can produce ambiguous delimiter runs. An
                        // inline HTML span preserves those uncommon cases.
                        let tag = level == 1 ? "strong" : (level == 2 ? "em" : "del")
                        output += "<\(tag)>\(content)</\(tag)>"
                    } else {
                        output += value + content + value
                    }
                }
                output += render(run[last...], level: level + 1)
            }
            start = end
        }
        return output
    }

    private static func ambiguousEmphasisNesting(_ run: ArraySlice<CharacterStyle>) -> Bool {
        // **a*b****c* and ***a*b*c*** do not parse as the intended
        // bold/italic ranges under CommonMark's delimiter rules.
        let hasItalicBoundary = run.first?.italic == true || run.last?.italic == true
        return hasItalicBoundary && run.contains { !$0.italic }
    }

    private static func needsHTMLSpan(_ characters: ArraySlice<CharacterStyle>, first: Int, last: Int) -> Bool {
        func punctuation(_ text: String) -> Bool {
            text.unicodeScalars.allSatisfy { CharacterSet.punctuationCharacters.union(.symbols).contains($0) }
        }
        func word(_ text: String) -> Bool { text.contains { $0.isLetter || $0.isNumber } }
        return (first > characters.startIndex && punctuation(characters[first].text) && word(characters[first - 1].text))
            || (last < characters.endIndex && punctuation(characters[last - 1].text) && word(characters[last].text))
    }

    private static func longestBacktickRun(in text: String) -> Int {
        var longest = 0, current = 0
        for character in text {
            current = character == "`" ? current + 1 : 0
            longest = max(longest, current)
        }
        return longest
    }
}
