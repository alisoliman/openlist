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
    case activity
    case tasks
    case lists
    case list(UUID)
    case label(UUID)
    case completed
    case trash
    case settings

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

    /// The list a reveal opened as a document for this visit only. Leaving the
    /// list or choosing a presentation ends it; it is never saved.
    private var revealedDocumentListID: UUID?

    /// The Inbox shown as triage for this visit only, as the widget's Triage
    /// link asks, whatever this Mac chose for it. Leaving the Inbox or
    /// choosing a presentation ends it; it is never saved.
    private var isTriageVisit = false

    /// Lists open as their document, and the Inbox as triage, until this Mac
    /// chooses otherwise for them.
    func listViewMode(for listID: UUID) -> ListViewMode {
        if listID == revealedDocumentListID, route == .list(listID) { return .document }
        if isTriageVisit, listID == inboxListID, route == .inbox { return .tasks }
        return listViewModes[listID] ?? defaultViewMode(for: listID)
    }

    /// Turns the Inbox on show to triage until it is left, even where this Mac
    /// shows it as a document.
    func showInboxTriage() {
        guard route == .inbox, let inboxListID else { return }
        let shown = listViewMode(for: inboxListID)
        isTriageVisit = true
        guard shown != .tasks else { return }
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
        if route == .list(listID) || (route == .inbox && listID == inboxListID) {
            contentReveal = nil
            clearSelection()
        }
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

    /// The task whose detail panel is open, if any.
    var openTaskID: UUID?

    /// Blocks selected in the current document, for multi-select actions.
    var selection: Set<UUID> = []
    private(set) var rowSelection = BlockSelection()
    private(set) var isSelectingRows = false
    private(set) var rowFocusRequest: UUID?

    /// Private drag identity is per environment/library, not a persisted block ID.
    let blockDragSessionID = UUID()
    var activeLegacyBlockDragID: UUID?

    var orderedSelection: [UUID] { rowSelection.ordered(selection) }

    func selectRow(_ id: UUID, gesture: BlockSelection.Gesture, scope: UUID, visible: [UUID]) {
        rowFocusRequest = nil
        selection = rowSelection.select(id, gesture: gesture, in: scope, visible: visible, selected: selection)
        isSelectingRows = true
    }

    func stepRowSelection(_ direction: Int, extending: Bool, scope: UUID, visible: [UUID]) {
        selection = rowSelection.step(direction, extending: extending, in: scope, visible: visible, selected: selection)
        isSelectingRows = true
        rowFocusRequest = rowSelection.focusID
    }

    func finishRowFocusRequest(_ id: UUID) {
        if rowFocusRequest == id { rowFocusRequest = nil }
    }

    func reconcileSelection(scope: UUID, visible: [UUID]) {
        selection = rowSelection.reconcile(in: scope, visible: visible, selected: selection)
    }

    func selectForEditing(_ id: UUID, scope: UUID, visible: [UUID]) {
        rowFocusRequest = nil
        selection = rowSelection.select(id, gesture: .replace, in: scope, visible: visible, selected: selection)
        isSelectingRows = false
    }

    func clearSelection() {
        selection.removeAll()
        rowSelection.clear()
        isSelectingRows = false
        rowFocusRequest = nil
    }

    func beginBlockDrag(_ id: UUID, scope: UUID, visible: [UUID]) -> String {
        if rowSelection.scopeID != scope || !selection.contains(id) {
            selectRow(id, gesture: .replace, scope: scope, visible: visible)
        }
        let ids = orderedSelection
        activeLegacyBlockDragID = ids.count == 1 ? ids.first : nil
        return DragPayload.encodeBlocks(ids, session: blockDragSessionID)
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
        go(to: .list(request.listID))
        // Exact-content navigation must reveal notes and collapsed hierarchy,
        // including when this list was last viewed as a task-only queue. The
        // document is for this visit: the list's saved presentation stays.
        revealedDocumentListID = request.listID
        openTaskID = request.taskID
        selection = request.blockID.map { [$0] } ?? []
        contentReveal = request
        searchActivation &+= 1
    }

    func finishReveal() { contentReveal = nil }

    private var backStack: [AppRoute] = []
    private var forwardStack: [AppRoute] = []
    @ObservationIgnored private var scrollOffsets: [AppRoute: CGFloat] = [:]

    func scrollOffset(for route: AppRoute) -> CGFloat? { scrollOffsets[route] }

    func rememberScrollOffset(_ offset: CGFloat, for route: AppRoute) {
        guard offset.isFinite else { return }
        // ScrollPosition uses native content coordinates, including the
        // negative offset at the top beneath a macOS toolbar.
        scrollOffsets[route] = offset
    }

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    /// Navigates, pushing the current route onto the back stack. The open task
    /// stays open, as it does going Back and Forward: the inspector belongs to
    /// the window, not to the screen.
    func go(to newRoute: AppRoute) {
        guard newRoute != route else { return }
        backStack.append(route)
        forwardStack.removeAll()
        route = newRoute
        revealedDocumentListID = nil
        isTriageVisit = false
        contentReveal = nil
        clearSelection()
        trimHistory()
    }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(route)
        route = previous
        revealedDocumentListID = nil
        isTriageVisit = false
        contentReveal = nil
        clearSelection()
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(route)
        route = next
        revealedDocumentListID = nil
        isTriageVisit = false
        contentReveal = nil
        clearSelection()
    }

    /// Replaces the current route without disturbing history — used when the
    /// list you are viewing is deleted underneath you.
    func replace(with newRoute: AppRoute) {
        route = newRoute
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
