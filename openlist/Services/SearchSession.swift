import Foundation
import Observation

@Observable
@MainActor
final class SearchSession {
    /// The latest answer. It stays listed while a newer search runs, so typing
    /// narrows the results instead of blanking them; `hitsOptions` says which
    /// search it answers.
    private(set) var hits: [SearchHit] = []
    private(set) var hitsOptions = SearchOptions()
    private(set) var isSearching = false
    /// A search still running after a moment, so the card can say it's searching.
    private(set) var isSlow = false
    private(set) var options = SearchOptions()
    @ObservationIgnored private var corpus: SearchCorpus?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var slowTimer: Task<Void, Never>?

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
        slowTimer?.cancel()
        slowTimer = nil
    }

    private func startSearch() {
        cancel()
        let generation = generation
        let options = options
        guard !options.needle.isEmpty else {
            answer([], for: options)
            return
        }
        isSearching = true
        slowTimer = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let self, self.generation == generation else { return }
            isSlow = true
        }
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
                answer(projection.hits, for: options)
            } catch {
                // Cancellation is expected when typing or when live data changes.
                guard let self, self.generation == generation else { return }
                answer([], for: options)
            }
        }
    }

    private func answer(_ hits: [SearchHit], for options: SearchOptions) {
        self.hits = hits
        hitsOptions = options
        isSearching = false
        isSlow = false
        slowTimer?.cancel()
        slowTimer = nil
    }
}
