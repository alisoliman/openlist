//
//  PhoneNavigator.swift
//  OpenlistiOS
//

import Foundation
import Observation
import SwiftUI

/// Where the phone is: the dock's tab, each tab's navigation stack, Today's
/// list or timeline, and the sheet and cover on top. Screens move with
/// `open(_:)`, which presents each route the way the design does; links and
/// notifications use `show(_:)`, which lands from wherever the app was.
@Observable
@MainActor
final class PhoneNavigator {
    enum TodayMode: Hashable { case list, timeline }

    var tab: PhoneTab = .today
    var todayPath: [PhoneRoute] = []
    var inboxPath: [PhoneRoute] = []
    var listsPath: [PhoneRoute] = []
    var workPath: [PhoneRoute] = []
    /// Today's list, or the same day as a timeline in its place.
    var todayMode: TodayMode = .list {
        didSet { if todayMode != oldValue { switchedFrom = oldValue } }
    }
    /// The view Today just switched from, until the new one's toggle reads it.
    @ObservationIgnored private var switchedFrom: TodayMode?
    /// The day the timeline shows; nil for today.
    var timelineDay: Date?
    var sheet: PhoneSheet?
    /// The Settings sheet's own stack: Activity and Trash push inside it.
    var settingsPath: [PhoneRoute] = []
    var cover: PhoneCover?
    /// The system Inbox, which the Inbox tab shows. Set once the store is ready
    /// and again after every sync: another device's Inbox can win the merge.
    var inboxListID: UUID?
    /// Screens that take the dock's place while they're up, such as Select's
    /// bulk bar. See `hidesDock(_:)`.
    private(set) var dockHiders: Set<UUID> = []

    #if DEBUG
    /// The component gallery, for design review. Also opens at launch with
    /// `OpenlistComponentGallery=1` in a review session's environment.
    var showsComponentGallery = ReviewSession.identifier != nil
        && ProcessInfo.processInfo.environment["OpenlistComponentGallery"] == "1"

    /// Opens the gallery once any sheet has gone.
    func showComponentGallery() {
        let wait = sheet != nil || cover != nil
        dismissModals()
        Task { [weak self] in
            if wait { try? await Task.sleep(for: .milliseconds(450)) }
            self?.showsComponentGallery = true
        }
    }
    #endif

    /// A sheet or cover waiting for the one on show to go first.
    @ObservationIgnored private var pendingModal: Task<Void, Never>?

    func path(for tab: PhoneTab) -> [PhoneRoute] {
        switch tab {
        case .today: todayPath
        case .inbox: inboxPath
        case .lists: listsPath
        case .work: workPath
        }
    }

    func setPath(_ path: [PhoneRoute], for tab: PhoneTab) {
        switch tab {
        case .today: todayPath = path
        case .inbox: inboxPath = path
        case .lists: listsPath = path
        case .work: workPath = path
        }
    }

    /// The current tab's root screen.
    var tabRoot: PhoneRoute {
        switch tab {
        case .today: todayMode == .timeline ? .timeline : .today
        case .inbox: .inbox
        case .lists: .lists
        case .work: .work
        }
    }

    /// The screen under `route` in the stack it's on: what its back link names.
    func screen(below route: PhoneRoute) -> PhoneRoute {
        if case .settings = sheet, let index = settingsPath.lastIndex(of: route) {
            return index > 0 ? settingsPath[index - 1] : .settings
        }
        let path = path(for: tab)
        if let index = path.lastIndex(of: route) { return index > 0 ? path[index - 1] : tabRoot }
        for other in PhoneTab.allCases where other != tab {
            let path = self.path(for: other)
            if let index = path.lastIndex(of: route) {
                return index > 0 ? path[index - 1] : other == .today ? .today : other == .inbox ? .inbox : other == .work ? .work : .lists
            }
        }
        return tabRoot
    }

    /// The pushed route on show in the current tab, if any.
    var topRoute: PhoneRoute? { path(for: tab).last }

    /// The screen on show, modals included.
    var visibleRoute: PhoneRoute {
        if let cover { return cover == .working ? .working : .triage }
        switch sheet {
        case .settings: return settingsPath.last ?? .settings
        case let .capture(request): return .capture(request)
        case nil: break
        }
        if let top = topRoute { return top }
        switch tab {
        case .today: return todayMode == .timeline ? .timeline : .today
        case .inbox: return .inbox
        case .lists: return .lists
        case .work: return .work
        }
    }

    /// Task detail carries its own action dock, and Select its bulk bar.
    var showsDock: Bool {
        if case .taskDetail = topRoute { return false }
        return dockHiders.isEmpty
    }

    /// Whether the screen on show has its own bar where the dock would be:
    /// Task detail's actions, Select's bulk bar. The tray rises above it.
    var showsScreenBar: Bool {
        if case .taskDetail = topRoute { return true }
        return !dockHiders.isEmpty
    }

    /// What the dock's + captures into: the list on show, else the Inbox.
    var captureRequest: CaptureRequest {
        if case let .list(id) = topRoute { return CaptureRequest(listID: id) }
        return CaptureRequest()
    }

    // MARK: Moving

    /// A dock tab. Tapping the tab on show goes back to its root, as iOS tab
    /// bars do.
    func select(_ tab: PhoneTab) {
        if self.tab == tab {
            setPath([], for: tab)
        } else {
            self.tab = tab
        }
    }

    /// Opens `route` from the screen on show: a push goes on the stack in
    /// front (the Settings sheet's, when it's up), a tab route switches tab.
    func open(_ route: PhoneRoute) {
        switch route.presentation {
        case let .tab(tab):
            dismissModals()
            self.tab = tab
            setPath([], for: tab)
            if tab == .today { todayMode = .list; timelineDay = nil }
        case let .mode(tab):
            dismissModals()
            self.tab = tab
            setPath([], for: tab)
            todayMode = .timeline
        case .push:
            if cover != nil { cover = nil }
            if case .settings = sheet {
                settingsPath.append(route)
            } else {
                if sheet != nil { sheet = nil }
                setPath(path(for: tab) + [route], for: tab)
            }
        case .sheet:
            if route == .settings {
                guard sheet != .settings else { return }
                settingsPath = []
                present(sheet: .settings)
            } else {
                present(sheet: captureSheet(route))
            }
        case .fullScreenCover:
            present(cover: route == .working ? .working : .triage)
        case .settingsStack:
            if case .settings = sheet {
                settingsPath.append(route)
            } else {
                settingsPath = [route]
                present(sheet: .settings)
            }
        }
    }

    /// The view Today just switched from, until the page switched to has
    /// appeared: its toggle slides from there.
    var todaySwitchedFrom: TodayMode? { switchedFrom }

    /// Reads the switch once, as the page switched to appears.
    func takeTodaySwitch() -> TodayMode? {
        defer { switchedFrom = nil }
        return switchedFrom
    }

    /// The timeline in Today's place, on `day` (nil for today).
    func openTimeline(on day: Date?) {
        timelineDay = day
        open(.timeline)
    }

    /// Lands on `route` from wherever the app was, as a link or notification
    /// asks: modals close and the screen opens in its home tab, a task on the
    /// page of its list (the Inbox's tab for the Inbox's tasks).
    func show(_ route: PhoneRoute, in listID: UUID? = nil) {
        switch route {
        case .taskDetail:
            dismissModals()
            if let listID, listID != inboxListID {
                tab = .lists
                listsPath = [.list(listID), route]
            } else {
                tab = listID == nil ? .today : .inbox
                setPath([route], for: tab)
            }
        case .list:
            dismissModals()
            tab = .lists
            listsPath = [route]
        case .activity, .find:
            dismissModals()
            tab = route.home
            setPath([route], for: tab)
        case .triage:
            // Whatever is up closes first, inside present(cover:).
            tab = .inbox
            inboxPath = []
            present(cover: .triage)
        case .working:
            present(cover: .working)
        case .timeline:
            // A link to the timeline lands on today, whichever day was browsed.
            openTimeline(on: nil)
        default:
            open(route)
        }
    }

    /// Goes back one screen in front: the Settings sheet's stack, or the tab's.
    func pop() {
        if case .settings = sheet, !settingsPath.isEmpty {
            settingsPath.removeLast()
        } else {
            var path = path(for: tab)
            guard !path.isEmpty else { return }
            path.removeLast()
            setPath(path, for: tab)
        }
    }

    func dismissSheet() { sheet = nil }
    func dismissCover() { cover = nil }

    func dismissModals() {
        pendingModal?.cancel()
        pendingModal = nil
        sheet = nil
        cover = nil
    }

    /// Hides the dock while `token`'s screen is up (Select mode's bulk bar);
    /// pass false to show it again.
    func hidesDock(_ hidden: Bool, for token: UUID) {
        if hidden { dockHiders.insert(token) } else { dockHiders.remove(token) }
    }

    private func captureSheet(_ route: PhoneRoute) -> PhoneSheet {
        if case let .capture(request) = route { return .capture(request) }
        return .capture(CaptureRequest())
    }

    private func present(sheet newSheet: PhoneSheet) {
        guard sheet != newSheet || pendingModal != nil else { return }
        presentOnceClosed { $0.sheet = newSheet }
    }

    private func present(cover newCover: PhoneCover) {
        guard cover != newCover || pendingModal != nil else { return }
        presentOnceClosed { $0.cover = newCover }
    }

    /// Sheets and covers present from the root, which can't present one while
    /// another is up or going: whatever is up goes first, then the next once
    /// it has, however the change came (a tap, a link, a notification).
    private func presentOnceClosed(_ present: @escaping @MainActor (PhoneNavigator) -> Void) {
        pendingModal?.cancel()
        pendingModal = nil
        guard sheet != nil || cover != nil else { return present(self) }
        sheet = nil
        cover = nil
        pendingModal = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled, let self else { return }
            pendingModal = nil
            present(self)
        }
    }

    // MARK: After a sync

    /// Keeps every stack on screens that still exist once another device's
    /// changes arrive: a merged list's page follows the list it merged into,
    /// and a deleted, trashed or unavailable task or list leaves its stack
    /// with whatever was pushed above it.
    func repair(list resolveList: (UUID) -> UUID?, taskExists: (UUID) -> Bool) {
        func repaired(_ path: [PhoneRoute]) -> [PhoneRoute] {
            var result: [PhoneRoute] = []
            for route in path {
                switch route {
                case let .list(id):
                    guard let resolved = resolveList(id) else { return result }
                    result.append(.list(resolved))
                case let .taskDetail(id):
                    guard taskExists(id) else { return result }
                    result.append(route)
                default:
                    result.append(route)
                }
            }
            return result
        }
        for tab in PhoneTab.allCases {
            let path = path(for: tab)
            let fixed = repaired(path)
            if fixed != path { setPath(fixed, for: tab) }
        }
        let settings = repaired(settingsPath)
        if settings != settingsPath { settingsPath = settings }
        if case let .capture(request) = sheet, let listID = request.listID, resolveList(listID) == nil {
            // The sheet keeps what's typed; the list it started on is gone.
            var fixed = request
            fixed.listID = nil
            sheet = .capture(fixed)
        }
    }
}
