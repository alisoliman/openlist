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

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.view = view
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.env = env
        context.coordinator.library = library
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: NextKeyHandler) {
        coordinator.uninstall()
    }

    func makeCoordinator() -> NextKeyHandler { NextKeyHandler(env: env, library: library) }
}

@MainActor
final class NextKeyHandler {
    var env: AppEnvironment
    var library: NextLibrary
    weak var view: NSView?
    private var monitor: Any?

    init(env: AppEnvironment, library: NextLibrary) {
        self.env = env
        self.library = library
    }

    func install() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let handled = MainActor.assumeIsolated { self.handle(event) }
            return handled ? nil : event
        }
    }

    func uninstall() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private enum Key {
        static let enter: UInt16 = 36, keypadEnter: UInt16 = 76, tab: UInt16 = 48, escape: UInt16 = 53
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

        if flags == .command && chars == "k" && navigator.isCommandPaletteOpen {
            navigator.isCommandPaletteOpen = false
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
            let commands = NXPalette.commands(env: env, library: library)
            switch key {
            case Key.down, Key.up:
                guard !commands.isEmpty else { return true }
                let current = min(workbench.paletteIndex, commands.count - 1)
                workbench.paletteIndex = max(0, min(commands.count - 1, current + (key == Key.down ? 1 : -1)))
                return true
            case Key.enter, Key.keypadEnter:
                if !commands.isEmpty { NXPalette.run(commands[min(workbench.paletteIndex, commands.count - 1)], env: env) }
                return true
            case Key.escape:
                navigator.isCommandPaletteOpen = false
                return true
            default:
                return false
            }
        }

        if navigator.isSearchOpen {
            guard !isComposing else { return false }
            let hits = NXSearch.hits(env: env, library: library)
            switch key {
            case Key.down, Key.up:
                guard !hits.isEmpty else { return true }
                let current = min(workbench.searchIndex, hits.count - 1)
                workbench.searchIndex = max(0, min(hits.count - 1, current + (key == Key.down ? 1 : -1)))
                return true
            case Key.enter, Key.keypadEnter:
                if !hits.isEmpty { hits[min(workbench.searchIndex, hits.count - 1)].run() }
                return true
            case Key.escape:
                navigator.isSearchOpen = false
                return true
            default:
                return false
            }
        }

        if workbench.tasksQueryFocused && isEditingText {
            guard !isComposing, flags.isEmpty || flags == .shift else { return false }
            switch key {
            case Key.tab where flags.isEmpty:
                let ghost = NXTaskQuery(library: library).parse(workbench.tasksQuery).ghost
                guard !ghost.isEmpty else { return false }
                workbench.tasksQuery += ghost + " "
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

        // Every other text field and the document editor keep their keys.
        if isEditingText { return false }

        if flags == .command {
            switch chars {
            case "z":
                workbench.undoLast()
                return true
            case ",":
                workbench.go(.settings)
                return true
            case "a":
                workbench.selectAllVisible()
                return true
            default:
                return false
            }
        }
        guard flags.isEmpty || flags == .shift else { return false }
        return handleSingleKey(key: key, chars: chars, shift: flags == .shift)
    }

    private func blurQuery(_ window: NSWindow) {
        env.workbench.tasksQueryFocused = false
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

        if navigator.route == .inbox, workbench.focusID == nil, workbench.selection.isEmpty, !shift,
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
            case (Key.enter, _), (Key.keypadEnter, _): workbench.inspect(task.id); return true
            default: break
            }
        }

        switch key {
        case Key.down:
            workbench.moveFocus(by: 1, extending: shift)
            return true
        case Key.up:
            workbench.moveFocus(by: -1, extending: shift)
            return true
        case Key.enter, Key.keypadEnter:
            guard let id = workbench.focusID ?? workbench.targetIDs.first else { return false }
            workbench.inspect(id)
            return true
        case Key.escape:
            if navigator.openTaskID != nil { navigator.closeTask() }
            else if !workbench.selection.isEmpty { workbench.selection = [] }
            else if workbench.focusID != nil { workbench.focusID = nil }
            else { return false }
            return true
        default:
            break
        }

        switch chars {
        case "g" where !shift:
            workbench.gPressedAt = .now
            return true
        case "n" where !shift:
            workbench.openCapture()
            return true
        case "/":
            navigator.isSearchOpen = true
            return true
        case "j":
            workbench.moveFocus(by: 1, extending: shift)
            return true
        case "k":
            workbench.moveFocus(by: -1, extending: shift)
            return true
        case "x" where !shift:
            guard let id = workbench.focusID else { return false }
            workbench.toggleSelection(id)
            return true
        default:
            break
        }

        guard !shift else { return false }
        let ids = workbench.targetIDs
        guard !ids.isEmpty else { return false }
        switch chars {
        case "e":
            let tasks = workbench.tasks(ids)
            if !tasks.isEmpty, tasks.allSatisfy(\.isCompleted) {
                tasks.forEach { workbench.reopen($0.id) }
            } else {
                workbench.complete(tasks.filter { !$0.isCompleted }.map(\.id))
            }
        case "t": workbench.schedule(ids, offset: 0)
        case "m": workbench.schedule(ids, offset: 1)
        case "f": workbench.star(ids)
        case "p": workbench.plan(ids)
        case "d": workbench.trash(ids)
        default: return false
        }
        return true
    }

    private static let goRoutes: [String: AppRoute] = [
        "i": .inbox, "t": .today, "c": .calendar, "a": .tasks, "l": .lists, "h": .activity,
    ]
}
