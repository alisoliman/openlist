//
//  PhoneEnvironmentTests.swift
//  OpenlistiOSTests
//

import Foundation
import SwiftData
import Testing
@testable import OpenlistiOS

/// The phone repeats the Mac's launch and sync steps: these are what keep
/// two devices' libraries convergent.
@MainActor
struct PhoneEnvironmentTests {
    @Test func bootstrapRunsOnceFromEitherTrigger() throws {
        let phone = try TestPhone(seeded: true, bootstrap: false)
        #expect(!phone.env.hasBootstrapped)
        // didFinishLaunching, then the first scene's task.
        phone.env.bootstrap()
        let blocks = try phone.container.mainContext.fetchCount(FetchDescriptor<Block>())
        let lists = phone.store.allLists(includeArchived: true).count
        phone.env.bootstrap()
        #expect(phone.env.hasBootstrapped)
        #expect(try phone.container.mainContext.fetchCount(FetchDescriptor<Block>()) == blocks)
        #expect(phone.store.allLists(includeArchived: true).count == lists)
        #expect(phone.store.allLists(includeArchived: true).filter(\.isSystemInbox).count == 1)
        #expect(phone.navigator.inboxListID == phone.store.inboxList()?.id)
    }

    @Test func seedsOnlyAnEmptyLibraryOnce() throws {
        let phone = try TestPhone(seeded: true)
        #expect(phone.env.settings.hasSeededSampleData)
        #expect(phone.list("Weekend in Kyoto") != nil)

        // A second launch of the same session finds content and seeds nothing.
        let again = PhoneEnvironment(context: phone.container.mainContext, sync: ICloudSyncMonitor(unavailableReason: "Tests"),
                                     libraryID: UUID(), settings: AppSettings(defaults: TestDefaults.make()),
                                     clock: TestClock.mockup, platform: .inert, calendarDefaults: TestDefaults.make())
        again.bootstrap()
        #expect(phone.store.allLists().filter { $0.title == "Weekend in Kyoto" }.count == 1)
    }

    @Test func anUnseededLibraryStaysEmpty() throws {
        let phone = try TestPhone(seeded: false)
        #expect(phone.store.allLists().filter { !$0.isSystemInbox }.isEmpty)
        #expect(try phone.savedTaskCount() == 0)
    }

    /// Sample data only ever goes into an isolated review session's empty
    /// library with iCloud off: anywhere else it would sync a copy up from
    /// every device.
    @Test func theFixtureNeedsAnEmptyLocalReviewLibrary() throws {
        // Held for the whole test: the store's context dies with its container.
        let library = try TestLibrary()
        func allowed(sync: Bool = false, session: String? = "Review", seeded: Bool = false) -> Bool {
            PhoneEnvironment.mayReceiveFixture(library.store, syncEnabled: sync, reviewSession: session, hasSeeded: seeded)
        }
        #expect(allowed())
        #expect(!allowed(sync: true))
        #expect(!allowed(session: nil))
        #expect(!allowed(seeded: true))

        let list = library.store.createList(title: "Groceries", icon: "🥕")
        #expect(!allowed())
        #expect(library.store.trashList(list))
        let inbox = try #require(library.store.inboxList())
        library.store.appendBlock(kind: .task, text: "Milk", to: DocumentContext(listID: inbox.id))
        library.store.save()
        #expect(!allowed())
    }

    /// Another device's Inbox arrives in an import: the older one wins, the
    /// phone's becomes an alias, and what was captured into it moves over.
    @Test func remoteChangeMergesASecondInbox() throws {
        let phone = try TestPhone()
        let store = phone.store
        let phoneInbox = try #require(store.inboxList())
        let capture = store.appendBlock(kind: .task, text: "Captured on the phone", to: DocumentContext(listID: phoneInbox.id))
        store.save()

        let macInbox = TaskList(title: "Inbox", icon: "📥", accent: .blue, isSystemInbox: true)
        macInbox.createdAt = phoneInbox.createdAt.addingTimeInterval(-86_400)
        macInbox.sortIndex = -1_000_000
        store.context.insert(macInbox)
        try store.context.save()
        #expect(store.allLists(includeArchived: true).filter { $0.isSystemInbox && $0.mergedIntoID == nil }.count == 2)

        phone.env.refreshAfterRemoteChange()

        let visible = store.allLists(includeArchived: true).filter { $0.isSystemInbox && $0.mergedIntoID == nil }
        #expect(visible.map(\.id) == [macInbox.id])
        #expect(phoneInbox.mergedIntoID == macInbox.id)
        #expect(store.inboxList()?.id == macInbox.id)
        #expect(phone.navigator.inboxListID == macInbox.id)
        #expect(capture.listID == macInbox.id)
        #expect(phone.env.remoteChangeCount == 1)
    }

    /// An iCloud account change can empty the local mirror, Inbox included;
    /// only bootstrap makes one, so the next merge runs it again.
    @Test func remoteChangeRestoresAPurgedInbox() throws {
        let phone = try TestPhone()
        let store = phone.store
        let inbox = try #require(store.inboxList())
        let section = try #require(store.defaultSection())
        let purgedID = inbox.id
        store.context.delete(inbox)
        store.context.delete(section)
        try store.context.save()
        #expect(store.inboxList() == nil)

        phone.env.refreshAfterRemoteChange()

        let restored = try #require(store.inboxList())
        #expect(restored.id != purgedID)
        #expect(store.defaultSection() != nil)
        #expect(phone.navigator.inboxListID == restored.id)
        #expect(store.allLists(includeArchived: true).filter(\.isSystemInbox).count == 1)
    }

    /// With iCloud off there is nothing for CloudKit's pushes to wake.
    @Test func aLocalLibraryNeverRegistersForPushes() throws {
        let recorder = RecordingPlatform()
        let phone = try TestPhone(platform: recorder.platform)
        #expect(phone.env.hasBootstrapped)
        #expect(!phone.env.sync.state.isEnabled)
        #expect(recorder.pushRegistrations == 0)
    }

    @Test func remoteChangeIsIgnoredBeforeBootstrap() throws {
        let phone = try TestPhone(bootstrap: false)
        phone.env.refreshAfterRemoteChange()
        #expect(phone.env.remoteChangeCount == 0)
    }

    /// A task trashed on the Mac leaves the stack it was open on.
    @Test func remoteChangeClosesScreensOnSomethingGone() throws {
        let phone = try TestPhone(seeded: true)
        let kyoto = try #require(phone.list("Weekend in Kyoto"))
        let task = try #require(phone.task("Renew passports"))
        phone.navigator.show(.taskDetail(task.id), in: kyoto.id)
        #expect(phone.navigator.listsPath == [.list(kyoto.id), .taskDetail(task.id)])

        #expect(phone.store.trashBlocks([task]))
        phone.env.refreshAfterRemoteChange()
        #expect(phone.navigator.listsPath == [.list(kyoto.id)])
    }

    /// Leaving the front writes what's dwelling and what's unsaved: iOS may
    /// end the app with no chance to ask.
    @Test func goingToTheBackgroundSavesEverything() async throws {
        let phone = try TestPhone(seeded: true)
        let task = try #require(phone.task("Start Piranesi"))
        phone.env.actions.complete([task])
        #expect(phone.env.actions.isClosing(task.id))
        #expect(!task.isCompleted)
        let draft = phone.store.appendBlock(kind: .task, text: "Unsaved line", to: DocumentContext(listID: task.listID!))
        #expect(phone.store.context.hasChanges)
        let saved = try phone.savedTaskCount()

        phone.env.sceneWillResignActive(toBackground: true)
        // The drain yields before its first save.
        for _ in 0..<50 where phone.store.context.hasChanges { try await Task.sleep(for: .milliseconds(20)) }

        #expect(task.isCompleted)
        #expect(!phone.env.actions.isClosing(task.id))
        #expect(!phone.store.context.hasChanges)
        #expect(try phone.savedTaskCount() == saved + 1)
        #expect(draft.modelContext != nil)
        #expect(phone.env.backgroundSaveCount == 1)
        #expect(!phone.env.isActive)
    }

    /// The save runs in background time iOS lends the app, handed back once
    /// the drain is done so the app can be suspended.
    @Test func theBackgroundSaveBorrowsTimeAndGivesItBack() async throws {
        let recorder = RecordingPlatform()
        let phone = try TestPhone(seeded: true, platform: recorder.platform)
        let task = try #require(phone.task("Start Piranesi"))
        phone.store.setPriority(.low, for: task)
        phone.env.sceneWillResignActive(toBackground: true)
        #expect(recorder.backgroundTasksBegun == 1)
        for _ in 0..<50 where recorder.backgroundTasksEnded == 0 { try await Task.sleep(for: .milliseconds(20)) }
        #expect(recorder.backgroundTasksEnded == 1)
        #expect(!phone.store.context.hasChanges)
    }

    /// Control Center or a call makes the scene inactive without leaving:
    /// what changed is saved there and then, a dwelling tick included.
    @Test func inactiveSavesWhatChanged() throws {
        let recorder = RecordingPlatform()
        let phone = try TestPhone(seeded: true, platform: recorder.platform)
        let task = try #require(phone.task("Start Piranesi"))
        phone.env.actions.complete([task])
        let saved = try phone.savedTaskCount()
        phone.store.appendBlock(kind: .task, text: "Typed before the call", to: DocumentContext(listID: task.listID!))
        #expect(phone.store.context.hasChanges)

        phone.env.sceneWillResignActive(toBackground: false)

        #expect(task.isCompleted)
        #expect(!phone.store.context.hasChanges)
        #expect(try phone.savedTaskCount() == saved + 1)
        #expect(phone.env.backgroundSaveCount == 0)
        #expect(recorder.backgroundTasksBegun == 0)
        phone.env.sceneBecameActive()
        #expect(phone.env.isActive)
    }

    @Test func lifecycleHandlersRunAfterTheEnvironmentsOwnWork() throws {
        let phone = try TestPhone(bootstrap: false)
        var moments: [PhoneEnvironment.Lifecycle] = []
        phone.env.on(.bootstrapped) { moments.append(.bootstrapped) }
        phone.env.on(.remoteChange) { moments.append(.remoteChange) }
        phone.env.on(.becameActive) { moments.append(.becameActive) }
        phone.env.bootstrap()
        phone.env.refreshAfterRemoteChange()
        phone.env.sceneBecameActive()
        #expect(moments == [.bootstrapped, .remoteChange, .becameActive])
    }

    /// The calendar is installed before any task changes: completions and
    /// work sessions record this device's ID.
    @Test func theCalendarGivesTheStoreThisDevicesID() throws {
        let phone = try TestPhone()
        #expect(phone.store.calendarDeviceID?.isEmpty == false)
    }

    /// The fixture's session is carried on at launch rather than paused at
    /// its last heartbeat, as the Mac would.
    @Test func theFixturesWorkIsUnderWay() throws {
        let phone = try TestPhone(seeded: true)
        let session = try #require(phone.env.calendar.activeSession)
        #expect(session.title == "Draft Q3 OKRs")
        #expect(session.endedAt == nil)
    }
}
