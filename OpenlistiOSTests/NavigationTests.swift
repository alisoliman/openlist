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
    static let id = UUID()
    static let allRoutes: [PhoneRoute] = [
        .today, .timeline, .activity, .taskDetail(id), .inbox, .triage, .lists, .list(id), .find(""),
        .settings, .trash, .working, .capture(CaptureRequest()), .work,
    ]

    @Test func everyRouteHasItsPresentation() {
        let expected: [PhoneRoute.Presentation] = [
            .tab(.today), .mode(.today), .push, .push, .tab(.inbox), .fullScreenCover, .tab(.lists), .push, .push,
            .sheet, .settingsStack, .fullScreenCover, .sheet, .tab(.work),
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
        // Tapping the tab on show goes back to its root.
        navigator.select(.lists)
        #expect(navigator.listsPath.isEmpty)
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
        navigator.dismissCover()
        navigator.open(.triage)
        #expect(navigator.cover == .triage)
        // Opening a screen from a cover closes it first.
        navigator.open(.taskDetail(Self.id))
        #expect(navigator.cover == nil)
        #expect(navigator.topRoute == .taskDetail(Self.id))
    }

    /// A link to Working while Settings (a cover) is up waits for it to go:
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

        navigator.show(.triage)
        #expect(navigator.tab == .inbox)
        #expect(navigator.cover == .triage)
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
        #expect(links.receive(WidgetLink.triage.url))
        #expect(navigator.cover == .triage)

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
