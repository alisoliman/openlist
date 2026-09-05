import Foundation
// Only this check binary uses the random media directory; no live data is read.
nonisolated enum ReviewSession {
    static let identifier: String? = "duplication-check-\(UUID().uuidString)"
}
