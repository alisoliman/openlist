import AppKit

/// The sheet can temporarily displace a native field editor. Restore it only
/// when search was cancelled, and only if it still belongs to this window.
@MainActor
final class SearchReturnFocus {
    private weak var responder: NSResponder?
    private var range: NSRange?
    private var activation = 0

    func remember(in window: NSWindow?, activation: Int) {
        responder = window?.firstResponder
        range = (responder as? NSTextView)?.selectedRange()
        self.activation = activation
    }

    func restore(in window: NSWindow?, activation: Int) {
        defer { responder = nil; range = nil }
        guard self.activation == activation, let window, let view = responder as? NSView,
              view.window === window else { return }
        if window.makeFirstResponder(view), let text = view as? NSTextView, let range,
           NSMaxRange(range) <= (text.string as NSString).length {
            text.setSelectedRange(range)
        }
    }
}
