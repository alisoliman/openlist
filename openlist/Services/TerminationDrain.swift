import Foundation

/// Awaiting OS work leaves the main actor available to editors. Save those
/// later edits too and finish synchronously only when that save queued no more
/// notification work. There is no suspension between the final save and reply.
@MainActor
enum TerminationDrain {
    static func run(commitDrafts: () -> Void, persist: () throws -> Void,
                    wait: () async -> Bool, hasPendingWork: () -> Bool,
                    finish: () -> Void) async throws {
        while true {
            commitDrafts()
            await Task.yield()
            try persist()
            let drained = await wait()
            commitDrafts()
            await Task.yield()
            try persist()
            // A timeout may leave OS work unconfirmed, but never unsaved user
            // edits. Next launch reconciles intent; no acceptance is invented.
            if !drained || !hasPendingWork() { finish(); return }
        }
    }
}
