//
//  VoiceCapture.swift
//  openlist
//

import Foundation
import Observation

/// Voice capture from start to finish, for the capture card and the phone's
/// Capture sheet alike: listen (`VoiceListener`), then read what was said
/// into tasks (`VoiceTaskInterpreter`) and hand them to the capture
/// (`onHeard`), which shows them before Add saves them with
/// `Store.saveSpokenTasks`.
@Observable
@MainActor
final class VoiceCapture {
    enum Phase: Equatable {
        case idle
        case preparing(progress: Double?)
        case listening
        /// Reading what was said into tasks.
        case understanding
        case failed(VoiceCaptureFailure)
    }

    let listener = VoiceListener()
    /// What Apple Intelligence could do when listening started.
    private(set) var intelligence = VoiceIntelligence.unsupported
    /// Whether Apple Intelligence read the last tasks heard.
    private(set) var usedIntelligence = false
    /// Whether the last task heard went in the capture field, whose caret
    /// then goes after it rather than selecting it.
    private(set) var filledField = false
    /// Gets the tasks heard, in the order said, once they're read.
    @ObservationIgnored var onHeard: (([SpokenTask]) -> Void)?

    private var isUnderstanding = false
    private var failure: VoiceCaptureFailure?
    @ObservationIgnored private var interpreter: VoiceTaskInterpreter?
    @ObservationIgnored private var run = 0

    var phase: Phase {
        if let failure { return .failed(failure) }
        if isUnderstanding { return .understanding }
        switch listener.state {
        case let .preparing(progress): return .preparing(progress: progress)
        case .listening, .stopping: return .listening
        case let .failed(failure): return .failed(failure)
        case .idle, .stopped: return .idle
        }
    }

    /// Whether it's listening or reading, when the capture shows it instead of its field.
    var isActive: Bool {
        switch phase {
        case .preparing, .listening, .understanding: true
        case .idle, .failed: false
        }
    }

    /// Listens, then reads what was said against `vocabulary` with dates
    /// relative to `now` at the time the speaker stops.
    func start(_ source: VoiceListener.Source = .capture, vocabulary: SpokenCapture.Vocabulary,
               now: @escaping () -> Date = { .now }) {
        guard !isActive else { return }
        run += 1
        let run = run
        failure = nil
        usedIntelligence = false
        filledField = false
        intelligence = VoiceIntelligence.current()
        let interpreter = VoiceTaskInterpreter()
        interpreter.prepare()
        self.interpreter = interpreter
        listener.onStop = { [weak self] transcript in
            Task { await self?.understand(transcript, vocabulary: vocabulary, now: now(), run: run) }
        }
        listener.start(source, contextualStrings: vocabulary.contextualStrings)
    }

    /// Stops listening now and reads what was said so far.
    func stop() {
        listener.stop()
    }

    /// Stops and forgets what was heard.
    func cancel() {
        run += 1
        listener.cancel()
        isUnderstanding = false
        failure = nil
        filledField = false
    }

    /// Puts a failure away, as the capture does once its text changes.
    func dismissFailure() {
        failure = nil
        if case .failed = listener.state { listener.cancel() }
    }

    private func understand(_ transcript: String, vocabulary: SpokenCapture.Vocabulary, now: Date, run: Int) async {
        guard self.run == run else { return }
        guard !transcript.isEmpty else {
            failure = .nothingHeard
            return
        }
        isUnderstanding = true
        let interpreter = interpreter ?? VoiceTaskInterpreter()
        let result = await interpreter.interpret(transcript, vocabulary: vocabulary, reference: now)
        guard self.run == run else { return }
        isUnderstanding = false
        usedIntelligence = result.usedIntelligence
        guard !result.tasks.isEmpty else {
            failure = .nothingHeard
            return
        }
        onHeard?(result.tasks)
    }
}

extension VoiceCapture {
    /// Voice capture's one control, a capture card's mic and ⌥⌘V alike:
    /// starts listening for `draft`, whose capture takes what's heard, read
    /// against `lists` and `labels`; while listening, stops and reads what
    /// was said; while getting ready, stops.
    func toggle<Draft: NXCaptureDraft>(for draft: Draft, lists: [TaskList], labels: [TaskLabel]) {
        switch phase {
        case .listening: stop()
        case .preparing: cancel()
        case .understanding: break
        case .idle, .failed:
            draft.spokenTasks = []
            onHeard = { [weak self, weak draft] heard in
                guard let draft else { return }
                self?.filledField = draft.take(heard)
            }
            start(vocabulary: SpokenCapture.Vocabulary(lists: lists, labels: labels))
        }
    }
}
