//
//  NextKeys.swift
//  openlist
//
//  One keyboard handler for the main window. Menu shortcuts stay with
//  AppCommands; this covers the overlays and the single-key map.
//

import AppKit
import SwiftUI

/// Installs the key monitor for the window it lives in.
struct NextKeyMonitorHost: NSViewRepresentable {
    @Environment(AppEnvironment.self) private var env
    let library: NextLibrary
    let overlays: NXOverlayState

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.view = view
        context.coordinator.install()
        overlays.host = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.env = env
        context.coordinator.library = library
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: NextKeyHandler) {
        coordinator.uninstall()
    }

    func makeCoordinator() -> NextKeyHandler { NextKeyHandler(env: env, library: library, overlays: overlays) }
}

@MainActor
final class NextKeyHandler {
    var env: AppEnvironment
    var library: NextLibrary
    let overlays: NXOverlayState
    weak var view: NSView?
    private var monitor: Any?
    private var clickMonitor: Any?
    /// Keys pressed while the list document moves its caret, in order.
    private var heldKeys: [NSEvent] = []

    init(env: AppEnvironment, library: NextLibrary, overlays: NXOverlayState) {
        self.env = env
        self.library = library
        self.overlays = overlays
    }

    func install() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let handled = MainActor.assumeIsolated { self.handle(event) }
            return handled ? nil : event
        }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self else { return event }
            MainActor.assumeIsolated { self.releaseForeignFocus(for: event) }
            return event
        }
    }

    func uninstall() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        monitor = nil
        clickMonitor = nil
    }

    private enum Key {
        static let enter: UInt16 = 36, keypadEnter: UInt16 = 76, tab: UInt16 = 48, escape: UInt16 = 53, space: UInt16 = 49
        static let delete: UInt16 = 51, forwardDelete: UInt16 = 117
        static let left: UInt16 = 123, right: UInt16 = 124, down: UInt16 = 125, up: UInt16 = 126
    }

    // MARK: Dispatch

    /// True when the event was handled and should not travel further.
    private func handle(_ event: NSEvent) -> Bool {
        guard let window = view?.window, event.window === window, window.attachedSheet == nil,
              NSApp.modalWindow == nil else { return false }
        let workbench = env.workbench
        let navigator = env.navigator
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let key = event.keyCode
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let responder = window.firstResponder
        let isEditingText = responder is NSText || responder is NSTextView
        let isComposing = (responder as? NSTextInputClient)?.hasMarkedText() == true
        let isEnter = key == Key.enter || key == Key.keypadEnter

        // After Return or Backspace the list document's caret is on its way
        // to another line. Keys typed meanwhile wait for it, in order, rather
        // than type into the line it left or reach the single-key map.
        if !flags.contains(.command), !heldKeys.isEmpty || workbench.document?.isMovingCaret == true {
            heldKeys.append(event)
            if heldKeys.count == 1 { releaseHeldKeys(in: window, since: .now) }
            return true
        }

        if flags == .command && chars == "k" && navigator.isCommandPaletteOpen {
            navigator.isCommandPaletteOpen = false
            return true
        }

        // The in-window Settings page, wherever focus is and over any overlay,
        // never the Settings window.
        if flags == .command && chars == "," {
            overlays.willNavigate()
            if workbench.captureOpen { workbench.closeCapture() }
            if workbench.tasksQueryFocused { blurQuery(window) }
            workbench.go(.settings)
            return true
        }

        if workbench.captureOpen {
            guard !isComposing else { return false }
            if isEnter && !flags.contains(.command) {
                _ = workbench.createFromCapture(keepOpen: flags.contains(.shift))
                return true
            }
            if key == Key.tab {
                workbench.cycleCaptureDestination(by: flags.contains(.shift) ? -1 : 1, among: library.lists.map(\.id))
                return true
            }
            if key == Key.escape {
                workbench.closeCapture()
                return true
            }
            return false
        }

        if navigator.isCommandPaletteOpen {
            guard !isComposing else { return false }
            return handleList(key, index: \.paletteIndex, items: { NXPalette.commands(env: env, library: library) },
                              run: { NXPalette.run($0, env: env, overlays: overlays) },
                              close: { navigator.isCommandPaletteOpen = false })
        }

        if navigator.isSearchOpen {
            guard !isComposing else { return false }
            // Return before the results are in opens the first once they are.
            if isEnter && NXSearch.waitsForAnswer(overlays.search, workbench: workbench) {
                overlays.pendingSearchOpen = NXSearch.options(workbench)
                return true
            }
            return handleList(key, index: \.searchIndex, items: { NXSearch.hits(overlays.search, workbench: workbench) },
                              run: { NXSearch.open($0, env: env, library: library, overlays: overlays) },
                              close: { navigator.isSearchOpen = false })
        }

        // Only the Tasks screen has the query; the flag alone can outlive it.
        if workbench.tasksQueryFocused && isEditingText && (navigator.route == .tasks || navigator.route == .completed) {
            guard !isComposing, flags.isEmpty || flags == .shift else { return false }
            switch key {
            // Tab never leaves the field; without Shift it takes the completion, if there is one.
            case Key.tab:
                let ghost = NXTaskQuery(library: library).parse(workbench.tasksQuery).ghost
                if flags.isEmpty, !ghost.isEmpty { workbench.tasksQuery += ghost + " " }
                return true
            case Key.escape:
                if workbench.tasksQuery.isEmpty { blurQuery(window) } else { workbench.tasksQuery = "" }
                return true
            case Key.enter, Key.keypadEnter:
                blurQuery(window)
                return true
            default:
                return false
            }
        }

        // An open sentence-bar menu takes Esc before the inspector, the selection and the focus do.
        if key == Key.escape && flags.isEmpty && !isComposing && workbench.tasksMenu != nil
            && (navigator.route == .tasks || navigator.route == .completed) {
            workbench.tasksMenu = nil
            return true
        }

        // Undo while a list document line is being written: once the line's
        // edit has changed more than its text, Undo takes the whole edit back.
        if flags == .command, chars == "z", isEditingText { workbench.document?.prepareForUndo() }

        // Every other text field and the document editor keep their keys.
        if isEditingText { return false }
        // So do controls and views outside the shell's own hosting view, such
        // as a document list's row gutter, pickers and date fields.
        if isForeign(responder) { return false }

        if flags == .command {
            switch chars {
            case "z":
                workbench.undoLast()
                return true
            case "a":
                guard !workbench.visibleIDs.isEmpty else { return false }
                workbench.selectAllVisible()
                return true
            default:
                return false
            }
        }
        guard flags.isEmpty || flags == .shift else { return false }
        return handleSingleKey(key: key, chars: chars, shift: flags == .shift)
    }

    /// ↑/↓ move `index`, Return runs the current item, Escape closes, and Tab
    /// stays in the overlay rather than moving focus behind it. `items` is only
    /// built for keys that use it, not for typing.
    private func handleList<Item>(_ key: UInt16, index: ReferenceWritableKeyPath<Workbench, Int>,
                                  items: () -> [Item], run: (Item) -> Void, close: () -> Void) -> Bool {
        let workbench = env.workbench
        switch key {
        case Key.down, Key.up:
            let items = items()
            guard !items.isEmpty else { return true }
            let current = min(workbench[keyPath: index], items.count - 1)
            workbench[keyPath: index] = max(0, min(items.count - 1, current + (key == Key.down ? 1 : -1)))
            return true
        case Key.enter, Key.keypadEnter:
            let items = items()
            if !items.isEmpty { run(items[min(workbench[keyPath: index], items.count - 1)]) }
            return true
        case Key.escape:
            close()
            return true
        case Key.tab:
            return true
        default:
            return false
        }
    }

    /// Hands held keys on once the caret has landed, or, if it never does,
    /// once the wait has run out and the document has let the move go.
    private func releaseHeldKeys(in window: NSWindow, since start: Date) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self, weak window] in
            guard let self else { return }
            guard let window else { self.heldKeys = []; return }
            let document = self.env.workbench.document
            if document?.isMovingCaret == true, Date.now.timeIntervalSince(start) < 0.4 {
                self.releaseHeldKeys(in: window, since: start)
                return
            }
            if document?.isMovingCaret == true { document?.requestFocus(nil) }
            let keys = self.heldKeys
            self.heldKeys = []
            // Straight to the window, past this monitor: each key reaches the
            // line that now has the caret, or the single-key map if none does.
            for key in keys where !self.handle(key) { window.sendEvent(key) }
        }
    }

    private func blurQuery(_ window: NSWindow) {
        env.workbench.tasksQueryFocused = false
        window.makeFirstResponder(nil)
    }

    /// A view other than the shell's hosting view (or the window) has the keys.
    private func isForeign(_ responder: NSResponder?) -> Bool {
        guard let focused = responder as? NSView, let host = view else { return false }
        return !host.isDescendant(of: focused)
    }

    /// Clicking a Next row doesn't move the first responder, so a control that
    /// had it (a picker, a date field) would keep the keys from the rows. A
    /// click anywhere outside it hands them back to the shell; a click on
    /// another control or field still lets that one take focus. Text fields
    /// keep AppKit's own behaviour.
    private func releaseForeignFocus(for event: NSEvent) {
        guard let window = view?.window, event.window === window,
              let focused = window.firstResponder as? NSView, !(focused is NSText), isForeign(focused),
              !focused.bounds.contains(focused.convert(event.locationInWindow, from: nil)) else { return }
        window.makeFirstResponder(nil)
    }

    // MARK: Single keys

    private func handleSingleKey(key: UInt16, chars: String, shift: Bool) -> Bool {
        let workbench = env.workbench
        let navigator = env.navigator

        if let pressed = workbench.gPressedAt {
            workbench.gPressedAt = nil
            if Date.now.timeIntervalSince(pressed) < 0.9, let route = Self.goRoutes[chars] {
                workbench.go(route)
                return true
            }
        }

        // The card's keys win whenever no row is focused, selection or not, and
        // Shift doesn't stop them, as in the design. The Inbox shown as its
        // document has no card.
        if navigator.route == .inbox, !navigator.documentOwnsEditorCommands, workbench.focusID == nil,
           let task = library.inboxQueue(workbench).first {
            if let digit = Int(chars), (1...9).contains(digit) {
                let destinations = library.destinations
                guard digit <= destinations.count else { return true }
                workbench.triage(task, action: .left, listID: destinations[digit - 1].id)
                return true
            }
            switch (key, chars) {
            case (_, "t"): workbench.triage(task, action: .up, offset: 0); return true
            case (_, "m"): workbench.triage(task, action: .up, offset: 1); return true
            case (Key.right, _): workbench.triage(task, action: .right); return true
            case (_, "e"): workbench.triage(task, action: .done); return true
            case (_, "d"): workbench.triage(task, action: .down); return true
            // Like the card's Details button: no focus, so triage keys still work once it closes.
            case (Key.enter, _), (Key.keypadEnter, _): navigator.openTask(task.id); return true
            default: break
            }
        }

        // The design's keys land even with nothing to act on: they do nothing,
        // quietly, rather than reach AppKit and beep. Only ↑/↓ pass through.
        switch key {
        case Key.down, Key.up:
            // Nothing on screen publishes rows: let the event reach the screen.
            guard !workbench.visibleIDs.isEmpty else { return false }
            workbench.moveFocus(by: key == Key.down ? 1 : -1, extending: shift)
            return true
        case Key.enter, Key.keypadEnter:
            // A list document's heading or text has no details: Return edits it.
            if let document = workbench.document, let id = workbench.focusID,
               let block = env.store.block(id: id), !block.isTask, block.listID == navigator.documentListID {
                document.edit(id)
            } else if let id = workbench.focusID ?? workbench.targetIDs.first { workbench.inspect(id) }
            return true
        case Key.tab where workbench.document != nil:
            // Tab and ⇧Tab nest and lift the focused rows, as they do the line being written.
            workbench.document?.indent(workbench.targetIDs, outdent: shift)
            return true
        case Key.space where workbench.document != nil && !shift:
            // Notes open in place, in the document's own rows.
            if let id = workbench.focusID, workbench.document?.shows(id) == true { workbench.toggleNote(id) }
            return true
        case Key.escape:
            if navigator.openTaskID != nil { navigator.closeTask() }
            else if !workbench.selection.isEmpty { workbench.clearSelection() }
            else { workbench.focusID = nil }
            return true
        default:
            break
        }

        switch chars {
        case "j", "k":
            workbench.moveFocus(by: chars == "j" ? 1 : -1, extending: shift)
            return true
        case "x" where !shift:
            if let id = workbench.focusID { workbench.toggleSelection(id) }
            return true
        default:
            if openGlobal(chars, shift: shift) { return true }
        }

        // ⇧ with an action key does nothing, but quietly, like the key alone
        // with no target; other ⇧-letters pass through.
        guard !shift else { return key == Key.delete || key == Key.forwardDelete || Self.actionKeys.contains(chars) }
        // Each action ignores an empty target list.
        let ids = workbench.targetIDs
        if key == Key.delete || key == Key.forwardDelete {
            workbench.trash(ids)
            return true
        }
        switch chars {
        case "e": workbench.complete(ids)
        case "t": workbench.schedule(ids, offset: 0)
        case "m": workbench.schedule(ids, offset: 1)
        case "f": workbench.star(ids)
        case "p": workbench.plan(ids)
        case "d": workbench.trash(ids)
        default: return false
        }
        return true
    }

    /// G (then a route key), N and / work on every screen.
    private func openGlobal(_ chars: String, shift: Bool) -> Bool {
        let workbench = env.workbench
        switch chars {
        case "g" where !shift:
            workbench.gPressedAt = .now
        case "n" where !shift:
            workbench.openCapture()
        case "/":
            env.navigator.isSearchOpen = true
        default:
            return false
        }
        return true
    }

    private static let goRoutes: [String: AppRoute] = [
        "i": .inbox, "t": .today, "c": .calendar, "a": .tasks, "l": .lists, "h": .activity,
    ]

    /// The design's letter keys besides J/K: x, the row actions, N and G.
    private static let actionKeys: Set<String> = ["x", "e", "t", "m", "f", "p", "d", "n", "g"]
}
