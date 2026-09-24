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
    case activity
    case tasks
    case lists
    case list(UUID)
    case label(UUID)
    case trash
    case settings

    var listID: UUID? {
        if case let .list(id) = self { return id }
        return nil
    }
}

/// Drives which view is on screen, plus the back/forward history behind ⌘[ and ⌘].
@Observable
@MainActor
final class Navigator {
    private(set) var route: AppRoute = .today

    private var listViewModes: [UUID: ListViewMode] = [:]
    @ObservationIgnored private let defaults: UserDefaults?
    private static let listViewModesKey = "listViewModes"

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        for (id, raw) in defaults?.dictionary(forKey: Self.listViewModesKey) ?? [:] {
            if let id = UUID(uuidString: id), let raw = raw as? String,
               let mode = ListViewMode(rawValue: raw) { listViewModes[id] = mode }
        }
    }

    /// The system Inbox list, so `.inbox` follows that list's presentation.
    /// Set by the app once the store is ready; nil in standalone checks.
    var inboxListID: UUID?

    /// The list a reveal opened as a document for this visit only, the Inbox
    /// among them. Leaving the list or choosing a presentation ends it; it is
    /// never saved.
    private var revealedDocumentListID: UUID?

    /// The Inbox shown as triage for this visit only, as the widget's Triage
    /// link asks, whatever this Mac chose for it. Leaving the Inbox or
    /// choosing a presentation ends it; it is never saved.
    private var isTriageVisit = false

    /// Lists open as their document, and the Inbox as triage, until this Mac
    /// chooses otherwise for them.
    func listViewMode(for listID: UUID) -> ListViewMode {
        if listID == revealedDocumentListID, shows(listID) { return .document }
        if isTriageVisit, listID == inboxListID, route == .inbox { return .tasks }
        return listViewModes[listID] ?? defaultViewMode(for: listID)
    }

    /// Turns the Inbox on show to triage until it is left, even where this Mac
    /// shows it as a document.
    func showInboxTriage() {
        guard route == .inbox, let inboxListID else { return }
        let shown = listViewMode(for: inboxListID)
        isTriageVisit = true
        if revealedDocumentListID == inboxListID { revealedDocumentListID = nil }
        guard shown != .tasks else { return }
        contentReveal = nil
        clearSelection()
    }

    /// Ends a triage visit on show, so the Inbox follows this Mac's choice
    /// again, as the widget's Inbox link asks.
    func followInboxPresentation() {
        guard isTriageVisit, let inboxListID else { return }
        let shown = listViewMode(for: inboxListID)
        isTriageVisit = false
        guard listViewMode(for: inboxListID) != shown else { return }
        contentReveal = nil
        clearSelection()
    }

    private func defaultViewMode(for listID: UUID) -> ListViewMode {
        listID == inboxListID ? .tasks : .document
    }

    func setListViewMode(_ mode: ListViewMode, for listID: UUID) {
        let shown = listViewMode(for: listID)
        if revealedDocumentListID == listID { revealedDocumentListID = nil }
        if listID == inboxListID { isTriageVisit = false }
        if (listViewModes[listID] ?? defaultViewMode(for: listID)) != mode {
            listViewModes[listID] = mode
            defaults?.set(Dictionary(uniqueKeysWithValues: listViewModes.map { ($0.key.uuidString, $0.value.rawValue) }),
                          forKey: Self.listViewModesKey)
        }
        guard shown != mode else { return }
        if shows(listID) {
            contentReveal = nil
            clearSelection()
        }
    }

    /// Whether the page on show is the list's: its own, or the Inbox's.
    func shows(_ listID: UUID) -> Bool {
        route == .list(listID) || (route == .inbox && listID == inboxListID)
    }

    /// Where a list's content is shown: the Inbox's on the Inbox, as
    /// everywhere else in the app, and any other list's on its page.
    func route(showing listID: UUID) -> AppRoute {
        listID == inboxListID ? .inbox : .list(listID)
    }

    /// The list whose document is on show: any list, drawn as the Next list
    /// document in either presentation, or the Inbox shown as a document.
    var documentListID: UUID? {
        switch route {
        case let .list(id): id
        case .inbox: inboxListID.flatMap { listViewMode(for: $0) == .document ? $0 : nil }
        default: nil
        }
    }

    /// Whether the screen on show is a document that takes the outline's menu
    /// commands. Everything else is a Next screen served by the workbench
    /// targets.
    var documentOwnsEditorCommands: Bool { documentListID != nil }

    /// The task the inspector shows, if any.
    var openTaskID: UUID?

    /// Blocks selected in the current document: the line being written, or
    /// the one a reveal lands on. The document's menu commands act on them.
    var selection: Set<UUID> = []
    private(set) var rowSelection = BlockSelection()

    /// Private drag identity is per environment/library, not a persisted block ID.
    let blockDragSessionID = UUID()

    func reconcileSelection(scope: UUID, visible: [UUID]) {
        selection = rowSelection.reconcile(in: scope, visible: visible, selected: selection)
    }

    func selectForEditing(_ id: UUID, scope: UUID, visible: [UUID]) {
        selection = rowSelection.select(id, in: scope, visible: visible, selected: selection)
    }

    func clearSelection() {
        selection.removeAll()
        rowSelection.clear()
    }

    // Overlays.
    var isCommandPaletteOpen = false
    var isSearchOpen = false
    var isShortcutSheetOpen = false

    /// Reusable exact-content navigation, retained only while viewing its page.
    private(set) var contentReveal: ContentReveal?
    private(set) var searchActivation = 0

    func reveal(_ request: ContentReveal) {
        // Revealing a target is an editing action, including in the same list.
        clearSelection()
        go(to: route(showing: request.listID))
        // Exact-content navigation must reveal notes and collapsed hierarchy,
        // including when this list was last viewed as a task-only queue. The
        // document is for this visit: the list's saved presentation stays.
        // The Inbox shows as this Mac shows it for a task, which opens in the
        // inspector, or for the Inbox itself; only a line needs its document.
        let revealsLine = request.blockID != nil && request.taskID == nil
        revealedDocumentListID = request.listID != inboxListID || revealsLine ? request.listID : nil
        openTaskID = request.taskID
        selection = request.blockID.map { [$0] } ?? []
        contentReveal = request
        searchActivation &+= 1
    }

    func finishReveal() { contentReveal = nil }

    /// A page in the history, and where it was scrolled to when it was left.
    private struct Visit {
        var route: AppRoute
        var scrollOffset: CGFloat?
    }

    private var backStack: [Visit] = []
    private var forwardStack: [Visit] = []
    /// Where each route's page is scrolled to, as the page reports it.
    @ObservationIgnored private var scrollOffsets: [AppRoute: CGFloat] = [:]
    /// The route Back or Forward just returned to, until its page has taken
    /// the place it was left at.
    @ObservationIgnored private var returnedRoute: AppRoute?

    func scrollOffset(for route: AppRoute) -> CGFloat? { scrollOffsets[route] }

    func rememberScrollOffset(_ offset: CGFloat, for route: AppRoute) {
        guard offset.isFinite else { return }
        // ScrollPosition uses native content coordinates, including the
        // negative offset at the top beneath a macOS toolbar.
        scrollOffsets[route] = offset
    }

    /// Where a page appearing for `route` should scroll to: where it was
    /// left, once, when Back or Forward returned to it. `nil` for a new
    /// visit, which starts at the top.
    func takeScrollRestoration(for route: AppRoute) -> CGFloat? {
        guard returnedRoute == route else { return nil }
        returnedRoute = nil
        return scrollOffsets[route]
    }

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    /// Navigates, pushing the current route onto the back stack. The open task
    /// stays open, as it does going Back and Forward: the inspector belongs to
    /// the window, not to the screen.
    func go(to newRoute: AppRoute) {
        guard newRoute != route else { return }
        backStack.append(Visit(route: route, scrollOffset: scrollOffsets[route]))
        forwardStack.removeAll()
        route = newRoute
        startVisit(returning: nil)
        revealedDocumentListID = nil
        isTriageVisit = false
        contentReveal = nil
        clearSelection()
        trimHistory()
    }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(Visit(route: route, scrollOffset: scrollOffsets[route]))
        route = previous.route
        startVisit(returning: previous)
        revealedDocumentListID = nil
        isTriageVisit = false
        contentReveal = nil
        clearSelection()
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(Visit(route: route, scrollOffset: scrollOffsets[route]))
        route = next.route
        startVisit(returning: next)
        revealedDocumentListID = nil
        isTriageVisit = false
        contentReveal = nil
        clearSelection()
    }

    /// Replaces the current route without disturbing history — used when the
    /// list you are viewing is deleted underneath you.
    func replace(with newRoute: AppRoute) {
        route = newRoute
        startVisit(returning: nil)
        revealedDocumentListID = nil
        isTriageVisit = false
        contentReveal = nil
        openTaskID = nil
        clearSelection()
    }

    /// Retarget both the visible route and history so Back/Forward cannot open
    /// the identity removed by a confirmed label merge.
    func retargetLabel(from sourceID: UUID, to destinationID: UUID) {
        let source = AppRoute.label(sourceID)
        let destination = AppRoute.label(destinationID)
        if route == source { route = destination }
        backStack = backStack.map { $0.route == source ? Visit(route: destination, scrollOffset: $0.scrollOffset) : $0 }
        forwardStack = forwardStack.map { $0.route == source ? Visit(route: destination, scrollOffset: $0.scrollOffset) : $0 }
        if returnedRoute == source { returnedRoute = nil }
    }

    func openTask(_ id: UUID?) {
        if contentReveal?.taskID != id { contentReveal = nil }
        openTaskID = id
    }

    func closeTask() {
        openTaskID = nil
        if contentReveal?.taskID != nil { contentReveal = nil }
    }

    /// The page on show is the route's new visit: back where `visit` left it,
    /// or from the top.
    private func startVisit(returning visit: Visit?) {
        scrollOffsets[route] = visit?.scrollOffset
        returnedRoute = visit?.scrollOffset == nil ? nil : route
    }

    private func trimHistory() {
        if backStack.count > 100 { backStack.removeFirst(backStack.count - 100) }
    }
}
