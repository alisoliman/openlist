//
//  StateFeedbackTests.swift
//  OpenlistiOSTests
//

import Foundation
import SwiftData
import Testing
@testable import OpenlistiOS

/// What the screens say at their edges: a library still arriving from
/// iCloud, an empty list, a save that failed, a failure said once, Find
/// with nothing found, and triage's kept cards.
@MainActor
struct StateFeedbackTests {
    private func library(_ phone: TestPhone) throws -> NextLibrary {
        let task = BlockKind.task.rawValue
        let tasks = try phone.container.mainContext.fetch(FetchDescriptor<Block>(
            predicate: #Predicate { $0.trashID == nil && $0.kindRaw == task }))
        return NextLibrary(lists: phone.store.allLists(includeArchived: true), sections: phone.store.allSections(),
                           labels: phone.store.allLabels(), tasks: tasks)
    }

    // MARK: The first import

    @Test func theFirstImportIsAwaitedOnlyUntilSomethingComesDown() {
        var state = ICloudSyncState()
        #expect(state.isAwaitingFirstImport, "Checking the account")
        state.account = .available
        let download = UUID()
        state.begin(.download, id: download)
        #expect(state.isAwaitingFirstImport, "Still on its way")
        state.finish(.download, id: download, at: TestClock.mockupNow, error: nil)
        #expect(!state.isAwaitingFirstImport)

        var offline = ICloudSyncState()
        offline.account = .available
        offline.begin(.download, id: download)
        offline.finish(.download, id: download, at: TestClock.mockupNow, error: "The network is offline.")
        #expect(!offline.isAwaitingFirstImport, "A failed download isn't on its way")

        var setup = ICloudSyncState()
        setup.account = .available
        setup.begin(.setup, id: download)
        setup.finish(.setup, id: download, at: TestClock.mockupNow, error: "No container.")
        #expect(!setup.isAwaitingFirstImport, "Nothing comes once setup has failed")

        var signedOut = ICloudSyncState()
        signedOut.account = .signedOut
        #expect(!signedOut.isAwaitingFirstImport)
        #expect(!ICloudSyncState(unavailableReason: "Local only.").isAwaitingFirstImport)
    }

    @Test func onlyAnEmptyLibraryWaitsForTheImport() throws {
        let phone = try TestPhone()
        let empty = try library(phone)
        #expect(empty.isEmptyLibrary, "The Inbox alone is empty")
        #expect(!phone.env.awaitsFirstImport(empty), "Sync is off")
        phone.env.sync.state.unavailableReason = nil
        #expect(phone.env.awaitsFirstImport(empty))

        phone.store.createList(title: "Garden")
        let withList = try library(phone)
        #expect(!withList.isEmptyLibrary)
        #expect(!phone.env.awaitsFirstImport(withList))

        let seeded = try TestPhone(seeded: true)
        seeded.env.sync.state.unavailableReason = nil
        #expect(!seeded.env.awaitsFirstImport(try library(seeded)))
    }

    // MARK: Empty states

    @Test func listCardsTellAnEmptyListFromOneAllDone() throws {
        let phone = try TestPhone(seeded: true)
        let garden = phone.store.createList(title: "Garden")
        let reading = try #require(phone.list("Reading"))
        #expect(try library(phone).cardDetail(for: garden) == "Empty")
        #expect(try library(phone).cardDetail(for: reading) == "2 open")
        for title in ["Finish The Overstory", "Start Piranesi"] {
            phone.store.toggleCompletion(try #require(phone.task(title)), now: TestClock.mockupNow)
        }
        #expect(try library(phone).cardDetail(for: reading) == "All done")
    }

    @Test func findWithNothingOpenCanStillFindItDone() throws {
        let phone = try TestPhone(seeded: true)
        let lib = try library(phone)
        let pool = lib.tasksInOutlineOrder(blocks: try phone.container.mainContext.fetch(FetchDescriptor<Block>(
            predicate: #Predicate { $0.trashID == nil })))
        func results(_ query: String) -> [String] {
            FindScreen.results(for: query, language: lib.findQuery, pool: pool, now: phone.env.now,
                               calendar: phone.env.settings.calendar).map(\.displayTitle)
        }
        #expect(results("#travel kasuga").isEmpty)
        #expect(results("#travel kasuga done") == ["Reply to Kasuga about the tatami room"])
        #expect(results("#travel zebra done").isEmpty)
    }

    // MARK: Failures

    @Test func aChangeTheSaveLostIsntReportedDone() throws {
        let failing = try FailingLibrary()
        let store = failing.store, actions = failing.actions
        let task = try store.saveCapture(CaptureSnapshot(title: "Water the herbs"), destinationID: nil)
        failing.savesFail = true
        actions.edit([task], "Starred “Water the herbs”", icon: "star") { store.toggleStar($0) }
        #expect(store.persistenceError != nil)
        #expect(actions.tray.message == nil, "Nothing says it was starred")
        #expect(actions.haptics.lastPlayed == .error)
        let list = store.createList(title: "Garden")
        actions.rename(list, to: "Yard")
        #expect(actions.tray.message == nil, "Nor that it was renamed")

        // The notice's Try Again saves what was kept, and the next change
        // is reported as usual.
        failing.savesFail = false
        store.save()
        #expect(store.persistenceError == nil)
        #expect(task.isStarred)
        actions.edit([task], "Unstarred “Water the herbs”", icon: "star") { store.toggleStar($0) }
        #expect(actions.tray.message?.text == "Unstarred “Water the herbs”")
    }

    @Test func aFailedSaveIsTheNoticesWithTryAgain() throws {
        let phone = try TestPhone(seeded: true)
        phone.store.persistenceError = "Your latest changes could not be saved."
        #expect(phone.env.notice?.retriesSave == true)
        #expect(phone.env.notice?.clears == nil)
        phone.store.persistenceError = nil
        phone.store.trashError = "That could not be erased."
        #expect(phone.env.notice?.retriesSave == false)
    }

    @Test func aFailureSaidInTheTrayIsntSaidAgainByTheNotice() throws {
        let failing = try FailingLibrary()
        let task = try failing.store.saveCapture(CaptureSnapshot(title: "Water the herbs"), destinationID: nil)
        failing.savesFail = true
        #expect(!failing.actions.trash([task]))
        #expect(failing.actions.tray.message?.text.hasPrefix("Content could not be moved to Trash") == true)
        #expect(failing.store.trashError == nil, "The tray said it; the notice doesn't again")
    }

    // MARK: Triage

    @Test func keptCardsAreReadFromTheirTasksDates() throws {
        let phone = try TestPhone(seeded: true)
        let later = try #require(phone.task("Send Jun the photos from Nara"))
        let dated = try #require(phone.task("Renew passports"))
        let due = try #require(dated.dueDate)
        let session = TriageSession()
        session.keep(later.id)
        session.schedule(dated.id, due: due)
        #expect(try library(phone).kept(by: session) == [later.id, dated.id])
        // Its date changed since, by Undo say: back on the queue.
        session.schedule(dated.id, due: due.addingTimeInterval(86_400))
        #expect(try library(phone).kept(by: session) == [later.id])
    }
}

/// A library whose saves fail while `savesFail` is on, as on a full disk,
/// with the phone's actions over it.
@MainActor
private final class FailingLibrary {
    let container: ModelContainer
    let store: Store
    let actions: PhoneActions
    private let failure: SaveFailure

    var savesFail: Bool {
        get { failure.isOn }
        set { failure.isOn = newValue }
    }

    init() throws {
        let failure = SaveFailure()
        self.failure = failure
        container = try TestLibrary.makeContainer()
        store = Store(context: container.mainContext) { context in
            if failure.isOn { throw CocoaError(.fileWriteOutOfSpace) }
            try context.save()
        }
        store.bootstrap()
        let defaults = TestDefaults.make()
        actions = PhoneActions(store: store, settings: AppSettings(defaults: defaults),
                               calendar: CalendarCoordinator(store: store, defaults: defaults), clock: TestClock.mockup)
    }
}

private final class SaveFailure {
    var isOn = false
}
