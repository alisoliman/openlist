import Foundation
nonisolated enum ReviewSession {
    static let identifier = ProcessInfo.processInfo.environment["OPENLIST_COPY_CHECK_ID"]
    /// `AppSettings` reads its preferences here; checks never create one.
    static var defaults: UserDefaults { .standard }
}
