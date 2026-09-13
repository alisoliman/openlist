import Foundation
import Observation

@Observable
@MainActor
final class SearchSession {
    private(set) var hits: [SearchHit] = []
    private(set) var isSearching = false
    private(set) var options = SearchOptions()
    @ObservationIgnored private var corpus: SearchCorpus?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var worker: Task<Void, Never>?

    func update(corpus: SearchCorpus) {
        self.corpus = corpus
        startSearch()
    }

    func update(options: SearchOptions) {
        self.options = options
        startSearch()
    }

    func cancel() {
        generation += 1
        worker?.cancel()
        worker = nil
    }

    private func startSearch() {
        cancel()
        let generation = generation
        let options = options
        // Never leave clickable results for the previous query on screen.
        hits = []
        guard !options.needle.isEmpty else { isSearching = false; return }
        isSearching = true
        guard let corpus else { return }
        worker = Task { [weak self] in
            let task = Task.detached(priority: .userInitiated) {
                try SearchProjection(corpus: corpus, options: options)
            }
            do {
                let projection = try await withTaskCancellationHandler {
                    try await task.value
                } onCancel: { task.cancel() }
                guard !Task.isCancelled, let self, self.generation == generation else { return }
                hits = projection.hits
                isSearching = false
            } catch {
                // Cancellation is expected when typing or when live data changes.
                guard let self, self.generation == generation else { return }
                isSearching = false
            }
        }
    }
}
