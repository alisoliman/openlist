// Checks the rich-text splice that lets a plain text field retitle a task
// without discarding its inline styling. Compiled against the real
// RichTextCodec by Tools/run-logic-checks.sh.

import AppKit

var failures = 0, checks = 0

@MainActor
func check(_ c: Bool, _ label: String, _ detail: @autoclosure () -> String = "") {
    checks += 1
    if !c { failures += 1; print("FAIL  \(label)\(detail().isEmpty ? "" : " — \(detail())")") }
}

@MainActor
func splice(_ source: NSAttributedString, _ newText: String) -> NSAttributedString {
    RichTextCodec.replacingText(in: source, with: newText)
}

let bold = NSFont.boldSystemFont(ofSize: 13)
let plain = NSFont.systemFont(ofSize: 13)

// "Call mum tomorrow" with "mum" bold.
@MainActor
func sample() -> NSAttributedString {
    let s = NSMutableAttributedString(string: "Call mum tomorrow", attributes: [.font: plain])
    s.addAttribute(.font, value: bold, range: NSRange(location: 5, length: 3))
    return s
}

@MainActor
func isBold(_ s: NSAttributedString, _ loc: Int) -> Bool {
    guard loc < s.length, let f = s.attribute(.font, at: loc, effectiveRange: nil) as? NSFont else { return false }
    return NSFontManager.shared.traits(of: f).contains(.boldFontMask)
}

do { // Append at end
    let r = splice(sample(), "Call mum tomorrow!")
    check(r.string == "Call mum tomorrow!", "append text", r.string)
    check(isBold(r, 5) && isBold(r, 7), "bold survives append")
    check(!isBold(r, 17), "appended char not bold")
}
do { // Delete the trailing word
    let r = splice(sample(), "Call mum")
    check(r.string == "Call mum", "delete suffix", r.string)
    check(isBold(r, 5) && isBold(r, 7), "bold survives suffix delete")
}
do { // Edit the leading word only
    let r = splice(sample(), "Ring mum tomorrow")
    check(r.string == "Ring mum tomorrow", "replace prefix word", r.string)
    check(isBold(r, 5) && isBold(r, 7), "bold span shifts intact")
    check(!isBold(r, 0), "prefix stays plain")
}
do { // Type inside the bold word
    let r = splice(sample(), "Call mumm tomorrow")
    check(r.string == "Call mumm tomorrow", "insert inside bold", r.string)
    check(isBold(r, 8), "insertion inherits bold")
}
do { // Full replacement
    let r = splice(sample(), "Something else")
    check(r.string == "Something else", "full replace", r.string)
}
do { // No-op returns the original
    let s = sample()
    check(splice(s, s.string).isEqual(to: s), "identical text is a no-op")
}
do { // Empty source
    let r = splice(NSAttributedString(string: ""), "New")
    check(r.string == "New", "empty source", r.string)
}
do { // Clearing everything
    let r = splice(sample(), "")
    check(r.string == "", "clear to empty", r.string)
}

print(failures == 0 ? "✅ \(checks) splice checks passed" : "❌ \(failures)/\(checks) failed")
exit(failures == 0 ? 0 : 1)
