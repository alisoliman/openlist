import AppKit
import Foundation

var failures = 0, checks = 0
@MainActor
func check(_ condition: Bool, _ label: String, _ detail: @autoclosure () -> String = "") {
    checks += 1
    if !condition { failures += 1; print("FAIL  \(label) — \(detail())") }
}
let plain = NSFont.systemFont(ofSize: 13)
let bold = NSFont.boldSystemFont(ofSize: 13)
let italic = NSFontManager.shared.convert(plain, toHaveTrait: .italicFontMask)
let boldItalic = NSFontManager.shared.convert(bold, toHaveTrait: .italicFontMask)

@MainActor
func export(_ source: NSAttributedString, kind: BlockKind = .paragraph) -> String {
    // Exercise the persisted RTF path, not just in-memory attribute rendering.
    let data = RichTextCodec.encode(source, kind: kind)
    let decoded = RichTextCodec.decode(data, plainText: source.string, kind: .paragraph)
    return InlineMarkdown.string(from: decoded)
}

do {
    let text = NSMutableAttributedString(string: "Review paragraph", attributes: [.font: boldItalic])
    text.addAttribute(.link, value: URL(string: "https://example.com")!, range: NSRange(location: 0, length: text.length))
    let result = export(text)
    check(result == "[***Review paragraph***](<https://example.com>)", "bold italic linked text survives RTF export", result)
}
do {
    let text = NSMutableAttributedString(string: "Bold then italic and plain", attributes: [.font: plain])
    text.addAttribute(.font, value: bold, range: NSRange(location: 0, length: 4))
    text.addAttribute(.font, value: italic, range: NSRange(location: 10, length: 6))
    check(export(text) == "**Bold** then *italic* and plain", "mixed independent emphasis runs", export(text))
}
do {
    let text = NSMutableAttributedString(string: "one two three", attributes: [.font: bold])
    text.addAttribute(.font, value: boldItalic, range: NSRange(location: 4, length: 3))
    check(export(text) == "**one *two* three**", "nested emphasis coalesces outer run", export(text))
}
do {
    let text = NSMutableAttributedString(string: "  styled  ", attributes: [.font: bold])
    check(export(text) == "  **styled**  ", "emphasis leaves boundary whitespace outside markers", export(text))
}
do {
    let text = NSMutableAttributedString(string: "a!b", attributes: [.font: plain])
    text.addAttribute(.font, value: bold, range: NSRange(location: 1, length: 1))
    check(export(text) == "a<strong>\\!</strong>b", "intraword punctuation uses valid inline HTML", export(text))
}
do {
    let text = NSMutableAttributedString(string: "done old", attributes: [.font: plain, .strikethroughStyle: 1])
    text.addAttribute(.openlistStrikethrough, value: true, range: NSRange(location: 5, length: 3))
    check(export(text) == "done ~~old~~", "completion strike excluded and deliberate strike preserved", export(text))
}
do {
    let text = NSMutableAttributedString(string: "`code`", attributes: [.openlistInlineCode: true])
    check(export(text) == "`` `code` ``", "inline code chooses nonconflicting padded delimiter", export(text))
    let spaces = NSAttributedString(string: " code ", attributes: [.openlistInlineCode: true])
    check(export(spaces) == "`  code  `", "inline code retains significant surrounding spaces", export(spaces))
    check(InlineMarkdown.codeFence(for: "let x = ```\nfoo") == "````", "fenced code cannot close on content backticks")
}
do {
    let text = NSAttributedString(string: "日本語 café 👩🏽‍💻 *literal* [bracket] <tag> #name", attributes: [.font: plain])
    check(export(text) == "日本語 café 👩🏽‍💻 \\*literal\\* \\[bracket\\] \\<tag\\> \\#name", "Unicode and Markdown metacharacters preserved", export(text))
    let text2 = NSAttributedString(string: "Heading", attributes: [.font: Theme.Editor.nsFont(for: .heading1)])
    check(export(text2, kind: .heading1) == "Heading", "heading presentation is not additional emphasis", export(text2, kind: .heading1))
    check(InlineMarkdown.destination("https://example.com/a(b)?x=1&y=2#frag") == "<https://example.com/a(b)?x=1&y=2#frag>", "parentheses and fragments remain valid in link destinations")
    check(InlineMarkdown.destination("assets/pic [1].png") == "<assets/pic%20%5B1%5D.png>", "relative media paths URL-encode reserved characters", InlineMarkdown.destination("assets/pic [1].png"))
}

// Parse exported Markdown with Foundation's independent CommonMark parser.
// All crossing bold/italic boundaries in a three-character word must retain
// the exact visible content and every character's original style.
do {
    let fonts = [plain, bold, italic, boldItalic]
    var roundTrips = true
    for a in 0..<4 {
        for b in 0..<4 {
            for c in 0..<4 {
                let source = NSMutableAttributedString(string: "abc")
                let styles = [a, b, c]
                for (index, style) in styles.enumerated() {
                    source.addAttribute(.font, value: fonts[style], range: NSRange(location: index, length: 1))
                }
                let markdown = export(source)
                let parsed = try AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
                var actual: [Int] = []
                var visible = ""
                var htmlBold = false
                for run in parsed.runs {
                    let value = String(parsed[run.range].characters)
                    // CommonMark returns inline HTML nodes; browsers apply
                    // their semantic tag while displaying the parsed contents.
                    if value == "<strong>" { htmlBold = true; continue }
                    if value == "</strong>" { htmlBold = false; continue }
                    let intent = run.inlinePresentationIntent ?? []
                    let style = (htmlBold || intent.contains(.stronglyEmphasized) ? 1 : 0) + (intent.contains(.emphasized) ? 2 : 0)
                    actual.append(contentsOf: Array(repeating: style, count: value.count))
                    visible += value
                }
                if visible != "abc" || actual != styles {
                    roundTrips = false
                    print("Bad Markdown round-trip: \(styles) → \(markdown) → \(actual)")
                }
            }
        }
    }
    check(roundTrips, "64 adjacent/crossing emphasis combinations parse back to original styled content")
} catch { check(false, "CommonMark parser round-trip", error.localizedDescription) }

do {
    let manager = FileManager.default
    let root = manager.temporaryDirectory.appendingPathComponent("openlist-export-check-\(UUID().uuidString)")
    try manager.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: root) }
    let source = root.appendingPathComponent("source.bin")
    let bytes = Data([0, 1, 2, 3, 254, 255])
    try bytes.write(to: source)
    let destination = root.appendingPathComponent("Review.md")
    let originalFolder = root.appendingPathComponent("Review.assets")
    try manager.createDirectory(at: originalFolder, withIntermediateDirectories: true)
    let sentinel = originalFolder.appendingPathComponent("keep.txt")
    try "keep".write(to: sentinel, atomically: true, encoding: .utf8)
    var relativePaths: [String: String] = [:]
    let assets: [MarkdownExportPackage.Asset] = [
        .init(key: "image", source: source, preferredFilename: "image.png"),
        .init(key: "file", source: source, preferredFilename: "notes.txt"),
        .init(key: "file2", source: source, preferredFilename: "NOTES.txt"),
        .init(key: "file", source: source, preferredFilename: "duplicate.txt"),
    ]
    try MarkdownExportPackage.write(to: destination, assets: assets) { paths in
        relativePaths = paths
        return "![image](\(InlineMarkdown.destination(paths["image"]!)))\n[attachment](\(InlineMarkdown.destination(paths["file"]!)))\n"
    }
    check(relativePaths.count == 3, "same source key deduplicated")
    check(Set(relativePaths.values.map { $0.lowercased() }).count == 3, "case-insensitive asset filenames do not collide")
    check(try Data(contentsOf: root.appendingPathComponent(relativePaths["image"]!)) == bytes, "image bytes copied faithfully")
    check(try Data(contentsOf: root.appendingPathComponent(relativePaths["file"]!)) == bytes, "attachment bytes copied faithfully")
    check(try String(contentsOf: sentinel, encoding: .utf8) == "keep", "preexisting assets folder untouched")
    let markdown = try String(contentsOf: destination, encoding: .utf8)
    check(markdown.contains("Review%202.assets/image.png"), "document links to new portable sibling assets", markdown)
    check(MarkdownExportPackage.availableURL(in: root, filename: "Review.md").lastPathComponent == "Review 2.md", "bulk export never overwrites existing Markdown")

    let listingBefore = try manager.contentsOfDirectory(atPath: root.path).sorted()
    do {
        try MarkdownExportPackage.write(to: destination, assets: [.init(key: "missing", source: root.appendingPathComponent("missing"), preferredFilename: "missing")]) { _ in "replacement" }
        check(false, "missing media must fail export")
    } catch { check(true, "missing media surfaces an export error") }
    check(try String(contentsOf: destination, encoding: .utf8) == markdown, "failed media export retains original Markdown")
    check(try manager.contentsOfDirectory(atPath: root.path).sorted() == listingBefore, "failed export cleans temporary artifacts")

    // Destination is a directory: writing Markdown fails after assets staged.
    let invalidDestination = root.appendingPathComponent("invalid.md")
    try manager.createDirectory(at: invalidDestination, withIntermediateDirectories: false)
    do {
        try MarkdownExportPackage.write(to: invalidDestination, assets: [assets[0]]) { _ in "invalid" }
        check(false, "failed document write must throw")
    } catch { check(true, "failed document write surfaces an error") }
    check(!manager.fileExists(atPath: root.appendingPathComponent("invalid.assets").path), "failed document write removes only newly exported assets")
    check(MarkdownExportPackage.safeFilename("../List:Name\n") == "-List-Name-", "unsafe display title sanitized")
    let longName = MarkdownExportPackage.safeFilename(String(repeating: "日本語👩🏽‍💻", count: 50) + ".pdf")
    check(longName.utf8.count <= 180 && longName.hasSuffix(".pdf"), "long Unicode attachment names keep extension within filesystem byte limit")
} catch {
    check(false, "export fixture setup", error.localizedDescription)
}

print(failures == 0 ? "✅ \(checks) export checks passed" : "❌ \(failures)/\(checks) export checks failed")
exit(failures == 0 ? 0 : 1)
