//
//  StoreSmokeTests.swift
//  OpenlistiOSTests
//

import Foundation
import Testing
@testable import OpenlistiOS

/// The shared Model and Store, compiled into the iPhone app, behave as on the Mac.
@MainActor
struct StoreSmokeTests {
    /// Every launch bootstraps, so a second run must not add another Inbox.
    @Test func bootstrapCreatesTheInboxAndDefaultSectionOnce() throws {
        let library = try TestLibrary()
        library.store.bootstrap()
        #expect(library.store.inboxList() != nil)
        #expect(library.store.allLists(includeArchived: true).filter(\.isSystemInbox).count == 1)
        #expect(library.store.defaultSection() != nil)
        #expect(library.store.persistenceError == nil)
    }

    @Test func createsAListInTheDefaultSection() throws {
        let library = try TestLibrary()
        let list = library.store.createList(title: "Weekend in Kyoto", icon: "⛩️")
        #expect(list.title == "Weekend in Kyoto")
        #expect(list.sectionID == library.store.defaultSection()?.id)
        #expect(library.store.list(id: list.id) === list)
    }

    @Test func usesTheIOSAppGroup() {
        #expect(AppGroup.identifier == "group.solimanali.openlist")
    }

    /// The scheme launches the host app in a review session, so running the
    /// tests never opens this simulator's real library or CloudKit.
    @Test func hostAppRunsInAReviewSession() {
        #expect(ReviewSession.identifier == "HostedTests")
        #expect(ICloudConfiguration.unavailableReason != nil)
    }
}
