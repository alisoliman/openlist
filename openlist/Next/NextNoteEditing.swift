//
//  NextNoteEditing.swift
//  openlist
//

import AppKit
import SwiftUI

/// The note's `/` menu while it's open: what's typed after the slash, the
/// choice highlighted, where the slash is, and the caret's line in the note
/// view's own space, for the menu to sit under.
struct NXNoteSlash: Equatable {
    var query = ""
    var selected = 0
    /// The "/" and its query, which a choice replaces.
    var range: NSRange
    var line: CGRect = .zero
    var blocks: [NoteMarkdown.Block] { NoteMarkdown.Block.matching(query) }
}

/// What a click on the note lands on, other than its words.
enum NXNoteWidget: Equatable {
    /// A checklist item's box, by its line's start.
    case box(Int)
    case link(URL)
}

/// What the note was last styled from, so an unchanged note isn't styled again.
struct NXNoteStyleKey: Equatable {
    let text: String
    let writing: Bool
    /// The line the caret's on while the note is written: its syntax shows
    /// where that line is a divider, a fence or a bookmark.
    let caretLine: Int?
    /// The inline construct the caret's inside, whose markers show.
    let group: NSRange?
    let large: Bool
    let accent: ObjectIdentifier
}

/// Something drawn under the note's words: a list's bullet or box, a
/// quote's rule, a code block's fill, a divider or a bookmark's card.
nonisolated struct NXNoteDecoration {
    enum Kind {
        case bullet
        case box(done: Bool)
        case quote
        /// From its opening fence's line to its closing one's.
        case code(through: NSRange)
        case rule
        case bookmark(URL, title: String, site: String)
    }

    let kind: Kind
    /// The line it belongs to.
    let line: NSRange
    /// Where a list item's gutter starts.
    var indent: CGFloat = 0
}

/// The note's ink, shared instances as `NXEditor`'s are: attributed
/// strings compare dynamic colours by identity.
nonisolated enum NXNoteInk {
    /// Syntax the caret is in, shown faint.
    static let syntax = NXEditor.ink.withAlphaComponent(0.3)
    /// `NX.textTertiary`: a quote steps back from the note around it.
    static let quote = NXEditor.inkColor(light: 0.62, dark: 0.56)
    static let done = NXEditor.ink.withAlphaComponent(0.45)
    static let codeFill = NXEditor.ink.withAlphaComponent(0.05)
    static let rule = NXEditor.ink.withAlphaComponent(0.12)
    static let bullet = NXEditor.ink.withAlphaComponent(0.55)
    static let boxRing = NXEditor.ink.withAlphaComponent(0.38)
    static let quoteRule = NXEditor.ink.withAlphaComponent(0.16)
    static let cardFill = NXEditor.ink.withAlphaComponent(0.03)
    static let cardRing = NXEditor.ink.withAlphaComponent(0.11)
    static let iconFill = NXEditor.ink.withAlphaComponent(0.06)
    static let site = NXEditor.inkColor(light: 0.55, dark: 0.5)
    /// Syntax out of sight: a face too small to take room, in no colour.
    /// Unlike a null glyph, it keeps a line that's only syntax, like an
    /// empty checklist item, a line of its own.
    nonisolated(unsafe) static let hiddenFont = NSFont.systemFont(ofSize: 0.01)
}

extension NSAttributedString.Key {
    /// Where a note's link or bare address goes, whether or not it's live.
    nonisolated static let nxNoteAddress = NSAttributedString.Key("openlist.noteAddress")
}

/// Lays the note out as TextKit does, then draws its decorations under the
/// words.
nonisolated final class NXNoteLayoutManager: NSLayoutManager {
    var decorations: [NXNoteDecoration] = []
    /// The note's body face, to set things on a line by.
    var bodyFont: NSFont = .systemFont(ofSize: 13.5)

    /// A list level's gutter, where its bullet or box sits.
    static let gutter: CGFloat = 22
    static let boxSize: CGFloat = 13
    /// A bookmark's line, its card inside it.
    static let cardLine: CGFloat = 52

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let width = textContainers.first?.size.width else { return }
        for decoration in decorations { draw(decoration, at: origin, width: width) }
    }

    /// The first line fragment of the line starting at `location`, and its
    /// first baseline in it.
    func firstLine(at index: Int) -> (rect: CGRect, baseline: CGFloat)? {
        guard let storage = textStorage, index < storage.length else { return nil }
        let glyph = glyphIndexForCharacter(at: index)
        guard glyph < numberOfGlyphs else { return nil }
        let rect = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        return (rect, location(forGlyphAt: glyph).y)
    }

    /// The last line fragment of `line`.
    func lastLine(of line: NSRange) -> CGRect? {
        guard let storage = textStorage, line.location < storage.length else { return nil }
        let end = max(line.location, min(NSMaxRange(line), storage.length) - 1)
        let glyph = glyphIndexForCharacter(at: end)
        guard glyph < numberOfGlyphs else { return nil }
        return lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
    }

    /// A checklist item's box, in the text container's space.
    func boxRect(for decoration: NXNoteDecoration) -> CGRect? {
        guard case .box = decoration.kind, let first = firstLine(at: decoration.line.location) else { return nil }
        let centre = first.rect.minY + first.baseline - bodyFont.capHeight / 2
        return CGRect(x: decoration.indent + 2, y: (centre - Self.boxSize / 2).rounded(), width: Self.boxSize, height: Self.boxSize)
    }

    /// A bookmark's card, in the text container's space.
    func cardRect(for decoration: NXNoteDecoration, width: CGFloat) -> CGRect? {
        guard case .bookmark = decoration.kind, let first = firstLine(at: decoration.line.location) else { return nil }
        return CGRect(x: 0, y: first.rect.minY + 4, width: min(width, 460), height: first.rect.height - 8)
    }

    private func draw(_ decoration: NXNoteDecoration, at origin: NSPoint, width: CGFloat) {
        switch decoration.kind {
        case .bullet:
            guard let first = firstLine(at: decoration.line.location) else { return }
            let centre = first.rect.minY + first.baseline - bodyFont.xHeight / 2
            let dot = CGRect(x: origin.x + decoration.indent + 7, y: origin.y + centre - 2.5, width: 5, height: 5)
            NXNoteInk.bullet.setFill()
            NSBezierPath(ovalIn: dot).fill()
        case let .box(done):
            guard let rect = boxRect(for: decoration)?.offsetBy(dx: origin.x, dy: origin.y) else { return }
            let box = NSBezierPath(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), xRadius: 3.5, yRadius: 3.5)
            if done {
                NXEditor.ink.setFill()
                NSBezierPath(roundedRect: rect, xRadius: 3.5, yRadius: 3.5).fill()
                let tick = NSBezierPath()
                tick.move(to: CGPoint(x: rect.minX + 3.2, y: rect.midY + 0.2))
                tick.line(to: CGPoint(x: rect.minX + 5.6, y: rect.maxY - 3.6))
                tick.line(to: CGPoint(x: rect.maxX - 3, y: rect.minY + 3.6))
                tick.lineWidth = 1.7
                tick.lineCapStyle = .round
                tick.lineJoinStyle = .round
                // The paper's colour on ink, in either appearance.
                NSColor(name: nil) { appearance in
                    appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .black : .white
                }.setStroke()
                tick.stroke()
            } else {
                NXNoteInk.boxRing.setStroke()
                box.lineWidth = 1.5
                box.stroke()
            }
        case .quote:
            guard let first = firstLine(at: decoration.line.location), let last = lastLine(of: decoration.line) else { return }
            let rule = CGRect(x: origin.x, y: origin.y + first.rect.minY + 2, width: 2, height: last.maxY - first.rect.minY - 4)
            NXNoteInk.quoteRule.setFill()
            NSBezierPath(roundedRect: rule, xRadius: 1, yRadius: 1).fill()
        case let .code(through):
            guard let first = firstLine(at: decoration.line.location), let last = lastLine(of: through) else { return }
            let block = CGRect(x: origin.x, y: origin.y + first.rect.minY, width: width, height: last.maxY - first.rect.minY)
            NXNoteInk.codeFill.setFill()
            NSBezierPath(roundedRect: block, xRadius: 7, yRadius: 7).fill()
        case .rule:
            guard let first = firstLine(at: decoration.line.location) else { return }
            NXNoteInk.rule.setFill()
            CGRect(x: origin.x, y: (origin.y + first.rect.midY).rounded(), width: width, height: 1).fill()
        case let .bookmark(url, title, site):
            guard let card = cardRect(for: decoration, width: width)?.offsetBy(dx: origin.x, dy: origin.y) else { return }
            drawCard(card, url: url, title: title, site: site)
        }
    }

    private func drawCard(_ card: CGRect, url: URL, title: String, site: String) {
        let shape = NSBezierPath(roundedRect: card.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9)
        NXNoteInk.cardFill.setFill()
        shape.fill()
        NXNoteInk.cardRing.setStroke()
        shape.lineWidth = 1
        shape.stroke()
        let icon = CGRect(x: card.minX + 7, y: card.midY - 14, width: 28, height: 28)
        NXNoteInk.iconFill.setFill()
        NSBezierPath(roundedRect: icon, xRadius: 7, yRadius: 7).fill()
        let symbol = url.host?.contains("google.") == true && url.path.contains("/maps") ? "mappin.and.ellipse" : "globe"
        let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            .applying(.init(paletteColors: [NXEditor.secondaryInk]))
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) {
            let size = image.size
            image.draw(in: CGRect(x: icon.midX - size.width / 2, y: icon.midY - size.height / 2, width: size.width, height: size.height),
                       from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        let words = CGRect(x: icon.maxX + 10, y: card.minY, width: max(0, card.maxX - icon.maxX - 22), height: card.height)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let titleText = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NXEditor.ink, .paragraphStyle: paragraph,
        ])
        let siteText = NSAttributedString(string: site, attributes: [
            .font: NSFont.systemFont(ofSize: 11.5), .foregroundColor: NXNoteInk.site, .paragraphStyle: paragraph,
        ])
        titleText.draw(with: CGRect(x: words.minX, y: card.midY - 16, width: words.width, height: 17),
                       options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        siteText.draw(with: CGRect(x: words.minX, y: card.midY + 1, width: words.width, height: 15),
                      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
}

// MARK: - The note's styling and editing

extension NXInspectorTextView {
    var noteLayout: NXNoteLayoutManager? { layoutManager as? NXNoteLayoutManager }

    /// The note's Markdown as it reads, with its syntax out of sight: a
    /// line's own syntax always, and an inline construct's unless the caret
    /// is inside it while the note is written, so clicking in moves nothing.
    /// A divider, a code fence and a bookmark show what they're written as
    /// while the caret's on their line. Only the look changes; the note
    /// stays the text typed.
    func styleNote() {
        guard !hasMarkedText(), let storage = textStorage else { return }
        let text = storage.string
        let selection = selectedRange()
        let lines = NoteMarkdown.lines(in: text)
        let spans = NoteMarkdown.spans(in: text)
        let caret = isWriting ? selection.location : nil
        let caretLine = caret.flatMap { caret in
            lines.first { caret >= $0.range.location && caret <= NSMaxRange($0.range) }?.range.location
        }
        let group = caret.flatMap { caret in
            spans.first { span in span.group.map { caret >= $0.location && caret <= NSMaxRange($0) } ?? false }?.group
        }
        let key = NXNoteStyleKey(text: text, writing: isWriting, caretLine: caretLine, group: group, large: isLarge,
                                 accent: ObjectIdentifier(accent))
        guard key != noteStyleKey else { return }
        noteStyleKey = key
        noteLayout?.bodyFont = metrics.font
        linkTextAttributes = [.foregroundColor: accent, .underlineStyle: NSUnderlineStyle.single.rawValue,
                              .underlineColor: accent.withAlphaComponent(0.4), .cursor: NSCursor.pointingHand]
        let whole = NSRange(location: 0, length: storage.length)
        guard whole.length > 0 else {
            noteLayout?.decorations = []
            return
        }
        let source = text as NSString
        let metrics = self.metrics
        var decorations: [NXNoteDecoration] = []
        func hide(_ range: NSRange) {
            guard range.length > 0 else { return }
            storage.addAttributes([.font: NXNoteInk.hiddenFont, .foregroundColor: NSColor.clear], range: range)
        }
        func paragraph(_ line: NoteMarkdown.Line, _ edit: (NSMutableParagraphStyle) -> Void) {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = metrics.leading
            // A line that's only hidden syntax keeps a line's height.
            style.minimumLineHeight = metrics.line - metrics.leading
            edit(style)
            storage.addAttribute(.paragraphStyle, value: style, range: source.paragraphRange(for: line.range))
        }
        func words(of line: NoteMarkdown.Line) -> NSRange {
            NSRange(location: NSMaxRange(line.prefix), length: NSMaxRange(line.range) - NSMaxRange(line.prefix))
        }

        storage.beginEditing()
        storage.setAttributes(metrics.attributes, range: whole)
        var openFence: NSRange?
        /// Bookmarks drawn as cards, whose words their card covers.
        var cards: [NSRange] = []
        for (index, line) in lines.enumerated() {
            let onCaret = caretLine == line.range.location
            switch line.kind {
            case .text:
                break
            case let .heading(level):
                hide(line.prefix)
                storage.addAttributes([.font: metrics.headingFonts[min(max(level, 1), 3) - 1], .foregroundColor: NXEditor.ink],
                                      range: words(of: line))
                // A heading opens a section: room above it, none under, and
                // less where a blank line already stands before it.
                let afterBlank = line.range.location >= 2
                    && source.substring(with: NSRange(location: line.range.location - 2, length: 2)) == "\n\n"
                paragraph(line) {
                    $0.paragraphSpacingBefore = index == 0 ? 0 : (metrics.lineBox * (afterBlank ? 0.15 : 0.6)).rounded()
                }
            case .bullet, .task:
                hide(line.prefix)
                let indent = CGFloat(line.depth) * NXNoteLayoutManager.gutter
                paragraph(line) {
                    $0.firstLineHeadIndent = indent + NXNoteLayoutManager.gutter
                    $0.headIndent = indent + NXNoteLayoutManager.gutter
                }
                if case let .task(done) = line.kind {
                    decorations.append(NXNoteDecoration(kind: .box(done: done), line: line.range, indent: indent))
                    if done {
                        storage.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue,
                                               .strikethroughColor: NXNoteInk.done, .foregroundColor: NXNoteInk.done],
                                              range: words(of: line))
                    }
                } else {
                    decorations.append(NXNoteDecoration(kind: .bullet, line: line.range, indent: indent))
                }
            case .numbered:
                // The number is the item's own: it stays, set back, and the
                // item's lines hang past it.
                storage.addAttribute(.foregroundColor, value: NXNoteInk.quote, range: line.prefix)
                let number = source.substring(with: line.prefix)
                let hang = ceil((number as NSString).size(withAttributes: [.font: metrics.font]).width)
                paragraph(line) { $0.headIndent = hang }
            case .quote:
                hide(line.prefix)
                storage.addAttribute(.foregroundColor, value: NXNoteInk.quote, range: words(of: line))
                paragraph(line) {
                    $0.firstLineHeadIndent = 14
                    $0.headIndent = 14
                }
                decorations.append(NXNoteDecoration(kind: .quote, line: line.range))
            case .fence:
                if let start = openFence {
                    decorations.append(NXNoteDecoration(kind: .code(through: line.range), line: start))
                    openFence = nil
                } else {
                    openFence = line.range
                }
                if onCaret {
                    storage.addAttributes([.font: metrics.codeFont, .foregroundColor: NXNoteInk.syntax], range: line.range)
                    paragraph(line) { $0.firstLineHeadIndent = 12 }
                } else {
                    // Out of sight, its line is the block's padding.
                    hide(line.range)
                    paragraph(line) {
                        $0.lineSpacing = 0
                        $0.minimumLineHeight = 8
                        $0.maximumLineHeight = 8
                    }
                }
            case .code:
                storage.addAttribute(.font, value: metrics.codeFont, range: line.range)
                paragraph(line) {
                    $0.firstLineHeadIndent = 12
                    $0.headIndent = 12
                    $0.tailIndent = -12
                }
            case .rule:
                if onCaret {
                    storage.addAttribute(.foregroundColor, value: NXNoteInk.syntax, range: line.range)
                } else {
                    hide(line.range)
                    decorations.append(NXNoteDecoration(kind: .rule, line: line.range))
                }
            case let .bookmark(url, title):
                guard !onCaret else { break }
                cards.append(line.range)
                // Its address stays the text, out of sight under its card.
                storage.addAttributes([.foregroundColor: NSColor.clear, .nxNoteAddress: url], range: line.range)
                paragraph(line) {
                    $0.lineSpacing = 0
                    $0.minimumLineHeight = NXNoteLayoutManager.cardLine
                    $0.maximumLineHeight = NXNoteLayoutManager.cardLine
                    $0.lineBreakMode = .byClipping
                }
                decorations.append(NXNoteDecoration(kind: .bookmark(url, title: title ?? NoteMarkdown.linkTitle(for: url),
                                                                    site: NoteMarkdown.shortAddress(url)), line: line.range))
            }
        }
        // A block not yet closed runs to the note's end.
        if let start = openFence, let last = lines.last {
            decorations.append(NXNoteDecoration(kind: .code(through: last.range), line: start))
        }
        for span in spans {
            guard let construct = span.group, !cards.contains(where: { NSIntersectionRange($0, span.range).length > 0 }) else {
                continue
            }
            let shows = construct == group
            switch span.kind {
            case .marker:
                if shows { storage.addAttribute(.foregroundColor, value: NXNoteInk.syntax, range: span.range) } else { hide(span.range) }
            case .bold:
                convertFonts(in: storage, range: span.range, to: .boldFontMask)
            case .italic:
                convertFonts(in: storage, range: span.range, to: .italicFontMask)
            case .strike:
                storage.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: NXNoteInk.done],
                                      range: span.range)
            case .code:
                storage.addAttributes([.font: metrics.codeFont, .backgroundColor: NXNoteInk.codeFill], range: span.range)
            case .link, .url:
                let url = span.address.flatMap(NoteMarkdown.openable)
                var link: [NSAttributedString.Key: Any] = [.foregroundColor: accent, .underlineStyle: NSUnderlineStyle.single.rawValue,
                                                            .underlineColor: accent.withAlphaComponent(0.4)]
                if let url {
                    link[.nxNoteAddress] = url
                    // Live at rest, where a click opens it; written, ⌘-click does.
                    if !isWriting { link[.link] = url }
                }
                storage.addAttributes(link, range: span.range)
            default:
                break
            }
        }
        storage.endEditing()
        // A face changed under laid-out glyphs, as hiding and showing syntax
        // changes them, needs them made again: TextKit only redoes their
        // layout for an attribute change.
        layoutManager?.invalidateGlyphs(forCharacterRange: whole, changeInLength: 0, actualCharacterRange: nil)
        layoutManager?.invalidateLayout(forCharacterRange: whole, actualCharacterRange: nil)
        noteLayout?.decorations = decorations
        typingAttributes = metrics.attributes
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    private func convertFonts(in storage: NSTextStorage, range: NSRange, to trait: NSFontTraitMask) {
        storage.enumerateAttribute(.font, in: range) { value, run, _ in
            guard let font = value as? NSFont, font.pointSize > 1 else { return }
            storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: trait), range: run)
        }
    }

    // MARK: Caret

    /// The line holding `location`, its break left out.
    func noteLine(at location: Int) -> NoteMarkdown.Line? {
        NoteMarkdown.lines(in: string).first { location >= $0.range.location && location <= NSMaxRange($0.range) }
    }

    /// Where a caret at `location` goes: past a line's hidden syntax.
    func snapped(_ location: Int) -> Int {
        guard let line = noteLine(at: location), line.hidesPrefix, location < NSMaxRange(line.prefix) else { return location }
        return NSMaxRange(line.prefix)
    }

    /// A caret moved inside a line's hidden syntax goes to the words after
    /// it, or, stepping back from them, to the line before.
    func snapped(_ ranges: [NSValue], from old: [NSValue]) -> [NSValue] {
        guard isWriting, ranges.count == 1, let new = ranges.first?.rangeValue, new.length == 0 else { return ranges }
        guard let line = noteLine(at: new.location), line.hidesPrefix, line.prefix.length > 0,
              new.location >= line.prefix.location, new.location < NSMaxRange(line.prefix) else { return ranges }
        let end = NSMaxRange(line.prefix)
        let previous = old.first?.rangeValue
        if previous == NSRange(location: end, length: 0), new.location == end - 1, line.range.location > 0 {
            return [NSValue(range: NSRange(location: line.range.location - 1, length: 0))]
        }
        return [NSValue(range: NSRange(location: end, length: 0))]
    }

    func selectionDidChangeInNote() {
        restyle()
        // Typing after a line's hidden syntax is in the note's own face.
        typingAttributes = metrics.attributes
        updateSlash()
        InlineFormatting.shared.update(self, focused: window?.firstResponder === self)
    }

    func textDidChangeInNote() {
        updateSlash()
    }

    // MARK: Clicks

    /// A box, or a link that opens: at rest, or with ⌘ while written.
    func noteWidget(at point: NSPoint, command: Bool) -> NXNoteWidget? {
        guard let layout = noteLayout, let container = textContainer, let storage = textStorage else { return nil }
        let origin = textContainerOrigin
        let local = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
        for decoration in layout.decorations {
            if let box = layout.boxRect(for: decoration), box.insetBy(dx: -4, dy: -4).contains(local) {
                return .box(decoration.line.location)
            }
            if case let .bookmark(url, _, _) = decoration.kind, let card = layout.cardRect(for: decoration, width: container.size.width),
               card.contains(local) {
                return .link(url)
            }
        }
        guard !isWriting || command, storage.length > 0 else { return nil }
        var fraction: CGFloat = 0
        let glyph = layout.glyphIndex(for: local, in: container, fractionOfDistanceThroughGlyph: &fraction)
        guard glyph < layout.numberOfGlyphs,
              layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).insetBy(dx: -1, dy: -2).contains(local)
        else { return nil }
        let index = layout.characterIndexForGlyph(at: glyph)
        guard index < storage.length, let url = storage.attribute(.nxNoteAddress, at: index, effectiveRange: nil) as? URL else { return nil }
        return .link(url)
    }

    func perform(_ widget: NXNoteWidget) {
        switch widget {
        case let .link(url):
            openLink?(url)
        case let .box(location):
            toggleBox(at: location)
        }
    }

    /// Ticks or unticks a checklist item: a step of the edit while the note
    /// is written, else one of its own, saved at once.
    func toggleBox(at location: Int) {
        guard let line = noteLine(at: location), case .task = line.kind,
              let toggled = NoteMarkdown.toggledTask((string as NSString).substring(with: line.range)) else { return }
        replace(line.range, with: toggled, caret: nil)
        if !isWriting {
            dropTyping()
            onCommit?()
        }
    }

    /// Replaces `range` as typing does, so Undo takes it back, and puts the
    /// caret at `caret` in the note, if given.
    @discardableResult
    func replace(_ range: NSRange, with text: String, caret: Int?) -> Bool {
        guard let storage = textStorage, NSMaxRange(range) <= storage.length, shouldChangeText(in: range, replacementString: text)
        else { return false }
        // In the note's own face, not the hidden syntax's it replaces.
        storage.replaceCharacters(in: range, with: NSAttributedString(string: text, attributes: metrics.attributes))
        didChangeText()
        if let caret { setSelectedRange(NSRange(location: min(caret, storage.length), length: 0)) }
        return true
    }

    // MARK: Keys

    /// The note's own keys: the `/` menu's, Backspace on a line's hidden
    /// syntax, Tab and ⇧Tab in a list, and Return after a code fence.
    func handleNoteCommand(_ selector: Selector) -> Bool {
        if var open = slash {
            let count = open.blocks.count
            switch selector {
            case #selector(moveDown(_:)), #selector(moveUp(_:)):
                guard count > 0 else { return true }
                open.selected = (open.selected + (selector == #selector(moveDown(_:)) ? 1 : count - 1)) % count
                setSlash(open)
                return true
            case #selector(insertNewline(_:)), #selector(insertTab(_:)):
                if let block = open.blocks[safe: open.selected] { applySlash(block) } else { closeSlash() }
                return true
            case #selector(cancelOperation(_:)):
                closeSlash()
                return true
            default:
                break
            }
        }
        let caret = selectedRange()
        guard caret.length == 0, let line = noteLine(at: caret.location) else { return false }
        switch selector {
        case #selector(deleteBackward(_:)):
            // Backspace on a line's start takes its syntax off, a level of a
            // nested list's first.
            guard line.hidesPrefix, line.prefix.length > 0, caret.location == NSMaxRange(line.prefix) else { return false }
            let syntax = (string as NSString).substring(with: line.prefix)
            if line.depth > 0 {
                let outdented = Self.outdent(syntax)
                return replace(line.prefix, with: outdented, caret: line.prefix.location + (outdented as NSString).length)
            }
            return replace(line.prefix, with: "", caret: line.prefix.location)
        case #selector(insertTab(_:)), #selector(insertBacktab(_:)):
            guard Self.isList(line) else { return false }
            let start = NSRange(location: line.range.location, length: 0)
            if selector == #selector(insertTab(_:)) {
                return replace(start, with: "  ", caret: caret.location + 2)
            }
            let syntax = (string as NSString).substring(with: line.prefix)
            let outdented = Self.outdent(syntax)
            guard outdented != syntax else { return false }
            let removed = (syntax as NSString).length - (outdented as NSString).length
            return replace(line.prefix, with: outdented, caret: caret.location - removed)
        case #selector(insertNewline(_:)):
            // Return after an opening fence starts the block and closes it.
            guard case .fence = line.kind, caret.location == NSMaxRange(line.range),
                  !Self.closesBlock(line, in: string) else { return false }
            return replace(NSRange(location: caret.location, length: 0), with: "\n\n```", caret: caret.location + 1)
        default:
            return false
        }
    }

    private static func isList(_ line: NoteMarkdown.Line) -> Bool {
        switch line.kind {
        case .bullet, .numbered, .task: true
        default: false
        }
    }

    /// A list item's syntax a level out: two spaces, or a tab, fewer.
    private static func outdent(_ syntax: String) -> String {
        if syntax.hasPrefix("\t") { return String(syntax.dropFirst()) }
        if syntax.hasPrefix("  ") { return String(syntax.dropFirst(2)) }
        if syntax.hasPrefix(" ") { return String(syntax.dropFirst()) }
        return syntax
    }

    /// Whether `fence` closes a block opened above it.
    private static func closesBlock(_ fence: NoteMarkdown.Line, in text: String) -> Bool {
        let fences = NoteMarkdown.lines(in: text).filter { if case .fence = $0.kind { true } else { false } }
        guard let index = fences.firstIndex(where: { $0.range == fence.range }) else { return false }
        return index % 2 == 1 || index + 1 < fences.count
    }

    /// ⌘⇧7, ⌘⇧8 and ⌘⇧9: the line becomes a numbered item, a bullet or a
    /// checklist item, or back to text if it is one already.
    func noteKeyEquivalent(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard flags == [.command, .shift] else { return false }
        let block: NoteMarkdown.Block
        switch event.keyCode {
        case 26: block = .numbered
        case 28: block = .bullet
        case 25: block = .checklist
        default: return false
        }
        guard let line = noteLine(at: selectedRange().location) else {
            let caret = selectedRange().location
            let made = block.line(from: "")
            return replace(NSRange(location: caret, length: 0), with: made.text, caret: caret + made.caret)
        }
        let already: Bool
        switch (block, line.kind) {
        case (.numbered, .numbered), (.bullet, .bullet), (.checklist, .task): already = true
        default: already = false
        }
        let text = (string as NSString).substring(with: line.range)
        let made = already ? NoteMarkdown.Block.text.line(from: text) : block.line(from: text)
        let wordsBefore = selectedRange().location - NSMaxRange(line.prefix)
        return replace(line.range, with: made.text, caret: line.range.location + made.caret + max(0, wordsBefore))
    }

    // MARK: Typing

    /// A space after `[]` or `[ ]` alone on a line makes it a checklist item.
    func insertNoteShortcut(_ inserted: Any) -> Bool {
        guard (inserted as? String) == " " || (inserted as? NSAttributedString)?.string == " " else { return false }
        let caret = selectedRange()
        guard caret.length == 0, let line = noteLine(at: caret.location), caret.location == NSMaxRange(line.range) else { return false }
        let text = (string as NSString).substring(with: line.range)
        guard NoteMarkdown.isChecklistShortcut(text) else { return false }
        let indent = String(text.prefix { $0 == " " || $0 == "\t" })
        return replace(line.range, with: indent + "- [ ] ", caret: line.range.location + (indent as NSString).length + 6)
    }

    /// A `/` typed on a line of its own opens the menu.
    func noteDidInsert(_ inserted: Any) {
        guard slash == nil, (inserted as? String) == "/" || (inserted as? NSAttributedString)?.string == "/" else { return }
        let caret = selectedRange()
        guard caret.length == 0, let line = noteLine(at: caret.location),
              (string as NSString).substring(with: line.range) == "/" else { return }
        setSlash(NXNoteSlash(range: line.range, line: caretLineRect()))
    }

    /// The menu follows what's typed after its slash, and goes once that's
    /// no longer a query on the caret's line.
    func updateSlash() {
        guard var open = slash else { return }
        let caret = selectedRange()
        let source = string as NSString
        guard isWriting, caret.length == 0, open.range.location < source.length,
              source.character(at: open.range.location) == 47, caret.location > open.range.location,
              let line = noteLine(at: caret.location), line.range.location == open.range.location else { return closeSlash() }
        let typed = source.substring(with: NSRange(location: open.range.location + 1, length: caret.location - open.range.location - 1))
        guard !typed.contains(where: \.isWhitespace), NSMaxRange(line.range) == caret.location else { return closeSlash() }
        open.range = NSRange(location: open.range.location, length: (typed as NSString).length + 1)
        if open.query != typed { open.selected = 0 }
        open.query = typed
        open.line = caretLineRect()
        guard !open.blocks.isEmpty || typed.count < 2 else { return closeSlash() }
        setSlash(open)
    }

    func applySlash(_ block: NoteMarkdown.Block) {
        guard let open = slash else { return }
        closeSlash()
        let made = block.line(from: "")
        replace(open.range, with: made.text, caret: open.range.location + made.caret)
    }

    func closeSlash() {
        guard slash != nil else { return }
        setSlash(nil)
    }

    private func setSlash(_ value: NXNoteSlash?) {
        guard slash != value else { return }
        slash = value
        onSlash?(value)
    }

    /// The caret's line, in the view's own space.
    private func caretLineRect() -> CGRect {
        guard let layout = layoutManager, let container = textContainer else { return .zero }
        let caret = selectedRange().location
        let origin = textContainerOrigin
        if caret >= (string as NSString).length, !layout.extraLineFragmentRect.isEmpty {
            return layout.extraLineFragmentRect.offsetBy(dx: origin.x, dy: origin.y)
        }
        let glyph = layout.glyphIndexForCharacter(at: max(0, min(caret, (string as NSString).length - 1)))
        var rect = layout.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
        rect.size.width = max(rect.width, 1)
        _ = container
        return rect.offsetBy(dx: origin.x, dy: origin.y)
    }

    // MARK: Formatting

    /// Format ▸ Bold, Italic, Strikethrough and Inline Code: the selection
    /// wrapped in the Markdown for it, or unwrapped if it has it.
    @objc func toggleBold(_ sender: Any?) { wrapSelection(in: "**") }
    @objc func toggleItalic(_ sender: Any?) { wrapSelection(in: "*") }
    @objc func toggleStrikethrough(_ sender: Any?) { wrapSelection(in: "~~") }
    @objc func toggleInlineCode(_ sender: Any?) { wrapSelection(in: "`") }

    private func wrapSelection(in marker: String) {
        guard role == .note, isWriting else { return }
        let range = selectedRange()
        guard range.length > 0 else { return }
        let source = string as NSString
        let length = (marker as NSString).length
        let selected = source.substring(with: range)
        if range.location >= length, NSMaxRange(range) + length <= source.length,
           source.substring(with: NSRange(location: range.location - length, length: length)) == marker,
           source.substring(with: NSRange(location: NSMaxRange(range), length: length)) == marker {
            let around = NSRange(location: range.location - length, length: range.length + 2 * length)
            if replace(around, with: selected, caret: nil) {
                setSelectedRange(NSRange(location: around.location, length: range.length))
            }
            return
        }
        if replace(range, with: marker + selected + marker, caret: nil) {
            setSelectedRange(NSRange(location: range.location + length, length: range.length))
        }
    }

    /// Format ▸ Add Link…: asks for an address, as a line's ⌘L does, and
    /// links the selected words to it.
    @objc func promptForLink(_ sender: Any?) {
        let range = selectedRange()
        guard role == .note, isWriting, range.length > 0, let prompter = BlockNSTextView.linkPrompter else { return }
        let words = (string as NSString).substring(with: range)
        prompter(LinkPrompt(text: words, currentURL: "") { [weak self] answer in
            guard let self, case let .apply(entry) = answer, let url = BlockNSTextView.linkURL(from: entry),
                  NSMaxRange(range) <= (self.string as NSString).length,
                  (self.string as NSString).substring(with: range) == words else { return }
            self.window?.makeFirstResponder(self)
            self.replace(range, with: "[\(words)](\(url.absoluteString))", caret: range.location + (words as NSString).length + 3
                         + (url.absoluteString as NSString).length + 1)
        })
    }

    /// An address pasted over words links them, rather than replacing them.
    func pasteLink(from pboard: NSPasteboard) -> Bool {
        let range = selectedRange()
        guard range.length > 0, let pasted = pboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !pasted.contains(where: \.isWhitespace), let url = NoteMarkdown.openable(pasted) else { return false }
        let words = (string as NSString).substring(with: range)
        guard !words.contains(where: \.isNewline), !words.contains("["), !words.contains("]") else { return false }
        let link = "[\(words)](\(url.absoluteString))"
        return replace(range, with: link, caret: range.location + (link as NSString).length)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
