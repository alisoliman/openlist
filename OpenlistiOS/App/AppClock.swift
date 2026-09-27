//
//  AppClock.swift
//  OpenlistiOS
//

import Foundation
import SwiftUI

/// What time it is for the phone's screens and actions.
///
/// Features read `env.clock.now` (or `@Environment(\.appClock)`) wherever
/// they would write `.now`, and pass it to the Store's `now:` parameters, so a
/// review session can pin the day the mockups show and a test can fix it.
/// Outside a Debug review session it is always the system clock.
nonisolated struct AppClock: Sendable {
    private let read: @Sendable () -> Date
    /// Whether the time is a fixture's rather than the system's. The calendar's
    /// 15-second ticks read the system clock, so a pinned clock runs without them.
    let isPinned: Bool

    init(isPinned: Bool, _ read: @escaping @Sendable () -> Date) {
        self.isPinned = isPinned
        self.read = read
    }

    var now: Date { read() }

    static let system = AppClock(isPinned: false) { .now }

    /// Always `date`: for tests.
    static func fixed(_ date: Date) -> AppClock {
        AppClock(isPinned: true) { date }
    }

    /// `date` at `start`, running on from there, so a review session opens on
    /// the fixture's moment and dwells, undo windows and "2 min ago" still move.
    static func pinned(at date: Date, from start: Date = .now) -> AppClock {
        AppClock(isPinned: true) { date.addingTimeInterval(Date.now.timeIntervalSince(start)) }
    }

    /// The launch's clock: `OpenlistFixtureNow` from the launch environment in
    /// a Debug review session, else the system clock.
    static func forLaunch(environment: [String: String] = ProcessInfo.processInfo.environment) -> AppClock {
        #if DEBUG
        if ReviewSession.identifier != nil, let value = environment["OpenlistFixtureNow"], let date = parse(value) {
            return .pinned(at: date)
        }
        #endif
        return .system
    }

    /// An ISO 8601 moment. One without a zone ("2026-09-23T10:40:00") is read
    /// in `timeZone`, so a screenshot shows the same clock time on any Mac.
    static func parse(_ value: String, timeZone: TimeZone = .current) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: value) { return date }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) { return date }
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = timeZone
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd"] {
            local.dateFormat = format
            if let date = local.date(from: value) { return date }
        }
        return nil
    }
}

extension EnvironmentValues {
    /// The app's clock, for views that only need the time.
    @Entry var appClock = AppClock.system
}
