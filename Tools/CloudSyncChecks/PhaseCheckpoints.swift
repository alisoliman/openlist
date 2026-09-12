import Foundation

@MainActor
final class CloudSyncCheckpoints {
    private let url: URL
    private var completed: Set<String>

    init(at url: URL) throws {
        self.url = url
        completed = FileManager.default.fileExists(atPath: url.path)
            ? try JSONDecoder().decode(Set<String>.self, from: Data(contentsOf: url))
            : []
    }

    func contains(_ phase: String) -> Bool {
        completed.contains(phase)
    }

    func record(_ phase: String) throws {
        let updated = completed.union([phase])
        try JSONEncoder().encode(updated).write(to: url, options: .atomic)
        completed = updated
    }

    func perform(_ phase: String, operation: () async throws -> Void) async throws {
        guard !contains(phase) else { return }
        try await operation()
        try record(phase)
    }
}
