import Foundation
// Stable only across this test runner's processes; never opens live media.
nonisolated enum ReviewSession {
    static var identifier: String? { "lifecycle-check-" + CommandLine.arguments[2] }
}
