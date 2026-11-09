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
        /// The whole inline construct the span belongs to, its markers too:
        /// what a caret inside it shows the syntax of while the note is
        /// written. Nil for a line's own syntax, which stays hidden.
        var group: NSRange? = nil
        /// Where a link or a bare address goes, as written.
        var address: String? = nil
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
    private static let bareURL = regex(#"(?:https?|openlist(?:-dev)?)://[^\s<>()\[\]]+[^\s<>()\[\].,;:!?'"]"#)
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
            let whole = match.range, label = match.range(at: 1)
            let address = source.substring(with: match.range(at: 2))
            spans.append(Span(range: NSRange(location: whole.location, length: 1), kind: .marker, group: whole))
            spans.append(Span(range: label, kind: .link, group: whole, address: address))
            spans.append(Span(range: NSRange(location: NSMaxRange(label), length: NSMaxRange(whole) - NSMaxRange(label)), kind: .marker,
                              group: whole))
        }
        for match in bareURL.matches(in: text, range: range) where free(match.range) {
            taken.append(match.range)
            spans.append(Span(range: match.range, kind: .url, group: match.range, address: source.substring(with: match.range)))
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
        spans.append(Span(range: NSRange(location: whole.location, length: inner.location - whole.location), kind: .marker, group: whole))
        spans.append(Span(range: inner, kind: kind, group: whole))
        spans.append(Span(range: NSRange(location: NSMaxRange(inner), length: NSMaxRange(whole) - NSMaxRange(inner)), kind: .marker,
                          group: whole))
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

    // MARK: Links

    private static let soleBareURL = regex(#"^(?:https?|openlist(?:-dev)?)://\S+$"#)
    private static let soleMarkdownLink = regex(#"^\[[^\]\n]+\]\(([^()\s]+)\)$"#)

    /// The link a note is made of when it holds nothing else: one bare
    /// address, or one `[words](address)`, alone. A row shows such a note as
    /// a link that opens, rather than as text to read.
    static func soleLink(in note: String) -> URL? {
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(where: \.isNewline) else { return nil }
        let whole = NSRange(location: 0, length: (text as NSString).length)
        if soleBareURL.firstMatch(in: text, range: whole) != nil { return openable(text) }
        guard let match = soleMarkdownLink.firstMatch(in: text, range: whole) else { return nil }
        return openable((text as NSString).substring(with: match.range(at: 1)))
    }

    /// An address a click may open: on the web, a mail, or an item in this
    /// library. Anything else stays text.
    static func openable(_ address: String) -> URL? {
        guard let url = URL(string: address), let scheme = url.scheme?.lowercased(),
              ["http", "https", "mailto", "openlist", "openlist-dev"].contains(scheme) else { return nil }
        if scheme.hasPrefix("http"), url.host?.isEmpty != false { return nil }
        return url
    }

    /// Where an address goes, short enough to name it: its host without
    /// `www.`, and the first step of its path, as `google.com/maps`.
    static func shortAddress(_ url: URL) -> String {
        if url.scheme?.lowercased().hasPrefix("openlist") == true { return "Openlist" }
        guard let host = url.host, !host.isEmpty else { return url.absoluteString }
        let name = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        guard let first = url.pathComponents.first(where: { $0 != "/" && !$0.isEmpty }) else { return name }
        return name + "/" + first
    }

    // MARK: Plain text

    /// The note as words to read in a line or two, like triage's preview:
    /// the Markdown's syntax left out, a link's words kept, a bare address
    /// shortened to where it goes, list items as bullets, and no blank runs.
    static func plainText(_ note: String) -> String {
        let source = note as NSString
        var drops: [NSRange] = []
        var swaps: [(NSRange, String)] = []
        for span in spans(in: note) where span.range.length > 0 {
            switch span.kind {
            case .marker:
                drops.append(span.range)
            case .url:
                let address = source.substring(with: span.range)
                swaps.append((span.range, URL(string: address).map(shortAddress) ?? address))
            case .bullet:
                // A list's bullet or box reads as a bullet; a rule as nothing.
                let syntax = source.substring(with: span.range).trimmingCharacters(in: .whitespaces)
                let rule = syntax.allSatisfy { "-*_ \t".contains($0) } && syntax.count >= 3
                swaps.append((span.range, rule ? "" : "• "))
            default:
                break
            }
        }
        let edits = (drops.map { ($0, "") } + swaps).sorted { $0.0.location > $1.0.location }
        let result = NSMutableString(string: note)
        var floor = source.length
        for (range, replacement) in edits where NSMaxRange(range) <= floor {
            result.replaceCharacters(in: range, with: replacement)
            floor = range.location
        }
        let lines = (result as String).components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        var kept: [String] = []
        for line in lines where !(line.isEmpty && (kept.last?.isEmpty ?? true)) { kept.append(line) }
        return kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Lines

    /// One line of a note, read for how it's drawn: what kind of block it
    /// is, and the syntax at its start the note leaves out of sight.
    struct Line: Equatable {
        enum Kind: Equatable {
            case text
            case heading(Int)
            case bullet
            case numbered
            case task(done: Bool)
            case quote
            /// An opening or closing ``` line.
            case fence
            /// A line inside a fenced block.
            case code
            /// `---` and its kin.
            case rule
            /// A line that's one link and nothing else, drawn as a bookmark:
            /// where it goes, and the words it was given, if any.
            case bookmark(URL, title: String?)
        }

        /// The line, without its break.
        let range: NSRange
        let kind: Kind
        /// The syntax that opens the line, its indent too: hashes, a quote's
        /// mark, a list's bullet or box. Empty where there's none.
        let prefix: NSRange
        /// How far a list item is nested: its indent in steps of two spaces
        /// or a tab.
        var depth = 0

        /// Lines whose opening syntax is never shown: the caret stays after it.
        var hidesPrefix: Bool {
            switch kind {
            case .heading, .bullet, .task, .quote: true
            default: false
            }
        }
    }

    static func lines(in text: String) -> [Line] {
        let source = text as NSString
        var lines: [Line] = []
        var fenced = false
        source.enumerateSubstrings(in: NSRange(location: 0, length: source.length), options: [.byLines, .substringNotRequired]) { _, range, _, _ in
            let content = source.substring(with: range)
            let whole = NSRange(location: 0, length: range.length)
            let empty = NSRange(location: range.location, length: 0)
            func shifted(_ prefix: NSRange) -> NSRange { NSRange(location: range.location + prefix.location, length: prefix.length) }
            if content.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                fenced.toggle()
                lines.append(Line(range: range, kind: .fence, prefix: empty))
                return
            }
            if fenced {
                lines.append(Line(range: range, kind: .code, prefix: empty))
                return
            }
            if rule.firstMatch(in: content, range: whole) != nil {
                lines.append(Line(range: range, kind: .rule, prefix: empty))
            } else if let match = heading.firstMatch(in: content, range: whole) {
                lines.append(Line(range: range, kind: .heading(match.range(at: 1).length), prefix: shifted(match.range)))
            } else if let match = quote.firstMatch(in: content, range: whole) {
                lines.append(Line(range: range, kind: .quote, prefix: shifted(match.range)))
            } else if let match = task.firstMatch(in: content, range: whole) {
                let done = (content as NSString).substring(with: match.range(at: 3)) != " "
                lines.append(Line(range: range, kind: .task(done: done), prefix: shifted(match.range),
                                  depth: depth((content as NSString).substring(with: match.range(at: 1)))))
            } else if let match = list.firstMatch(in: content, range: whole) {
                let bullet = (content as NSString).substring(with: match.range(at: 2))
                lines.append(Line(range: range, kind: "-*+".contains(bullet) ? .bullet : .numbered, prefix: shifted(match.range),
                                  depth: depth((content as NSString).substring(with: match.range(at: 1)))))
            } else if let bookmark = bookmark(in: content) {
                lines.append(Line(range: range, kind: bookmark, prefix: empty))
            } else {
                lines.append(Line(range: range, kind: .text, prefix: empty))
            }
        }
        return lines
    }

    /// Two spaces, or a tab, nest a list item one step.
    private static func depth(_ indent: String) -> Int {
        indent.reduce(0) { $0 + ($1 == "\t" ? 2 : 1) } / 2
    }

    /// A line that's one bare address, or one `[words](address)`, alone.
    private static func bookmark(in line: String) -> Line.Kind? {
        let text = line.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, text.count == line.count else { return nil }
        let whole = NSRange(location: 0, length: (text as NSString).length)
        if soleBareURL.firstMatch(in: text, range: whole) != nil {
            return openable(text).map { .bookmark($0, title: nil) }
        }
        guard let match = soleMarkdownLink.firstMatch(in: text, range: whole),
              let url = openable((text as NSString).substring(with: match.range(at: 1))) else { return nil }
        let words = (text as NSString).substring(with: NSRange(location: 1, length: match.range(at: 1).location - 3))
        return .bookmark(url, title: words)
    }

    /// The words a bookmark goes by when it was given none, read from its
    /// address alone, as nothing is fetched: a Maps place's name, else its
    /// last step put back into words, else its site.
    static func linkTitle(for url: URL) -> String {
        let steps = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        // An item in this library, whose name isn't in its address.
        if url.scheme?.lowercased().hasPrefix("openlist") == true {
            return steps.contains("list") ? "A list in Openlist" : "A task in Openlist"
        }
        let site = shortAddress(url).components(separatedBy: "/").first ?? shortAddress(url)
        if url.host?.contains("google.") == true, let place = steps.firstIndex(of: "place"), place + 1 < steps.count {
            let name = words(steps[place + 1])
            if !name.isEmpty { return name }
        }
        for step in steps.reversed() {
            let stem = (step as NSString).deletingPathExtension
            guard stem.lowercased() != "index", stem.contains(where: \.isLetter), !stem.hasPrefix("@") else { continue }
            let name = words(stem)
            guard !name.isEmpty else { continue }
            return name.prefix(1).uppercased() + name.dropFirst()
        }
        return site
    }

    /// A path step as words: `+`, `-` and `_` as spaces, escapes undone.
    private static func words(_ step: String) -> String {
        let spaced = step.replacingOccurrences(of: "+", with: " ")
        let decoded = spaced.removingPercentEncoding ?? spaced
        return decoded.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
            .split(separator: " ").joined(separator: " ")
    }

    // MARK: Blocks

    /// What the note's `/` menu turns a line into, and the Markdown each
    /// starts the line with.
    enum Block: CaseIterable, Equatable {
        case text, heading1, heading2, heading3, bullet, numbered, checklist, quote, code, divider

        var label: String {
            switch self {
            case .text: "Text"
            case .heading1: "Heading 1"
            case .heading2: "Heading 2"
            case .heading3: "Heading 3"
            case .bullet: "Bullet list"
            case .numbered: "Numbered list"
            case .checklist: "Checklist"
            case .quote: "Quote"
            case .code: "Code"
            case .divider: "Divider"
            }
        }

        var symbol: String {
            switch self {
            case .text: "text.alignleft"
            case .heading1: "textformat.size.larger"
            case .heading2: "textformat.size"
            case .heading3: "textformat.size.smaller"
            case .bullet: "list.bullet"
            case .numbered: "list.number"
            case .checklist: "checklist"
            case .quote: "text.quote"
            case .code: "chevron.left.forwardslash.chevron.right"
            case .divider: "minus"
            }
        }

        /// The shortcut that makes the same block as it's typed.
        var shortcut: String {
            switch self {
            case .text: ""
            case .heading1: "#"
            case .heading2: "##"
            case .heading3: "###"
            case .bullet: "-"
            case .numbered: "1."
            case .checklist: "[]"
            case .quote: ">"
            case .code: "```"
            case .divider: "---"
            }
        }

        private var terms: [String] {
            switch self {
            case .text: ["text", "paragraph", "plain"]
            case .heading1: ["heading", "h1", "title"]
            case .heading2: ["heading", "h2", "subheading"]
            case .heading3: ["heading", "h3"]
            case .bullet: ["bullet", "list", "unordered"]
            case .numbered: ["numbered", "list", "ordered"]
            case .checklist: ["checklist", "todo", "task", "checkbox", "box"]
            case .quote: ["quote", "blockquote"]
            case .code: ["code", "snippet"]
            case .divider: ["divider", "rule", "line", "separator"]
            }
        }

        /// The blocks a `/query` brings up, in the menu's order.
        static func matching(_ query: String) -> [Block] {
            let needle = query.lowercased().trimmingCharacters(in: .whitespaces)
            guard !needle.isEmpty else { return allCases }
            return allCases.filter { block in
                block.label.lowercased().contains(needle) || block.terms.contains { $0.hasPrefix(needle) }
            }
        }

        /// `line`'s words as this block, its own syntax taken off first, and
        /// where the caret goes in what's returned.
        func line(from text: String) -> (text: String, caret: Int) {
            let words = NoteMarkdown.words(of: text)
            switch self {
            case .text: return (words, 0)
            case .heading1: return ("# " + words, 2)
            case .heading2: return ("## " + words, 3)
            case .heading3: return ("### " + words, 4)
            case .bullet: return ("- " + words, 2)
            case .numbered: return ("1. " + words, 3)
            case .checklist: return ("- [ ] " + words, 6)
            case .quote: return ("> " + words, 2)
            case .code: return ("```\n" + words + "\n```", 4)
            case .divider: return ("---\n" + words, 4)
            }
        }
    }

    /// A line's words without the syntax that opens it.
    static func words(of line: String) -> String {
        guard let first = lines(in: line).first, first.prefix.length > 0 else { return line }
        return (line as NSString).substring(from: first.prefix.length)
    }

    // MARK: Typing

    /// A box typed as the list document's shortcut, `[]` or `[ ]`, which the
    /// space after it turns into a checklist item.
    static func isChecklistShortcut(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed == "[]" || trimmed == "[ ]"
    }

    /// The checklist item on `line` ticked, or unticked.
    static func toggledTask(_ line: String) -> String? {
        let whole = NSRange(location: 0, length: (line as NSString).length)
        guard let match = task.firstMatch(in: line, range: whole) else { return nil }
        let box = match.range(at: 3)
        let ticked = (line as NSString).substring(with: box) != " "
        return (line as NSString).replacingCharacters(in: box, with: ticked ? " " : "x")
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // The patterns are fixed, so one that fails to compile is a bug here.
        try! NSRegularExpression(pattern: pattern)
    }
}
