import Foundation

/// Keeps each run's preferences and snapshot file apart from the app's.
nonisolated enum ReviewSession {
    static var identifier: String? { "widget-snapshot-" + CommandLine.arguments[2] }
    static var suiteName: String { "openlist.widget-snapshot-checks." + CommandLine.arguments[2] }
    static var defaults: UserDefaults { UserDefaults(suiteName: suiteName)! }
}

nonisolated enum AppGroup {
    static var snapshotURL: URL? {
        URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("widget-snapshot.json")
    }
}
