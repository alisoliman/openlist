//
//  QuickCapturePanel.swift
//  openlist
//

import AppKit
import SwiftData
import SwiftUI

/// What opened Quick Add asks of it. The hot key, the menu bar and File ▸
/// Quick Add ask nothing; a widget can name a list, or plan for today.
struct QuickCaptureRequest: Equatable {
    /// The list the card starts on; Inbox when nil.
    var listID: UUID?
    /// Plans the task for today, as the calendar does, instead of giving it a
    /// due date.
    var plansForToday = false
    /// Adds the task at the end of `listID`'s document, where that list's
    /// Tasks view has its add row, while that list is still the destination.
    var appendsToList = false
}

/// Quick Add: the design's capture card floating over whatever app is in
/// front, from ⇧⌥Space, the menu bar or File ▸ Quick Add.
///
/// A non-activating panel takes typing without making Openlist the active
/// app, so the main window stays where it is and focus goes back to the app
/// you were in once the panel closes. Escape, ⌘W and Return close it and are
/// done with the draft. Clicking or switching away closes it too, but keeps
/// what was typed for the next Quick Add for a few minutes, as Spotlight
/// keeps its query.
@MainActor
final class QuickCapturePanel: NSObject, NSWindowDelegate {
    static let shared = QuickCapturePanel()

    /// How a card closes, which decides what happens to its draft and to focus.
    enum Dismissal {
        /// Escape, ⌘W, or Return adding the task: the draft is done with.
        case finished
        /// A click around the card: the draft waits, and focus goes back.
        case dismissed
        /// Another window or app took the keyboard: the draft waits, and
        /// focus stays where it went.
        case resigned
    }

    /// How long a draft put aside by a click away waits for the next Quick Add.
    private static let keptDraftLifetime: TimeInterval = 5 * 60

    private var env: AppEnvironment?
    private var container: ModelContainer?
    private var panel: CapturePanel?
    /// The open card's draft, and after a click away the one the next card resumes.
    private var draft: QuickCaptureDraft?
    private var keptUntil: Date?
    /// Where the panel's top-left corner sits, kept as the card grows and shrinks.
    private var topLeft: NSPoint?
    /// The app to give focus back to on close, when showing the card made
    /// Openlist the active app.
    private var returnTo: NSRunningApplication?
    /// Showing any window unhides a hidden app, all its windows with it, so a
    /// card shown while Openlist was hidden (⌘H) hides it again on close.
    private var hidesOnClose = false

    // What `showFromMenuBar` needs to tell whether the popover made Openlist active.
    private var lastOtherApp: NSRunningApplication?
    private var cameFrom: NSRunningApplication?
    private var activatedAt: Date?
    // What `showFromWidget` needs to tell which app you were in: the last one
    // with windows of its own, Openlist included, and not a widget's host.
    private var lastRegularApp: NSRunningApplication?
    private var cameFromRegular: NSRunningApplication?
    /// When Openlist last came out of hiding, for `showFromWidget`.
    private var unhiddenAt: Date?
    private weak var lastKeyWindow: NSWindow?
    private var lastKeyAt: Date?
    private var observers: [NSObjectProtocol] = []
    private var menuObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?
    private var responderObservation: NSKeyValueObservation?
    /// Ordering the panel out resigns its key status, which would close it again.
    private var isClosing = false

    /// Hands the panel the library once it has opened at launch.
    func install(env: AppEnvironment, container: ModelContainer) {
        self.env = env
        self.container = container
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil,
                                               queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.activated(app) }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didUnhideNotification, object: nil,
                                                                queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.unhiddenAt = .now }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil,
                                                                queue: .main) { [weak self] note in
            let window = note.object as? NSWindow
            MainActor.assumeIsolated {
                self?.lastKeyWindow = window
                self?.lastKeyAt = .now
            }
        })
    }

    /// Wires ⇧⌥Space to the panel at launch, whether or not a window opens,
    /// and registers it while Settings has it on.
    func installHotKey(enabled: Bool) {
        QuickCaptureHotKey.shared.onTrigger = { [weak self] in self?.show() }
        if enabled { QuickCaptureHotKey.shared.register() }
    }

    /// Opens the card, resuming a draft put aside by a click away. A request
    /// with a list or plan re-aims the card, an open one included; one that
    /// asks nothing leaves the card as it was.
    func show(_ request: QuickCaptureRequest = QuickCaptureRequest()) {
        guard let env, let container else { return }
        let panel = panel ?? makePanel()
        self.panel = panel
        if panel.isVisible, let draft {
            draft.apply(request)
            panel.makeKeyAndOrderFront(nil)
            return
        }
        let draft: QuickCaptureDraft
        if let kept = self.draft, let keptUntil, keptUntil > .now {
            kept.apply(request)
            draft = kept
            if !kept.captureText.isEmpty { caretToEnd(in: panel) }
        } else {
            draft = QuickCaptureDraft(store: env.store, settings: env.settings, request: request)
        }
        self.draft = draft
        keptUntil = nil
        // Motion is the card's own, from the Next style, which follows Reduce Motion.
        let host = NSHostingView(rootView: QuickCaptureView(draft: draft, close: { [weak self] in self?.close($0) })
            .environment(env)
            .modelContainer(container)
            .environment(\.calendar, env.settings.calendar))
        // The panel takes the card's size, and follows it as chips wrap or a notice shows.
        host.sizingOptions = .standardBounds
        panel.contentView = host
        panel.appearance = env.settings.appearance.colorScheme.flatMap { NSAppearance(named: $0 == .dark ? .darkAqua : .aqua) }
        panel.setContentSize(host.fittingSize)
        place(panel)
        hidesOnClose = NSApp.isHidden
        // VoiceOver reads the active app, so with it on Openlist activates to
        // put the card in front of it, and gives focus back on close. The card
        // takes the keyboard once Openlist is active, so activating can't hand
        // it to another window and close the card.
        if NSWorkspace.shared.isVoiceOverEnabled, !NSApp.isActive {
            returnTo = returnTo ?? NSWorkspace.shared.frontmostApplication
            panel.orderFrontRegardless()
            keyOnActivation(panel)
            NSApp.activate()
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    /// A field selects all its text as it takes focus. A resumed draft puts
    /// the caret after it instead, so pasting or typing adds to it.
    private func caretToEnd(in panel: NSPanel) {
        responderObservation = panel.observe(\.firstResponder, options: [.new]) { [weak self] panel, _ in
            MainActor.assumeIsolated {
                guard let editor = panel.firstResponder as? NSTextView, editor.isFieldEditor else { return }
                // Once the field has made its own selection.
                DispatchQueue.main.async {
                    self?.responderObservation = nil
                    editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
                }
            }
        }
    }

    private func keyOnActivation(_ panel: NSPanel) {
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        activationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                                                    object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.keyAfterActivation() }
        }
        // In case activation is refused.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.keyAfterActivation() }
    }

    private func keyAfterActivation() {
        guard let activationObserver else { return }
        NotificationCenter.default.removeObserver(activationObserver)
        self.activationObserver = nil
        if let panel, panel.isVisible { panel.makeKeyAndOrderFront(nil) }
    }

    /// From the menu bar popover's New task row, before the popover closes.
    /// The card opens once the popover has let go of the keyboard, so its
    /// closing can't hand the keyboard to another Openlist window after the
    /// card has taken it. If opening the popover made Openlist the active
    /// app, focus goes back to the app you were in when the card closes.
    func showFromMenuBar(closing menu: NSWindow?) {
        // Openlist became active as the popover took the keyboard, not before.
        if NSApp.isActive, let menu, lastKeyWindow === menu, let lastKeyAt, let activatedAt,
           activatedAt.timeIntervalSince(lastKeyAt) > -0.5 {
            returnTo = cameFrom
        } else {
            returnTo = nil
        }
        if let menuObserver { NotificationCenter.default.removeObserver(menuObserver) }
        menuObserver = nil
        guard let menu, menu.isKeyWindow else {
            DispatchQueue.main.async { self.show() }
            return
        }
        menuObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: menu,
                                                              queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.showAfterMenu() }
        }
        // In case the popover never reports letting go.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.showAfterMenu() }
    }

    /// From a widget's Quick Add. Opening the widget's link can make Openlist
    /// the active app, and show it if it was hidden, before or after the card
    /// opens. The card then gives focus back to the app you were in when it
    /// closes, and hides Openlist again, as if Openlist had stayed where it was.
    func showFromWidget(_ request: QuickCaptureRequest) {
        let justNow = { (date: Date?) in date.map { $0.timeIntervalSinceNow > -1 } ?? false }
        let previous: NSRunningApplication?
        if NSApp.isActive {
            // Openlist became active as the link opened, not before.
            previous = justNow(activatedAt) ? cameFromRegular : nil
        } else {
            // The link's activation may still be on its way. Should it never
            // come, close leaves focus where it is.
            let front = NSWorkspace.shared.frontmostApplication
            previous = Self.canReturn(to: front) ? front : lastRegularApp
        }
        let wasHidden = justNow(unhiddenAt)
        show(request)
        guard panel?.isVisible == true else { return }
        // In place of none, or of VoiceOver's pick when that was the widget's host.
        if Self.canReturn(to: previous), !Self.canReturn(to: returnTo) { returnTo = previous }
        if wasHidden { hidesOnClose = true }
    }

    private func showAfterMenu() {
        guard let menuObserver else { return }
        NotificationCenter.default.removeObserver(menuObserver)
        self.menuObserver = nil
        // After AppKit has picked the next key window.
        DispatchQueue.main.async { self.show() }
    }

    func close(_ dismissal: Dismissal) {
        guard let panel, panel.isVisible, !isClosing else { return }
        isClosing = true
        defer { isClosing = false }
        topLeft = nil
        responderObservation = nil
        if dismissal == .finished {
            draft = nil
            keptUntil = nil
        } else {
            keptUntil = .now + Self.keptDraftLifetime
        }
        panel.orderOut(nil)
        // The next card is a new view, over the kept draft or a new one. The
        // old one goes once the key press or click that closed it has
        // finished with it.
        DispatchQueue.main.async { [weak panel] in
            guard let panel, !panel.isVisible else { return }
            panel.contentView = NSView()
        }
        // Focus that moved to another Openlist window, or an alert, stays there.
        let movedWithin = dismissal == .resigned && NSApp.isActive
        let app = returnTo
        returnTo = nil
        if hidesOnClose, !movedWithin {
            NSApp.hide(nil)
        } else if dismissal != .resigned, NSApp.isActive, let app, !app.isTerminated {
            _ = app.activate()
        }
        hidesOnClose = false
    }

    private func activated(_ app: NSRunningApplication?) {
        if Self.isOpenlist(app) {
            cameFrom = lastOtherApp
            cameFromRegular = lastRegularApp
            activatedAt = .now
        } else {
            lastOtherApp = app
        }
        if Self.isOpenlist(app) || app?.activationPolicy == .regular { lastRegularApp = app }
    }

    private static func isOpenlist(_ app: NSRunningApplication?) -> Bool {
        app?.processIdentifier == NSRunningApplication.current.processIdentifier
    }

    /// Another app with windows of its own: not Openlist, which you stay in,
    /// or a widget's host, which has no window to come back to.
    private static func canReturn(to app: NSRunningApplication?) -> Bool {
        guard let app else { return false }
        return app.activationPolicy == .regular && !isOpenlist(app)
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
    /// window's backdrop closes capture there, and keeps its draft.
    func windowDidResignKey(_ notification: Notification) {
        close(.resigned)
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
