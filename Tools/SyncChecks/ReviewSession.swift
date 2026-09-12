import Foundation

nonisolated enum ReviewSession {
    static var identifier: String? {
        guard CommandLine.arguments.count > 2,
              UUID(uuidString: CommandLine.arguments[2]) != nil else {
            preconditionFailure("Sync checks require a unique fixture UUID")
        }
        return "Sync-" + CommandLine.arguments[2]
    }
}

nonisolated enum AppGroup {
    static var snapshotURL: URL? {
        URL(fileURLWithPath: CommandLine.arguments[1])
            .deletingLastPathComponent().appendingPathComponent("widget-snapshot.json")
    }
}
