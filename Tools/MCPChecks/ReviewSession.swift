import Foundation

nonisolated enum ReviewSession {
    static var identifier: String? { "mcp-check-" + CommandLine.arguments[2] }
    static var defaults: UserDefaults {
        UserDefaults(suiteName: "solimanali.openlist.mcp-check.\(CommandLine.arguments[2])")!
    }
}
