//
//  WidgetLinkRouter.swift
//  openlist
//

import Foundation

/// The navigation the main window's screens use. `Workbench` provides it in
/// the app, so a widget link lands exactly as a click in the sidebar would.
protocol WidgetLinkScreens: AnyObject {
    func go(_ route: AppRoute)
    /// The Calendar on a range that shows `day`, whichever range it was left on.
    func showOnCalendar(_ day: Date)
}

/// Takes the app to what a widget was showing when it was clicked.
///
/// Widget links arrive through the same URL handlers as item links, often
/// while the app is still launching. Screen links wait until the library is
/// open and the main window is on screen: bootstrap puts every launch on
/// Today, and a route set before that would be overwritten. They then bring
/// Openlist forward.
///
/// Quick Add links wait for the library only. Quick Add is a panel floating
/// over whatever app is in front (`QuickCapturePanel`), so it needs no main
/// window, and the router never activates Openlist for it. macOS may, as it
/// opens the link; the card undoes that as it closes.
@MainActor
final class WidgetLinkRouter {
    private let store: Store
    private let navigator: Navigator
    private let screens: any WidgetLinkScreens
    /// Opens Quick Add for a request. The app installs it.
    var capture: ((QuickCaptureRequest) -> Void)?
    /// Makes Openlist the active app once a link has shown its screen. The
    /// app installs it; Quick Add never calls it.
    var activate: () -> Void = {}
    /// Says that a task or list link's target is gone, as an item link's
    /// notice does: a link that silently does nothing explains nothing.
    var unavailable: () -> Void = {}
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

    /// Opens what can open now, in the order the links came. A screen link
    /// waiting for the window holds back the ones after it, so a capture
    /// never jumps ahead of a screen clicked first.
    private func drain() {
        guard isStoreReady else { return }
        while let link = pending.first {
            guard isWindowReady || link.isCapture else { return }
            pending.removeFirst()
            open(link)
        }
    }

    private func open(_ link: WidgetLink) {
        switch link {
        case let .capture(listID):
            // A list's "Add to …" starts the card on that list; without one,
            // Quick Add starts on the Inbox. An open card keeps what has been
            // typed and moves to the request's list.
            capture?(QuickCaptureRequest(listID: listID))
        case .captureToday:
            // As New task on the app's Today: still the Inbox, but a task typed
            // without a date is due today, so it lands on the widget it came from.
            capture?(QuickCaptureRequest(dueToday: true))
        case .inbox:
            // This Mac's choice for the Inbox, even straight after a triage visit.
            show(.inbox)
            navigator.followInboxPresentation()
            activate()
        case .triage:
            // Triage is the Inbox's card view, which the document presentation
            // replaces. The cards are for this visit: an Inbox kept as a
            // document stays one the next time it opens. After `show`, since
            // arriving on the Inbox starts a fresh visit.
            show(.inbox)
            navigator.showInboxTriage()
            activate()
        case .today:
            show(.today)
            activate()
        case .calendar:
            // Up Next and Agenda: today's work, whichever range the Calendar was left on.
            navigator.isShortcutSheetOpen = false
            screens.showOnCalendar(.now)
            activate()
        case .activity:
            show(.activity)
            activate()
        case let .list(id):
            // Follows a list merged into another since the widget last refreshed.
            guard let list = store.list(id: id) else { return missing() }
            reveal(.list(list.id))
        case let .task(id):
            guard let task = store.block(id: id), task.isTask, task.trashID == nil,
                  store.list(id: task.listID) != nil else { return missing() }
            reveal(.block(task.id))
        }
    }

    /// Lands on a list or a task as an item link does (`LocalLinkNavigation`):
    /// a task's row focused with the inspector open, and the folded parents
    /// and done lines on its path shown for the visit, since a widget lists
    /// subtasks and completed tasks the page may be hiding.
    private func reveal(_ destination: SearchDestination) {
        let request: ContentReveal
        do {
            let lists = store.allLists(includeArchived: true)
            var blocks: [Block] = []
            if case let .block(id) = destination, let listID = store.block(id: id)?.listID {
                blocks = store.blocks(inList: listID)
            }
            request = try ContentReveal.resolve(destination, blocks: blocks, lists: lists)
        } catch {
            return missing()
        }
        navigator.isSearchOpen = false
        navigator.isCommandPaletteOpen = false
        navigator.isShortcutSheetOpen = false
        navigator.reveal(request)
        activate()
    }

    /// Leaves the window where it is, and says why.
    private func missing() {
        navigator.isShortcutSheetOpen = false
        unavailable()
        activate()
    }

    private func show(_ route: AppRoute) {
        navigator.isShortcutSheetOpen = false
        screens.go(route)
    }
}

extension WidgetLink {
    /// Quick Add, which opens without the main window.
    var isCapture: Bool {
        switch self {
        case .capture, .captureToday: true
        default: false
        }
    }
}
