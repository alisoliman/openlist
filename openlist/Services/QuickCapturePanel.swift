//
//  QuickCapturePanel.swift
//  openlist
//

import AppKit
import SwiftData
import SwiftUI

/// Quick Add: the design's capture card floating over whatever app is in
/// front, from ⇧⌥Space, the menu bar or File ▸ Quick Add.
///
/// A non-activating panel takes typing without making Openlist the active
/// app, so the main window stays where it is and focus goes back to the app
/// you were in once the panel closes: on Escape, once Return adds the task,
/// or when you click or switch away.
@MainActor
final class QuickCapturePanel: NSObject, NSWindowDelegate {
    static let shared = QuickCapturePanel()

    private var env: AppEnvironment?
    private var container: ModelContainer?
    private var panel: CapturePanel?
    /// Where the panel's top-left corner sits, kept as the card grows and shrinks.
    private var topLeft: NSPoint?

    /// Hands the panel the library once it has opened at launch.
    func install(env: AppEnvironment, container: ModelContainer) {
        self.env = env
        self.container = container
    }

    /// Opens a fresh card filed into `listID`, or Inbox, and due today when
    /// `forToday`, or when new tasks go to Today. An open card is focused as it is.
    func show(listID: UUID? = nil, forToday: Bool? = nil) {
        guard let env, let container else { return }
        let panel = panel ?? makePanel()
        self.panel = panel
        guard !panel.isVisible else {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        let draft = QuickCaptureDraft(store: env.store, settings: env.settings, listID: listID, forToday: forToday)
        // Motion is the card's own, from the Next style, which follows Reduce Motion.
        let host = NSHostingView(rootView: QuickAddWindowView(draft: draft, close: { [weak self] in self?.close() })
            .environment(env)
            .modelContainer(container)
            .environment(\.calendar, env.settings.calendar))
        // The panel takes the card's size, and follows it as chips wrap or a notice shows.
        host.sizingOptions = .standardBounds
        panel.contentView = host
        panel.appearance = env.settings.appearance.colorScheme.flatMap { NSAppearance(named: $0 == .dark ? .darkAqua : .aqua) }
        panel.setContentSize(host.fittingSize)
        place(panel)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        guard let panel, panel.isVisible else { return }
        topLeft = nil
        panel.orderOut(nil)
        // The next Quick Add starts from a new card. The old one goes once the
        // key press or click that closed it has finished with it.
        DispatchQueue.main.async { [weak panel] in
            guard let panel, !panel.isVisible else { return }
            panel.contentView = NSView()
        }
    }

    /// Centred on the screen with the pointer, a fifth of the way down, as
    /// Spotlight sits.
    private func place(_ panel: NSPanel) {
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) }) ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let point = NSPoint(x: (visible.midX - panel.frame.width / 2).rounded(), y: (visible.maxY - visible.height * 0.18).rounded())
        topLeft = point
        panel.setFrameTopLeftPoint(point)
    }

    private func makePanel() -> CapturePanel {
        let panel = CapturePanel(contentRect: NSRect(x: 0, y: 0, width: 712, height: 240),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.title = "Quick Add"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The card draws the design's shadow inside the panel's margin.
        panel.hasShadow = false
        panel.delegate = self
        return panel
    }

    // MARK: NSWindowDelegate

    /// Clicking or switching away closes the card, as a click on the
    /// window's backdrop closes capture there.
    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    /// AppKit keeps a window's bottom edge as its content resizes it; the
    /// card keeps its top edge instead and grows downwards.
    func windowDidResize(_ notification: Notification) {
        guard let panel, let topLeft, panel.frame.minX != topLeft.x || panel.frame.maxY != topLeft.y else { return }
        panel.setFrameTopLeftPoint(topLeft)
    }
}

/// A borderless panel that still takes the keyboard.
private final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
