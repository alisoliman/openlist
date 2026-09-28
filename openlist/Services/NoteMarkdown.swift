//
//  NoteMarkdown.swift
//  openlist
//

import Foundation

/// The Markdown a task's note is written in, read for styling: where its
/// headings, emphasis, code, links, lists and quotes are, and which of its
/// characters are syntax. The note stays the text as typed; only its look
/// comes from here.
nonisolated enum NoteMarkdown {
    enum Kind: Equatable {
        /// The text of a `#`, `##` or `###` line.
        case heading(Int)
        case bold
        case italic
        case strike
        case code
        /// A line inside, or fencing, a ``` block.
        case codeBlock
        /// The text of `[text](url)`.
        case link
        /// A bare `https://` address.
        case url
        /// A `- `, `* `, `1. ` or `- [ ] ` line, whose wrapped lines hang
        /// past its first `indent` UTF-16 units.
        case listItem(indent: Int)
        /// The text of a `>` line.
        case quote
        /// The text of a ticked `- [x] ` item.
        case done
        /// Syntax: shown faint while the note is written, hidden otherwise.
        case marker
        /// Syntax that stays shown, faint: a list's bullet or a rule.
        case bullet
    }

    struct Span: Equatable {
        let range: NSRange
        let kind: Kind
    }

    static func spans(in text: String) -> [Span] {
        let source = text as NSString
        var spans: [Span] = []
        var fenced = false
        source.enumerateSubstrings(in: NSRange(location: 0, length: source.length), options: [.byLines, .substringNotRequired]) { _, line, _, _ in
            let content = source.substring(with: line)
            if content.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                fenced.toggle()
                spans.append(Span(range: line, kind: .codeBlock))
                spans.append(Span(range: line, kind: .marker))
                return
            }
            if fenced {
                spans.append(Span(range: line, kind: .codeBlock))
                return
            }
            let body = block(content, at: line.location, into: &spans)
            inline(source, in: body, into: &spans)
        }
        return spans
    }

    // MARK: Lines

    private static let heading = regex(#"^(#{1,3})[ \t]+"#)
    private static let quote = regex(#"^>[ \t]?"#)
    private static let task = regex(#"^([ \t]*)([-*+])[ \t]\[( |x|X)\][ \t]"#)
    private static let list = regex(#"^([ \t]*)([-*+]|\d{1,9}[.)])[ \t]"#)
    private static let rule = regex(#"^[ \t]*([-*_])(?:[ \t]*\1){2,}[ \t]*$"#)

    /// Marks the line's own syntax and returns where its text is, for the inline pass.
    private static func block(_ line: String, at start: Int, into spans: inout [Span]) -> NSRange {
        let length = (line as NSString).length
        let whole = NSRange(location: 0, length: length)
        func shifted(_ range: NSRange) -> NSRange { NSRange(location: range.location + start, length: range.length) }
        let rest: (NSRange) -> NSRange = { prefix in
            shifted(NSRange(location: NSMaxRange(prefix), length: length - NSMaxRange(prefix)))
        }
        if rule.firstMatch(in: line, range: whole) != nil {
            spans.append(Span(range: shifted(whole), kind: .bullet))
            return NSRange(location: start + length, length: 0)
        }
        if let match = heading.firstMatch(in: line, range: whole) {
            let text = rest(match.range)
            spans.append(Span(range: shifted(match.range), kind: .marker))
            spans.append(Span(range: text, kind: .heading(match.range(at: 1).length)))
            return text
        }
        if let match = quote.firstMatch(in: line, range: whole) {
            let text = rest(match.range)
            spans.append(Span(range: shifted(match.range), kind: .marker))
            spans.append(Span(range: text, kind: .quote))
            return text
        }
        if let match = task.firstMatch(in: line, range: whole) {
            let text = rest(match.range)
            spans.append(Span(range: shifted(whole), kind: .listItem(indent: match.range.length)))
            spans.append(Span(range: shifted(match.range), kind: .bullet))
            if (line as NSString).substring(with: match.range(at: 3)) != " " {
                spans.append(Span(range: text, kind: .done))
            }
            return text
        }
        if let match = list.firstMatch(in: line, range: whole) {
            spans.append(Span(range: shifted(whole), kind: .listItem(indent: match.range.length)))
            spans.append(Span(range: shifted(match.range), kind: .bullet))
            return rest(match.range)
        }
        return shifted(whole)
    }

    // MARK: Inline

    private static let code = regex(#"`([^`\n]+)`"#)
    private static let link = regex(#"\[([^\]\n]+)\]\(([^()\s]+)\)"#)
    private static let bareURL = regex(#"https?://[^\s<>()\[\]]+[^\s<>()\[\].,;:!?'"]"#)
    private static let bold = regex(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
    private static let italic = regex(#"(?<![*\w])\*(?=[^\s*])([^*\n]+?)(?<=[^\s*])\*(?![*\w])|(?<![_\w])_(?=[^\s_])([^_\n]+?)(?<=[^\s_])_(?![_\w])"#)
    private static let strike = regex(#"~~(?=\S)(.+?)(?<=\S)~~"#)

    private static func inline(_ source: NSString, in range: NSRange, into spans: inout [Span]) {
        guard range.length > 0 else { return }
        let text = source as String
        // Code and links are taken first; nothing inside them is emphasis.
        var taken: [NSRange] = []
        func free(_ candidate: NSRange) -> Bool {
            !taken.contains { NSIntersectionRange($0, candidate).length > 0 }
        }
        for match in code.matches(in: text, range: range) {
            taken.append(match.range)
            wrap(match.range, inner: match.range(at: 1), kind: .code, into: &spans)
        }
        for match in link.matches(in: text, range: range) where free(match.range) {
            taken.append(match.range)
            let label = match.range(at: 1)
            spans.append(Span(range: NSRange(location: match.range.location, length: 1), kind: .marker))
            spans.append(Span(range: label, kind: .link))
            spans.append(Span(range: NSRange(location: NSMaxRange(label), length: NSMaxRange(match.range) - NSMaxRange(label)), kind: .marker))
        }
        for match in bareURL.matches(in: text, range: range) where free(match.range) {
            taken.append(match.range)
            spans.append(Span(range: match.range, kind: .url))
        }
        for match in bold.matches(in: text, range: range) where free(match.range) {
            wrap(match.range, inner: match.range(at: 2), kind: .bold, into: &spans)
        }
        for match in italic.matches(in: text, range: range) where free(match.range) {
            let inner = match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 2)
            wrap(match.range, inner: inner, kind: .italic, into: &spans)
        }
        for match in strike.matches(in: text, range: range) where free(match.range) {
            wrap(match.range, inner: match.range(at: 1), kind: .strike, into: &spans)
        }
    }

    /// `kind` over `inner`, and what surrounds it in `whole` as markers.
    private static func wrap(_ whole: NSRange, inner: NSRange, kind: Kind, into spans: inout [Span]) {
        spans.append(Span(range: NSRange(location: whole.location, length: inner.location - whole.location), kind: .marker))
        spans.append(Span(range: inner, kind: kind))
        spans.append(Span(range: NSRange(location: NSMaxRange(inner), length: NSMaxRange(whole) - NSMaxRange(inner)), kind: .marker))
    }

    // MARK: Lists

    enum Continuation: Equatable {
        /// Return starts the next item with this.
        case next(String)
        /// Return on an empty item ends the list, taking its bullet off.
        case end(bulletLength: Int)
    }

    /// What Return at the end of `line` does in a list: the next item's
    /// bullet, the number one on, and a new task unticked; or, on an item
    /// with nothing written, the list ends.
    static func continuation(of line: String) -> Continuation? {
        let whole = NSRange(location: 0, length: (line as NSString).length)
        let match = task.firstMatch(in: line, range: whole) ?? list.firstMatch(in: line, range: whole)
        guard let match else { return nil }
        let text = line as NSString
        if text.substring(from: NSMaxRange(match.range)).trimmingCharacters(in: .whitespaces).isEmpty {
            return .end(bulletLength: match.range.length)
        }
        let indent = text.substring(with: match.range(at: 1))
        let bullet = text.substring(with: match.range(at: 2))
        if match.numberOfRanges > 3, match.range(at: 3).location != NSNotFound {
            return .next("\(indent)\(bullet) [ ] ")
        }
        if let number = Int(bullet.dropLast()) {
            return .next("\(indent)\(number + 1)\(bullet.suffix(1)) ")
        }
        return .next("\(indent)\(bullet) ")
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // The patterns are fixed, so one that fails to compile is a bug here.
        try! NSRegularExpression(pattern: pattern)
    }
}
