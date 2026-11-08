//
//  NextInspectorText.swift
//  openlist
//

import AppKit
import SwiftUI

/// The inspector's title or note, written in place: a native extra, as the
/// design's are static text. A text view rather than a SwiftUI field, which
/// on macOS draws neither a strike nor a paragraph's line spacing, so that a
/// completed task's title is struck through and wrapped lines fall on their
/// line box: a 600 20/1.25 title, and a 400 13.5/1.6 note set for reading,
/// as the task's body; the page's a step larger.
struct NXInspectorText: NSViewRepresentable {
    enum Role { case title, note }
    let role: Role
    @Binding var text: String
    /// A completed task's title: ink 0.45, struck through.
    var done = false
    /// Set at the page's larger size.
    var large = false
    /// The page's title in the screens' display serif, as their titles are.
    var serif = false
    let caretColor: NSColor
    let fields: NXInspectorFields
    /// It took the keyboard, or let it go.
    let onFocus: (Bool) -> Void
    /// Tab from the title, ⇧Tab from the note: the other one. Without it, they
    /// finish the edit.
    var onSwitch: (() -> Void)?
    /// Opens a link the note holds, as the window opens one.
    var openLink: ((URL) -> Void)?
    /// A box ticked while the note is at rest, which saves the note at once.
    var onCommit: (() -> Void)?
    /// The note's `/` menu opened, moved or closed.
    var onSlash: ((NXNoteSlash?) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NXInspectorTextView {
        let view = NXInspectorTextView.make(role: role)
        view.delegate = context.coordinator
        fields.register(view)
        context.coordinator.parent = self
        update(view)
        return view
    }

    func updateNSView(_ view: NXInspectorTextView, context: Context) {
        context.coordinator.parent = self
        update(view)
    }

    private func update(_ view: NXInspectorTextView) {
        view.onFocus = onFocus
        view.onSwitch = onSwitch
        view.openLink = openLink
        view.onCommit = onCommit
        view.onSlash = onSlash
        if view.insertionPointColor != caretColor { view.insertionPointColor = caretColor }
        if view.accent !== caretColor { view.accent = caretColor }
        if view.isDone != done { view.isDone = done }
        if view.isLarge != large || view.isSerif != serif { view.setSize(large: large, serif: serif) }
        // Set from outside: another task's, a commit's trim, or Undo.
        if view.string != text { view.show(text) }
    }

    /// Taken away while written, as the panel moves on to another task, the
    /// view is never told it let the keyboard go; its typing leaves Undo all
    /// the same, and it tells the panel so itself.
    static func dismantleNSView(_ view: NXInspectorTextView, coordinator: Coordinator) {
        view.leave(replacedIn: coordinator.parent?.fields)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NXInspectorTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 1 else { return nil }
        return CGSize(width: width, height: nsView.height(fittingWidth: width))
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NXInspectorText?

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NXInspectorTextView else { return }
            view.restyle()
            view.invalidateIntrinsicContentSize()
            // The placeholder comes and goes with the text.
            view.needsDisplay = true
            if let parent, parent.text != view.string { parent.text = view.string }
        }

        /// The caret never rests inside a line's hidden syntax.
        func textView(_ textView: NSTextView, willChangeSelectionFromCharacterRanges old: [NSValue],
                      toCharacterRanges new: [NSValue]) -> [NSValue] {
            guard let view = textView as? NXInspectorTextView, view.role == .note else { return new }
            return view.snapped(new, from: old)
        }
    }
}

/// The panel's title and note, for the keys that go from one to the other.
@MainActor
final class NXInspectorFields {
    private weak var title: NXInspectorTextView?
    private weak var note: NXInspectorTextView?
    /// The title of the details on show, beside the screen or as its page.
    private static weak var shownTitle: NXInspectorTextView?

    fileprivate func register(_ view: NXInspectorTextView) {
        switch view.role {
        case .title:
            title = view
            Self.shownTitle = view
        case .note: note = view
        }
    }

    /// Whether the title or the note on screen has the keyboard.
    fileprivate func isWriting(_ role: NXInspectorText.Role) -> Bool {
        (role == .title ? title : note)?.isWriting == true
    }

    /// Puts the caret at the end of the title or the note, as the design's
    /// ⇧Tab puts it at the end of the line the note is under.
    func write(_ role: NXInspectorText.Role) {
        guard let view = role == .title ? title : note else { return }
        Self.write(view)
    }

    /// A choice clicked in the note's `/` menu.
    func applySlash(_ block: NoteMarkdown.Block) { note?.applySlash(block) }

    /// The note's `/` menu, put away.
    func closeSlash() { note?.closeSlash() }

    /// Return on the row of the task the details show: the caret goes to
    /// the end of their title.
    static func writeShownTitle() {
        guard let shownTitle else { return }
        write(shownTitle)
    }

    private static func write(_ view: NXInspectorTextView) {
        guard let window = view.window, window.makeFirstResponder(view) else { return }
        view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
    }
}

/// The text view behind `NXInspectorText`. The note keeps the list
/// document's note keys: Return breaks the line, or goes on to a list's next
/// item; Esc, Tab and ⌘Return finish it; ⇧Tab goes back to the title. It's
/// written in Markdown, drawn as it reads: see `styleNote`. The title stays one line, as
/// the design's line input does: Return, Esc and ⇧Tab finish it, Tab goes
/// on to the note when one shows, and a paste's or a drop's line breaks
/// become spaces. At rest either shows its text alone, as the design's
/// static text: no selection, and no spelling marks.
final class NXInspectorTextView: NSTextView {
    private(set) var role: NXInspectorText.Role = .note
    var isDone = false {
        didSet { if isDone != oldValue { restyle(); needsDisplay = true } }
    }
    /// At the page's larger size, and in its serif.
    private(set) var isLarge = false
    private(set) var isSerif = false
    /// The note's links, in the caret's accent.
    var accent: NSColor = NXEditor.ink {
        didSet { if accent !== oldValue { restyle() } }
    }
    var onFocus: ((Bool) -> Void)?
    var onSwitch: (() -> Void)?
    /// Whether it has the keyboard, and what the panel was last told.
    private(set) var isWriting = false
    private var reportedWriting = false
    /// The note checks spelling only while it's written; what Edit ▸
    /// Spelling set then holds for the next time.
    private var checksSpelling = false
    /// Where its typing goes, still known once it has left the window.
    private weak var typingUndo: UndoManager?
    // The note's own, in NextNoteEditing.swift.
    var openLink: ((URL) -> Void)?
    var onCommit: (() -> Void)?
    var onSlash: ((NXNoteSlash?) -> Void)?
    /// The `/` menu while it's open.
    var slash: NXNoteSlash?
    /// What the note was last styled from, so an unchanged note isn't styled again.
    var noteStyleKey: NXNoteStyleKey?
    /// The character a click that's giving the note the keyboard landed on,
    /// read before its syntax shows and moves the text under the pointer.
    private var clickedIndex: Int?

    // Shared instances: attributed strings compare dynamic colours by
    // identity, as `NXEditor`'s colours note.
    private static let doneInk = NXEditor.ink.withAlphaComponent(0.45)

    /// One role's type at one size, made once: its face, line box and the
    /// attributes built from them.
    struct Metrics {
        let font: NSFont
        /// `size × line-height`.
        let lineBox: CGFloat
        /// The first line's height as laid out: the line box, or the face's
        /// own line where that's taller, as the serif's is.
        let line: CGFloat
        /// What the line box leaves over TextKit's own line: all of it goes
        /// between wrapped lines, and half of it above the first and below
        /// the last, as CSS places a line's leading, so n lines stand n line
        /// boxes tall.
        let leading: CGFloat
        let attributes: [NSAttributedString.Key: Any]
        /// A done title's: grey and struck.
        let doneAttributes: [NSAttributedString.Key: Any]
        /// A note's Markdown headings, levels 1 to 3, and its code.
        let headingFonts: [NSFont]
        let codeFont: NSFont

        init(size: CGFloat, weight: NSFont.Weight, lineHeight: CGFloat, color: NSColor, kern: CGFloat = 0,
             headings: [CGFloat] = [], code: CGFloat = 12) {
            self.init(font: .systemFont(ofSize: size, weight: weight), lineHeight: lineHeight, color: color, kern: kern,
                      headings: headings, code: code)
        }

        init(font: NSFont, lineHeight: CGFloat, color: NSColor, kern: CGFloat = 0,
             headings: [CGFloat] = [], code: CGFloat = 12) {
            self.font = font
            lineBox = font.pointSize * lineHeight
            let natural = NSLayoutManager().defaultLineHeight(for: font)
            line = max(lineBox, natural)
            leading = max(0, lineBox - natural)
            attributes = Self.attributes(font: font, color: color, leading: leading, kern: kern)
            doneAttributes = Self.attributes(font: font, color: NXInspectorTextView.doneInk, leading: leading, kern: kern, struck: true)
            headingFonts = headings.map { NSFont.systemFont(ofSize: $0, weight: .semibold) }
            codeFont = .monospacedSystemFont(ofSize: code, weight: .regular)
        }

        private static func attributes(font: NSFont, color: NSColor, leading: CGFloat, kern: CGFloat,
                                       struck: Bool = false) -> [NSAttributedString.Key: Any] {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = leading
            var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
            if kern != 0 { attributes[.kern] = kern }
            if struck { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            return attributes
        }
    }

    /// A large title, as Superlist heads a task.
    private static let titleMetrics = Metrics(size: 20, weight: .semibold, lineHeight: 1.25, color: NXEditor.ink)
    /// A reading size, with the open line box long notes need, in the list
    /// document's reading ink, `NX.textSecondary`.
    private static let noteMetrics = Metrics(size: 13.5, weight: .regular, lineHeight: 1.6, color: NXEditor.secondaryInk,
                                             headings: [17, 15, 13.5], code: 12.5)
    /// The page's title in a screen title's 700 27, and its note a step
    /// larger to read at length.
    private static let pageTitleMetrics = Metrics(size: 27, weight: .bold, lineHeight: 1.15, color: NXEditor.ink, kern: -0.27)
    private static let pageNoteMetrics = Metrics(size: 14.5, weight: .regular, lineHeight: 1.65, color: NXEditor.secondaryInk,
                                                 headings: [18.5, 16.5, 14.5], code: 13)
    /// A screen's serif title, 34/1.05.
    private static let pageSerifTitleMetrics = Metrics(
        font: NSFont(name: "InstrumentSerif-Regular", size: 34)
            ?? NSFont(descriptor: NSFont.systemFont(ofSize: 34).fontDescriptor.withDesign(.serif) ?? NSFont.systemFont(ofSize: 34).fontDescriptor,
                      size: 34) ?? .systemFont(ofSize: 34),
        lineHeight: 1.05, color: NXEditor.ink)

    static func metrics(_ role: NXInspectorText.Role, large: Bool = false, serif: Bool = false) -> Metrics {
        switch (role, large) {
        case (.title, false): titleMetrics
        case (.title, true): serif ? pageSerifTitleMetrics : pageTitleMetrics
        case (.note, false): noteMetrics
        case (.note, true): pageNoteMetrics
        }
    }

    var metrics: Metrics { Self.metrics(role, large: isLarge, serif: isSerif) }

    /// Sets the text at the page's size and face, or back at the panel's.
    func setSize(large: Bool, serif: Bool) {
        isLarge = large
        isSerif = serif
        textContainerInset = NSSize(width: 0, height: metrics.leading / 2)
        noteStyleKey = nil
        textStorage.map { $0.setAttributes(attributes, range: NSRange(location: 0, length: $0.length)) }
        restyle()
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    /// The panel's line boxes, `size × line-height`.
    static func lineBox(_ role: NXInspectorText.Role) -> CGFloat { metrics(role).lineBox }

    static func leading(_ role: NXInspectorText.Role) -> CGFloat { metrics(role).leading }

    /// `text` with each line break a space, as the list document's paste
    /// joins them (`BlockNSTextView.joiningLines`).
    static func oneLine(_ text: String) -> String {
        BlockNSTextView.joiningLines(NSAttributedString(string: text)).string
    }

    static func make(role: NXInspectorText.Role) -> NXInspectorTextView {
        let storage = NSTextStorage()
        // The note draws its bullets, boxes, rules and bookmarks under its words.
        let layout = role == .note ? NXNoteLayoutManager() : NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        let view = NXInspectorTextView(frame: .zero, textContainer: container)
        view.role = role
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.checksSpelling = role == .note
        view.isContinuousSpellCheckingEnabled = false
        view.textContainerInset = NSSize(width: 0, height: leading(role) / 2)
        view.typingAttributes = view.attributes
        view.updateDragTypeRegistration()
        view.setAccessibilityLabel(role == .title ? "Task" : "Note")
        // One line that Return finishes reads as a field; the note, a text area.
        if role == .title { view.setAccessibilityRole(.textField) }
        view.setAccessibilityPlaceholderValue(view.placeholder)
        return view
    }

    var attributes: [NSAttributedString.Key: Any] {
        role == .title && isDone ? metrics.doneAttributes : metrics.attributes
    }

    private var placeholder: String { role == .title ? "Task" : "Add a note…" }

    /// Shows `text`, set from outside, keeping the caret where it can.
    func show(_ text: String) {
        guard !hasMarkedText(), let storage = textStorage else { return }
        // Typing Undo would step through text that's no longer there.
        undoManager?.removeAllActions(withTarget: storage)
        let selection = selectedRange()
        storage.setAttributedString(NSAttributedString(string: text, attributes: attributes))
        noteStyleKey = nil
        restyle()
        let location = min(selection.location, storage.length)
        setSelectedRange(NSRange(location: location, length: min(selection.length, storage.length - location)))
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    /// Keeps all the text in the one colour and strike, as ticking the task
    /// changes them and Undo can put back text typed before. The fonts stay,
    /// where TextKit has swapped one in for an emoji.
    func restyle() {
        let attributes = self.attributes
        typingAttributes = attributes
        if role == .note { return styleNote() }
        guard !hasMarkedText(), let storage = textStorage, storage.length > 0 else { return }
        let whole = NSRange(location: 0, length: storage.length)
        let color = attributes[.foregroundColor] as? NSColor
        let strike = attributes[.strikethroughStyle] as? Int
        var styled = true
        storage.enumerateAttributes(in: whole) { run, _, stop in
            guard (run[.foregroundColor] as? NSColor) !== color || (run[.strikethroughStyle] as? Int) != strike else { return }
            styled = false
            stop.pointee = true
        }
        guard !styled else { return }
        storage.beginEditing()
        storage.removeAttribute(.strikethroughStyle, range: whole)
        storage.addAttributes(attributes.filter { $0.key != .font }, range: whole)
        storage.endEditing()
    }

    func height(fittingWidth width: CGFloat) -> CGFloat {
        let font = metrics.font
        guard let container = textContainer, let layout = layoutManager else { return metrics.lineBox }
        container.containerSize = CGSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container)
        let lines = max(used.maxY, layout.extraLineFragmentRect.maxY, layout.defaultLineHeight(for: font))
        // A width only asked about isn't the one drawn at: the text goes
        // back to its own width, which a frame left as it was won't reset.
        if bounds.width > 0, bounds.width != width {
            container.containerSize = CGSize(width: bounds.width, height: .greatestFiniteMagnitude)
        }
        return lines + textContainerInset.height * 2
    }

    // MARK: The note's changes

    /// The `/` menu follows what's typed.
    override func didChangeText() {
        super.didChangeText()
        if role == .note { textDidChangeInNote() }
    }

    /// Syntax the caret has gone into, or out of, shows or goes, and the
    /// Format menu follows what's selected.
    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        if role == .note, !stillSelecting { selectionDidChangeInNote() }
    }

    // MARK: Keyboard

    override func becomeFirstResponder() -> Bool {
        if role == .note, !isWriting, let event = NSApp.currentEvent, event.type == .leftMouseDown, event.window === window {
            let point = convert(event.locationInWindow, from: nil)
            // A click on a box, a link or a bookmark acts on it, and the
            // note stays at rest.
            if noteWidget(at: point, command: event.modifierFlags.contains(.command)) != nil { return false }
            clickedIndex = bounds.contains(point) ? characterIndexForInsertion(at: point) : nil
        }
        guard super.becomeFirstResponder() else {
            clickedIndex = nil
            return false
        }
        isWriting = true
        if role == .note { restyle() }
        isContinuousSpellCheckingEnabled = checksSpelling
        typingUndo = undoManager
        updateDragTypeRegistration()
        reportWriting()
        return true
    }

    override func resignFirstResponder() -> Bool {
        guard super.resignFirstResponder() else { return false }
        isWriting = false
        // As a blurred input shows no selection. An overlay that borrows the
        // keyboard noted it first, and puts it back when it closes.
        setSelectedRange(NSRange(location: NSMaxRange(selectedRange()), length: 0))
        if role == .note {
            closeSlash()
            restyle()
            InlineFormatting.shared.update(self, focused: false)
        }
        stopCheckingSpelling()
        updateDragTypeRegistration()
        dropTyping()
        reportWriting()
        return true
    }

    /// The marks made while it was written go with the edit.
    private func stopCheckingSpelling() {
        checksSpelling = isContinuousSpellCheckingEnabled
        isContinuousSpellCheckingEnabled = false
        guard let layoutManager, let textStorage, textStorage.length > 0 else { return }
        layoutManager.removeTemporaryAttribute(.spellingState, forCharacterRange: NSRange(location: 0, length: textStorage.length))
    }

    /// What was typed is saved as one step, which the typing mustn't stay
    /// under, as the list document's note folds it into its step.
    func dropTyping() {
        breakUndoCoalescing()
        if let textStorage { (undoManager ?? typingUndo)?.removeAllActions(withTarget: textStorage) }
    }

    /// Taken away while written: it lets the keyboard go without being told,
    /// so the panel's focus, and Task ▸ Open Details, don't stay on it.
    func leave(replacedIn fields: NXInspectorFields?) {
        dropTyping()
        guard isWriting else { return }
        isWriting = false
        reportWriting(replacedIn: fields)
    }

    /// Tells the panel once the change is over, never in the middle of the
    /// update that took the view away, and only what still holds by then:
    /// not that a view taken away let go, once the one in its place has the keyboard.
    private func reportWriting(replacedIn fields: NXInspectorFields? = nil) {
        DispatchQueue.main.async { [self] in
            guard isWriting != reportedWriting, fields?.isWriting(role) != true else { return }
            reportedWriting = isWriting
            onFocus?(isWriting)
        }
    }

    /// A click that gave the note the keyboard puts the caret on the
    /// character it was on as the note read at rest.
    override func mouseDown(with event: NSEvent) {
        if role == .note, let widget = noteWidget(at: convert(event.locationInWindow, from: nil),
                                                  command: event.modifierFlags.contains(.command)) {
            clickedIndex = nil
            return perform(widget)
        }
        let clicked = clickedIndex
        clickedIndex = nil
        super.mouseDown(with: event)
        guard let clicked, clicked != NSNotFound, selectedRange().length == 0 else { return }
        let location = min(clicked, (string as NSString).length)
        setSelectedRange(NSRange(location: role == .note ? snapped(location) : location, length: 0))
    }

    /// A box, and a link that opens, take the pointing hand.
    override func mouseMoved(with event: NSEvent) {
        if role == .note, noteWidget(at: convert(event.locationInWindow, from: nil),
                                     command: event.modifierFlags.contains(.command)) != nil {
            NSCursor.pointingHand.set()
            return
        }
        super.mouseMoved(with: event)
    }

    override func doCommand(by selector: Selector) {
        if role == .note, handleNoteCommand(selector) { return }
        if !handle(selector) { super.doCommand(by: selector) }
    }

    private func handle(_ selector: Selector) -> Bool {
        switch selector {
        // Esc saves and lets go; the next Esc closes the panel.
        case #selector(cancelOperation(_:)):
            finish()
        // Tab leaves the note, as it leaves the design's textarea, rather
        // than typing a tab (⌥Tab still types one); from the title it goes
        // on to the note. ⇧Tab goes back from the note to the title, as the
        // design's goes back to the note's line.
        case #selector(insertTab(_:)):
            if role == .title, let onSwitch { onSwitch() } else { leave(forward: true) }
        case #selector(insertBacktab(_:)):
            if role == .note, let onSwitch { onSwitch() } else { leave(forward: false) }
        // Every line break finishes the title, as Return submits an input.
        // In the note, Return goes on to a list's next item.
        case #selector(insertNewline(_:)), #selector(insertNewlineIgnoringFieldEditor(_:)),
             #selector(insertLineBreak(_:)), #selector(insertParagraphSeparator(_:)):
            guard role == .title else { return selector == #selector(insertNewline(_:)) && continueList() }
            finish()
        default:
            return false
        }
        return true
    }

    override func keyDown(with event: NSEvent) {
        if role == .note, Self.finishesNote(event) {
            finish()
            return
        }
        super.keyDown(with: event)
    }

    /// ⌘Return finishes the note before the menus see it, so Task ▸ Open
    /// Details can't take it, as the list document's note does. ⇧⌘Return
    /// goes on to Task ▸ Expand Details.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard role == .note, window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        if Self.finishesNote(event) {
            finish()
            return true
        }
        return noteKeyEquivalent(event) || super.performKeyEquivalent(with: event)
    }

    private static func finishesNote(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return (event.keyCode == 36 || event.keyCode == 76) && flags.contains(.command) && !flags.contains(.shift)
    }

    func finish() { window?.makeFirstResponder(nil) }

    /// Tab out of the note, or ⇧Tab out of the title: with Keyboard
    /// navigation on, on to the next control or back to the one before, as
    /// Tab leaves a textarea; otherwise the edit finishes.
    private func leave(forward: Bool) {
        guard NSApp.isFullKeyboardAccessEnabled, let window else { return finish() }
        if forward { window.selectNextKeyView(self) } else { window.selectPreviousKeyView(self) }
        if window.firstResponder === self { finish() }
    }

    /// Return on a list item starts the next, with the same bullet, the
    /// number after or an open box; on an empty one it takes the bullet off,
    /// ending the list. Anywhere else it's an ordinary line break.
    func continueList() -> Bool {
        let text = string as NSString
        let caret = selectedRange()
        guard caret.length == 0, !hasMarkedText(), caret.location <= text.length else { return false }
        let line = text.lineRange(for: NSRange(location: caret.location, length: 0))
        var end = NSMaxRange(line)
        if end > line.location, text.character(at: end - 1) == 10 { end -= 1 }
        switch NoteMarkdown.continuation(of: text.substring(with: NSRange(location: line.location, length: end - line.location))) {
        case let .next(bullet)?:
            insertText("\n" + bullet, replacementRange: caret)
        case let .end(length)?:
            let bullet = NSRange(location: line.location, length: length)
            guard shouldChangeText(in: bullet, replacementString: "") else { return true }
            textStorage?.replaceCharacters(in: bullet, with: "")
            didChangeText()
        case nil:
            return false
        }
        return true
    }

    // MARK: One-line title

    /// Typed or dictated text keeps the title to one line. In the note, a
    /// space after `[]` makes a checklist item, and a `/` opens the menu.
    override func insertText(_ string: Any, replacementRange: NSRange) {
        if role == .note {
            if insertNoteShortcut(string) { return }
            super.insertText(string, replacementRange: replacementRange)
            return noteDidInsert(string)
        }
        switch string {
        case let text as NSAttributedString: super.insertText(BlockNSTextView.joiningLines(text), replacementRange: replacementRange)
        case let text as String: super.insertText(Self.oneLine(text), replacementRange: replacementRange)
        default: super.insertText(string, replacementRange: replacementRange)
        }
    }

    /// A paste or a drop keeps it to one line too, each break a space, as
    /// the list document's line takes one.
    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        // An address pasted over words in the note links them.
        if role == .note, pasteLink(from: pboard) { return true }
        guard role == .title else { return super.readSelection(from: pboard, type: type) }
        let range = rangeForUserTextChange
        let length = textStorage?.length ?? 0
        guard super.readSelection(from: pboard, type: type) else { return false }
        guard range.location != NSNotFound, let storage = textStorage else { return true }
        let pasted = NSRange(location: range.location, length: range.length + storage.length - length)
        guard pasted.length > 0, NSMaxRange(pasted) <= storage.length else { return true }
        let text = storage.attributedSubstring(from: pasted)
        let joined = BlockNSTextView.joiningLines(text)
        if joined.string != text.string, shouldChangeText(in: pasted, replacementString: joined.string) {
            storage.replaceCharacters(in: pasted, with: joined)
            didChangeText()
            setSelectedRange(NSRange(location: pasted.location + joined.length, length: 0))
        }
        return true
    }

    /// Only while it's being written does text dropped on it go in. Until
    /// then a drop is the panel's, which keeps dropped files with the task.
    override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
        isWriting ? [.string] : []
    }

    // MARK: Placeholder

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !hasMarkedText() else { return }
        var attributes = self.attributes
        attributes[.foregroundColor] = NXEditor.placeholderInk
        attributes[.strikethroughStyle] = nil
        // Being written, an empty note says how its blocks are made.
        NSAttributedString(string: role == .note && isWriting ? "Type / for blocks" : placeholder, attributes: attributes)
            .draw(in: NSRect(origin: textContainerOrigin, size: NSSize(
                width: bounds.width, height: bounds.height - textContainerInset.height * 2
            )))
    }
}
