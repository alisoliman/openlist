import Foundation
// The real MediaStore uses only this test's unique fixture directory.
nonisolated enum ReviewSession {
    static let identifier: String? = "export-integration-check-\(UUID().uuidString)"
}
