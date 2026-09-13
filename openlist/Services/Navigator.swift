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

    /// Reusable exact-content navigation, retained only while viewing its page.
    private(set) var contentReveal: ContentReveal?
    private(set) var searchActivation = 0

    func reveal(_ request: ContentReveal) {
        go(to: .list(request.listID))
        openTaskID = request.taskID
        selection = request.blockID.map { [$0] } ?? []
        contentReveal = request
        searchActivation &+= 1
    }

    func finishReveal() { contentReveal = nil }

    private var backStack: [AppRoute] = []
    private var forwardStack: [AppRoute] = []
    @ObservationIgnored private var scrollOffsets: [AppRoute: CGFloat] = [:]

    func scrollOffset(for route: AppRoute) -> CGFloat { scrollOffsets[route] ?? 0 }

    func rememberScrollOffset(_ offset: CGFloat, for route: AppRoute) {
        guard offset.isFinite else { return }
        scrollOffsets[route] = max(0, offset)
    }

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    /// Navigates, pushing the current route onto the back stack.
    func go(to newRoute: AppRoute) {
        guard newRoute != route else { return }
        backStack.append(route)
        forwardStack.removeAll()
        route = newRoute
        contentReveal = nil
        openTaskID = nil
        selection.removeAll()
        trimHistory()
    }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(route)
        route = previous
        contentReveal = nil
        openTaskID = nil
        selection.removeAll()
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(route)
        route = next
        contentReveal = nil
        openTaskID = nil
        selection.removeAll()
    }

    /// Replaces the current route without disturbing history — used when the
    /// list you are viewing is deleted underneath you.
    func replace(with newRoute: AppRoute) {
        route = newRoute
        contentReveal = nil
        openTaskID = nil
        selection.removeAll()
    }

    /// Retarget both the visible route and history so Back/Forward cannot open
    /// the identity removed by a confirmed label merge.
    func retargetLabel(from sourceID: UUID, to destinationID: UUID) {
        let source = AppRoute.label(sourceID)
        let destination = AppRoute.label(destinationID)
        if route == source { route = destination }
        backStack = backStack.map { $0 == source ? destination : $0 }
        forwardStack = forwardStack.map { $0 == source ? destination : $0 }
    }

    func openTask(_ id: UUID?) {
        if contentReveal?.taskID != id { contentReveal = nil }
        openTaskID = id
    }

    func closeTask() {
        openTaskID = nil
        if contentReveal?.taskID != nil { contentReveal = nil }
    }

    private func trimHistory() {
        if backStack.count > 100 { backStack.removeFirst(backStack.count - 100) }
    }
}
