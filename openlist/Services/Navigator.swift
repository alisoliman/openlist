//
//  Navigator.swift
//  openlist
//

import Foundation
import SwiftUI

/// Everywhere the sidebar can take you.
enum AppRoute: Hashable, Codable {
    case inbox
    case today
    case calendar
    case updates
    case tasks
    case lists
    case list(UUID)
    case label(UUID)
    case completed

    var isSmartView: Bool {
        switch self {
        case .list: false
        default: true
        }
    }

    var listID: UUID? {
        if case let .list(id) = self { return id }
        return nil
    }

    /// `true` for routes that render a `DocumentView`, which then owns menu
    /// commands for that screen.
    var hasDocumentEditor: Bool {
        switch self {
        case .list, .inbox: true
        default: false
        }
    }
}

/// Drives which view is on screen, plus the back/forward history behind ⌘[ and ⌘].
@Observable
@MainActor
final class Navigator {
    private(set) var route: AppRoute = .today

    /// The task whose detail panel is open, if any.
    var openTaskID: UUID?

    /// Blocks selected in the current document, for multi-select actions.
    var selection: Set<UUID> = []

    // Overlays.
    var isCommandPaletteOpen = false
    var isSearchOpen = false
    var isShortcutSheetOpen = false

    private var backStack: [AppRoute] = []
    private var forwardStack: [AppRoute] = []

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    /// Navigates, pushing the current route onto the back stack.
    func go(to newRoute: AppRoute) {
        guard newRoute != route else { return }
        backStack.append(route)
        forwardStack.removeAll()
        route = newRoute
        openTaskID = nil
        selection.removeAll()
        trimHistory()
    }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(route)
        route = previous
        openTaskID = nil
        selection.removeAll()
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(route)
        route = next
        openTaskID = nil
        selection.removeAll()
    }

    /// Replaces the current route without disturbing history — used when the
    /// list you are viewing is deleted underneath you.
    func replace(with newRoute: AppRoute) {
        route = newRoute
        openTaskID = nil
        selection.removeAll()
    }

    func openTask(_ id: UUID?) {
        openTaskID = id
    }

    func closeTask() {
        openTaskID = nil
    }

    private func trimHistory() {
        if backStack.count > 100 { backStack.removeFirst(backStack.count - 100) }
    }
}
