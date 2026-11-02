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
    var sheet: PhoneSheet? {
        didSet {
            if case let .capture(request) = sheet, request.id == captureListenRequestID { return }
            captureListenRequestID = nil
        }
    }
    var captureListenRequestID: UUID?
    /// The Settings sheet's own stack: Activity and Trash push inside it.
    var settingsPath: [PhoneRoute] = []
    var cover: PhoneCover? {
        didSet { if cover != oldValue { coverPath = [] } }
    }
    /// The cover's own stack: a task opened from Working pushes inside it, so
    /// Back returns to the timer rather than to the tab underneath.
    var coverPath: [PhoneRoute] = []
    /// What's typed in Capture and not yet added, kept while something else
    /// takes the screen (a link, a notification, Working) so the next Capture
    /// starts from it. Add and a confirmed Discard drop it.
    var captureDraft: CaptureDraft?
    /// Tasks heard and not yet added, kept with the draft while the app runs.
    @ObservationIgnored var capturedSpoken: [SpokenTask] = []
    /// Counts the times everything on show was put away for somewhere else (a
    /// link, a notification, a cover), so a screen's own sheet closes too
    /// rather than staying over a page that changed under it.
    private(set) var arrivals = 0
    /// Each tab's request to scroll its root page to the top, as tapping the
    /// tab on show at its root asks.
    private(set) var scrollsToTop: [PhoneTab: Int] = [:]
    /// A task page closed by moving its task to Trash, until Undo brings the
    /// task back to reopen it, where it was left.
    @ObservationIgnored private var trashedPage: (task: UUID, tab: PhoneTab, path: [PhoneRoute])?
    /// The cards Triage deals while it's up, which its switch changes: the
    /// Inbox's, or the lists' tasks with no date.
    var triageMode: TriageMode = .inbox
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
        if let cover, let index = coverPath.lastIndex(of: route) {
            return index > 0 ? coverPath[index - 1] : coverRoute(cover)
        }
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
        if let cover { return coverPath.last ?? coverRoute(cover) }
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

    /// A dock tab. Tapping the tab on show goes back to its root, and at its
    /// root to the top of the page, as iOS tab bars do.
    func select(_ tab: PhoneTab) {
        if self.tab == tab {
            if path(for: tab).isEmpty {
                scrollsToTop[tab, default: 0] += 1
            } else {
                setPath([], for: tab)
            }
        } else {
            self.tab = tab
        }
    }

    /// How many times `tab`'s root page has been asked to scroll to its top.
    func scrollToTopRequests(for tab: PhoneTab) -> Int { scrollsToTop[tab] ?? 0 }

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
            if cover != nil {
                coverPath = Self.pushing(route, onto: coverPath)
            } else if case .settings = sheet {
                settingsPath = Self.pushing(route, onto: settingsPath)
            } else {
                if sheet != nil { sheet = nil }
                setPath(Self.pushing(route, onto: path(for: tab)), for: tab)
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
            // Triage already up switches to the cards asked for.
            if case let .triage(mode) = route { triageMode = mode }
            present(cover: route == .working ? .working : .triage)
        case .settingsStack:
            if case .settings = sheet {
                settingsPath = Self.pushing(route, onto: settingsPath)
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
        case let .triage(mode):
            // Whatever is up closes first, inside present(cover:).
            tab = .inbox
            inboxPath = []
            triageMode = mode
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

    /// Goes back one screen in front: the cover's stack, the Settings sheet's,
    /// or the tab's.
    func pop() {
        if cover != nil, !coverPath.isEmpty {
            coverPath.removeLast()
        } else if case .settings = sheet, !settingsPath.isEmpty {
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
        arrivals += 1
    }

    /// Hides the dock while `token`'s screen is up (Select mode's bulk bar);
    /// pass false to show it again.
    func hidesDock(_ hidden: Bool, for token: UUID) {
        if hidden { dockHiders.insert(token) } else { dockHiders.remove(token) }
    }

    /// `route` on top of `path`; a screen already in it is gone back to
    /// rather than pushed again, so links between pages (a task and its
    /// history, Activity and a task) never pile up a stack to back out of.
    static func pushing(_ route: PhoneRoute, onto path: [PhoneRoute]) -> [PhoneRoute] {
        guard let index = path.lastIndex(of: route) else { return path + [route] }
        return Array(path.prefix(through: index))
    }

    /// The screen a cover shows at its root.
    private func coverRoute(_ cover: PhoneCover) -> PhoneRoute {
        cover == .working ? .working : .triage(triageMode)
    }

    private func captureSheet(_ route: PhoneRoute) -> PhoneSheet {
        if case let .capture(request) = route { return .capture(request) }
        return .capture(CaptureRequest())
    }

    private func present(sheet newSheet: PhoneSheet) {
        if case let .capture(current) = sheet, case let .capture(incoming) = newSheet {
            if incoming.listens { captureListenRequestID = current.id }
            return
        }
        guard sheet != newSheet || pendingModal != nil else { return }
        presentOnceClosed { $0.sheet = newSheet }
    }

    private func present(cover newCover: PhoneCover) {
        guard cover != newCover || pendingModal != nil else {
            // Working asked for while it's up comes back to the timer.
            coverPath = []
            return
        }
        presentOnceClosed { $0.cover = newCover }
    }

    /// Sheets and covers present from the root, which can't present one while
    /// another is up or going: whatever is up goes first, then the next once
    /// it has, however the change came (a tap, a link, a notification).
    private func presentOnceClosed(_ present: @escaping @MainActor (PhoneNavigator) -> Void) {
        pendingModal?.cancel()
        pendingModal = nil
        arrivals += 1
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

    // MARK: Trash from a task's page

    /// The task's page, on show, closes as its task goes to Trash; Undo, from
    /// where it was left, opens it again.
    func closeTrashedPage(of taskID: UUID) {
        guard topRoute == .taskDetail(taskID) || coverPath.last == .taskDetail(taskID)
            || (sheet == .settings && settingsPath.last == .taskDetail(taskID)) else { return }
        pop()
        trashedPage = cover == nil && sheet == nil ? (taskID, tab, path(for: tab)) : nil
    }

    /// After an Undo: the page closed for its task's trashing comes back if
    /// the task did and nothing else moved since.
    func reopenTrashedPage(taskExists: (UUID) -> Bool) {
        guard let page = trashedPage else { return }
        trashedPage = nil
        guard taskExists(page.task), cover == nil, sheet == nil, tab == page.tab, path(for: tab) == page.path else { return }
        setPath(page.path + [.taskDetail(page.task)], for: tab)
    }

    // MARK: Restoring

    /// Where the phone is, as its scene keeps it to come back to after the
    /// system has ended the app in the background: the tab and each tab's
    /// stack, Today's view, and Settings, Capture or a cover with what they
    /// showed. Quitting the app clears it, as the system clears a scene's
    /// storage then.
    struct Place: Codable, Equatable {
        var tab: PhoneTab = .today
        var today: [PhoneRoute] = []
        var inbox: [PhoneRoute] = []
        var lists: [PhoneRoute] = []
        var work: [PhoneRoute] = []
        var showsTimeline = false
        var timelineDay: Date?
        var sheet: PhoneSheet?
        var settingsPath: [PhoneRoute] = []
        var cover: PhoneCover?
        var coverPath: [PhoneRoute] = []
        var triageMode: TriageMode = .inbox
        var captureDraft: CaptureDraft?
    }

    var place: Place {
        Place(tab: tab, today: todayPath, inbox: inboxPath, lists: listsPath, work: workPath,
              showsTimeline: todayMode == .timeline, timelineDay: timelineDay, sheet: sheet,
              settingsPath: sheet == .settings ? settingsPath : [], cover: cover, coverPath: cover == nil ? [] : coverPath,
              triageMode: triageMode, captureDraft: captureDraft)
    }

    /// Whether nothing has moved the phone since launch: Today's list, every
    /// stack at its root and nothing on top. A place is only put back here,
    /// never over where a launch route or a link already went.
    var isAtLaunch: Bool {
        tab == .today && todayMode == .list && sheet == nil && cover == nil
            && PhoneTab.allCases.allSatisfy { path(for: $0).isEmpty }
    }

    /// Puts the phone back at `place`, keeping only what can still be shown:
    /// each stack keeps the screens pushed there (and Settings' its own), a
    /// browsed day that's past goes back to today, Working only comes back
    /// while there is work, and Capture never starts listening by itself.
    /// The caller repairs the stacks against the library afterwards.
    func restore(_ place: Place, today: Date, hasWork: Bool) {
        func pushed(_ path: [PhoneRoute]) -> [PhoneRoute] { path.filter { $0.presentation == .push } }
        tab = place.tab
        todayPath = pushed(place.today)
        inboxPath = pushed(place.inbox)
        listsPath = pushed(place.lists)
        workPath = pushed(place.work)
        todayMode = place.showsTimeline ? .timeline : .list
        // The toggle didn't move; there's nothing to slide from.
        switchedFrom = nil
        timelineDay = place.timelineDay.flatMap { $0 >= today ? $0 : nil }
        triageMode = place.triageMode
        captureDraft = place.captureDraft
        switch place.sheet {
        case .settings:
            settingsPath = place.settingsPath.filter { $0.presentation == .push || $0.presentation == .settingsStack }
            sheet = .settings
        case let .capture(request):
            var request = request
            request.listens = false
            sheet = .capture(request)
        case nil:
            if let cover = place.cover, cover != .working || hasWork {
                self.cover = cover
                coverPath = pushed(place.coverPath)
            }
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
        let covered = repaired(coverPath)
        if covered != coverPath { coverPath = covered }
        if case let .capture(request) = sheet, let listID = request.listID, resolveList(listID) == nil {
            // The sheet keeps what's typed; the list it started on is gone.
            var fixed = request
            fixed.listID = nil
            sheet = .capture(fixed)
        }
    }
}

/// What Capture held when it went: the text typed, the list it was going to,
/// a date picked for it and its note.
struct CaptureDraft: Codable, Equatable {
    var text: String
    var listID: UUID?
    var dueDate: CaptureDueDate = .automatic
    /// Optional, so a place saved before notes reads back as it was.
    var note: String?
}
