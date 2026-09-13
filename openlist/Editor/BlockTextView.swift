//
//  BlockTextView.swift
//  openlist
//

import AppKit
import SwiftUI

/// Which way an arrow key was heading when it ran off the end of a block.
enum EditorArrow {
    case up, down
}

/// Everything the outline needs to hear about from one block's text view.
///
/// Each closure returns `true` when the outline consumed the event, in which
/// case the text view suppresses its own default behaviour.
struct BlockEditorCallbacks {
    var onChange: (NSAttributedString) -> Void = { _ in }
    /// Return pressed. Receives the caret offset so the outline can split.
    var onReturn: (Int, NSAttributedString) -> Bool = { _, _ in false }
    /// Tab (or Shift-Tab) pressed.
    var onTab: (_ isBacktab: Bool, _ caret: Int) -> Bool = { _, _ in false }
    /// Backspace with the caret at offset zero and nothing selected.
    var onBackspaceAtStart: (NSAttributedString) -> Bool = { _ in false }
    /// Forward-delete with the caret at the very end.
    var onDeleteAtEnd: () -> Bool = { false }
    /// Arrow key that would leave this block.
    var onArrowOut: (_ direction: EditorArrow, _ caret: Int) -> Bool = { _, _ in false }
    var onFocus: () -> Void = {}
    var onEscape: () -> Void = {}
    /// The `/` menu query changed. `nil` means the menu should close.
    /// `range` covers the trigger and its query, so the outline can remove
    /// exactly that span rather than assuming it sits at the end of the line.
    var onSlashQuery: (_ query: String?, _ range: NSRange, _ caretRect: CGRect, _ viewport: CGRect) -> Void = { _, _, _, _ in }
    /// A block-kind change requested by a markdown prefix such as `## `.
    var onMarkdownPrefix: (BlockKind) -> Void = { _ in }
    /// A multi-line paste. Return `true` to keep the default insert from
    /// dumping the whole thing into this one block.
    var onPasteMultiline: (String) -> Bool = { _ in false }
}

/// A single editable line of a document, backed by `NSTextView`.
///
/// SwiftUI's `TextEditor` cannot express the key handling an outliner needs —
/// Return that splits a block, Tab that re-parents it, Backspace that merges
/// upwards — so each block hosts a bare `NSTextView` and the outline arbitrates.
struct BlockTextView: NSViewRepresentable {
    let blockID: UUID
    let kind: BlockKind
    let isCompleted: Bool
    let attributedText: NSAttributedString
    var placeholder: String = ""
    var isFocused: Bool
    /// Caret offset to apply on the next focus pass. `-1` means end of text.
    var pendingCaret: Int?
    /// Changes only when focus is moved programmatically, so ordinary typing
    /// never yanks the caret back.
    var focusToken: Int
    /// While the `/` menu is showing it takes over Return, Tab and the arrows.
    var isSlashMenuOpen: Bool = false
    var onSlashCommand: (SlashMenuCommand) -> Void = { _ in }
    var callbacks: BlockEditorCallbacks

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> BlockNSTextView {
        // An explicit TextKit 1 stack: layout metrics are needed synchronously
        // for self-sizing, which TextKit 2's async layout does not guarantee.
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)

        let view = BlockNSTextView(frame: .zero, textContainer: container)
        view.coordinator = context.coordinator
        view.delegate = context.coordinator
        view.isRichText = true
        view.isEditable = true
        view.isSelectable = true
        view.allowsUndo = true
        view.drawsBackground = false
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.textContainerInset = NSSize.zero
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isAutomaticLinkDetectionEnabled = true
        view.isContinuousSpellCheckingEnabled = true
        view.usesFindBar = false
        let linkAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand,
        ]
        view.linkTextAttributes = linkAttributes

        context.coordinator.apply(attributedText, to: view, kind: kind, isCompleted: isCompleted)
        view.placeholderString = placeholder
        view.isSlashMenuOpen = isSlashMenuOpen
        view.slashMenuCommand = onSlashCommand
        return view
    }

    func updateNSView(_ view: BlockNSTextView, context: Context) {
        context.coordinator.parent = self
        view.placeholderString = placeholder
        view.isSlashMenuOpen = isSlashMenuOpen
        view.slashMenuCommand = onSlashCommand

        // Only touch the storage when something actually changed underneath us,
        // otherwise every keystroke would reset the caret.
        let signature = ContentSignature(
            attributedText: attributedText,
            kind: kind,
            isCompleted: isCompleted
        )
        if context.coordinator.signature != signature || context.coordinator.consumeRestyleRequest() {
            context.coordinator.apply(attributedText, to: view, kind: kind, isCompleted: isCompleted)
        }

        context.coordinator.syncFocus(view: view, shouldFocus: isFocused, caret: pendingCaret, token: focusToken)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: BlockNSTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 1 else { return nil }
        return CGSize(width: width, height: nsView.height(fittingWidth: width))
    }

    // MARK: - Coordinator

    struct ContentSignature: Equatable {
        let attributedText: NSAttributedString
        let kind: BlockKind
        let isCompleted: Bool

        init(attributedText: NSAttributedString, kind: BlockKind, isCompleted: Bool) {
            self.attributedText = NSAttributedString(attributedString: attributedText)
            self.kind = kind
            self.isCompleted = isCompleted
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: BlockTextView
        var signature: ContentSignature?
        /// Guards against re-entrant model writes while we restyle the storage.
        private var isApplyingExternalChange = false
        private var lastFocusToken: Int?
        /// Set when the block's appearance must be rebuilt even though its text
        /// is unchanged — a kind change carries no text edit with it.
        private var needsRestyle = false
        /// Length before the current edit, so `textDidChange` can tell an
        /// insertion from a deletion.
        private var previousLength = 0
        private var dismissedSlashIndex: Int?

        init(_ parent: BlockTextView) {
            self.parent = parent
        }

        /// Reads and clears the pending restyle request.
        func consumeRestyleRequest() -> Bool {
            defer { needsRestyle = false }
            return needsRestyle
        }

        func apply(_ attributed: NSAttributedString, to view: BlockNSTextView, kind: BlockKind, isCompleted: Bool) {
            isApplyingExternalChange = true
            defer { isApplyingExternalChange = false }

            let previousSelection = view.selectedRange()
            view.textStorage?.setAttributedString(attributed)
            view.typingAttributes = RichTextCodec.baseAttributes(for: kind, isCompleted: isCompleted)
            view.blockKind = kind

            let length = view.textStorage?.length ?? 0
            let restored = NSRange(
                location: min(previousSelection.location, length),
                length: min(previousSelection.length, max(0, length - min(previousSelection.location, length)))
            )
            view.setSelectedRange(restored)
            view.invalidateIntrinsicContentSize()
            view.needsDisplay = true

            signature = ContentSignature(attributedText: attributed, kind: kind, isCompleted: isCompleted)
            previousLength = attributed.length
        }

        /// Applies a *programmatic* focus move.
        ///
        /// Keyed on `token` rather than the boolean, because while a block is
        /// focused SwiftUI re-runs `updateNSView` on every keystroke and a
        /// naive check would drag the caret back to `pendingCaret` each time.
        func syncFocus(view: BlockNSTextView, shouldFocus: Bool, caret: Int?, token: Int) {
            guard token != lastFocusToken else { return }
            lastFocusToken = token
            guard shouldFocus else { return }

            // Defer: during a SwiftUI update pass the view may not be in a
            // window yet, and makeFirstResponder would fail silently.
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, self.lastFocusToken == token, self.parent.isFocused,
                      let view, let window = view.window else { return }
                if window.firstResponder !== view {
                    window.makeFirstResponder(view)
                }
                if let caret {
                    let length = view.textStorage?.length ?? 0
                    let clamped = caret < 0 ? length : min(caret, length)
                    view.setSelectedRange(NSRange(location: clamped, length: 0))
                    view.scrollRangeToVisible(NSRange(location: clamped, length: 0))
                }
            }
        }

        // MARK: NSTextViewDelegate

        func textDidChange(_ notification: Notification) {
            guard !isApplyingExternalChange,
                  let view = notification.object as? BlockNSTextView,
                  let storage = view.textStorage
            else { return }

            // Markdown prefixes convert the whole block before anything is stored.
            let wasInsertion = storage.length > previousLength
            previousLength = storage.length

            if let rule = MarkdownInputRules.matchBlockPrefix(
                in: storage,
                caret: view.selectedRange().location,
                wasInsertion: wasInsertion,
                kind: parent.kind
            ) {
                storage.deleteCharacters(in: rule.range)
                view.setSelectedRange(NSRange(location: 0, length: 0))
                view.invalidateIntrinsicContentSize()

                // Persist the stripped text before changing kind, otherwise the
                // model keeps the "## " the user just consumed.
                parent.callbacks.onChange(NSAttributedString(attributedString: storage))
                signature = ContentSignature(
                    attributedText: storage,
                    kind: parent.kind,
                    isCompleted: parent.isCompleted
                )
                // The kind is about to change out from under us, and the new
                // fonts have to be applied even though the text did not move.
                needsRestyle = true
                parent.callbacks.onMarkdownPrefix(rule.kind)
                return
            }

            // Inline rules such as **bold** fire on the closing delimiter.
            if MarkdownInputRules.applyInlineRules(in: storage, view: view, kind: parent.kind) {
                view.invalidateIntrinsicContentSize()
            }

            signature = ContentSignature(
                attributedText: storage,
                kind: parent.kind,
                isCompleted: parent.isCompleted
            )
            parent.callbacks.onChange(NSAttributedString(attributedString: storage))
            updateSlashQuery(in: view)
            view.invalidateIntrinsicContentSize()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            // Selection changes fire while `apply` is rewriting the storage;
            // reporting then would push SwiftUI state during a view update.
            guard !isApplyingExternalChange,
                  let view = notification.object as? BlockNSTextView
            else { return }
            updateSlashQuery(in: view)
        }

        func textDidBeginEditing(_ notification: Notification) {
            parent.callbacks.onFocus()
        }

        func textDidEndEditing(_ notification: Notification) {
            guard let view = notification.object as? BlockNSTextView, view.isSlashMenuOpen else { return }
            // Allow a popup button action to consume the query first.
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view, view.window?.firstResponder !== view else { return }
                self.dismissSlash(in: view)
            }
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            let url: URL?
            switch link {
            case let value as URL: url = value
            case let value as String: url = URL(string: value)
            default: url = nil
            }
            guard let url else { return false }
            NSWorkspace.shared.open(url)
            return true
        }

        /// Routes special keys to the outline before the text view sees them.
        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard let view = textView as? BlockNSTextView, let storage = view.textStorage else { return false }
            let selection = view.selectedRange()
            let content = NSAttributedString(attributedString: storage)

            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                if view.isSlashMenuOpen {
                    // The slash menu owns Return while it is showing.
                    view.slashMenuCommand?(.confirm)
                    return true
                }
                // Return replaces a selection before splitting, just as native
                // text editing does. Persist the deletion before outline logic.
                if selection.length > 0 {
                    view.insertText("", replacementRange: selection)
                }
                return parent.callbacks.onReturn(view.selectedRange().location, NSAttributedString(attributedString: storage))

            case #selector(NSResponder.insertLineBreak(_:)):
                // Shift-Return inserts a soft break inside the same block.
                view.insertText("\u{2028}", replacementRange: selection)
                return true

            case #selector(NSResponder.insertTab(_:)):
                if view.isSlashMenuOpen {
                    view.slashMenuCommand?(.next)
                    return true
                }
                return parent.callbacks.onTab(false, selection.location)

            case #selector(NSResponder.insertBacktab(_:)):
                if view.isSlashMenuOpen {
                    view.slashMenuCommand?(.previous)
                    return true
                }
                return parent.callbacks.onTab(true, selection.location)

            case #selector(NSResponder.deleteBackward(_:)):
                guard selection.location == 0, selection.length == 0 else { return false }
                return parent.callbacks.onBackspaceAtStart(content)

            case #selector(NSResponder.deleteForward(_:)):
                guard selection.location == storage.length, selection.length == 0 else { return false }
                return parent.callbacks.onDeleteAtEnd()

            case #selector(NSResponder.moveUp(_:)):
                if view.isSlashMenuOpen {
                    view.slashMenuCommand?(.previous)
                    return true
                }
                guard selection.length == 0, view.isOnFirstLine(selection.location) else { return false }
                return parent.callbacks.onArrowOut(.up, selection.location)

            case #selector(NSResponder.moveDown(_:)):
                if view.isSlashMenuOpen {
                    view.slashMenuCommand?(.next)
                    return true
                }
                guard selection.length == 0, view.isOnLastLine(selection.location) else { return false }
                return parent.callbacks.onArrowOut(.down, selection.location)

            case #selector(NSResponder.moveLeft(_:)):
                guard selection.location == 0, selection.length == 0 else { return false }
                return parent.callbacks.onArrowOut(.up, -1)

            case #selector(NSResponder.moveRight(_:)):
                guard selection.location == storage.length, selection.length == 0 else { return false }
                return parent.callbacks.onArrowOut(.down, 0)

            case #selector(NSResponder.cancelOperation(_:)):
                if view.isSlashMenuOpen {
                    dismissSlash(in: view)
                    return true
                }
                parent.callbacks.onEscape()
                return true

            default:
                return false
            }
        }

        /// Recomputes the `/` query from the text immediately before the caret.
        func suppressCurrentSlash(in view: BlockNSTextView) {
            dismissedSlashIndex = MarkdownInputRules.slashTriggerIndex(in: view.string as NSString, caret: view.selectedRange().location)
        }

        func dismissSlash(in view: BlockNSTextView) {
            suppressCurrentSlash(in: view)
            view.slashMenuCommand?(.dismiss)
        }

        func updateSlashQuery(in view: BlockNSTextView) {
            let selection = view.selectedRange()
            guard selection.length == 0, let storage = view.textStorage else {
                parent.callbacks.onSlashQuery(nil, NSRange(location: 0, length: 0), .zero, .zero)
                return
            }

            let text = storage.string as NSString
            let caret = min(selection.location, text.length)
            guard !view.hasMarkedText(), parent.kind != .code,
                  let slashIndex = MarkdownInputRules.slashTriggerIndex(in: text, caret: caret) else {
                dismissedSlashIndex = nil
                if view.isSlashMenuOpen {
                    parent.callbacks.onSlashQuery(nil, NSRange(location: 0, length: 0), .zero, .zero)
                }
                return
            }

            guard slashIndex != dismissedSlashIndex else { return }
            let range = NSRange(location: slashIndex, length: caret - slashIndex)
            let query = text.substring(with: NSRange(location: slashIndex + 1, length: caret - slashIndex - 1))
            let rect = view.caretRectLocal(at: caret)
            let viewport = view.editorViewport
            if view.window != nil, !viewport.intersects(rect) {
                if view.isSlashMenuOpen { dismissSlash(in: view) }
                return
            }
            parent.callbacks.onSlashQuery(query, range, rect, viewport)
        }
    }
}

// MARK: - The text view

/// Commands the outline's slash menu understands while it is on screen.
enum SlashMenuCommand {
    case next, previous, confirm, dismiss
}

/// `NSTextView` subclass that self-sizes, draws a placeholder, and exposes the
/// formatting actions the app's Format menu sends down the responder chain.
final class BlockNSTextView: NSTextView {
    weak var coordinator: BlockTextView.Coordinator?
    var blockKind: BlockKind = .paragraph
    var placeholderString: String = "" {
        didSet { if placeholderString != oldValue { needsDisplay = true } }
    }
    /// Set by the outline while the `/` menu is visible so key handling defers to it.
    var isSlashMenuOpen = false {
        didSet {
            if oldValue && !isSlashMenuOpen { coordinator?.suppressCurrentSlash(in: self) }
        }
    }
    var slashMenuCommand: ((SlashMenuCommand) -> Void)?

    private var cachedHeight: (width: CGFloat, height: CGFloat)?
    private var geometryUpdatePending = false

    /// The enclosing scroll viewport, expressed in text-view coordinates. It
    /// can extend beyond this row and is intersected across nested inspectors.
    var editorViewport: CGRect {
        guard let contentView = window?.contentView else { return bounds }
        var result = convert(contentView.bounds, from: contentView)
        var ancestor = superview
        while let view = ancestor {
            if view is NSClipView { result = result.intersection(convert(view.bounds, from: view)) }
            ancestor = view.superview
        }
        return result
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: nil)
        var ancestor = superview
        while let view = ancestor {
            if let clip = view as? NSClipView {
                clip.postsBoundsChangedNotifications = true
                NotificationCenter.default.addObserver(self, selector: #selector(viewportChanged), name: NSView.boundsDidChangeNotification, object: clip)
            }
            ancestor = view.superview
        }
        queueGeometryUpdate()
    }

    @objc private func viewportChanged(_ notification: Notification) { queueGeometryUpdate() }

    private func queueGeometryUpdate() {
        guard !geometryUpdatePending else { return }
        geometryUpdatePending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.geometryUpdatePending = false
            guard self.isSlashMenuOpen else { return }
            self.coordinator?.updateSlashQuery(in: self)
        }
    }


    // MARK: Sizing

    /// Laid-out height for a given width, used by `sizeThatFits`.
    func height(fittingWidth width: CGFloat) -> CGFloat {
        if let cachedHeight, abs(cachedHeight.width - width) < 0.5 {
            return cachedHeight.height
        }
        guard let container = textContainer, let layout = layoutManager else { return width > 0 ? 20 : 0 }

        container.containerSize = CGSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container)

        // Empty storage still needs one line's worth of height.
        let minimum = (font ?? NSFont.systemFont(ofSize: Theme.Editor.bodyPointSize)).boundingRectForFont.height
            * Theme.Editor.lineHeightMultiple
        let height = max(ceil(used.height), ceil(minimum))
        cachedHeight = (width, height)
        return height
    }

    override func invalidateIntrinsicContentSize() {
        cachedHeight = nil
        super.invalidateIntrinsicContentSize()
    }

    override func setFrameSize(_ newSize: NSSize) {
        if abs(newSize.width - frame.width) > 0.5 { cachedHeight = nil }
        super.setFrameSize(newSize)
        queueGeometryUpdate()
    }

    // MARK: Placeholder

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard (textStorage?.length ?? 0) == 0, !placeholderString.isEmpty else { return }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: Theme.Editor.nsFont(for: blockKind),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = Theme.Editor.lineHeightMultiple
        var merged = attributes
        merged[.paragraphStyle] = paragraph

        NSAttributedString(string: placeholderString, attributes: merged)
            .draw(in: NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height))
    }

    // MARK: Caret geometry

    /// Rect of the caret at `location`, in this view's own coordinates. The
    /// outline adds the row's origin to position the slash menu.
    func caretRectLocal(at location: Int) -> CGRect {
        guard let layout = layoutManager, let container = textContainer else { return .zero }
        layout.ensureLayout(for: container)
        let length = textStorage?.length ?? 0
        let offset = min(max(0, location), length)
        var rect: CGRect
        if offset == length, layout.extraLineFragmentTextContainer != nil {
            rect = layout.extraLineFragmentRect
            rect.size.width = 1
        } else if layout.numberOfGlyphs > 0 {
            let glyph = layout.glyphIndexForCharacter(at: min(offset, max(0, length - 1)))
            rect = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let point = layout.location(forGlyphAt: glyph)
            rect.origin.x += point.x
            if offset == length {
                rect.origin.x = layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).maxX
            }
            rect.size.width = 1
        } else {
            rect = CGRect(x: 0, y: 0, width: 1, height: Theme.Editor.nsFont(for: blockKind).boundingRectForFont.height)
        }
        rect.origin.x += textContainerOrigin.x
        rect.origin.y += textContainerOrigin.y
        return rect
    }

    func isOnFirstLine(_ location: Int) -> Bool {
        guard let layout = layoutManager, (textStorage?.length ?? 0) > 0 else { return true }
        var effective = NSRange()
        layout.lineFragmentRect(
            forGlyphAt: layout.glyphIndexForCharacter(at: min(location, (textStorage?.length ?? 1) - 1)),
            effectiveRange: &effective
        )
        if location == textStorage?.length, layout.extraLineFragmentTextContainer != nil { return false }
        return effective.location == 0
    }

    func isOnLastLine(_ location: Int) -> Bool {
        guard let layout = layoutManager, let storage = textStorage, storage.length > 0 else { return true }
        var effective = NSRange()
        layout.lineFragmentRect(
            forGlyphAt: layout.glyphIndexForCharacter(at: min(location, storage.length - 1)),
            effectiveRange: &effective
        )
        if layout.extraLineFragmentTextContainer != nil { return location == storage.length }
        return NSMaxRange(effective) >= layout.numberOfGlyphs
    }

    // MARK: Paste

    /// Splits a multi-line paste into blocks instead of one run of text.
    ///
    /// A pasted markdown list should become a list. Single-line pastes fall
    /// through to AppKit so ordinary paste — including styled text — is
    /// untouched.
    override func paste(_ sender: Any?) {
        let text = NSPasteboard.general.string(forType: .string)
        if let text, text.contains("\n"), coordinator?.parent.callbacks.onPasteMultiline(text) == true {
            return
        }
        super.paste(sender)
    }

    // MARK: Formatting actions

    /// ⌘B — sent from the Format menu via the responder chain.
    @objc func toggleBold(_ sender: Any?) {
        applyFormatting { storage, range in
            RichTextCodec.toggleTrait(.boldFontMask, in: storage, range: range, kind: self.blockKind)
        }
    }

    /// ⌘I
    @objc func toggleItalic(_ sender: Any?) {
        applyFormatting { storage, range in
            RichTextCodec.toggleTrait(.italicFontMask, in: storage, range: range, kind: self.blockKind)
        }
    }

    /// ⌘⇧X
    @objc func toggleStrikethrough(_ sender: Any?) {
        applyFormatting { storage, range in
            RichTextCodec.toggleStrikethrough(in: storage, range: range)
        }
    }

    /// ⌘E
    @objc func toggleInlineCode(_ sender: Any?) {
        applyFormatting { storage, range in
            RichTextCodec.toggleInlineCode(in: storage, range: range, kind: self.blockKind)
        }
    }

    /// ⌘L — asks for a URL, then links the selection.
    @objc func promptForLink(_ sender: Any?) {
        let range = selectedRange()
        guard range.length > 0, let storage = textStorage else { return }

        let existing = storage.attribute(.link, at: range.location, effectiveRange: nil)
        let currentURL = (existing as? URL)?.absoluteString ?? (existing as? String) ?? ""

        let alert = NSAlert()
        alert.messageText = "Add link"
        alert.informativeText = "Enter a URL for “\(storage.attributedSubstring(from: range).string)”."
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Cancel")
        if !currentURL.isEmpty { alert.addButton(withTitle: "Remove") }

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = currentURL.isEmpty ? "https://" : currentURL
        field.placeholderString = "https://example.com"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        let response = alert.runModal()
        guard response != .alertSecondButtonReturn else { return }

        if response == .alertThirdButtonReturn {
            applyFormatting { storage, range in
                RichTextCodec.setLink(nil, in: storage, range: range)
            }
            return
        }

        var text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text) else { return }

        applyFormatting { storage, range in
            RichTextCodec.setLink(url, in: storage, range: range)
        }
    }

    /// Mutates the selected range and pushes the result back to the model.
    private func applyFormatting(_ body: (NSMutableAttributedString, NSRange) -> Void) {
        guard let storage = textStorage else { return }
        let range = selectedRange()
        guard range.length > 0 else { return }

        let mutable = NSMutableAttributedString(attributedString: storage)
        body(mutable, range)

        storage.setAttributedString(mutable)
        setSelectedRange(range)
        if let coordinator {
            coordinator.signature = BlockTextView.ContentSignature(
                attributedText: storage, kind: blockKind, isCompleted: coordinator.parent.isCompleted
            )
            coordinator.parent.callbacks.onChange(NSAttributedString(attributedString: storage))
        }
        invalidateIntrinsicContentSize()
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(toggleBold(_:)),
             #selector(toggleItalic(_:)),
             #selector(toggleStrikethrough(_:)),
             #selector(toggleInlineCode(_:)),
             #selector(promptForLink(_:)):
            return selectedRange().length > 0
        default:
            return super.validateUserInterfaceItem(item)
        }
    }

    // MARK: Focus reporting

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { coordinator?.parent.callbacks.onFocus() }
        return result
    }
}
