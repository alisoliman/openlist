import AppKit
import SwiftUI

/// Owns this editor's real AppKit selection, including a selected substring.
/// No SwiftUI field editor participates in the destination focus round-trip.
@MainActor
final class CaptureTitleFocus {
    weak var view: CaptureTitleNSTextView?
    private var retainedRange = NSRange(location: 0, length: 0)
    private var needsInitialFocus = true

    func reset(insertionPoint: Int) {
        retainedRange = NSRange(location: insertionPoint, length: 0)
        needsInitialFocus = true
    }

    func preserveSelection() {
        if let view { retainedRange = view.selectedRange() }
    }

    func restoreSelection() {
        guard let view, let window = view.window else { return }
        window.makeFirstResponder(view)
        applySelection(to: view)
    }

    func attach(_ view: CaptureTitleNSTextView) {
        self.view = view
        guard needsInitialFocus, view.window != nil else { return }
        needsInitialFocus = false
        restoreSelection()
    }

    func applySelection(to view: NSTextView) {
        let length = (view.string as NSString).length
        let location = min(retainedRange.location, length)
        let count = min(retainedRange.length, length - location)
        view.setSelectedRange(NSRange(location: location, length: count))
        view.scrollRangeToVisible(view.selectedRange())
    }
}

/// Native multiline input keeps typing undo and a stable selectedRange when a
/// popover returns first responder. Return submits; Shift-Return adds a line.
struct CaptureTitleField: NSViewRepresentable {
    @Binding var text: String
    let focus: CaptureTitleFocus
    let onSubmit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 512, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        let editor = CaptureTitleNSTextView(frame: NSRect(x: 0, y: 0, width: 512, height: 26), textContainer: container)
        editor.font = NSFont.preferredFont(forTextStyle: .title2)
        editor.textColor = .labelColor
        editor.insertionPointColor = .labelColor
        editor.isRichText = false
        editor.isEditable = true
        editor.isSelectable = true
        editor.allowsUndo = true
        editor.drawsBackground = false
        editor.textContainerInset = .zero
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.minSize = NSSize(width: 0, height: 26)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.string = text
        editor.captureFocus = focus
        editor.submit = onSubmit
        editor.cancel = onCancel
        editor.delegate = context.coordinator
        editor.setAccessibilityIdentifier("capture.title")
        editor.setAccessibilityLabel("What needs doing?")

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = editor
        focus.view = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? CaptureTitleNSTextView else { return }
        editor.submit = onSubmit
        editor.cancel = onCancel
        if editor.string != text {
            editor.string = text
            editor.undoManager?.removeAllActions()
        }
        editor.needsDisplay = true
        focus.attach(editor)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0,
              let editor = nsView.documentView as? NSTextView,
              let container = editor.textContainer, let layout = editor.layoutManager else { return nil }
        container.size = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let lineHeight = layout.defaultLineHeight(for: editor.font ?? .systemFont(ofSize: 17))
        let contentHeight = max(layout.usedRect(for: container).maxY, layout.extraLineFragmentRect.maxY)
        return CGSize(width: width, height: min(lineHeight * 4, max(lineHeight, ceil(contentHeight))))
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CaptureTitleField
        init(_ parent: CaptureTitleField) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
        }
    }
}

final class CaptureTitleNSTextView: NSTextView {
    weak var captureFocus: CaptureTitleFocus?
    var submit: (() -> Void)?
    var cancel: (() -> Void)?
    private let captureUndoManager = UndoManager()
    override var undoManager: UndoManager? { captureUndoManager }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // One bounded handoff after the hosting view enters its window.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            captureFocus?.attach(self)
        }
    }

    override func resignFirstResponder() -> Bool {
        captureFocus?.preserveSelection()
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        if !hasMarkedText() {
            switch event.keyCode {
            case 36, 76:
                if !event.modifierFlags.contains(.shift) { submit?(); return }
            case 53:
                cancel?()
                return
            case 48:
                if event.modifierFlags.contains(.shift) { window?.selectPreviousKeyView(self) }
                else { window?.selectNextKeyView(self) }
                return
            default: break
            }
        }
        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty else { return }
        ("What needs doing?" as NSString).draw(at: .zero, withAttributes: [
            .font: font ?? NSFont.preferredFont(forTextStyle: .title2),
            .foregroundColor: NSColor.placeholderTextColor,
        ])
    }
}
