//
//  PhoneLinkRouter.swift
//  OpenlistiOS
//

import Foundation

/// Opens openlist:// links on the phone: a widget's (`WidgetLink`, the same
/// URLs the Mac's widgets use) and item links pasted into notes (`LocalLink`),
/// plus a notification's task.
///
/// The Mac's `WidgetLinkRouter` and `LocalLinkNavigation` drive its sidebar
/// `Navigator`; the phone keeps their contract rather than their navigator.
/// Links are parsed and resolved by the same shared code, held until the
/// library is open and the window is on screen (a launch lands on Today, and
/// an earlier route would be overwritten), and then opened in the order they
/// came. A widget link is tried first, then an item link, so a link that
/// can't open says why instead of doing nothing.
@MainActor
final class PhoneLinkRouter {
    private enum Delivery {
        case url(URL)
        case task(UUID)
    }

    private let store: Store
    private let navigator: PhoneNavigator
    private let libraryID: UUID?
    /// Whether another device's item links may open here: with iCloud on, a
    /// task or list keeps its identity on every device, but each device's
    /// library has its own.
    var acceptsOtherLibraries: () -> Bool = { false }
    /// Says why a link didn't open. The environment puts it in the tray.
    var unavailable: (String) -> Void = { _ in }
    private var pending: [Delivery] = []
    private var isStoreReady = false
    private var isWindowReady = false

    init(store: Store, navigator: PhoneNavigator, libraryID: UUID?) {
        self.store = store
        self.navigator = navigator
        self.libraryID = libraryID
    }

    /// Queues an openlist:// URL, and returns whether it was one (a widget's
    /// or an item's) rather than something for the system.
    @discardableResult
    func receive(_ url: URL) -> Bool {
        guard WidgetLink.isWidgetLink(url) || url.scheme == LocalLink.scheme else { return false }
        pending.append(.url(url))
        drain()
        return true
    }

    /// A notification's task, once the library and window are ready.
    func openTask(_ id: UUID) {
        pending.append(.task(id))
        drain()
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
        let deliveries = pending
        pending.removeAll()
        for delivery in deliveries {
            switch delivery {
            case let .url(url):
                if let link = WidgetLink(url: url) { open(link) } else { openItem(url) }
            case let .task(id):
                showTask(id)
            }
        }
    }

    private func open(_ link: WidgetLink) {
        switch link {
        case let .capture(listID):
            navigator.open(.capture(CaptureRequest(listID: listID.flatMap { store.list(id: $0)?.id })))
        case .captureToday:
            navigator.open(.capture(CaptureRequest(dueToday: true)))
        case .inbox:
            navigator.show(.inbox)
        case .triage:
            navigator.show(.triage)
        case .today:
            navigator.show(.today)
        case .calendar:
            navigator.show(.timeline)
        case .activity:
            navigator.show(.activity)
        case .working:
            navigator.show(.working)
        case let .list(id):
            // Follows a list merged into another since the widget last refreshed.
            guard let list = store.list(id: id) else { return missing(LocalLinkError.targetUnavailable) }
            show(list)
        case let .task(id):
            showTask(id)
        }
    }

    private func openItem(_ url: URL) {
        do {
            let link = try LocalLink.parse(url)
            guard let libraryID else { throw LocalLinkError.identityUnavailable }
            guard link.libraryID == libraryID || acceptsOtherLibraries() else { throw LocalLinkError.wrongLibrary }
            switch link.target {
            case let .task(id): showTask(id)
            case let .list(id):
                guard let list = store.list(id: id) else { throw LocalLinkError.targetUnavailable }
                show(list)
            }
        } catch {
            missing(error as? LocalLinkError ?? .targetUnavailable)
        }
    }

    private func show(_ list: TaskList) {
        if list.isSystemInbox { navigator.show(.inbox) } else { navigator.show(.list(list.id)) }
    }

    private func showTask(_ id: UUID) {
        guard let task = store.block(id: id), task.isTask, task.trashID == nil,
              let list = store.list(id: task.listID) else { return missing(LocalLinkError.targetUnavailable) }
        navigator.show(.taskDetail(task.id), in: list.id)
    }

    private func missing(_ error: LocalLinkError) {
        unavailable(error.errorDescription ?? "That link can’t be opened.")
    }
}
