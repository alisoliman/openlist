import Foundation

/// Points `AppGroup.containerURL` at a throwaway directory, so the command
/// queue checks never touch the real App Group.
nonisolated enum ReviewSession {
    static var identifier: String? {
        guard CommandLine.arguments.count > 1, UUID(uuidString: CommandLine.arguments[1]) != nil else {
            preconditionFailure("Widget checks require a unique fixture UUID")
        }
        return "WidgetChecks-" + CommandLine.arguments[1]
    }
}
