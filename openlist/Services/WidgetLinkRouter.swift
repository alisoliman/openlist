//
//  WidgetLinkRouter.swift
//  openlist
//

import Foundation

/// The navigation the main window's screens use. `Workbench` provides it in
/// the app, so a widget link lands exactly as a click in the sidebar would.
protocol WidgetLinkScreens: AnyObject {
    func go(_ route: AppRoute)
    /// The screen that shows a list: the Inbox list is the Inbox screen.
    func route(for list: TaskList) -> AppRoute
    /// Opens a task in the inspector, with its row focused.
    func inspect(_ id: UUID?)
}

/// Takes the app to what a widget was showing when it was clicked.
///
/// Widget links arrive through the same URL handlers as item links, often
/// while the app is still launching. They wait until the library is open and
/// the main window is on screen: bootstrap puts every launch on Today, and a
/// route set before that would be overwritten.
///
/// Quick Add links wait for the main window too, and it comes forward with
/// the Quick Add panel even when it was closed, unlike Quick Add from the menu
/// bar or the shortcut. That is deliberate: only the main scene takes URLs,
/// so its window is back on screen by the time a link gets here, and it is
/// what installs the opener Quick Add needs. A capture that left the main
/// window alone would need the Quick Add scene to take capture URLs itself,
/// a change to scene matching that these checks cannot cover.
@MainActor
final class WidgetLinkRouter {
    private let store: Store
    private let navigator: Navigator
    private let screens: any WidgetLinkScreens
    /// Opens the Quick Add window for a request. The app installs it; only a
    /// view can open windows.
    var capture: ((TaskCaptureRequest) -> Void)?
    private var pending: [WidgetLink] = []
    private var isStoreReady = false
    private var isWindowReady = false

    init(store: Store, navigator: Navigator, screens: any WidgetLinkScreens) {
        self.store = store
        self.navigator = navigator
        self.screens = screens
    }

    /// Queues a widget URL, and returns whether it was one this build opens.
    /// Malformed ones, and the other build's, are refused here; the app's
    /// callers go through `AppEnvironment.openLink`, which hands those to
    /// item-link handling so its notice says what is wrong.
    @discardableResult
    func receive(_ url: URL) -> Bool {
        guard let link = WidgetLink(url: url) else { return false }
        pending.append(link)
        drain()
        return true
    }

    func storeReady() {
        isStoreReady = true
        drain()
    }

    func windowReady(_ value: Bool) {
        isWindowReady = value
        drain()
    }

    private func drain() {
        guard isStoreReady, isWindowReady else { return }
        let links = pending
        pending.removeAll()
        for link in links { open(link) }
    }

    private func open(_ link: WidgetLink) {
        switch link {
        case let .capture(listID):
            // A list's "Add to …" files into that list, and appends as capture
            // from its own Tasks screen does. The Inbox's prepends, as every
            // Inbox capture does; it still starts in the Inbox, so it moves a
            // Quick Add draft aimed at another list. Without a list, Quick Add
            // starts in the Inbox.
            let appends = listID.flatMap { store.list(id: $0) }.map { !$0.isSystemInbox } ?? false
            capture?(TaskCaptureRequest(suggestedListID: listID, startsInSuggestedList: listID != nil,
                                        appendsToSuggestedList: appends))
        case .captureToday:
            // As New task on the app's Today: still the Inbox, but a task typed
            // without a date is due today, so it lands on the widget it came from.
            capture?(TaskCaptureRequest(dueTodayWhenUndated: true))
        case .inbox:
            show(.inbox)
        case .triage:
            // Triage is the Inbox's card view, which the document presentation
            // replaces. The cards are for this visit: an Inbox kept as a
            // document stays one the next time it opens. After `show`, since
            // arriving on the Inbox starts a fresh visit.
            show(.inbox)
            navigator.triageInbox()
        case .today:
            show(.today)
        case .calendar:
            show(.calendar)
        case .activity:
            show(.activity)
        case let .list(id):
            // Follows a list merged into another since the widget last refreshed.
            guard let list = store.list(id: id) else { return }
            show(screens.route(for: list))
        case let .task(id):
            guard let task = store.block(id: id), task.isTask, let list = store.list(id: task.listID) else { return }
            show(screens.route(for: list))
            screens.inspect(task.id)
        }
    }

    private func show(_ route: AppRoute) {
        navigator.isShortcutSheetOpen = false
        screens.go(route)
    }
}
