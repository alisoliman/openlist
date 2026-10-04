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
    private(set) var completionMode = AppSettings.AfterVoiceCapture.reviewBeforeSaving
    /// Gets the tasks heard, in the order said, once they're read.
    @ObservationIgnored var onHeard: (([SpokenTask]) -> Void)?

    private var isUnderstanding = false
    private var failure: VoiceCaptureFailure?
    @ObservationIgnored private var interpreter: VoiceTaskInterpreter?
    @ObservationIgnored private var session = VoiceCaptureSession()

    var generation: Int { session.generation }

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
               afterCapture: AppSettings.AfterVoiceCapture = .reviewBeforeSaving, hasDraft: Bool = false,
               now: @escaping () -> Date = { .now }) {
        guard !isActive else { return }
        let run = session.begin(afterCapture: afterCapture, hasDraft: hasDraft)
        failure = nil
        usedIntelligence = false
        filledField = false
        intelligence = source.isFixture ? .unsupported : VoiceIntelligence.current()
        if !source.isFixture {
            let interpreter = VoiceTaskInterpreter()
            interpreter.prepare()
            self.interpreter = interpreter
        }
        listener.onStop = { [weak self] transcript in
            guard let self else { return }
            if case .failed = self.listener.state { return }
            guard self.session.beginUnderstanding(run: run) else { return }
            self.isUnderstanding = true
            Task { [weak self] in
                await self?.understand(transcript, vocabulary: vocabulary, now: now(), run: run, usesFixture: source.isFixture)
            }
        }
        listener.start(source, contextualStrings: vocabulary.contextualStrings)
    }

    /// Stops listening now and reads what was said so far.
    func stop() {
        listener.stop()
    }

    func applicationResignedActive() {
        switch listener.state {
        case .preparing:
            cancel()
        case .listening:
            preserveForReview()
            stop()
        case .idle, .stopping, .stopped, .failed:
            break
        }
    }

    func preserveForReview() {
        session.requireReview()
    }

    func sceneDepartedActive(isBackground: Bool) {
        if isActive, case .preparing = phase {
            if isBackground { cancel() }
            return
        }
        if isActive { preserveForReview() }
        if phase == .listening { stop() }
    }

    /// Stops and forgets what was heard.
    func cancel() {
        session.cancel()
        listener.cancel()
        listener.onStop = nil
        onHeard = nil
        interpreter = nil
        isUnderstanding = false
        failure = nil
        filledField = false
    }

    /// Puts a failure away, as the capture does once its text changes.
    func dismissFailure() {
        failure = nil
        if case .failed = listener.state { cancel() }
    }

    private func understand(_ transcript: String, vocabulary: SpokenCapture.Vocabulary, now: Date, run: Int, usesFixture: Bool) async {
        guard session.isCurrent(run: run) else { return }
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            _ = session.complete(run: run, hasTasks: false)
            isUnderstanding = false
            failure = .nothingHeard
            return
        }
        let result: VoiceTaskInterpreter.Result
        #if DEBUG
        if usesFixture {
            result = VoiceTaskInterpreter.Result(tasks: transcript.components(separatedBy: .newlines).flatMap {
                SpokenCapture.fallback($0, vocabulary: vocabulary, reference: now)
            }, usedIntelligence: false)
        } else {
            result = await (interpreter ?? VoiceTaskInterpreter()).interpret(transcript, vocabulary: vocabulary, reference: now)
        }
        #else
        result = await (interpreter ?? VoiceTaskInterpreter()).interpret(transcript, vocabulary: vocabulary, reference: now)
        #endif
        guard session.isCurrent(run: run) else { return }
        isUnderstanding = false
        usedIntelligence = result.usedIntelligence
        guard let mode = session.complete(run: run, hasTasks: !result.tasks.isEmpty) else {
            failure = .nothingHeard
            return
        }
        completionMode = mode
        onHeard?(result.tasks)
    }
}

extension VoiceCapture {
    /// Voice capture's one control, a capture card's mic and ⌥⌘V alike:
    /// starts listening for `draft`, whose capture takes what's heard, read
    /// against `lists` and `labels`; while listening, stops and reads what
    /// was said; while getting ready, stops.
    func toggle<Draft: NXCaptureDraft>(for draft: Draft, lists: [TaskList], labels: [TaskLabel],
                                     onSave: ((NXCaptureOutcome) -> Void)? = nil) {
        switch phase {
        case .listening: stop()
        case .preparing: cancel()
        case .understanding: break
        case .idle, .failed:
            onHeard = { [weak self, weak draft] heard in
                guard let self, let draft else { return }
                if let outcome = draft.receiveVoice(heard, afterCapture: self.completionMode) {
                    onSave?(outcome)
                } else {
                    self.filledField = draft.spokenTasks.isEmpty && !draft.captureText.isEmpty
                }
            }
            start(vocabulary: SpokenCapture.Vocabulary(lists: lists, labels: labels),
                  afterCapture: onSave == nil ? .reviewBeforeSaving : draft.settings.afterVoiceCapture,
                  hasDraft: draft.hasCaptureDraft)
        }
    }
}
