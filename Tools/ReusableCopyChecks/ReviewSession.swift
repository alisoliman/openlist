import Foundation
nonisolated enum ReviewSession {
    static let identifier = ProcessInfo.processInfo.environment["OPENLIST_COPY_CHECK_ID"]
}
