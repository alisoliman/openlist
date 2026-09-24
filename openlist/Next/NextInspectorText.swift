//
//  NextInspectorText.swift
//  openlist
//

import AppKit
import SwiftUI

/// The inspector's title or note, written in place: a native extra, as the
/// design's are static text. A text view rather than a SwiftUI field, which
/// on macOS draws neither a strike nor a paragraph's line spacing, so that a
/// completed task's title is struck through and wrapped lines fall on the
/// design's line box, 600 18/1.3 and 400 13/1.55, as the design's do.
struct NXInspectorText: NSViewRepresentable {
    enum Role { case title, note }
    let role: Role
    @Binding var text: String
    /// A completed task's title: ink 0.45, struck through.
    var done = false
    let caretColor: NSColor
    let fields: NXInspectorFields
    /// Takes the keyboard once it's on screen, as "Add a note" opens the note.
    var takesKeyboard = false
    /// It took the keyboard, or let it go.
    let onFocus: (Bool) -> Void
    /// Tab from the title, ⇧Tab from the note: the other one. Without it, they
    /// finish the edit.
    var onSwitch: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NXInspectorTextView {
        let view = NXInspectorTextView.make(role: role)
        view.delegate = context.coordinator
        view.wantsKeyboard = takesKeyboard
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
        if view.insertionPointColor != caretColor { view.insertionPointColor = caretColor }
        if view.isDone != done { view.isDone = done }
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
    }
}

/// The panel's title and note, for the keys that go from one to the other.
@MainActor
final class NXInspectorFields {
    private weak var title: NXInspectorTextView?
    private weak var note: NXInspectorTextView?

    fileprivate func register(_ view: NXInspectorTextView) {
        switch view.role {
        case .title: title = view
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
        guard let view = role == .title ? title : note, let window = view.window,
              window.makeFirstResponder(view) else { return }
        view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
    }
}

/// The text view behind `NXInspectorText`. The note keeps the list
/// document's note keys: Return breaks the line; Esc, Tab and ⌘Return
/// finish it; ⇧Tab goes back to the title. The title stays one line, as
/// the design's line input does: Return, Esc and ⇧Tab finish it, Tab goes
/// on to the note when one shows, and a paste's or a drop's line breaks
/// become spaces. At rest either shows its text alone, as the design's
/// static text: no selection, and no spelling marks.
final class NXInspectorTextView: NSTextView {
    private(set) var role: NXInspectorText.Role = .note
    var isDone = false {
        didSet { if isDone != oldValue { restyle(); needsDisplay = true } }
    }
    var onFocus: ((Bool) -> Void)?
    var onSwitch: (() -> Void)?
    /// Takes the keyboard as it lands in a window.
    var wantsKeyboard = false
    /// Whether it has the keyboard, and what the panel was last told.
    private(set) var isWriting = false
    private var reportedWriting = false
    /// The note checks spelling only while it's written; what Edit ▸
    /// Spelling set then holds for the next time.
    private var checksSpelling = false
    /// Where its typing goes, still known once it has left the window.
    private weak var typingUndo: UndoManager?

    static let titleFont = NSFont.systemFont(ofSize: 18, weight: .semibold)
    static let noteFont = NSFont.systemFont(ofSize: 13)

    /// The design's line boxes, `size × line-height`.
    static func lineBox(_ role: NXInspectorText.Role) -> CGFloat {
        role == .title ? 18 * 1.3 : 13 * 1.55
    }

    /// What the line box leaves over TextKit's own line: all of it goes
    /// between wrapped lines, and half of it above the first and below the
    /// last, as CSS places a line's leading, so n lines stand n line boxes tall.
    static func leading(_ role: NXInspectorText.Role) -> CGFloat {
        role == .title ? titleLeading : noteLeading
    }

    private static let titleLeading = max(0, lineBox(.title) - NSLayoutManager().defaultLineHeight(for: titleFont))
    private static let noteLeading = max(0, lineBox(.note) - NSLayoutManager().defaultLineHeight(for: noteFont))

    // Shared instances: attributed strings compare dynamic colours by
    // identity, as `NXEditor`'s colours note.
    private static let doneInk = NXEditor.ink.withAlphaComponent(0.45)
    private static let noteInk = NXEditor.ink.withAlphaComponent(0.7)
    private static let titleAttributes = attributes(font: titleFont, color: NXEditor.ink, leading: titleLeading)
    private static let doneTitleAttributes = attributes(font: titleFont, color: doneInk, leading: titleLeading, struck: true)
    private static let noteAttributes = attributes(font: noteFont, color: noteInk, leading: noteLeading)

    private static func attributes(font: NSFont, color: NSColor, leading: CGFloat,
                                   struck: Bool = false) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = leading
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
        if struck { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        return attributes
    }

    /// `text` with each line break a space, as the list document's paste
    /// joins them (`BlockNSTextView.joiningLines`).
    static func oneLine(_ text: String) -> String {
        BlockNSTextView.joiningLines(NSAttributedString(string: text)).string
    }

    static func make(role: NXInspectorText.Role) -> NXInspectorTextView {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
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
        switch role {
        case .title: isDone ? Self.doneTitleAttributes : Self.titleAttributes
        case .note: Self.noteAttributes
        }
    }

    private var placeholder: String { role == .title ? "Task" : "Add a note…" }

    /// Shows `text`, set from outside, keeping the caret where it can.
    func show(_ text: String) {
        guard !hasMarkedText(), let storage = textStorage else { return }
        // Typing Undo would step through text that's no longer there.
        undoManager?.removeAllActions(withTarget: storage)
        let selection = selectedRange()
        storage.setAttributedString(NSAttributedString(string: text, attributes: attributes))
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
        let font = role == .title ? Self.titleFont : Self.noteFont
        guard let container = textContainer, let layout = layoutManager else { return Self.lineBox(role) }
        container.containerSize = CGSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container)
        let lines = max(used.maxY, layout.extraLineFragmentRect.maxY, layout.defaultLineHeight(for: font))
        return lines + textContainerInset.height * 2
    }

    // MARK: Keyboard

    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        isWriting = true
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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard wantsKeyboard, window != nil else { return }
        wantsKeyboard = false
        // Once it's on screen, or the keyboard can miss it.
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window, window.makeFirstResponder(self) else { return }
            self.setSelectedRange(NSRange(location: (self.string as NSString).length, length: 0))
        }
    }

    override func doCommand(by selector: Selector) {
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
            if role == .title, let onSwitch { onSwitch() } else { finish() }
        case #selector(insertBacktab(_:)):
            if role == .note, let onSwitch { onSwitch() } else { finish() }
        // Every line break finishes the title, as Return submits an input.
        case #selector(insertNewline(_:)), #selector(insertNewlineIgnoringFieldEditor(_:)),
             #selector(insertLineBreak(_:)), #selector(insertParagraphSeparator(_:)):
            guard role == .title else { return false }
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
    /// Details can't take it, as the list document's note does.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard role == .note, Self.finishesNote(event), window?.firstResponder === self else {
            return super.performKeyEquivalent(with: event)
        }
        finish()
        return true
    }

    private static func finishesNote(_ event: NSEvent) -> Bool {
        (event.keyCode == 36 || event.keyCode == 76)
            && event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
    }

    private func finish() { window?.makeFirstResponder(nil) }

    // MARK: One-line title

    /// Typed or dictated text keeps the title to one line.
    override func insertText(_ string: Any, replacementRange: NSRange) {
        guard role == .title else { return super.insertText(string, replacementRange: replacementRange) }
        switch string {
        case let text as NSAttributedString: super.insertText(BlockNSTextView.joiningLines(text), replacementRange: replacementRange)
        case let text as String: super.insertText(Self.oneLine(text), replacementRange: replacementRange)
        default: super.insertText(string, replacementRange: replacementRange)
        }
    }

    /// A paste or a drop keeps it to one line too, each break a space, as
    /// the list document's line takes one.
    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
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
        NSAttributedString(string: placeholder, attributes: attributes)
            .draw(in: NSRect(origin: textContainerOrigin, size: NSSize(
                width: bounds.width, height: bounds.height - textContainerInset.height * 2
            )))
    }
}
