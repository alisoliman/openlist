import Foundation

/// Keeps each run's preferences, snapshot and command queue apart from the app's.
nonisolated enum ReviewSession {
    static var identifier: String? { "widget-action-" + CommandLine.arguments[2] }
    static var suiteName: String { "openlist.widget-action-checks." + CommandLine.arguments[2] }
    static var defaults: UserDefaults { UserDefaults(suiteName: suiteName)! }
}

nonisolated enum AppGroup {
    /// Unique per run, so the Darwin signal never reaches another checkout's run.
    static var identifier: String { "openlist.widget-action-checks." + CommandLine.arguments[2] }
    static var containerURL: URL? { URL(fileURLWithPath: CommandLine.arguments[1]) }
    static var snapshotURL: URL? { containerURL?.appendingPathComponent("widget-snapshot.json") }
}
