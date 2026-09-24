//
//  MarkdownInputRules.swift
//  openlist
//

import AppKit
import Foundation

/// Type-to-format rules applied as the user writes.
///
/// Two families: the design's block prefixes (`## `, `- `, `[] `) that change
/// the whole block's kind, and inline pairs (`**bold**`, `` `code` ``) that
/// restyle a span the moment the closing delimiter is typed.
enum MarkdownInputRules {
    struct BlockPrefixMatch {
        /// The characters to delete, including the trailing space.
        var range: NSRange
        var kind: BlockKind
    }

    /// The list document's block prefixes, the design's, longest first so
    /// `##` beats `#`. Anything else stays as typed.
    private static let blockPrefixes: [(String, BlockKind)] = [
        ("## ", .heading2),
        ("# ", .heading1),
        ("[] ", .task),
        ("[ ] ", .task),
        ("* ", .bullet),
        ("- ", .bullet),
        ("> ", .quote),
    ]

    /// Detects a markdown prefix the user just *typed* at the start of a block.
    ///
    /// Two guards matter. The caret must sit immediately after the prefix, so
    /// typing further along a line that starts with "- " converts nothing (a
    /// paste or drop is `matchPastedPrefix`'s). And the change must have been
    /// an insertion — otherwise backspacing the "x" out of `# xSection` would
    /// leave `# Section`, match the heading rule, and turn a line the user
    /// was editing into a heading.
    static func matchBlockPrefix(
        in storage: NSTextStorage,
        caret: Int,
        wasInsertion: Bool,
        kind: BlockKind
    ) -> BlockPrefixMatch? {
        guard wasInsertion, kind != .code else { return nil }

        let text = storage.string as NSString
        guard text.length > 0 else { return nil }

        for (prefix, kind) in blockPrefixes {
            let prefixLength = (prefix as NSString).length
            guard caret == prefixLength, text.length >= prefixLength else { continue }
            if text.substring(to: prefixLength).lowercased() == prefix {
                return BlockPrefixMatch(range: NSRange(location: 0, length: prefixLength), kind: kind)
            }
        }
        return nil
    }

    /// The design's prefix a paste or drop at the start of a block left it
    /// starting with, as the design's change converts a pasted `# Packing`
    /// into a heading "Packing". `- [ ] ` reads as a list item there, as only
    /// `- ` matches at its start, as in the design's anchored pattern. A code
    /// block keeps what's pasted.
    static func matchPastedPrefix(in storage: NSTextStorage, kind: BlockKind) -> BlockPrefixMatch? {
        guard kind != .code else { return nil }
        let text = storage.string as NSString
        for (prefix, kind) in blockPrefixes {
            let prefixLength = (prefix as NSString).length
            if text.length >= prefixLength, text.substring(to: prefixLength) == prefix {
                return BlockPrefixMatch(range: NSRange(location: 0, length: prefixLength), kind: kind)
            }
        }
        return nil
    }

    // MARK: - Inline rules

    private struct InlineRule {
        var pattern: String
        var apply: (NSMutableAttributedString, NSRange, BlockKind) -> Void
    }

    /// `**bold**`, `__bold__`, `*italic*`, `_italic_`, `~~strike~~`, `` `code` ``.
    ///
    /// Patterns capture the inner text in group 1 so the delimiters can be
    /// dropped and the styling applied to what remains.
    private static let inlineRules: [InlineRule] = [
        InlineRule(pattern: "\\*\\*(.+?)\\*\\*") { storage, range, kind in
            RichTextCodec.toggleTrait(.boldFontMask, in: storage, range: range, kind: kind)
        },
        InlineRule(pattern: "__(.+?)__") { storage, range, kind in
            RichTextCodec.toggleTrait(.boldFontMask, in: storage, range: range, kind: kind)
        },
        InlineRule(pattern: "~~(.+?)~~") { storage, range, _ in
            RichTextCodec.toggleStrikethrough(in: storage, range: range)
        },
        InlineRule(pattern: "(?<![\\*\\w])\\*(?!\\*)(.+?)(?<!\\*)\\*(?![\\*\\w])") { storage, range, kind in
            RichTextCodec.toggleTrait(.italicFontMask, in: storage, range: range, kind: kind)
        },
        InlineRule(pattern: "(?<![_\\w])_(?!_)(.+?)(?<!_)_(?![_\\w])") { storage, range, kind in
            RichTextCodec.toggleTrait(.italicFontMask, in: storage, range: range, kind: kind)
        },
        InlineRule(pattern: "`([^`]+?)`") { storage, range, kind in
            RichTextCodec.toggleInlineCode(in: storage, range: range, kind: kind)
        },
    ]

    private static let regexCache = RegexCache()

    /// Characters that can close an inline rule. Typing anything else cannot
    /// complete one, so the scan is skipped entirely.
    private static let closingDelimiters: Set<Character> = ["*", "_", "~", "`"]

    /// Applies any inline rule whose closing delimiter sits just before the caret.
    ///
    /// - Returns: `true` when the storage was rewritten.
    @discardableResult
    static func applyInlineRules(in storage: NSTextStorage, view: NSTextView, kind: BlockKind) -> Bool {
        let caret = view.selectedRange().location
        guard caret > 0, view.selectedRange().length == 0 else { return false }

        let text = storage.string
        let ns = text as NSString

        // Only a match ending exactly at the caret can fire, so unless the
        // character just typed closes a rule there is nothing to find. This
        // skips six full-text regex scans on the vast majority of keystrokes.
        guard let lastCharacter = Character(UnicodeScalar(ns.character(at: caret - 1)) ?? " ") as Character?,
              closingDelimiters.contains(lastCharacter)
        else { return false }

        for rule in inlineRules {
            guard let regex = regexCache.regex(for: rule.pattern) else { continue }
            let searchRange = NSRange(location: 0, length: ns.length)

            for match in regex.matches(in: text, options: [], range: searchRange) {
                // Only fire for the delimiter the user just completed.
                guard NSMaxRange(match.range) == caret, match.numberOfRanges > 1 else { continue }

                let innerRange = match.range(at: 1)
                let inner = storage.attributedSubstring(from: innerRange)

                let mutable = NSMutableAttributedString(attributedString: inner)
                rule.apply(mutable, NSRange(location: 0, length: mutable.length), kind)

                storage.replaceCharacters(in: match.range, with: mutable)

                let newCaret = match.range.location + mutable.length
                view.setSelectedRange(NSRange(location: newCaret, length: 0))
                // Reset typing attributes so continued typing is unstyled.
                view.typingAttributes = RichTextCodec.baseAttributes(for: kind)
                return true
            }
        }
        return false
    }

    // MARK: - Paste conversion

    /// Parses pasted Markdown into a list of block descriptors.
    ///
    /// Used when the user pastes multiple lines: each becomes its own block,
    /// with indentation preserved as nesting depth.
    struct ParsedLine {
        var kind: BlockKind
        var text: String
        var depth: Int
        var isCompleted: Bool
    }

    /// Pasted text as a list document's lines, which hold one line each, as
    /// the design's do. Markdown that reads as lines comes in as
    /// `parseMarkdown` reads it. Anything else comes in as written, a text
    /// line for each of its lines, trimmed as the design's commit trims a
    /// line, and a fenced block as one code line, which keeps its breaks and
    /// indent. The breaks around the text, as copied lines end with one,
    /// aren't lines.
    static func pasteLines(_ text: String) -> [ParsedLine] {
        let source = text.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .newlines)
        if let lines = readingAsLines(source) { return lines }
        var result: [ParsedLine] = []
        // The open fence's character and length, its indent, and the code so far.
        var fence: (mark: Character, length: Int, indent: Int)?
        var code: [String] = []
        func closeFence() {
            if code.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                result.append(ParsedLine(kind: .code, text: code.joined(separator: "\n"), depth: 0, isCompleted: false))
            }
            fence = nil
            code = []
        }
        for line in source.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let run = trimmed.prefix { $0 == trimmed.first }
            if let open = fence {
                if run.first == open.mark, run.count >= open.length, run.count == trimmed.count {
                    closeFence()
                } else {
                    // Code lines lose only the fence's own indent.
                    code.append(String(line.dropFirst(min(open.indent, line.prefix { $0 == " " }.count))))
                }
            } else if let mark = run.first, mark == "`" || mark == "~", run.count >= 3,
                      mark == "~" || !trimmed.dropFirst(run.count).contains("`") {
                fence = (mark, run.count, line.prefix { $0 == " " }.count)
            } else if !trimmed.isEmpty {
                result.append(ParsedLine(kind: .paragraph, text: trimmed, depth: 0, isCompleted: false))
            }
        }
        // A fence left open runs to the end, as Markdown's does.
        if fence != nil { closeFence() }
        return result
    }

    /// `source` as Markdown lines, or nil when it doesn't read as them.
    private static func readingAsLines(_ source: String) -> [ParsedLine]? {
        let lines = source.components(separatedBy: .newlines)
        let parsed = parseMarkdown(source)
        let unsupported = source.contains("```") || source.contains("~~~")
            || lines.contains { $0.isEmpty || $0.last?.isWhitespace == true }
            || lines.contains { line in
                let indent = line.prefix { $0.isWhitespace }
                return indent.filter { $0 == " " }.count % 2 != 0
                    || indent.contains { $0 != " " && $0 != "\t" }
            }
            || parsed.count != lines.count
        var previousDepth = 0
        let malformedIndent = parsed.enumerated().contains { index, line in
            defer { previousDepth = line.depth }
            return (index == 0 && line.depth != 0) || line.depth > previousDepth + 1
                || (line.depth > 0 && line.kind == .paragraph)
        }
        return unsupported || malformedIndent ? nil : parsed
    }

    static func parseMarkdown(_ source: String) -> [ParsedLine] {
        var results: [ParsedLine] = []

        for rawLine in source.components(separatedBy: .newlines) {
            let leadingSpaces = rawLine.prefix { $0 == " " || $0 == "\t" }
            let depth = leadingSpaces.reduce(0) { $0 + ($1 == "\t" ? 1 : 0) } + (leadingSpaces.filter { $0 == " " }.count / 2)
            var line = rawLine.trimmingCharacters(in: .whitespaces)

            guard !line.isEmpty else { continue }

            var kind = BlockKind.paragraph
            var isCompleted = false

            if line == "---" || line == "***" || line == "___" {
                results.append(ParsedLine(kind: .divider, text: "", depth: depth, isCompleted: false))
                continue
            }

            if line.hasPrefix("### ") {
                kind = .heading3
                line.removeFirst(4)
            } else if line.hasPrefix("## ") {
                kind = .heading2
                line.removeFirst(3)
            } else if line.hasPrefix("# ") {
                kind = .heading1
                line.removeFirst(2)
            } else if line.hasPrefix("> ") {
                kind = .quote
                line.removeFirst(2)
            } else if let taskMatch = matchTaskLine(line) {
                kind = .task
                isCompleted = taskMatch.isCompleted
                line = taskMatch.text
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                kind = .bullet
                line.removeFirst(2)
            } else if let range = line.range(of: "^\\d+[.)]\\s+", options: .regularExpression) {
                kind = .numbered
                line.removeSubrange(range)
            }

            results.append(
                ParsedLine(
                    kind: kind,
                    text: line.trimmingCharacters(in: .whitespaces),
                    depth: depth,
                    isCompleted: isCompleted
                )
            )
        }

        return results
    }

    private static func matchTaskLine(_ line: String) -> (text: String, isCompleted: Bool)? {
        let patterns = ["- [ ] ", "- [x] ", "- [X] ", "* [ ] ", "* [x] ", "[] ", "[ ] ", "[x] "]
        for pattern in patterns where line.hasPrefix(pattern) {
            let completed = pattern.lowercased().contains("[x]")
            return (String(line.dropFirst(pattern.count)), completed)
        }
        return nil
    }
}
