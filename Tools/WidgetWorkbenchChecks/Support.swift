import Foundation
import Observation

// The suite builds the whole app target, `Workbench` and its screens
// included, apart from what needs a Swift package or the app's entry point.

/// Keeps each run's preferences, snapshot and command queue apart from the app's.
nonisolated enum ReviewSession {
    static var identifier: String? { "widget-workbench-" + CommandLine.arguments[2] }
    static var suiteName: String { "openlist.widget-workbench-checks." + CommandLine.arguments[2] }
    static var defaults: UserDefaults { UserDefaults(suiteName: suiteName)! }
}

nonisolated enum AppGroup {
    static var identifier: String { "openlist.widget-workbench-checks." + CommandLine.arguments[2] }
    static var containerURL: URL? { URL(fileURLWithPath: CommandLine.arguments[1]) }
    static var snapshotURL: URL? { containerURL?.appendingPathComponent("widget-snapshot.json") }
}

/// `openlistApp.swift`'s, which holds the app's entry point.
enum WindowID {
    static let main = "main"
}

/// The MCP server needs its Swift package; the settings screen reads only this.
@Observable
@MainActor
final class MCPIntegration {
    enum Status: Equatable { case off, starting, running, failed(String) }
    enum ClientFormat: String, CaseIterable, Identifiable {
        case stdio, vscode
        var id: String { rawValue }
        var title: String { rawValue }
    }
    private(set) var status = Status.off
    init(store: Store, settings: AppSettings) {}
    var url: String { "" }
    var isRunning: Bool { false }
    var statusText: String { "Off" }
    func start(storageAvailable: Bool) {}
    func setEnabled(_ enabled: Bool) {}
    func setAllowsWrites(_ allowed: Bool) {}
    func setPort(_ text: String) -> Bool { false }
    func restart(rotatingToken: Bool = false) {}
    func configuration(for format: ClientFormat, bundleURL: URL = Bundle.main.bundleURL) throws -> String { "" }
    func accessToken() throws -> String { "" }
}
