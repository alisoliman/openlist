//
//  TestLibrary.swift
//  OpenlistiOSTests
//

import Foundation
import SwiftData
@testable import OpenlistiOS

/// An empty library in memory, with the app's real schema and `Store`.
///
/// Hold the library, not just its `store`, for as long as the store is used:
/// a context doesn't keep its container alive, and `TestLibrary().store`
/// traps in SwiftData a few fetches later.
///
/// Tests never touch the host app's store: the scheme also launches the host
/// in a review session, so it runs local-only with its own files. CloudKit
/// stays off explicitly here, because `.automatic` would try to mirror an
/// iCloud-entitled host's in-memory store.
@MainActor
struct TestLibrary {
    let container: ModelContainer
    let store: Store

    init(bootstrap: Bool = true) throws {
        container = try Self.makeContainer()
        store = Store(context: container.mainContext)
        if bootstrap { store.bootstrap() }
    }

    static func makeContainer() throws -> ModelContainer {
        let schema = AppPersistence.schema
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)]
        )
    }
}

/// The time tests run at: the mockups' Wednesday 23 September 2026, 10:40.
enum TestClock {
    static let mockupNow = AppClock.parse(PhoneFixture.mockupNow)!
    static var mockup: AppClock { .fixed(mockupNow) }

    /// Week from Monday, as the fixture sets it.
    static var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }
}

/// A `PhonePlatform` that does nothing but count what the environment asks
/// of the OS: push registration, and background time begun and ended.
@MainActor
final class RecordingPlatform {
    private(set) var pushRegistrations = 0
    private(set) var backgroundTasksBegun = 0
    private(set) var backgroundTasksEnded = 0

    var platform: PhonePlatform {
        var platform = PhonePlatform.inert
        platform.registerForRemoteNotifications = { [unowned self] in pushRegistrations += 1 }
        platform.beginBackgroundTask = { [unowned self] _, _ in
            backgroundTasksBegun += 1
            return { [unowned self] in backgroundTasksEnded += 1 }
        }
        return platform
    }
}

/// A defaults suite of its own, emptied, for settings and calendar state.
enum TestDefaults {
    static func make() -> UserDefaults {
        let name = "openlist.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}

/// A whole `PhoneEnvironment` around an in-memory library: nothing reaches
/// the OS (no push registration, no process-wide handlers, no calendar
/// clock), settings and calendar state live in their own defaults, and the
/// clock is fixed at the mockups' moment.
@MainActor
struct TestPhone {
    let container: ModelContainer
    let env: PhoneEnvironment
    let defaults: UserDefaults

    var store: Store { env.store }
    var navigator: PhoneNavigator { env.navigator }

    /// - Parameter seeded: bootstraps and seeds the iPhone fixture, as a
    ///   review session's first launch does.
    ///   `platform` stands in for the OS; `.inert` does nothing.
    init(seeded: Bool = false, bootstrap: Bool = true, clock: AppClock = TestClock.mockup,
         platform: PhonePlatform = .inert) throws {
        container = try TestLibrary.makeContainer()
        defaults = TestDefaults.make()
        env = PhoneEnvironment(context: container.mainContext, sync: ICloudSyncMonitor(unavailableReason: "Tests run local-only."),
                               libraryID: UUID(), settings: AppSettings(defaults: defaults), clock: clock,
                               platform: platform, seedsReviewFixture: seeded, calendarDefaults: defaults)
        if bootstrap { env.bootstrap() }
    }

    /// A task by its title, anywhere in the library.
    func task(_ title: String) -> Block? {
        let task = BlockKind.task.rawValue
        return try? container.mainContext.fetch(FetchDescriptor<Block>(
            predicate: #Predicate { $0.kindRaw == task && $0.text == title })).first
    }

    func list(_ title: String) -> TaskList? {
        store.allLists(includeArchived: true).first { $0.title == title }
    }

    /// What a second context reads from the store's file: what was saved.
    func savedTaskCount() throws -> Int {
        let reader = ModelContext(container)
        let task = BlockKind.task.rawValue
        return try reader.fetchCount(FetchDescriptor<Block>(predicate: #Predicate { $0.kindRaw == task }))
    }
}
