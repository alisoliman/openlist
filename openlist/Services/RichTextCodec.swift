//
//  RichTextCodec.swift
//  openlist
//

import AppKit
import Foundation

/// Custom attribute marking a run as inline code, so it survives a round trip
/// through RTF (which has no notion of "code", only fonts).
extension NSAttributedString.Key {
    static let openlistInlineCode = NSAttributedString.Key("openlistInlineCode")
    /// Marks strikethrough the *user* applied, as opposed to the strikethrough
    /// a completed task is drawn with. Without the distinction, encoding either
    /// keeps "done" in the text forever or loses ⇧⌘X entirely.
    static let openlistStrikethrough = NSAttributedString.Key("openlistStrikethrough")
}

/// Converts between a block's stored `richData` and the attributed string the
/// editor works with.
///
/// Inline styling is stored as RTF, but fonts are *not* trusted on the way
/// back in: only the symbolic traits (bold, italic) and code-ness are read,
/// then re-applied on top of the base font for the block's current kind. That
/// is what lets a bold word stay bold when a paragraph becomes a heading.
enum RichTextCodec {
    /// The canonical font used when writing RTF, so archives stay comparable.
    private static var canonicalFont: NSFont { .systemFont(ofSize: Theme.Editor.bodyPointSize) }

    // MARK: - Encoding

    static func encode(_ attributed: NSAttributedString, kind: BlockKind = .paragraph) -> Data? {
        guard attributed.length > 0 else { return nil }
        let normalised = NSMutableAttributedString(attributedString: attributed)
        let full = NSRange(location: 0, length: normalised.length)

        // Drop fonts that merely match the block's own base font. A heading is
        // bold because it is a heading, not because the user made it bold —
        // recording that would keep the weight after a change to body text.
        let baseFont = Theme.Editor.nsFont(for: kind)
        normalised.enumerateAttribute(.font, in: full) { value, range, _ in
            guard let font = value as? NSFont, font.isEquivalent(to: baseFont) else { return }
            normalised.removeAttribute(.font, range: range)
        }

        // Strip colours and paragraph styles; those are presentation concerns
        // owned by the current theme, not by the document.
        normalised.removeAttribute(.foregroundColor, range: full)
        normalised.removeAttribute(.backgroundColor, range: full)
        normalised.removeAttribute(.paragraphStyle, range: full)

        // Clear completion strikethrough, then put back only the runs the user
        // struck through themselves. RTF has no way to tell the two apart, so
        // the marker attribute decides before it is dropped.
        var userStruck: [NSRange] = []
        normalised.enumerateAttribute(.openlistStrikethrough, in: full) { value, range, _ in
            if (value as? Bool) == true { userStruck.append(range) }
        }
        normalised.removeAttribute(.strikethroughStyle, range: full)
        normalised.removeAttribute(.strikethroughColor, range: full)
        normalised.removeAttribute(.openlistStrikethrough, range: full)
        for range in userStruck {
            normalised.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        }

        // Fold inline-code runs into a monospaced font so RTF can carry them.
        normalised.enumerateAttribute(.openlistInlineCode, in: full) { value, range, _ in
            guard (value as? Bool) == true else { return }
            let existing = normalised.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
            let traits = existing.map { NSFontManager.shared.traits(of: $0) } ?? []
            var weight: NSFont.Weight = traits.contains(.boldFontMask) ? .bold : .regular
            if traits.contains(.boldFontMask) { weight = .bold }
            normalised.addAttribute(
                .font,
                value: NSFont.monospacedSystemFont(ofSize: Theme.Editor.codePointSize, weight: weight),
                range: range
            )
        }
        normalised.removeAttribute(.openlistInlineCode, range: full)

        return normalised.rtf(from: full, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    }

    // MARK: - Decoding

    /// Rebuilds the attributed string for a block, restyled for `kind`.
    static func decode(_ data: Data?, plainText: String, kind: BlockKind, isCompleted: Bool = false) -> NSAttributedString {
        let base = baseAttributes(for: kind, isCompleted: isCompleted)

        guard
            let data,
            let stored = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            ),
            // A stale archive whose text no longer matches the plain-text
            // mirror is discarded rather than shown out of date.
            stored.string.replacingOccurrences(of: "\u{fffc}", with: "") == plainText
        else {
            return NSAttributedString(string: plainText, attributes: base)
        }

        let result = NSMutableAttributedString(string: stored.string, attributes: base)
        let full = NSRange(location: 0, length: stored.length)
        let baseFont = Theme.Editor.nsFont(for: kind)

        stored.enumerateAttributes(in: full) { attributes, range, _ in
            var traits: NSFontTraitMask = []
            var isCode = false

            if let font = attributes[.font] as? NSFont {
                let mask = NSFontManager.shared.traits(of: font)
                if mask.contains(.boldFontMask) { traits.insert(.boldFontMask) }
                if mask.contains(.italicFontMask) { traits.insert(.italicFontMask) }
                isCode = font.fontDescriptor.symbolicTraits.contains(.monoSpace)
                    || (font.fontName.lowercased().contains("mono") && kind != .code)
            }

            if isCode, kind != .code {
                let weight: NSFont.Weight = traits.contains(.boldFontMask) ? .bold : .regular
                result.addAttribute(
                    .font,
                    value: NSFont.monospacedSystemFont(ofSize: Theme.Editor.codePointSize, weight: weight),
                    range: range
                )
                result.addAttribute(.openlistInlineCode, value: true, range: range)
            } else if !traits.isEmpty {
                var styled = baseFont
                if traits.contains(.boldFontMask) {
                    styled = NSFontManager.shared.convert(styled, toHaveTrait: .boldFontMask)
                }
                if traits.contains(.italicFontMask) {
                    styled = NSFontManager.shared.convert(styled, toHaveTrait: .italicFontMask)
                }
                result.addAttribute(.font, value: styled, range: range)
            }

            if let link = attributes[.link] {
                result.addAttribute(.link, value: link, range: range)
                result.addAttribute(.foregroundColor, value: NSColor.linkColor, range: range)
                result.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }

            // Anything struck through in the archive was struck by the user;
            // completion strike never reaches storage.
            if let raw = attributes[.strikethroughStyle] as? Int, raw != 0 {
                result.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                result.addAttribute(.openlistStrikethrough, value: true, range: range)
            }
        }

        return result
    }

    // MARK: - Base styling

    /// Font, colour and paragraph style for a block kind in its normal state.
    static func baseAttributes(for kind: BlockKind, isCompleted: Bool = false) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        let font = Theme.Editor.nsFont(for: kind)
        // Keep the first and last line at the font's natural height. A line
        // height multiplier puts the extra leading before the baseline and
        // makes a single-line title sit low in its selection highlight.
        let multiple = kind == .code ? 1.15 : Theme.Editor.lineHeightMultiple
        paragraph.lineSpacing = NSLayoutManager().defaultLineHeight(for: font) * (multiple - 1)
        paragraph.lineBreakMode = .byWordWrapping

        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph,
            .foregroundColor: isCompleted ? NSColor.tertiaryLabelColor : NSColor.labelColor,
        ]

        if isCompleted {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            attributes[.strikethroughColor] = NSColor.tertiaryLabelColor
        }
        if kind == .quote {
            attributes[.foregroundColor] = isCompleted ? NSColor.tertiaryLabelColor : NSColor.secondaryLabelColor
        }
        return attributes
    }

    // MARK: - Editing helpers

    /// Concatenates two blocks' contents, used when Backspace merges rows.
    static func merged(_ lhs: NSAttributedString, _ rhs: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: lhs)
        result.append(rhs)
        return result
    }

    /// Rewrites the text of an attributed string while keeping the styling of
    /// everything that did not change.
    ///
    /// Plain `TextField`s elsewhere in the app edit a task's title, but the
    /// title may carry bold or a link from the outline editor. Replacing the
    /// whole run would drop that, so only the span between the common prefix
    /// and the common suffix is touched — which for typing, backspacing or
    /// pasting is exactly the part the user changed.
    static func replacingText(in source: NSAttributedString, with newText: String) -> NSAttributedString {
        let old = source.string as NSString
        let new = newText as NSString
        guard old != new else { return source }
        guard source.length > 0 else {
            return NSAttributedString(string: newText)
        }

        let limit = min(old.length, new.length)

        var prefix = 0
        while prefix < limit, old.character(at: prefix) == new.character(at: prefix) {
            prefix += 1
        }

        var suffix = 0
        while suffix < limit - prefix,
              old.character(at: old.length - 1 - suffix) == new.character(at: new.length - 1 - suffix) {
            suffix += 1
        }

        let removedRange = NSRange(location: prefix, length: old.length - prefix - suffix)
        let inserted = new.substring(with: NSRange(location: prefix, length: new.length - prefix - suffix))

        // Inherit the styling of the character the insertion follows, so typing
        // inside a bold word stays bold.
        let styleIndex = prefix > 0 ? prefix - 1 : min(prefix, source.length - 1)
        var attributes = source.attributes(at: styleIndex, effectiveRange: nil)
        // A link should not swallow adjacent typing.
        attributes.removeValue(forKey: .link)

        let result = NSMutableAttributedString(attributedString: source)
        result.replaceCharacters(
            in: removedRange,
            with: NSAttributedString(string: inserted, attributes: attributes)
        )
        return result
    }

    /// Splits at `location`, returning the text before and after the caret.
    static func split(_ source: NSAttributedString, at location: Int) -> (head: NSAttributedString, tail: NSAttributedString) {
        let clamped = max(0, min(location, source.length))
        let head = source.attributedSubstring(from: NSRange(location: 0, length: clamped))
        let tail = source.attributedSubstring(from: NSRange(location: clamped, length: source.length - clamped))
        return (head, tail)
    }

    /// Toggles a font trait across `range`, matching the behaviour of ⌘B / ⌘I.
    static func toggleTrait(
        _ trait: NSFontTraitMask,
        in attributed: NSMutableAttributedString,
        range: NSRange,
        kind: BlockKind
    ) {
        guard range.length > 0 else { return }
        let manager = NSFontManager.shared
        let baseFont = Theme.Editor.nsFont(for: kind)

        // Turn the trait off only when every character already has it.
        var allHaveTrait = true
        attributed.enumerateAttribute(.font, in: range) { value, _, stop in
            let font = (value as? NSFont) ?? baseFont
            if !manager.traits(of: font).contains(trait) {
                allHaveTrait = false
                stop.pointee = true
            }
        }

        attributed.enumerateAttribute(.font, in: range) { value, subrange, _ in
            let font = (value as? NSFont) ?? baseFont
            let updated = allHaveTrait
                ? manager.convert(font, toNotHaveTrait: trait)
                : manager.convert(font, toHaveTrait: trait)
            attributed.addAttribute(.font, value: updated, range: subrange)
        }
    }

    /// Toggles strikethrough across `range`, marking it as user-applied.
    static func toggleStrikethrough(in attributed: NSMutableAttributedString, range: NSRange) {
        guard range.length > 0 else { return }
        var allStruck = true
        attributed.enumerateAttribute(.openlistStrikethrough, in: range) { value, _, stop in
            if (value as? Bool) != true {
                allStruck = false
                stop.pointee = true
            }
        }
        if allStruck {
            attributed.removeAttribute(.strikethroughStyle, range: range)
            attributed.removeAttribute(.openlistStrikethrough, range: range)
        } else {
            attributed.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            attributed.addAttribute(.openlistStrikethrough, value: true, range: range)
        }
    }

    /// Toggles inline code across `range`.
    static func toggleInlineCode(in attributed: NSMutableAttributedString, range: NSRange, kind: BlockKind) {
        guard range.length > 0 else { return }
        var allCode = true
        attributed.enumerateAttribute(.openlistInlineCode, in: range) { value, _, stop in
            if (value as? Bool) != true {
                allCode = false
                stop.pointee = true
            }
        }

        if allCode {
            attributed.removeAttribute(.openlistInlineCode, range: range)
            attributed.addAttribute(.font, value: Theme.Editor.nsFont(for: kind), range: range)
        } else {
            attributed.addAttribute(.openlistInlineCode, value: true, range: range)
            attributed.addAttribute(
                .font,
                value: NSFont.monospacedSystemFont(ofSize: Theme.Editor.codePointSize, weight: .regular),
                range: range
            )
        }
    }

    /// Applies or clears a hyperlink across `range`.
    static func setLink(_ url: URL?, in attributed: NSMutableAttributedString, range: NSRange) {
        guard range.length > 0 else { return }
        if let url {
            attributed.addAttribute(.link, value: url, range: range)
            attributed.addAttribute(.foregroundColor, value: NSColor.linkColor, range: range)
            attributed.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        } else {
            attributed.removeAttribute(.link, range: range)
            attributed.removeAttribute(.underlineStyle, range: range)
            attributed.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
        }
    }

    /// Plain-text mirror, with attachment placeholders removed.
    static func plainText(from attributed: NSAttributedString) -> String {
        attributed.string.replacingOccurrences(of: "\u{fffc}", with: "")
    }
}

extension NSFont {
    /// Same family, size and traits — used to spot runs that carry no styling
    /// beyond their block's base font.
    func isEquivalent(to other: NSFont) -> Bool {
        fontName == other.fontName && abs(pointSize - other.pointSize) < 0.01
    }
}
