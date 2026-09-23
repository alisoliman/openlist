//
//  NextWindowChrome.swift
//  openlist
//

import AppKit
import SwiftUI

/// Sits the window's traffic lights on the 52pt bar the way the design draws
/// them: centred on its midline, the first one 20pt in from the edge. AppKit
/// lays the title bar out again on resizes, zooms and full-screen changes, so
/// the lights are put back whenever it moves them.
@Observable @MainActor
final class NXWindowChrome {
    static let barHeight: CGFloat = 52
    /// From the window's edge to the close button's edge.
    static let leadingInset: CGFloat = 20
    /// Where the lights end, from the window's leading edge. The design's
    /// three 12pt dots 8pt apart end at 72.
    private(set) var trailingEdge: CGFloat = 72
    /// Full screen hides the lights with the title bar.
    private(set) var isFullScreen = false
    @ObservationIgnored private weak var window: NSWindow?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// Moving the buttons reports their frames changing; this ignores our own moves.
    @ObservationIgnored private var isPlacing = false
    /// The system's distance between the buttons, read before the first move.
    @ObservationIgnored private var spacing: CGFloat?
    /// The title bar container being watched; full screen can hand back a new one.
    @ObservationIgnored private weak var watchedContainer: NSView?

    func attach(to window: NSWindow?) {
        guard window !== self.window else { return }
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        watchedContainer = nil
        self.window = window
        guard let window else { return }
        isFullScreen = window.styleMask.contains(.fullScreen)
        observe(NSWindow.didResizeNotification, of: window) { $0.place() }
        observe(NSWindow.willEnterFullScreenNotification, of: window) { $0.isFullScreen = true }
        observe(NSWindow.didExitFullScreenNotification, of: window) { chrome in
            chrome.isFullScreen = false
            chrome.place()
        }
        // AppKit resets the buttons' frames in its own layout passes, not only on resize.
        buttons(of: window).forEach(watchFrame)
        place()
    }

    private func watchFrame(of view: NSView) {
        view.postsFrameChangedNotifications = true
        observe(NSView.frameDidChangeNotification, of: view) { $0.place() }
    }

    private func observe(_ name: Notification.Name, of object: AnyObject,
                         _ handler: @escaping @MainActor (NXWindowChrome) -> Void) {
        observers.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self { handler(self) } }
        })
    }

    private func buttons(of window: NSWindow) -> [NSButton] {
        [.closeButton, .miniaturizeButton, .zoomButton].compactMap { window.standardWindowButton($0) }
    }

    /// The title bar's container: the buttons' ancestor that sits directly in
    /// the window's frame view.
    private func titlebarContainer(of window: NSWindow) -> NSView? {
        guard let frameView = window.contentView?.superview,
              var view = window.standardWindowButton(.closeButton)?.superview else { return nil }
        while let parent = view.superview, parent !== frameView { view = parent }
        return view.superview === frameView ? view : nil
    }

    private func place() {
        guard !isPlacing, !isFullScreen, let window, !window.styleMask.contains(.fullScreen),
              let container = titlebarContainer(of: window), let frameView = container.superview else { return }
        let buttons = buttons(of: window)
        guard buttons.count == 3 else { return }
        let spacing = spacing ?? buttons[1].frame.minX - buttons[0].frame.minX
        guard spacing > 0 else { return }
        self.spacing = spacing
        // The container's height is reset in the same passes.
        if container !== watchedContainer {
            watchedContainer = container
            watchFrame(of: container)
        }
        isPlacing = true
        defer { isPlacing = false }
        // A 52pt title bar keeps the moved buttons inside it, so they still take clicks.
        var bar = container.frame
        bar.size.height = Self.barHeight
        bar.origin.y = frameView.isFlipped ? 0 : frameView.bounds.height - Self.barHeight
        if container.frame != bar { container.frame = bar }
        // Keep the system's spacing; move the group and centre it on the bar.
        let windowHeight = frameView.bounds.height
        for (index, button) in buttons.enumerated() {
            guard let parent = button.superview else { continue }
            let size = button.frame.size
            let centre = NSPoint(x: Self.leadingInset + size.width / 2 + CGFloat(index) * spacing,
                                 y: windowHeight - Self.barHeight / 2)
            let local = parent.convert(centre, from: nil)
            let origin = NSPoint(x: (local.x - size.width / 2).rounded(), y: (local.y - size.height / 2).rounded())
            if button.frame.origin != origin { button.setFrameOrigin(origin) }
        }
        let edge = (buttons[2].convert(buttons[2].bounds, to: nil).maxX).rounded(.up)
        if edge != trailingEdge { trailingEdge = edge }
    }
}

/// Hands the shell's window to the chrome once the view is in it.
struct NXWindowChromeHost: NSViewRepresentable {
    let chrome: NXWindowChrome

    func makeNSView(context: Context) -> Probe {
        let view = Probe()
        view.chrome = chrome
        return view
    }

    func updateNSView(_ nsView: Probe, context: Context) {
        nsView.chrome = chrome
    }

    final class Probe: NSView {
        weak var chrome: NXWindowChrome?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            chrome?.attach(to: window)
        }
    }
}

private struct NXTrafficLightsInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// Room the toolbar leaves at its leading edge for the traffic lights,
    /// when the sidebar isn't there to hold them.
    var nxTrafficLightsInset: CGFloat {
        get { self[NXTrafficLightsInsetKey.self] }
        set { self[NXTrafficLightsInsetKey.self] = newValue }
    }
}
