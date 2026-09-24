//
//  BlockTextView.swift
//  openlist
//

import AppKit
import SwiftUI

/// Which way an arrow key was heading when it ran off a block: ↑ off its
/// first visual line, or ↓ off its last.
enum EditorArrow {
    case up, down
}

/// Everything the outline needs to hear about from one block's text view.
///
/// Each closure returns `true` when the outline consumed the event, in which
/// case the text view suppresses its own default behaviour.
struct BlockEditorCallbacks {
    var onChange: (NSAttributedString) -> Void = { _ in }
    /// Return pressed, with the caret offset and the block's content.
    var onReturn: (Int, NSAttributedString) -> Bool = { _, _ in false }
    /// Tab (or Shift-Tab) pressed.
    var onTab: (_ isBacktab: Bool, _ caret: Int) -> Bool = { _, _ in false }
    /// Backspace with the caret at offset zero and nothing selected.
    var onBackspaceAtStart: (NSAttributedString) -> Bool = { _ in false }
    /// Arrow key that would leave this block.
    var onArrowOut: (_ direction: EditorArrow, _ caret: Int) -> Bool = { _, _ in false }
    var onFocus: () -> Void = {}
    /// The programmatic focus move `token` has been carried out: the text
    /// view holds the keyboard, with the caret where the move put it.
    var onFocusApplied: (_ token: Int) -> Void = { _ in }
    /// Escape pressed while the `/` menu is closed. The text view has already
    /// resigned first responder, so the next key reaches the window.
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
    var onPasteFragment: () -> Bool = { false }
    /// The text view gave up the keyboard. `undoTarget` is what its typing
    /// Undo is registered against, for an outline that folds that typing
    /// into one step of its own.
    var onEndEditing: (_ undoTarget: NSTextStorage) -> Void = { _ in }
    /// Shift-Return, with the `/` menu showing or not. Return `true` to claim
    /// it; otherwise it inserts a soft break in the same block.
    var onLineBreak: () -> Bool = { false }
    /// A click on the text while it isn't editing. Return `true` to claim
    /// it, so the text view neither takes the keyboard nor moves a caret.
    var onInactiveClick: (NSEvent) -> Bool = { _ in false }
    /// A double-click on the text, after the text view has selected a word.
    var onDoubleClick: () -> Void = {}
    /// The menu a right-click or Control-click on the text shows, in place
    /// of the text view's own, such as its row's menu while the line isn't
    /// being written. `nil`, or a `nil` menu, keeps the text menu.
    var contextMenu: (() -> NSMenu?)?
}

/// A single editable line of a document, backed by `NSTextView`.
///
/// SwiftUI's `TextEditor` cannot express the key handling an outliner needs —
/// Return that finishes a line and opens the next, Tab that nests it,
/// Backspace that steps it out or turns it into text — so each block hosts a
/// bare `NSTextView` and the outline arbitrates.
struct BlockTextView: NSViewRepresentable {
    @Environment(\.openURL) private var openURL
    let blockID: UUID
    let kind: BlockKind
    let isCompleted: Bool
    /// Draws the completion strike whatever `isCompleted` says, so a renderer
    /// can strike a task during its completion dwell, before the store marks
    /// it done. `nil` follows `isCompleted`.
    var struck: Bool? = nil
    /// The strike's colour while `struck` draws it, such as the accent while
    /// a task is closing. `nil` uses the editor's strike ink. Pass a stable
    /// instance: the colour is part of the content signature, so one made per
    /// render would restyle the text, and reset the caret, on every update.
    var strikeColor: NSColor? = nil
    /// Whether the strike also fades the text to the completed ink. A task
    /// struck during its completion dwell keeps its ink, as the design's does.
    var dimsStruck = true
    /// Whether the text itself is struck through. A renderer that draws the
    /// strike over the text, as the list document draws the design's across
    /// a task, passes `false`: struck text then only fades, as `dimsStruck` says.
    var drawsStrike = true
    /// Space above and below the text: the list document passes its kind's
    /// line-box inset, `NXEditor.lineBoxInset(for:)`.
    var verticalInset: CGFloat = 0
    let attributedText: NSAttributedString
    var placeholder: String = ""
    var isFocused: Bool
    /// Caret offset to apply on the next focus pass. `-1` means end of text.
    var pendingCaret: Int?
    /// Changes only when focus is moved programmatically, so ordinary typing
    /// never yanks the caret back.
    var focusToken: Int
    /// While the `/` menu is showing it takes over Return, ↑, ↓ and Escape.
    /// Tab still nests the line, as the design's does. Only a `/` that
    /// starts the block opens it.
    var isSlashMenuOpen: Bool = false
    /// The insertion point's colour. `nil` keeps AppKit's.
    var caretColor: NSColor? = nil
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
        view.textContainerInset = NSSize(width: 0, height: verticalInset)
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isAutomaticLinkDetectionEnabled = true
        // Spelling is checked only in the line being written (see
        // becomeFirstResponder), so a document at rest reads without squiggles.
        view.isContinuousSpellCheckingEnabled = false
        view.usesFindBar = false
        let linkAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NXEditor.link,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand,
        ]
        view.linkTextAttributes = linkAttributes

        context.coordinator.apply(attributedText, to: view, kind: kind, isCompleted: isCompleted,
                                  struck: struck, strikeColor: strikeColor, dimsStruck: dimsStruck,
                                  drawsStrike: drawsStrike)
        view.placeholderString = placeholder
        view.isSlashMenuOpen = isSlashMenuOpen
        view.slashMenuCommand = onSlashCommand
        if let caretColor { view.insertionPointColor = caretColor }
        return view
    }

    func updateNSView(_ view: BlockNSTextView, context: Context) {
        context.coordinator.parent = self
        view.placeholderString = placeholder
        view.isSlashMenuOpen = isSlashMenuOpen
        view.slashMenuCommand = onSlashCommand
        if let caretColor, view.insertionPointColor !== caretColor { view.insertionPointColor = caretColor }
        if view.textContainerInset.height != verticalInset {
            view.textContainerInset = NSSize(width: 0, height: verticalInset)
            view.invalidateIntrinsicContentSize()
        }

        context.coordinator.updateContent(of: view)
        context.coordinator.syncFocus(view: view, shouldFocus: isFocused, caret: pendingCaret, token: focusToken)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: BlockNSTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 1 else { return nil }
        return CGSize(width: width, height: nsView.height(fittingWidth: width))
    }

    // MARK: - Coordinator

    /// What the text storage was last built from. `attributedText` is always
    /// the model's form, never a struck-through presentation of it, so the
    /// model's echo of a local edit matches without a restyle.
    struct ContentSignature: Equatable {
        let attributedText: NSAttributedString
        let kind: BlockKind
        let isCompleted: Bool
        let struck: Bool
        let strikeColor: NSColor?
        let dimsStruck: Bool
        let drawsStrike: Bool

        init(attributedText: NSAttributedString, kind: BlockKind, isCompleted: Bool,
             struck: Bool? = nil, strikeColor: NSColor? = nil, dimsStruck: Bool = true, drawsStrike: Bool = true) {
            self.attributedText = NSAttributedString(attributedString: attributedText)
            self.kind = kind
            self.isCompleted = isCompleted
            self.struck = struck ?? isCompleted
            self.strikeColor = self.struck && drawsStrike ? strikeColor : nil
            self.dimsStruck = self.struck ? dimsStruck : true
            self.drawsStrike = self.struck ? drawsStrike : true
        }

        /// Whether the storage shows a strike state other than the model's.
        var overridesCompletion: Bool { struck != isCompleted || strikeColor != nil || !dimsStruck || !drawsStrike }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: BlockTextView
        var signature: ContentSignature?
        /// Guards against re-entrant model writes while we restyle the storage.
        private var isApplyingExternalChange = false
        /// Set while the text view hands its own edit to the model.
        private var isReportingEdit = false
        private var lastFocusToken: Int?
        /// The focus move this view has yet to carry out, and its caret.
        private var pendingFocus: (token: Int, caret: Int?)?
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

        /// Brings the storage up to what `parent` shows, unless it has it.
        ///
        /// Not while the text view hands its own edit to the model: SwiftUI
        /// can redraw the line from inside that write, before the model holds
        /// the edit, and the line it hands over would take the keystroke back
        /// and move the caret. Nothing but the text changes in the middle of
        /// a keystroke, and the text view has that already.
        func updateContent(of view: BlockNSTextView) {
            guard !isReportingEdit else { return }
            // Only touch the storage when something actually changed underneath
            // us, otherwise every keystroke would reset the caret.
            let current = ContentSignature(attributedText: parent.attributedText, kind: parent.kind,
                                           isCompleted: parent.isCompleted, struck: parent.struck,
                                           strikeColor: parent.strikeColor, dimsStruck: parent.dimsStruck,
                                           drawsStrike: parent.drawsStrike)
            if signature != current || consumeRestyleRequest() {
                apply(parent.attributedText, to: view, kind: parent.kind, isCompleted: parent.isCompleted,
                      struck: parent.struck, strikeColor: parent.strikeColor, dimsStruck: parent.dimsStruck,
                      drawsStrike: parent.drawsStrike)
            }
        }

        /// Hands the text view's own edit to the model.
        func reportEdit(_ content: NSAttributedString) {
            isReportingEdit = true
            defer { isReportingEdit = false }
            parent.callbacks.onChange(content)
        }

        func apply(_ attributed: NSAttributedString, to view: BlockNSTextView, kind: BlockKind, isCompleted: Bool,
                   struck: Bool? = nil, strikeColor: NSColor? = nil, dimsStruck: Bool = true, drawsStrike: Bool = true) {
            isApplyingExternalChange = true
            defer { isApplyingExternalChange = false }

            let applied = ContentSignature(attributedText: attributed, kind: kind, isCompleted: isCompleted,
                                           struck: struck, strikeColor: strikeColor, dimsStruck: dimsStruck,
                                           drawsStrike: drawsStrike)
            let previousSelection = view.selectedRange()
            view.textStorage?.setAttributedString(applied.overridesCompletion
                ? RichTextCodec.restylingCompletion(of: attributed, kind: kind, struck: applied.struck,
                                                    strikeColor: applied.strikeColor, dimsCompleted: applied.dimsStruck,
                                                    strikes: applied.drawsStrike)
                : attributed)
            view.typingAttributes = RichTextCodec.baseAttributes(for: kind, isCompleted: applied.struck,
                                                                 strikeColor: applied.strikeColor,
                                                                 dimsCompleted: applied.dimsStruck,
                                                                 strikes: applied.drawsStrike)
            view.blockKind = kind

            let length = view.textStorage?.length ?? 0
            let restored = NSRange(
                location: min(previousSelection.location, length),
                length: min(previousSelection.length, max(0, length - min(previousSelection.location, length)))
            )
            view.setSelectedRange(restored)
            view.invalidateIntrinsicContentSize()
            view.needsDisplay = true

            signature = applied
            previousLength = attributed.length
        }

        /// Records a local edit, so the model's echo of it is not mistaken for
        /// an outside change. A struck presentation is recorded in the model's
        /// form, which is what the echo will carry.
        func recordLocalEdit(_ storage: NSAttributedString, kind: BlockKind) {
            let current = ContentSignature(attributedText: storage, kind: kind, isCompleted: parent.isCompleted,
                                           struck: parent.struck, strikeColor: parent.strikeColor,
                                           dimsStruck: parent.dimsStruck, drawsStrike: parent.drawsStrike)
            guard current.overridesCompletion else {
                signature = current
                return
            }
            signature = ContentSignature(
                attributedText: RichTextCodec.restylingCompletion(of: storage, kind: kind, struck: parent.isCompleted),
                kind: kind, isCompleted: parent.isCompleted, struck: parent.struck, strikeColor: parent.strikeColor,
                dimsStruck: parent.dimsStruck, drawsStrike: parent.drawsStrike
            )
        }

        /// Applies a *programmatic* focus move.
        ///
        /// Keyed on `token` rather than the boolean, because while a block is
        /// focused SwiftUI re-runs `updateNSView` on every keystroke and a
        /// naive check would drag the caret back to `pendingCaret` each time.
        /// Once the move is carried out, `onFocusApplied` hears its token.
        func syncFocus(view: BlockNSTextView, shouldFocus: Bool, caret: Int?, token: Int) {
            guard token != lastFocusToken else { return }
            lastFocusToken = token
            pendingFocus = shouldFocus ? (token, caret) : nil
            guard shouldFocus else { return }

            // Defer: during a SwiftUI update pass the view may not be in a
            // window yet, and makeFirstResponder would fail silently.
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view else { return }
                self.carryOutFocus(in: view)
            }
        }

        /// Carries out the focus move `syncFocus` left pending, once the view
        /// is in a window. A line SwiftUI puts in its window only after the
        /// update that sent it the caret takes the caret then.
        func carryOutFocus(in view: BlockNSTextView) {
            guard let pending = pendingFocus, pending.token == lastFocusToken, parent.isFocused,
                  let window = view.window else { return }
            pendingFocus = nil
            if window.firstResponder !== view {
                window.makeFirstResponder(view)
            }
            if let caret = pending.caret {
                let length = view.textStorage?.length ?? 0
                let clamped = caret < 0 ? length : min(caret, length)
                view.setSelectedRange(NSRange(location: clamped, length: 0))
                view.scrollRangeToVisible(NSRange(location: clamped, length: 0))
            }
            parent.callbacks.onFocusApplied(pending.token)
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

            if !view.isPasting, let rule = MarkdownInputRules.matchBlockPrefix(
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
                reportEdit(NSAttributedString(attributedString: storage))
                recordLocalEdit(storage, kind: parent.kind)
                // The kind is about to change out from under us, and the new
                // fonts have to be applied even though the text did not move.
                needsRestyle = true
                parent.callbacks.onMarkdownPrefix(rule.kind)
                return
            }

            // Inline rules such as **bold** fire on the closing delimiter.
            if !view.isPasting, MarkdownInputRules.applyInlineRules(in: storage, view: view, kind: parent.kind) {
                view.invalidateIntrinsicContentSize()
            }

            recordLocalEdit(storage, kind: parent.kind)
            reportEdit(NSAttributedString(attributedString: storage))
            // As the design's next change does, typing in a line that still
            // starts with "/" brings back the card Escape put away.
            dismissedSlashIndex = nil
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
            guard let view = notification.object as? BlockNSTextView else { return }
            if let storage = view.textStorage { parent.callbacks.onEndEditing(storage) }
            guard view.isSlashMenuOpen else { return }
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
            parent.openURL(url)
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
                // Return finishes the whole line, so a selection stays as it is.
                return parent.callbacks.onReturn(selection.location, content)

            case #selector(NSResponder.insertLineBreak(_:)):
                if parent.callbacks.onLineBreak() { return true }
                // Shift-Return inserts a soft break inside the same block.
                view.insertText("\u{2028}", replacementRange: selection)
                return true

            // Tab and ⇧Tab nest and lift the line with the `/` menu showing
            // too, as the design's do, and leave it up.
            case #selector(NSResponder.insertTab(_:)):
                return parent.callbacks.onTab(false, selection.location)

            case #selector(NSResponder.insertBacktab(_:)):
                return parent.callbacks.onTab(true, selection.location)

            case #selector(NSResponder.deleteBackward(_:)):
                guard selection.location == 0, selection.length == 0 else { return false }
                return parent.callbacks.onBackspaceAtStart(content)

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

            case #selector(NSResponder.cancelOperation(_:)):
                if view.isSlashMenuOpen {
                    dismissSlash(in: view)
                    return true
                }
                // Leave editing as well, otherwise the text view keeps the
                // keyboard and the next single-key shortcut types into the row.
                // Resign first so the outline, and its host, see the window
                // holding the keyboard and can move it on.
                if view.window?.firstResponder === view {
                    view.window?.makeFirstResponder(nil)
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
                  let slashIndex = MarkdownInputRules.slashTriggerIndex(in: text, caret: caret),
                  slashIndex == 0 else {
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

/// What Format ▸ Add Link… (⌘L) asks about: the selected text, the link it
/// has (empty for none), and where the answer goes. Cancel sends none.
struct LinkPrompt: Identifiable {
    enum Answer {
        /// The URL as typed; ``BlockNSTextView/linkURL(from:)`` reads it.
        case apply(String)
        case remove
    }

    let id = UUID()
    let text: String
    let currentURL: String
    let answer: (Answer) -> Void
}

/// `NSTextView` subclass that self-sizes, draws a placeholder, and exposes the
/// formatting actions the app's Format menu sends down the responder chain.
final class BlockNSTextView: NSTextView {
    weak var coordinator: BlockTextView.Coordinator?
    var blockKind: BlockKind = .paragraph
    var placeholderString: String = "" {
        didSet {
            guard placeholderString != oldValue else { return }
            needsDisplay = true
            // Drawn by hand, so VoiceOver hears of it here.
            setAccessibilityPlaceholderValue(placeholderString.isEmpty ? nil : placeholderString)
        }
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

    /// A line taken away while it holds the keyboard, folded away or settled,
    /// loses it without a word from AppKit, so once the update that took it
    /// is over, and it hasn't come back, the outline hears the line was left.
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil, let window, window.firstResponder === self {
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, self.window == nil, let storage = self.textStorage else { return }
                if window?.firstResponder === self { window?.makeFirstResponder(nil) }
                self.coordinator?.parent.callbacks.onEndEditing(storage)
            }
        }
        super.viewWillMove(toWindow: newWindow)
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
        // Sent the caret before it was in a window, the line takes it once
        // the update that put it here is over.
        if window != nil {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.coordinator?.carryOutFocus(in: self)
            }
        }
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

        // Size from the same TextKit metrics that place the glyphs. The font's
        // bounding box includes unrelated glyph extents and is not a line box.
        let minimum = layout.defaultLineHeight(for: NXEditor.nsFont(for: blockKind))
        let textHeight = max(used.maxY, layout.extraLineFragmentRect.maxY, minimum)
        let height = ceil(textHeight) + textContainerInset.height * 2
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

        var merged = RichTextCodec.baseAttributes(for: blockKind)
        merged[.foregroundColor] = NXEditor.placeholderInk

        NSAttributedString(string: placeholderString, attributes: merged)
            .draw(in: NSRect(origin: textContainerOrigin, size: NSSize(
                width: bounds.width, height: bounds.height - textContainerInset.height * 2
            )))
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
            rect = CGRect(x: 0, y: 0, width: 1, height: NXEditor.nsFont(for: blockKind).boundingRectForFont.height)
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
    private(set) var isPasting = false

    override func paste(_ sender: Any?) {
        isPasting = true
        defer { isPasting = false }
        if selectedRange().length > 0 {
            super.paste(sender)
            return
        }
        let hasFragment = NSPasteboard.general.availableType(from: [.init("solimanali.openlist.document-fragment")]) != nil
        if hasFragment {
            // Existing text selections and inline insertions remain native.
            // Only an empty document row opts ordinary Paste into structure.
            if string.isEmpty, selectedRange().length == 0,
               coordinator?.parent.callbacks.onPasteFragment() == true { return }
            super.paste(sender)
            return
        }
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

    /// Asks ⌘L's question, in the window's Next link sheet; the app sets it.
    /// With none, as in the headless checks, ⌘L asks nothing.
    static var linkPrompter: ((LinkPrompt) -> Void)?

    /// ⌘L — asks for a URL, then links the selection.
    @objc func promptForLink(_ sender: Any?) {
        let range = selectedRange()
        guard range.length > 0, let storage = textStorage, let prompter = Self.linkPrompter else { return }

        let existing = storage.attribute(.link, at: range.location, effectiveRange: nil)
        let currentURL = (existing as? URL)?.absoluteString ?? (existing as? String) ?? ""
        let text = storage.attributedSubstring(from: range).string
        prompter(LinkPrompt(text: text, currentURL: currentURL) { [weak self] answer in
            self?.applyLink(answer, to: range, text: text)
        })
    }

    /// The sheet's answer, for the text it asked about. The sheet doesn't stop
    /// the app as the old modal alert did, so a line that changed meanwhile,
    /// by sync or an agent, keeps its text as it now is.
    private func applyLink(_ answer: LinkPrompt.Answer, to range: NSRange, text: String) {
        guard let storage = textStorage, NSMaxRange(range) <= storage.length,
              storage.attributedSubstring(from: range).string == text else { return }
        let url: URL?
        switch answer {
        case .remove: url = nil
        case let .apply(entry):
            guard let typed = Self.linkURL(from: entry) else { return }
            url = typed
        }
        setSelectedRange(range)
        applyFormatting { storage, range in
            RichTextCodec.setLink(url, in: storage, range: range)
        }
    }

    /// The URL typed for a link, trimmed, with `https://` in front when it
    /// names no scheme. `nil` for an empty entry or one that isn't a URL.
    static func linkURL(from entry: String) -> URL? {
        var text = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        return URL(string: text)
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
            coordinator.recordLocalEdit(storage, kind: blockKind)
            coordinator.reportEdit(NSAttributedString(attributedString: storage))
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

    // MARK: Clicks

    override func menu(for event: NSEvent) -> NSMenu? {
        coordinator?.parent.callbacks.contextMenu?() ?? super.menu(for: event)
    }

    override func mouseDown(with event: NSEvent) {
        if window?.firstResponder !== self, coordinator?.parent.callbacks.onInactiveClick(event) == true { return }
        super.mouseDown(with: event)
        // AppKit's own tracking has run to the mouse-up by now, so the word
        // is selected before the outline hears about the double-click.
        if event.clickCount == 2 { coordinator?.parent.callbacks.onDoubleClick() }
    }

    // MARK: Accessibility

    /// A heading line is a text area VoiceOver announces as a heading.
    override func accessibilityRoleDescription() -> String? {
        switch blockKind {
        case .heading1: "heading level 1"
        case .heading2: "heading level 2"
        case .heading3: "heading level 3"
        default: super.accessibilityRoleDescription()
        }
    }

    // MARK: Focus reporting

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            isContinuousSpellCheckingEnabled = true
            coordinator?.parent.callbacks.onFocus()
        }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result {
            isContinuousSpellCheckingEnabled = false
            // Turning checking off leaves the marks it drew; clear them too.
            if let storage = textStorage, storage.length > 0 {
                layoutManager?.removeTemporaryAttribute(.spellingState,
                                                        forCharacterRange: NSRange(location: 0, length: storage.length))
            }
        }
        return result
    }
}
