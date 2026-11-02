//
//  NavigationTests.swift
//  OpenlistiOSTests
//

import Foundation
import ObjectiveC
import Testing
import UIKit
@testable import OpenlistiOS

/// Every screen has a route, and each route is presented the way the design
/// presents it.
@MainActor
struct NavigationTests {
    @Test func explicitVoiceReachesAnExistingTypedCapture() {
        let navigator = PhoneNavigator()
        let original = CaptureRequest(listID: UUID(), dueToday: true)
        navigator.open(.capture(original))
        navigator.open(.capture(CaptureRequest()))
        #expect(navigator.sheet == .capture(original))
        #expect(navigator.captureListenRequestID == nil)
        navigator.open(.capture(CaptureRequest(listens: true)))
        #expect(navigator.sheet == .capture(original))
        #expect(navigator.captureListenRequestID == original.id)
        navigator.captureListenRequestID = nil
        navigator.open(.capture(CaptureRequest(listens: true)))
        #expect(navigator.captureListenRequestID == original.id)
        navigator.dismissSheet()
        #expect(navigator.captureListenRequestID == nil)
    }

    @Test func voiceLinkKeepsThePresentedDraftAndRequestsListening() throws {
        let phone = try TestPhone()
        phone.env.links.windowReady(true)
        let original = CaptureRequest(listID: UUID(), dueToday: true)
        phone.navigator.open(.capture(original))
        #expect(phone.env.links.receive(WidgetLink.captureVoice.url))
        #expect(phone.navigator.sheet == .capture(original))
        #expect(phone.navigator.captureListenRequestID == original.id)
    }

    static let id = UUID()
    static let allRoutes: [PhoneRoute] = [
        .today, .timeline, .activity, .taskDetail(id), .inbox, .triage(.inbox), .lists, .list(id), .find(""),
        .settings, .trash, .working, .capture(CaptureRequest()), .work, .taskHistory(id), .planHours,
    ]

    @Test func everyRouteHasItsPresentation() {
        let expected: [PhoneRoute.Presentation] = [
            .tab(.today), .mode(.today), .push, .push, .tab(.inbox), .fullScreenCover, .tab(.lists), .push, .push,
            .sheet, .settingsStack, .fullScreenCover, .sheet, .tab(.work), .push, .settingsStack,
        ]
        #expect(Self.allRoutes.map(\.presentation) == expected)
        #expect(Set(Self.allRoutes.map(\.screenIdentifier)).count == Self.allRoutes.count)
    }

    @Test func tabsHaveTheirRoots() {
        let navigator = PhoneNavigator()
        navigator.open(.inbox)
        #expect(navigator.tab == .inbox)
        #expect(navigator.visibleRoute == .inbox)
        navigator.open(.lists)
        #expect(navigator.visibleRoute == .lists)
        navigator.open(.today)
        #expect(navigator.visibleRoute == .today)
        navigator.open(.work)
        #expect(navigator.visibleRoute == .work)
        navigator.open(.taskDetail(Self.id))
        #expect(navigator.workPath == [.taskDetail(Self.id)])
        #expect(navigator.screen(below: .taskDetail(Self.id)) == .work)
        navigator.select(.work)
        #expect(navigator.workPath.isEmpty)
    }

    @Test func anotherCaptureRequestKeepsTheCurrentDraft() {
        let navigator = PhoneNavigator()
        let request = CaptureRequest(listID: Self.id, dueToday: true)
        navigator.open(.capture(request))
        navigator.open(.capture(CaptureRequest(listens: true)))
        #expect(navigator.sheet == .capture(request))
        navigator.dismissSheet()
        let voice = CaptureRequest(listens: true)
        navigator.open(.capture(voice))
        navigator.open(.capture(CaptureRequest()))
        #expect(navigator.sheet == .capture(voice))
    }

    @Test func timelineReplacesTodayInPlace() {
        let navigator = PhoneNavigator()
        navigator.open(.timeline)
        #expect(navigator.tab == .today)
        #expect(navigator.todayPath.isEmpty)
        #expect(navigator.visibleRoute == .timeline)
        navigator.open(.today)
        #expect(navigator.todayMode == .list)
    }

    @Test func pushesGoOnTheStackInFront() {
        let navigator = PhoneNavigator()
        navigator.open(.activity)
        #expect(navigator.todayPath == [.activity])
        navigator.open(.taskDetail(Self.id))
        #expect(navigator.todayPath == [.activity, .taskDetail(Self.id)])
        #expect(navigator.screen(below: .taskDetail(Self.id)) == .activity)
        #expect(navigator.screen(below: .activity) == .today)
        navigator.pop()
        #expect(navigator.visibleRoute == .activity)

        navigator.select(.lists)
        navigator.open(.list(Self.id))
        navigator.open(.find("#travel"))
        #expect(navigator.listsPath == [.list(Self.id), .find("#travel")])
        // The other tab keeps its stack.
        #expect(navigator.todayPath == [.activity])
        // Tapping the tab on show goes back to its root, and at its root to
        // the top of the page.
        navigator.select(.lists)
        #expect(navigator.listsPath.isEmpty)
        #expect(navigator.scrollToTopRequests(for: .lists) == 0)
        navigator.select(.lists)
        #expect(navigator.scrollToTopRequests(for: .lists) == 1)
        #expect(navigator.scrollToTopRequests(for: .today) == 0)
    }

    /// Links between pages, such as a task and its history or Activity and a
    /// task, go back to a page already on the stack rather than piling up.
    @Test func aScreenAlreadyOnTheStackIsGoneBackTo() {
        let navigator = PhoneNavigator()
        navigator.open(.activity)
        navigator.open(.taskDetail(Self.id))
        navigator.open(.taskHistory(Self.id))
        navigator.open(.activity)
        #expect(navigator.todayPath == [.activity])
        navigator.open(.taskDetail(Self.id))
        navigator.open(.taskDetail(Self.id))
        #expect(navigator.todayPath == [.activity, .taskDetail(Self.id)])
        #expect(PhoneNavigator.pushing(.find(""), onto: [.list(Self.id)]) == [.list(Self.id), .find("")])
    }

    @Test func taskDetailHidesTheDock() {
        let navigator = PhoneNavigator()
        #expect(navigator.showsDock)
        navigator.open(.taskDetail(Self.id))
        #expect(!navigator.showsDock)
        navigator.pop()
        let token = UUID()
        navigator.hidesDock(true, for: token)
        #expect(!navigator.showsDock)
        navigator.hidesDock(false, for: token)
        #expect(navigator.showsDock)
    }

    @Test func settingsIsASheetWithItsOwnStack() {
        let navigator = PhoneNavigator()
        navigator.open(.settings)
        #expect(navigator.sheet == .settings)
        #expect(navigator.visibleRoute == .settings)
        navigator.open(.trash)
        #expect(navigator.settingsPath == [.trash])
        #expect(navigator.visibleRoute == .trash)
        #expect(navigator.screen(below: .trash) == .settings)
        navigator.open(.activity)
        #expect(navigator.settingsPath == [.trash, .activity])
        #expect(navigator.todayPath.isEmpty)
        navigator.dismissSheet()
        navigator.open(.trash)
        #expect(navigator.sheet == .settings)
        #expect(navigator.settingsPath == [.trash])
    }

    @Test func workingAndTriageCoverEverything() {
        let navigator = PhoneNavigator()
        navigator.open(.working)
        #expect(navigator.cover == .working)
        #expect(navigator.visibleRoute == .working)
        // A screen opened from a cover pushes inside it, and Back comes back
        // to the cover's own screen.
        navigator.open(.taskDetail(Self.id))
        #expect(navigator.cover == .working)
        #expect(navigator.coverPath == [.taskDetail(Self.id)])
        #expect(navigator.visibleRoute == .taskDetail(Self.id))
        #expect(navigator.screen(below: .taskDetail(Self.id)) == .working)
        #expect(navigator.todayPath.isEmpty)
        // Working asked for again comes back to the timer.
        navigator.open(.working)
        #expect(navigator.cover == .working && navigator.coverPath.isEmpty)
        navigator.open(.taskDetail(Self.id))
        navigator.pop()
        #expect(navigator.coverPath.isEmpty && navigator.cover == .working)
        navigator.open(.taskDetail(Self.id))
        navigator.dismissCover()
        #expect(navigator.coverPath.isEmpty)
        navigator.open(.triage(.inbox))
        #expect(navigator.cover == .triage)
    }

    /// A link to Working while the Settings sheet is up waits for it to go:
    /// the root presents one modal at a time.
    @Test func aCoverWaitsForTheModalOnShowToClose() async throws {
        let navigator = PhoneNavigator()
        navigator.open(.settings)
        navigator.show(.working)
        #expect(navigator.sheet == nil && navigator.cover == nil)
        try await Task.sleep(for: .milliseconds(700))
        #expect(navigator.cover == .working)
        // And a sheet waits for a cover the same way.
        navigator.open(.capture(CaptureRequest()))
        #expect(navigator.cover == nil && navigator.sheet == nil)
        try await Task.sleep(for: .milliseconds(700))
        guard case .capture = navigator.sheet else { Issue.record("No capture sheet"); return }
    }

    @Test func captureTakesTheListOnShow() {
        let navigator = PhoneNavigator()
        #expect(navigator.captureRequest.listID == nil)
        navigator.select(.lists)
        navigator.open(.list(Self.id))
        #expect(navigator.captureRequest.listID == Self.id)
        navigator.open(.capture(navigator.captureRequest))
        guard case let .capture(request) = navigator.sheet else { Issue.record("No capture sheet"); return }
        #expect(request.listID == Self.id)
    }

    @Test func linksLandFromAnywhere() {
        let navigator = PhoneNavigator()
        navigator.open(.settings)
        let list = UUID()
        navigator.show(.taskDetail(Self.id), in: list)
        #expect(navigator.sheet == nil)
        #expect(navigator.tab == .lists)
        #expect(navigator.listsPath == [.list(list), .taskDetail(Self.id)])

        let inbox = UUID()
        navigator.inboxListID = inbox
        navigator.show(.taskDetail(Self.id), in: inbox)
        #expect(navigator.tab == .inbox)
        #expect(navigator.inboxPath == [.taskDetail(Self.id)])

        navigator.show(.triage(.inbox))
        #expect(navigator.tab == .inbox)
        #expect(navigator.cover == .triage)
    }

    /// Triage opens on the pass asked for, and asked for the other while
    /// it's up, switches to it in place.
    @Test func triageOpensOnEitherPass() {
        let navigator = PhoneNavigator()
        navigator.open(.triage(.undated))
        #expect(navigator.cover == .triage)
        #expect(navigator.visibleRoute == .triage(.undated))
        navigator.open(.triage(.inbox))
        #expect(navigator.cover == .triage)
        #expect(navigator.visibleRoute == .triage(.inbox))
        // The switch on screen sets the mode, which the route follows.
        navigator.triageMode = .undated
        #expect(navigator.visibleRoute == .triage(.undated))
        navigator.dismissCover()
        navigator.select(.lists)
        navigator.show(.triage(.undated))
        #expect(navigator.tab == .inbox)
        #expect(navigator.cover == .triage && navigator.triageMode == .undated)
        #expect(PhoneRoute.triage(.undated).presentation == .fullScreenCover)
        #expect(PhoneRoute.triage(.undated).screenIdentifier == PhoneRoute.triage(.inbox).screenIdentifier)
    }

    @Test func repairFollowsMergesAndDropsWhatsGone() {
        let navigator = PhoneNavigator()
        let merged = UUID(), canonical = UUID(), gone = UUID()
        navigator.listsPath = [.list(merged), .taskDetail(Self.id), .find("")]
        navigator.todayPath = [.activity, .taskDetail(gone)]
        navigator.repair(list: { $0 == merged ? canonical : nil }, taskExists: { $0 == Self.id })
        #expect(navigator.listsPath == [.list(canonical), .taskDetail(Self.id), .find("")])
        #expect(navigator.todayPath == [.activity])
    }

    /// Everything on show goes away for a link, a notification or a cover,
    /// and the screens' own sheets hear it, so none stays over a page that
    /// changed under it.
    @Test func arrivalsAreCounted() {
        let navigator = PhoneNavigator()
        navigator.open(.taskDetail(Self.id))
        let before = navigator.arrivals
        navigator.show(.inbox)
        #expect(navigator.arrivals > before)
        let shown = navigator.arrivals
        navigator.open(.taskDetail(Self.id))
        #expect(navigator.arrivals == shown)
    }

    // MARK: Restoring

    /// Where the phone was survives encoding, as the scene keeps it, and
    /// comes back as it was.
    @Test func aPlaceComesBackAsItWas() throws {
        let navigator = PhoneNavigator()
        navigator.select(.lists)
        navigator.open(.list(Self.id))
        navigator.open(.taskDetail(Self.id))
        navigator.select(.today)
        navigator.openTimeline(on: TestClock.mockupNow.addingTimeInterval(86_400))
        navigator.captureDraft = CaptureDraft(text: "Book flights fri", listID: Self.id, dueDate: .cleared)
        let data = try JSONEncoder().encode(navigator.place)

        let restored = PhoneNavigator()
        #expect(restored.isAtLaunch)
        restored.restore(try JSONDecoder().decode(PhoneNavigator.Place.self, from: data),
                         today: TestClock.calendar.startOfDay(for: TestClock.mockupNow), hasWork: false)
        #expect(restored.tab == .today)
        #expect(restored.todayMode == .timeline)
        // The toggle didn't move: nothing slides in from the list.
        #expect(restored.todaySwitchedFrom == nil)
        #expect(restored.timelineDay == navigator.timelineDay)
        #expect(restored.listsPath == [.list(Self.id), .taskDetail(Self.id)])
        #expect(restored.captureDraft == navigator.captureDraft)
        #expect(!restored.isAtLaunch)
    }

    /// Only what can still be shown comes back: screens pushed where they
    /// belong, a day not yet past, Working while there's work, and a Capture
    /// that waits to be asked before it listens.
    @Test func aPlaceKeepsOnlyWhatCanStillBeShown() {
        let today = TestClock.calendar.startOfDay(for: TestClock.mockupNow)
        var place = PhoneNavigator.Place()
        place.today = [.activity, .settings, .working, .taskDetail(Self.id)]
        place.showsTimeline = true
        place.timelineDay = today.addingTimeInterval(-86_400)
        place.cover = .working
        place.coverPath = [.taskDetail(Self.id)]
        let navigator = PhoneNavigator()
        navigator.restore(place, today: today, hasWork: false)
        #expect(navigator.todayPath == [.activity, .taskDetail(Self.id)])
        #expect(navigator.timelineDay == nil)
        #expect(navigator.cover == nil && navigator.coverPath.isEmpty)
        let working = PhoneNavigator()
        working.restore(place, today: today, hasWork: true)
        #expect(working.cover == .working && working.coverPath == [.taskDetail(Self.id)])

        var capturing = PhoneNavigator.Place()
        capturing.sheet = .capture(CaptureRequest(listID: Self.id, listens: true))
        let capture = PhoneNavigator()
        capture.restore(capturing, today: today, hasWork: false)
        guard case let .capture(request) = capture.sheet else { Issue.record("No capture sheet"); return }
        #expect(!request.listens && request.listID == Self.id)

        var settings = PhoneNavigator.Place()
        settings.sheet = .settings
        settings.settingsPath = [.trash, .capture(CaptureRequest()), .planHours]
        let set = PhoneNavigator()
        set.restore(settings, today: today, hasWork: false)
        #expect(set.sheet == .settings && set.settingsPath == [.trash, .planHours])
    }

    /// A review session starts where its launch variables say: the window's
    /// appearing opens links but puts no saved place back.
    @Test func reviewSessionsDontRestore() throws {
        let phone = try TestPhone()
        var place = PhoneNavigator.Place()
        place.tab = .lists
        phone.env.windowAppeared(restoring: try JSONEncoder().encode(place))
        #expect(phone.navigator.tab == .today)
        #expect(phone.env.hasShownWindow)
    }

    /// A task's page closed by sending it to Trash opens again with Undo,
    /// unless the user has moved on.
    @Test func undoingATrashFromItsPageReopensIt() {
        let navigator = PhoneNavigator()
        let list = UUID()
        navigator.select(.lists)
        navigator.open(.list(list))
        navigator.open(.taskDetail(Self.id))
        navigator.closeTrashedPage(of: Self.id)
        #expect(navigator.listsPath == [.list(list)])
        navigator.reopenTrashedPage(taskExists: { _ in true })
        #expect(navigator.listsPath == [.list(list), .taskDetail(Self.id)])

        navigator.closeTrashedPage(of: Self.id)
        navigator.select(.today)
        navigator.reopenTrashedPage(taskExists: { _ in true })
        #expect(navigator.listsPath == [.list(list)])
        #expect(navigator.todayPath.isEmpty)
    }

    /// Swipe back (Platform/SwipeBack.swift) adds its methods to UIKit's
    /// navigation controller. Had UIKit its own, the category would have
    /// replaced them: each name must appear once.
    @Test func swipeBackReplacesNothingOfUIKits() {
        var count: UInt32 = 0
        guard let methods = class_copyMethodList(UINavigationController.self, &count) else {
            Issue.record("No methods on UINavigationController")
            return
        }
        defer { free(methods) }
        let names = (0..<Int(count)).map { NSStringFromSelector(method_getName(methods[$0])) }
        #expect(names.filter { $0 == "viewDidLoad" }.count == 1)
        #expect(names.filter { $0 == "gestureRecognizerShouldBegin:" }.count == 1)
    }

    // MARK: Links

    @Test func widgetLinksOpenTheirScreens() throws {
        let phone = try TestPhone(seeded: true)
        let links = phone.env.links
        let navigator = phone.navigator
        links.windowReady(true)

        #expect(links.receive(WidgetLink.calendar.url))
        #expect(navigator.visibleRoute == .timeline)
        #expect(links.receive(WidgetLink.inbox.url))
        #expect(navigator.visibleRoute == .inbox)
        #expect(links.receive(WidgetLink.activity.url))
        #expect(navigator.visibleRoute == .activity)
        // The widget's Triage is the Inbox's, whichever pass was last on show.
        navigator.triageMode = .undated
        #expect(links.receive(WidgetLink.triage.url))
        #expect(navigator.cover == .triage && navigator.triageMode == .inbox)

        let kyoto = try #require(phone.list("Weekend in Kyoto"))
        #expect(links.receive(WidgetLink.list(kyoto.id).url))
        #expect(navigator.tab == .lists && navigator.listsPath == [.list(kyoto.id)])

        let task = try #require(phone.task("Book the ryokan"))
        #expect(links.receive(WidgetLink.task(task.id).url))
        #expect(navigator.listsPath == [.list(kyoto.id), .taskDetail(task.id)])

        #expect(links.receive(WidgetLink.capture(listID: kyoto.id).url))
        guard case let .capture(request) = navigator.sheet else { Issue.record("No capture sheet"); return }
        #expect(request.listID == kyoto.id)

        #expect(!links.receive(URL(string: "https://example.com")!))
    }

    @Test func linksWaitForTheWindow() throws {
        let phone = try TestPhone()
        phone.env.links.receive(WidgetLink.activity.url)
        #expect(phone.navigator.todayPath.isEmpty)
        phone.env.links.windowReady(true)
        #expect(phone.navigator.todayPath == [.activity])
    }

    @Test func aLinkToSomethingGoneSaysSo() throws {
        let phone = try TestPhone()
        phone.env.links.windowReady(true)
        phone.env.links.receive(WidgetLink.task(UUID()).url)
        #expect(phone.env.tray.message?.tone == .danger)
        #expect(phone.navigator.visibleRoute == .today)
    }

    @Test func itemLinksOpenInTheirLibrary() throws {
        let phone = try TestPhone(seeded: true)
        phone.env.links.windowReady(true)
        let task = try #require(phone.task("Draft Q3 OKRs"))
        let url = LocalLink(libraryID: try #require(phone.env.libraryID), target: .task(task.id)).url()
        #expect(phone.env.openLink(url))
        #expect(phone.navigator.topRoute == .taskDetail(task.id))

        // Another library's link, with iCloud off: refused, with the reason.
        let other = LocalLink(libraryID: UUID(), target: .task(task.id)).url()
        phone.navigator.open(.today)
        #expect(phone.env.openLink(other))
        #expect(phone.navigator.visibleRoute == .today)
        #expect(phone.env.tray.message?.text == LocalLinkError.wrongLibrary.errorDescription)
    }
}
