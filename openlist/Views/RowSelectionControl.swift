import AppKit
import SwiftUI

struct RowSelectionControl: NSViewRepresentable {
    let title: String
    let isSelected: Bool
    let isSelectionFocus: Bool
    let requestsKeyboardFocus: Bool
    let defersPlainClick: Bool
    let onSelect: (BlockSelection.Gesture) -> Void
    let onStep: (Int, Bool) -> Void
    let onClear: () -> Void
    let onFocusRequestHandled: () -> Void
    let onDrag: () -> String
    let onDragEnd: () -> Void

    func makeNSView(context: Context) -> RowSelectionNSControl { RowSelectionNSControl() }

    func updateNSView(_ view: RowSelectionNSControl, context: Context) {
        view.configuration = self
        view.toolTip = "Select \(title). Command-click toggles; Shift-click selects a range. Use arrows or Shift-arrows here. Drag to move selected rows."
        view.setAccessibilityLabel("Select \(title)")
        view.setAccessibilityValue(isSelected ? "Selected" : "Not selected")
        view.setAccessibilityHelp(view.toolTip)
        view.needsDisplay = true
        if requestsKeyboardFocus { view.followSelectionFocus() }
    }
}

final class RowSelectionNSControl: NSControl, NSDraggingSource {
    var configuration: RowSelectionControl?
    private var handlingMouse = false
    private var pendingClick = false
    private var didDrag = false
    private var mouseDownPoint: NSPoint?

    /// Transfer focus after an arrow move without creating a fresh anchor.
    /// Deferring also allows ScrollViewReader to realize an offscreen row.
    func followSelectionFocus() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let configuration = self.configuration, configuration.requestsKeyboardFocus,
                  let window = self.window, window.isKeyWindow else { return }
            // Lazy scrolling may have removed the previous gutter and handed
            // focus back to the window. An explicit arrow request can reclaim
            // it, while a text field the user clicked remains untouched.
            guard window.firstResponder is RowSelectionNSControl
                    || window.firstResponder is NSWindow || window.firstResponder == nil else { return }
            self.handlingMouse = true
            window.makeFirstResponder(self)
            self.handlingMouse = false
            self.scrollToVisible(self.bounds)
            configuration.onFocusRequestHandled()
        }
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }

    override func accessibilityPerformPress() -> Bool {
        configuration?.onSelect(.toggle)
        return true
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted && !handlingMouse { configuration?.onSelect(.replace) }
        needsDisplay = true
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return super.resignFirstResponder()
    }

    override func mouseDown(with event: NSEvent) {
        handlingMouse = true
        window?.makeFirstResponder(self)
        handlingMouse = false
        didDrag = false
        mouseDownPoint = event.locationInWindow
        let command = event.modifierFlags.contains(.command)
        let shift = event.modifierFlags.contains(.shift)
        pendingClick = !command && !shift && configuration?.defersPlainClick == true
        if !pendingClick {
            configuration?.onSelect(shift ? (command ? .addingRange : .range) : (command ? .toggle : .replace))
        }
    }

    override func mouseUp(with event: NSEvent) {
        if pendingClick && !didDrag { configuration?.onSelect(.replace) }
        pendingClick = false
        mouseDownPoint = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didDrag, let start = mouseDownPoint,
              hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) > 4,
              let configuration else { return }
        didDrag = true
        pendingClick = false
        // A private type keeps an editable NSTextView from mistaking a row
        // move for literal text. Plain-text legacy drops remain readable.
        let payload = NSPasteboardItem()
        payload.setString(configuration.onDrag(), forType: NSPasteboard.PasteboardType(DragPayload.blockTypeIdentifier))
        let item = NSDraggingItem(pasteboardWriter: payload)
        let image = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "Selected rows") ?? NSImage()
        item.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        configuration?.onDragEnd()
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.isDisjoint(with: [.command, .option, .control]) else { super.keyDown(with: event); return }
        switch event.keyCode {
        case 126, 125:
            configuration?.onStep(event.keyCode == 126 ? -1 : 1, flags.contains(.shift))
        case 49:
            configuration?.onSelect(.toggle)
        case 53:
            configuration?.onClear()
            window?.makeFirstResponder(nil)
        case 51, 117:
            // Bulk deletion has a separate confirmation/recovery contract.
            NSSound.beep()
        default:
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let configuration else { return }
        let rect = NSRect(x: (bounds.width - 12) / 2, y: (bounds.height - 12) / 2, width: 12, height: 12)
        let shape = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
        if configuration.isSelected {
            NSColor.controlAccentColor.setFill()
            shape.fill()
            let check = NSBezierPath()
            check.move(to: NSPoint(x: rect.minX + 3, y: rect.midY))
            check.line(to: NSPoint(x: rect.midX - 1, y: rect.minY + 3))
            check.line(to: NSPoint(x: rect.maxX - 2, y: rect.maxY - 3))
            check.lineWidth = 1.5
            NSColor.white.setStroke()
            check.stroke()
        } else {
            NSColor.tertiaryLabelColor.setStroke()
            shape.lineWidth = 1
            shape.stroke()
        }
        if configuration.isSelectionFocus {
            let ring = NSBezierPath(roundedRect: rect.insetBy(dx: -3, dy: -3), xRadius: 5, yRadius: 5)
            NSColor.keyboardFocusIndicatorColor.setStroke()
            ring.lineWidth = 2
            ring.stroke()
        }
    }
}
