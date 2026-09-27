//
//  RichTextCodec.swift
//  openlist
//

#if os(macOS)
import AppKit
#else
import UIKit
#endif
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
///
/// The Mac and the iPhone read and write the same archives, synced through
/// `Block.richData`. Only the font primitives at the end differ per platform
/// (AppKit's font manager, UIKit's font descriptors); every rule about what
/// is stored lives once, above them.
enum RichTextCodec {
    /// Heading 1 was once system bold at this size, so a run styled inside an
    /// older heading was archived bold along with its own trait.
    private static let legacyHeading1PointSize: CGFloat = 21

    // MARK: - Encoding

    static func encode(_ attributed: NSAttributedString, kind: BlockKind = .paragraph) -> Data? {
        guard attributed.length > 0 else { return nil }
        let normalised = NSMutableAttributedString(attributedString: attributed)
        let full = NSRange(location: 0, length: normalised.length)

        // Drop fonts that merely match the block's own base font. A heading is
        // bold because it is a heading, not because the user made it bold —
        // recording that would keep the weight after a change to body text.
        let baseFont = NXEditor.nsFont(for: kind)
        normalised.enumerateAttribute(.font, in: full) { value, range, _ in
            guard let font = value as? PlatformFont, font.isEquivalent(to: baseFont) else { return }
            normalised.removeAttribute(.font, range: range)
        }

        // Strip colours, spacing and paragraph styles; those are presentation
        // concerns owned by the current theme, not by the document.
        normalised.removeAttribute(.foregroundColor, range: full)
        normalised.removeAttribute(.backgroundColor, range: full)
        normalised.removeAttribute(.paragraphStyle, range: full)
        normalised.removeAttribute(.kern, range: full)

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
            let existing = normalised.attribute(.font, at: range.location, effectiveRange: nil)
            let weight: PlatformFont.Weight = fontTraits(of: existing).bold ? .bold : .regular
            normalised.addAttribute(
                .font,
                value: PlatformFont.monospacedSystemFont(ofSize: NXEditor.codePointSize, weight: weight),
                range: range
            )
        }
        normalised.removeAttribute(.openlistInlineCode, range: full)

        return rtf(from: normalised)
    }

    // MARK: - Decoding

    /// Rebuilds the attributed string for a block, restyled for `kind`.
    static func decode(_ data: Data?, plainText: String, kind: BlockKind, isCompleted: Bool = false) -> NSAttributedString {
        let base = baseAttributes(for: kind, isCompleted: isCompleted)

        guard
            let data,
            let stored = attributedString(fromRTF: data),
            // A stale archive whose text no longer matches the plain-text
            // mirror is discarded rather than shown out of date.
            stored.string.replacingOccurrences(of: "\u{fffc}", with: "") == plainText
        else {
            return NSAttributedString(string: plainText, attributes: base)
        }

        let result = NSMutableAttributedString(string: stored.string, attributes: base)
        let full = NSRange(location: 0, length: stored.length)
        let baseFont = NXEditor.nsFont(for: kind)

        stored.enumerateAttributes(in: full) { attributes, range, _ in
            var traits: FontTraits = []
            var isCode = false

            if let font = attributes[.font] as? PlatformFont {
                let mask = self.traits(of: font)
                // That bold was the old heading's weight, not the user's: the
                // heading's own weight draws it, and the next `encode` stores
                // the run without it.
                let isLegacyHeadingWeight = kind == .heading1
                    && abs(font.pointSize - legacyHeading1PointSize) < 0.01
                if mask.contains(boldTrait), !isLegacyHeadingWeight { traits.insert(boldTrait) }
                if mask.contains(italicTrait) { traits.insert(italicTrait) }
                isCode = isMonospaced(font)
                    || (font.fontName.lowercased().contains("mono") && kind != .code)
            }

            if isCode, kind != .code {
                let weight: PlatformFont.Weight = traits.contains(boldTrait) ? .bold : .regular
                result.addAttribute(
                    .font,
                    value: PlatformFont.monospacedSystemFont(ofSize: NXEditor.codePointSize, weight: weight),
                    range: range
                )
                result.addAttribute(.openlistInlineCode, value: true, range: range)
            } else if !traits.isEmpty {
                result.addAttribute(.font, value: font(baseFont, adding: traits), range: range)
            }

            // A link keeps a neutral ink here; the text view draws it in the
            // chosen accent (`BlockTextView.applyAccent`).
            if let link = attributes[.link] {
                result.addAttribute(.link, value: link, range: range)
                result.addAttribute(.foregroundColor, value: NXEditor.ink, range: range)
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
    ///
    /// - Parameters:
    ///   - dimsCompleted: whether completed text fades to the completed ink.
    ///     A done task being written keeps its ink.
    ///   - strikes: whether completed text is struck through, where a
    ///     renderer draws no strike over it of its own.
    static func baseAttributes(for kind: BlockKind, isCompleted: Bool = false,
                               dimsCompleted: Bool = true, strikes: Bool = true) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        let font = NXEditor.nsFont(for: kind)
        // Keep the first and last line at the font's natural height. A line
        // height multiplier puts the extra leading before the baseline and
        // makes a single-line title sit low in its selection highlight.
        paragraph.lineSpacing = NXEditor.lineSpacing(for: kind)
        paragraph.lineBreakMode = .byWordWrapping

        let ink = kind == .paragraph || kind == .quote ? NXEditor.secondaryInk : NXEditor.ink
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph,
            .foregroundColor: isCompleted && dimsCompleted ? NXEditor.completedInk : ink,
        ]
        if kind == .heading1 { attributes[.kern] = NXEditor.heading1Kern }

        if isCompleted, strikes {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            attributes[.strikethroughColor] = NXEditor.strikeInk
        }
        return attributes
    }

    /// Redraws `attributed` struck through or not, whatever completion state
    /// it was decoded with. Only presentation changes: the strike carries no
    /// `openlistStrikethrough` marker, so `encode` never stores it, and a run
    /// the user struck through keeps its own strike either way.
    ///
    /// Restyling decoded content to its own completion state returns it
    /// unchanged, which is what lets the editor compare against the model.
    /// With `strikes` false, struck text only fades, for a renderer that
    /// draws the strike over it.
    static func restylingCompletion(of attributed: NSAttributedString, kind: BlockKind, struck: Bool,
                                    dimsCompleted: Bool = true, strikes: Bool = true) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: attributed)
        let full = NSRange(location: 0, length: result.length)
        let base = baseAttributes(for: kind, isCompleted: struck, dimsCompleted: dimsCompleted, strikes: strikes)
        attributed.enumerateAttributes(in: full) { attributes, range, _ in
            if attributes[.link] == nil, let color = base[.foregroundColor] {
                result.addAttribute(.foregroundColor, value: color, range: range)
            }
            if (struck && strikes) || (attributes[.openlistStrikethrough] as? Bool) == true {
                result.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            } else {
                result.removeAttribute(.strikethroughStyle, range: range)
            }
        }
        if let color = base[.strikethroughColor] {
            result.addAttribute(.strikethroughColor, value: color, range: full)
        } else {
            result.removeAttribute(.strikethroughColor, range: full)
        }
        return result
    }

    /// `base` with the bold and italic traits in `traits`. A proportional face
    /// with no such variant, like the bundled display serif, falls back to the
    /// system face at the same size: converting it would return the base font
    /// unchanged, so the styling would neither show nor survive the next
    /// `encode`. Code keeps its monospaced face either way.
    static func font(_ base: PlatformFont, adding traits: FontTraits) -> PlatformFont {
        func converting(_ font: PlatformFont) -> PlatformFont {
            var font = font
            for trait in [boldTrait, italicTrait] where traits.contains(trait) {
                font = adding(trait, to: font)
            }
            return font
        }
        let styled = converting(base)
        let wanted = traits.intersection([boldTrait, italicTrait])
        guard !isFixedPitch(base), !self.traits(of: styled).isSuperset(of: wanted) else { return styled }
        return converting(.systemFont(ofSize: base.pointSize))
    }

    /// `font` made bold, then italic, as far as its own family goes. Unlike
    /// `font(_:adding:)`, a face without the variant stays as it is.
    static func converting(_ font: PlatformFont, bold: Bool, italic: Bool) -> PlatformFont {
        var font = font
        if bold { font = adding(boldTrait, to: font) }
        if italic { font = adding(italicTrait, to: font) }
        return font
    }

    /// Whether a `.font` attribute value is bold and italic, for serializers
    /// that write the traits out rather than the font.
    static func fontTraits(of value: Any?) -> (bold: Bool, italic: Bool) {
        let traits = (value as? PlatformFont).map { self.traits(of: $0) } ?? []
        return (traits.contains(boldTrait), traits.contains(italicTrait))
    }

    // MARK: - Editing helpers

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

    /// Toggles a font trait across `range`, matching the behaviour of ⌘B / ⌘I.
    static func toggleTrait(
        _ trait: FontTraits,
        in attributed: NSMutableAttributedString,
        range: NSRange,
        kind: BlockKind
    ) {
        guard range.length > 0 else { return }
        let baseFont = NXEditor.nsFont(for: kind)

        // Turn the trait off only when every character already has it.
        var allHaveTrait = true
        attributed.enumerateAttribute(.font, in: range) { value, _, stop in
            let font = (value as? PlatformFont) ?? baseFont
            if !traits(of: font).contains(trait) {
                allHaveTrait = false
                stop.pointee = true
            }
        }

        attributed.enumerateAttribute(.font, in: range) { value, subrange, _ in
            let font = (value as? PlatformFont) ?? baseFont
            let updated = allHaveTrait
                ? removing(trait, from: font)
                : Self.font(font, adding: trait)
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
            attributed.addAttribute(.font, value: NXEditor.nsFont(for: kind), range: range)
        } else {
            attributed.addAttribute(.openlistInlineCode, value: true, range: range)
            attributed.addAttribute(
                .font,
                value: PlatformFont.monospacedSystemFont(ofSize: NXEditor.codePointSize, weight: .regular),
                range: range
            )
        }
    }

    /// Applies or clears a hyperlink across `range`.
    static func setLink(_ url: URL?, in attributed: NSMutableAttributedString, range: NSRange) {
        guard range.length > 0 else { return }
        if let url {
            attributed.addAttribute(.link, value: url, range: range)
            attributed.addAttribute(.foregroundColor, value: NXEditor.ink, range: range)
            attributed.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        } else {
            attributed.removeAttribute(.link, range: range)
            attributed.removeAttribute(.underlineStyle, range: range)
            attributed.addAttribute(.foregroundColor, value: NXEditor.ink, range: range)
        }
    }

    /// Plain-text mirror, with attachment placeholders removed.
    static func plainText(from attributed: NSAttributedString) -> String {
        attributed.string.replacingOccurrences(of: "\u{fffc}", with: "")
    }
}

// MARK: - Platform font primitives

#if os(macOS)
extension RichTextCodec {
    /// The font class the platform's text system keeps in `.font`.
    typealias PlatformFont = NSFont
    /// Bold and italic, as the platform's font API names them.
    typealias FontTraits = NSFontTraitMask

    static var boldTrait: FontTraits { .boldFontMask }
    static var italicTrait: FontTraits { .italicFontMask }

    static func traits(of font: NSFont) -> NSFontTraitMask {
        NSFontManager.shared.traits(of: font)
    }

    /// The font manager's conversion, which returns `font` itself when its
    /// family has no such face.
    static func adding(_ trait: NSFontTraitMask, to font: NSFont) -> NSFont {
        NSFontManager.shared.convert(font, toHaveTrait: trait)
    }

    static func removing(_ trait: NSFontTraitMask, from font: NSFont) -> NSFont {
        NSFontManager.shared.convert(font, toNotHaveTrait: trait)
    }

    static func isMonospaced(_ font: NSFont) -> Bool {
        font.fontDescriptor.symbolicTraits.contains(.monoSpace)
    }

    static func isFixedPitch(_ font: NSFont) -> Bool { font.isFixedPitch }

    fileprivate static func rtf(from text: NSAttributedString) -> Data? {
        text.rtf(from: NSRange(location: 0, length: text.length),
                 documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    }

    fileprivate static func attributedString(fromRTF data: Data) -> NSAttributedString? {
        try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf],
                                documentAttributes: nil)
    }
}

extension NSFont {
    /// Same family, size and traits — used to spot runs that carry no styling
    /// beyond their block's base font.
    func isEquivalent(to other: NSFont) -> Bool {
        fontName == other.fontName && abs(pointSize - other.pointSize) < 0.01
    }
}
#else
extension RichTextCodec {
    typealias PlatformFont = UIFont
    typealias FontTraits = UIFontDescriptor.SymbolicTraits

    static var boldTrait: FontTraits { .traitBold }
    static var italicTrait: FontTraits { .traitItalic }

    static func traits(of font: UIFont) -> UIFontDescriptor.SymbolicTraits {
        font.fontDescriptor.symbolicTraits
    }

    /// Like AppKit's font manager: `font` itself when its family has no such
    /// face, so `font(_:adding:)` can fall back to the system face.
    static func adding(_ trait: UIFontDescriptor.SymbolicTraits, to font: UIFont) -> UIFont {
        restyled(font, traits: font.fontDescriptor.symbolicTraits.union(trait))
    }

    static func removing(_ trait: UIFontDescriptor.SymbolicTraits, from font: UIFont) -> UIFont {
        restyled(font, traits: font.fontDescriptor.symbolicTraits.subtracting(trait))
    }

    private static func restyled(_ font: UIFont, traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        guard traits != font.fontDescriptor.symbolicTraits,
              let descriptor = font.fontDescriptor.withSymbolicTraits(traits) else { return font }
        return UIFont(descriptor: descriptor, size: font.pointSize)
    }

    static func isMonospaced(_ font: UIFont) -> Bool {
        font.fontDescriptor.symbolicTraits.contains(.traitMonoSpace)
    }

    static func isFixedPitch(_ font: UIFont) -> Bool { isMonospaced(font) }

    /// Written at the Mac's point scale, so an archive from the iPhone reads
    /// on the Mac exactly like one the Mac wrote. UIKit otherwise writes RTF
    /// at its own text scale, every size about 30% larger.
    fileprivate static func rtf(from text: NSAttributedString) -> Data? {
        try? text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [
            .documentType: NSAttributedString.DocumentType.rtf,
            .textScaling: NSTextScalingType.standard.rawValue,
            .sourceTextScaling: NSTextScalingType.standard.rawValue,
        ])
    }

    /// Read at the Mac's point scale too, so sizes compare as they do there
    /// (the legacy heading check in `decode`).
    fileprivate static func attributedString(fromRTF data: Data) -> NSAttributedString? {
        try? NSAttributedString(data: data, options: [
            .documentType: NSAttributedString.DocumentType.rtf,
            .targetTextScaling: NSTextScalingType.standard.rawValue,
        ], documentAttributes: nil)
    }
}

extension UIFont {
    /// Same family, size and traits — used to spot runs that carry no styling
    /// beyond their block's base font.
    func isEquivalent(to other: UIFont) -> Bool {
        fontName == other.fontName && abs(pointSize - other.pointSize) < 0.01
    }
}
#endif
