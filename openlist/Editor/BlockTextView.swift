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
    /// `range` covers the "/" and its query, so the outline removes exactly
    /// that span, and only while the line still holds it.
    var onSlashQuery: (_ query: String?, _ range: NSRange, _ viewport: CGRect) -> Void = { _, _, _ in }
    /// A block-kind change requested by a markdown prefix such as `## `.
    var onMarkdownPrefix: (BlockKind) -> Void = { _ in }
    /// A multi-line paste. Return `true` to keep the default insert from
    /// dumping the whole thing into this one block.
    var onPasteMultiline: (String) -> Bool = { _ in false }
    var onPasteFragment: () -> Bool = { false }
    /// Lines to paste as they are, as Paste and Match Style reads them from
    /// Openlist content. Return `true` to keep the default insert.
    var onPasteLines: ([MarkdownInputRules.ParsedLine]) -> Bool = { _ in false }
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
    /// Whether a completed line fades to the completed ink. A done task
    /// being written keeps its ink, as the design's input does.
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
    /// Whether the design's prefixes, typed or pasted at the start, turn the
    /// line into another kind. A presentation that draws only tasks keeps
    /// them as typed, so a line never turns into one it doesn't draw.
    var convertsPrefixes = true
    /// While the `/` menu is showing it takes over Return, ↑, ↓ and Escape.
    /// Tab still nests the line, as the design's does. Only a `/` that
    /// starts the block opens it.
    var isSlashMenuOpen: Bool = false
    /// The chosen accent (`NextAccent.editorColor`), drawn as the insertion
    /// point and as links. `nil` keeps AppKit's caret, with links in Next's
    /// default accent.
    var accentColor: NSColor? = nil
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

        context.coordinator.apply(attributedText, to: view, kind: kind, isCompleted: isCompleted,
                                  dimsStruck: dimsStruck, drawsStrike: drawsStrike)
        view.placeholderString = placeholder
        view.isSlashMenuOpen = isSlashMenuOpen
        view.slashMenuCommand = onSlashCommand
        applyAccent(to: view)
        return view
    }

    func updateNSView(_ view: BlockNSTextView, context: Context) {
        context.coordinator.parent = self
        view.placeholderString = placeholder
        view.isSlashMenuOpen = isSlashMenuOpen
        view.slashMenuCommand = onSlashCommand
        applyAccent(to: view)
        if view.textContainerInset.height != verticalInset {
            view.textContainerInset = NSSize(width: 0, height: verticalInset)
            view.invalidateIntrinsicContentSize()
        }

        context.coordinator.updateContent(of: view)
        context.coordinator.syncFocus(view: view, shouldFocus: isFocused, caret: pendingCaret, token: focusToken)
    }

    /// Draws the caret and links in the accent. NSTextView draws a link with
    /// `linkTextAttributes`, over the storage's ink. Each is set only when its
    /// colour changes, so an update doesn't disturb the caret or the IME.
    func applyAccent(to view: BlockNSTextView) {
        if let accentColor, view.insertionPointColor !== accentColor { view.insertionPointColor = accentColor }
        let link = accentColor ?? NXEditor.accentViolet
        guard view.linkTextAttributes?[.foregroundColor] as? NSColor !== link else { return }
        view.linkTextAttributes = [
            .foregroundColor: link,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand,
        ]
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: BlockNSTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 1 else { return nil }
        return CGSize(width: width, height: nsView.height(fittingWidth: width))
    }

    // MARK: - Coordinator

    /// What the text storage was last built from. `attributedText` is always
    /// the model's form, never a restyled presentation of it, so the model's
    /// echo of a local edit matches without a restyle.
    struct ContentSignature: Equatable {
        let attributedText: NSAttributedString
        let kind: BlockKind
        let isCompleted: Bool
        let dimsStruck: Bool
        let drawsStrike: Bool

        init(attributedText: NSAttributedString, kind: BlockKind, isCompleted: Bool,
             dimsStruck: Bool = true, drawsStrike: Bool = true) {
            self.attributedText = NSAttributedString(attributedString: attributedText)
            self.kind = kind
            self.isCompleted = isCompleted
            self.dimsStruck = isCompleted ? dimsStruck : true
            self.drawsStrike = isCompleted ? drawsStrike : true
        }

        /// Whether the storage shows a completed line other than as the model
        /// decodes it: unfaded, or with its strike drawn over it.
        var overridesCompletion: Bool { !dimsStruck || !drawsStrike }
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
                                           isCompleted: parent.isCompleted, dimsStruck: parent.dimsStruck,
                                           drawsStrike: parent.drawsStrike)
            if signature != current || consumeRestyleRequest() {
                apply(parent.attributedText, to: view, kind: parent.kind, isCompleted: parent.isCompleted,
                      dimsStruck: parent.dimsStruck, drawsStrike: parent.drawsStrike)
            }
        }

        /// Hands the text view's own edit to the model.
        func reportEdit(_ content: NSAttributedString) {
            isReportingEdit = true
            defer { isReportingEdit = false }
            parent.callbacks.onChange(content)
        }

        func apply(_ attributed: NSAttributedString, to view: BlockNSTextView, kind: BlockKind, isCompleted: Bool,
                   dimsStruck: Bool = true, drawsStrike: Bool = true) {
            isApplyingExternalChange = true
            defer { isApplyingExternalChange = false }

            let applied = ContentSignature(attributedText: attributed, kind: kind, isCompleted: isCompleted,
                                           dimsStruck: dimsStruck, drawsStrike: drawsStrike)
            let previousSelection = view.selectedRange()
            view.textStorage?.setAttributedString(applied.overridesCompletion
                ? RichTextCodec.restylingCompletion(of: attributed, kind: kind, struck: isCompleted,
                                                    dimsCompleted: applied.dimsStruck, strikes: applied.drawsStrike)
                : attributed)
            view.typingAttributes = RichTextCodec.baseAttributes(for: kind, isCompleted: isCompleted,
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
        /// an outside change. A restyled presentation is recorded in the
        /// model's form, which is what the echo will carry.
        func recordLocalEdit(_ storage: NSAttributedString, kind: BlockKind) {
            let current = ContentSignature(attributedText: storage, kind: kind, isCompleted: parent.isCompleted,
                                           dimsStruck: parent.dimsStruck, drawsStrike: parent.drawsStrike)
            guard current.overridesCompletion else {
                signature = current
                return
            }
            signature = ContentSignature(
                attributedText: RichTextCodec.restylingCompletion(of: storage, kind: kind, struck: parent.isCompleted),
                kind: kind, isCompleted: parent.isCompleted, dimsStruck: parent.dimsStruck, drawsStrike: parent.drawsStrike
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

            if parent.convertsPrefixes, !view.isPasting, let rule = MarkdownInputRules.matchBlockPrefix(
                in: storage,
                caret: view.selectedRange().location,
                wasInsertion: wasInsertion,
                kind: parent.kind
            ) {
                convert(by: rule, in: view, storage: storage)
                return
            }

            // Inline rules such as **bold** fire on the closing delimiter.
            if !view.isPasting, MarkdownInputRules.applyInlineRules(in: storage, view: view, kind: parent.kind) {
                view.invalidateIntrinsicContentSize()
            }

            recordLocalEdit(storage, kind: parent.kind)
            reportEdit(NSAttributedString(attributedString: storage))
            // As the design's change does, a line that starts with "/" brings
            // the card up, the one Escape put away too.
            updateSlashQuery(in: view, textChanged: true)
            view.invalidateIntrinsicContentSize()
        }

        /// A paste that went in at the start of the line and left it starting
        /// with one of the design's prefixes converts it, as typing it does.
        func convertPastedPrefix(in view: BlockNSTextView) {
            guard parent.convertsPrefixes, let storage = view.textStorage,
                  let rule = MarkdownInputRules.matchPastedPrefix(in: storage, kind: parent.kind) else { return }
            convert(by: rule, in: view, storage: storage)
        }

        /// Takes `rule`'s prefix off the line and turns it into its kind.
        private func convert(by rule: MarkdownInputRules.BlockPrefixMatch, in view: BlockNSTextView, storage: NSTextStorage) {
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
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            // Selection changes fire while `apply` is rewriting the storage;
            // reporting then would push SwiftUI state during a view update.
            guard !isApplyingExternalChange,
                  let view = notification.object as? BlockNSTextView
            else { return }
            updateSlashQuery(in: view)
            InlineFormatting.shared.update(view, focused: view.window?.firstResponder === view)
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

        func dismissSlash(in view: BlockNSTextView) {
            view.slashMenuCommand?(.dismiss)
        }

        /// The design's Turn into card is up while the line starts with "/",
        /// from the change that writes it there until Escape, a pick or the
        /// "/" going, and filters by everything after the "/", spaces and all,
        /// wherever the caret is. A change to the text reports the query; the
        /// caret or the page moving only follows a card that's up.
        func updateSlashQuery(in view: BlockNSTextView, textChanged: Bool = false) {
            guard textChanged || view.isSlashMenuOpen, let storage = view.textStorage else { return }
            let text = storage.string as NSString
            guard !view.hasMarkedText(), parent.kind != .code, text.hasPrefix("/") else {
                parent.callbacks.onSlashQuery(nil, NSRange(location: 0, length: 0), .zero)
                return
            }
            let rect = view.caretRectLocal(at: min(view.selectedRange().location, text.length))
            let viewport = view.editorViewport
            if view.window != nil, !viewport.intersects(rect) {
                if view.isSlashMenuOpen { dismissSlash(in: view) }
                return
            }
            parent.callbacks.onSlashQuery(text.substring(from: 1), NSRange(location: 0, length: text.length), viewport)
        }
    }
}

// MARK: - The text view

/// Whether the line being written has text selected, which Format ▸'s inline
/// styles act on. SwiftUI's menu items take their state only from `.disabled`,
/// never from AppKit's validation, so the line reports it here.
@Observable @MainActor
final class InlineFormatting {
    static let shared = InlineFormatting()
    private(set) var hasSelection = false
    /// The line that last had the keyboard.
    @ObservationIgnored private weak var line: NSTextView?

    /// `view`'s selection while it has the keyboard. Another line's report
    /// that it doesn't leaves the one that has it alone.
    func update(_ view: NSTextView, focused: Bool) {
        if focused { line = view } else if line == nil || line === view { line = nil } else { return }
        let selected = focused && view.selectedRange().length > 0
        if selected != hasSelection { hasSelection = selected }
    }
}

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
    var isSlashMenuOpen = false
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
                InlineFormatting.shared.update(self, focused: false)
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
    /// slash card stays up only while the caret is on the visible page.
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

    /// Pastes as the design's lines take it, one line each.
    ///
    /// With nothing selected, Openlist content goes in after the line, whole,
    /// and several lines of text become lines of their own, after this one
    /// or filling it while it's empty, as Openlist content's lines do under
    /// Paste and Match Style, however many there are. Over a selection,
    /// Openlist content goes in as the text of its lines, a space between
    /// them. Anything else is AppKit's paste, styled text included, read as
    /// `readSelection(from:type:)` reads it. A code line, one of the editor's
    /// own kinds, keeps the breaks and prefixes.
    private(set) var isPasting = false

    override func paste(_ sender: Any?) {
        paste(from: .general) { super.paste(sender) }
    }

    /// Paste and Match Style reads Openlist content as its lines of text.
    override func pasteAsPlainText(_ sender: Any?) {
        paste(from: .general, structured: false) { super.pasteAsPlainText(sender) }
    }

    /// Pastes what `pasteboard` holds, with `native` as AppKit's paste of it.
    func paste(from pasteboard: NSPasteboard, structured: Bool = true, native: () -> Void) {
        isPasting = true
        defer { isPasting = false }
        let fragment = NSPasteboard.PasteboardType("solimanali.openlist.document-fragment")
        if selectedRange().length == 0 {
            let callbacks = coordinator?.parent.callbacks
            let isContent = pasteboard.availableType(from: [fragment]) != nil
            if structured, isContent, callbacks?.onPasteFragment() == true { return }
            // Openlist content is lines even as one, so a copied task stays a
            // task. They're read from the content, not from its Markdown,
            // which is written for other apps: escaped, with a task's star,
            // labels and files as text. Content of only images has no lines
            // of text: its text goes in as other text does.
            if blockKind != .code, isContent, let data = pasteboard.data(forType: fragment),
               let content = try? DocumentFragment.decode(data) {
                let lines = MarkdownInputRules.pasteLines(of: content)
                if !lines.isEmpty, callbacks?.onPasteLines(lines) == true { return }
            }
            // One line with a break at its end is still one line.
            if blockKind != .code, let text = pasteboard.string(forType: .string),
               text.trimmingCharacters(in: .newlines).rangeOfCharacter(from: .newlines) != nil,
               callbacks?.onPasteMultiline(text) == true { return }
        } else if blockKind != .code, let data = pasteboard.data(forType: fragment),
                  let content = try? DocumentFragment.decode(data) {
            // Its Markdown would write list markers and indents into the line.
            insertText(Self.lineTexts(of: content), replacementRange: selectedRange())
            return
        }
        native()
    }

    /// The text of Openlist content's lines, in order, a space between them.
    static func lineTexts(of fragment: DocumentFragment) -> String {
        let byID = Dictionary(fragment.blocks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let children = Dictionary(grouping: fragment.blocks, by: \.parentID)
        var stack = Array(fragment.roots.reversed())
        var texts: [String] = []
        while let id = stack.popLast(), let block = byID[id] {
            texts += block.text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
            stack += (children[id] ?? []).reversed().map(\.id)
        }
        return texts.filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Set while a drop of text dragged within this line is read, which
    /// AppKit also takes out of its old place.
    private var isDroppingOwnText = false

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        isDroppingOwnText = (sender.draggingSource as AnyObject?) === self
        defer { isDroppingOwnText = false }
        return super.performDragOperation(sender)
    }

    /// Every paste and text drop into the line reads through here, so each
    /// line break it brings becomes a space, as the design's single-line
    /// inputs take a paste, and one at the start of the line that leaves it
    /// starting with one of the design's prefixes converts it, as the
    /// design's change does.
    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        let range = rangeForUserTextChange
        let length = textStorage?.length ?? 0
        let before = string
        guard super.readSelection(from: pboard, type: type) else { return false }
        guard blockKind != .code, range.location != NSNotFound, let storage = textStorage else { return true }
        let pasted = NSRange(location: range.location, length: range.length + storage.length - length)
        if pasted.length > 0, NSMaxRange(pasted) <= storage.length {
            let text = storage.attributedSubstring(from: pasted)
            let joined = Self.joiningLines(text)
            if joined.string != text.string, shouldChangeText(in: pasted, replacementString: joined.string) {
                storage.replaceCharacters(in: pasted, with: joined)
                didChangeText()
                setSelectedRange(NSRange(location: pasted.location + joined.length, length: 0))
            }
        }
        // A drop of a prefix alone may have converted as it was typed, leaving
        // the line as it was. Text dragged within the line stays as dropped,
        // so AppKit finds its old place where it left it.
        if range.location == 0, string != before, !isDroppingOwnText { coordinator?.convertPastedPrefix(in: self) }
        return true
    }

    /// `text` with each line break a space, "\r\n" as one, as a single-line
    /// input takes pasted lines. Its styling stays.
    static func joiningLines(_ text: NSAttributedString) -> NSAttributedString {
        let joined = NSMutableAttributedString(attributedString: text)
        let characters = joined.mutableString
        characters.replaceOccurrences(of: "\r\n", with: " ", options: .literal,
                                      range: NSRange(location: 0, length: characters.length))
        var found = characters.rangeOfCharacter(from: .newlines)
        while found.location != NSNotFound {
            characters.replaceCharacters(in: found, with: " ")
            let next = found.location + 1
            found = characters.rangeOfCharacter(from: .newlines, options: [],
                                                range: NSRange(location: next, length: characters.length - next))
        }
        return joined
    }

    // MARK: Formatting actions

    /// ⌘B — sent from the Format menu via the responder chain.
    @objc func toggleBold(_ sender: Any?) {
        guard !isUnderSheet else { return }
        applyFormatting { storage, range in
            RichTextCodec.toggleTrait(.boldFontMask, in: storage, range: range, kind: self.blockKind)
        }
    }

    /// ⌘I
    @objc func toggleItalic(_ sender: Any?) {
        guard !isUnderSheet else { return }
        applyFormatting { storage, range in
            RichTextCodec.toggleTrait(.italicFontMask, in: storage, range: range, kind: self.blockKind)
        }
    }

    /// ⌘⇧X
    @objc func toggleStrikethrough(_ sender: Any?) {
        guard !isUnderSheet else { return }
        applyFormatting { storage, range in
            RichTextCodec.toggleStrikethrough(in: storage, range: range)
        }
    }

    /// ⌘E
    @objc func toggleInlineCode(_ sender: Any?) {
        guard !isUnderSheet else { return }
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
        guard range.length > 0, !isUnderSheet, let storage = textStorage, let prompter = Self.linkPrompter else { return }

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
    /// names no scheme. `nil` for an empty entry, one that isn't a URL, or a
    /// web address with no host, as the sheet's "https://" alone is.
    static func linkURL(from entry: String) -> URL? {
        var text = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text) else { return nil }
        if ["http", "https"].contains(url.scheme?.lowercased()), url.host()?.isEmpty != false { return nil }
        return url
    }

    /// Whether a sheet is over this line's window, as Add Link…'s is. The
    /// Format menu sends its actions on to the window under a sheet whose
    /// field doesn't take them, and this line keeps its selection there, so
    /// the menu would format, or ask again, behind the sheet.
    private var isUnderSheet: Bool { window?.attachedSheet != nil }

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

    /// The Format styles in a writing line's right-click menu, which act on
    /// its selection: only while it has one, and not under a sheet. The menu
    /// bar's Format items take their state from `InlineFormatting` instead.
    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(toggleBold(_:)),
             #selector(toggleItalic(_:)),
             #selector(toggleStrikethrough(_:)),
             #selector(toggleInlineCode(_:)),
             #selector(promptForLink(_:)):
            return selectedRange().length > 0 && !isUnderSheet
        default:
            return super.validateUserInterfaceItem(item)
        }
    }

    // MARK: Clicks

    override func menu(for event: NSEvent) -> NSMenu? {
        if let menu = coordinator?.parent.callbacks.contextMenu?() { return menu }
        return super.menu(for: event).map(writingMenu)
    }

    /// The text's own menu, for a line being written, with the Format menu's
    /// styles after Paste in place of AppKit's Font and Layout Orientation
    /// menus, whose fonts, underline, colours and sizes the document doesn't
    /// keep. Look Up, Spelling and Grammar, Substitutions, Speech and the
    /// rest stay.
    func writingMenu(_ menu: NSMenu) -> NSMenu {
        let styling: Set<Selector> = [#selector(NSFontManager.orderFrontFontPanel(_:)),
                                      #selector(NSTextView.changeLayoutOrientation(_:))]
        func styles(_ item: NSMenuItem) -> Bool {
            item.action.map(styling.contains) == true || item.submenu?.items.contains(where: styles) == true
        }
        for item in menu.items.reversed() where styles(item) { menu.removeItem(item) }
        // Two separators the removal left side by side, or one at either end, go too.
        for (index, item) in menu.items.enumerated().reversed() where item.isSeparatorItem
            && (index == 0 || index == menu.items.count - 1 || menu.items[index + 1].isSeparatorItem) {
            menu.removeItem(at: index)
        }
        let formats: [(String, Selector, String, NSEvent.ModifierFlags)] = [
            ("Bold", #selector(toggleBold(_:)), "b", .command),
            ("Italic", #selector(toggleItalic(_:)), "i", .command),
            ("Strikethrough", #selector(toggleStrikethrough(_:)), "x", [.command, .shift]),
            ("Inline Code", #selector(toggleInlineCode(_:)), "e", .command),
            ("Add Link…", #selector(promptForLink(_:)), "l", .command),
        ]
        let editing: Set<Selector> = [#selector(NSText.cut(_:)), #selector(NSText.copy(_:)), #selector(NSText.paste(_:)),
                                      #selector(NSTextView.pasteAsPlainText(_:))]
        var index = (menu.items.lastIndex { $0.action.map(editing.contains) == true }).map { $0 + 1 } ?? 0
        if index > 0 {
            menu.insertItem(.separator(), at: index)
            index += 1
        }
        for (title, action, key, modifiers) in formats {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            item.target = self
            menu.insertItem(item, at: index)
            index += 1
        }
        if index < menu.items.count, !menu.items[index].isSeparatorItem { menu.insertItem(.separator(), at: index) }
        return menu
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
            InlineFormatting.shared.update(self, focused: true)
        }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result {
            isContinuousSpellCheckingEnabled = false
            InlineFormatting.shared.update(self, focused: false)
            // Turning checking off leaves the marks it drew; clear them too.
            if let storage = textStorage, storage.length > 0 {
                layoutManager?.removeTemporaryAttribute(.spellingState,
                                                        forCharacterRange: NSRange(location: 0, length: storage.length))
            }
        }
        return result
    }
}
