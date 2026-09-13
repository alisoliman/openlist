import Foundation
nonisolated enum ReviewSession {
    static var identifier: String? { "inbox-check-" + URL(fileURLWithPath: CommandLine.arguments[1]).deletingLastPathComponent().lastPathComponent.replacingOccurrences(of: ".", with: "-") }
}
