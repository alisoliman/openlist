import Foundation
nonisolated enum ReviewSession {
    static var identifier: String? { "calendar-runtime-" + CommandLine.arguments[1] }
    static var defaults: UserDefaults { UserDefaults(suiteName: "openlist.calendar.runtime." + CommandLine.arguments[1])! }
}
