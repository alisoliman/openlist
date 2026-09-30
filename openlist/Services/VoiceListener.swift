//
//  VoiceListener.swift
//  openlist
//

import AVFoundation
import Foundation
import Observation
import Speech

/// Why voice capture couldn't listen, or heard nothing to add.
enum VoiceCaptureFailure: Equatable {
    case microphoneDenied
    case noMicrophone
    case unsupportedLanguage
    case nothingHeard
    case failed(String)

    var message: String {
        switch self {
        case .microphoneDenied: "Openlist can’t use the microphone. Allow it in Privacy & Security ▸ Microphone."
        case .noMicrophone: "There’s no microphone to listen with."
        case .unsupportedLanguage: "Voice capture doesn’t support your language yet."
        case .nothingHeard: "Didn’t catch that. Try again, a little closer to the microphone."
        case let .failed(reason): "Voice capture stopped. \(reason)"
        }
    }
}

/// Listens for a spoken capture with the system's on-device speech model:
/// the words confirmed so far and the ones still being made out, until the
/// speaker pauses or `stop()` is called. The words come from the microphone,
/// or from a recording, which reads the same way.
@Observable
@MainActor
final class VoiceListener {
    enum State: Equatable {
        case idle
        /// Asking for the microphone, or fetching the language's speech
        /// model, with its progress once the download has one.
        case preparing(progress: Double?)
        case listening
        /// Stopped; the last words are being confirmed.
        case stopping
        case stopped
        case failed(VoiceCaptureFailure)
    }

    enum Source {
        case microphone
        case file(URL)

        /// What the capture listens to: the microphone, or in a Debug review
        /// session the recording `OpenlistVoiceRecording` names, so the
        /// simulator, UI tests and screenshots can say tasks.
        static var capture: Source {
            #if DEBUG
            if ReviewSession.identifier != nil, let path = ProcessInfo.processInfo.environment["OpenlistVoiceRecording"] {
                return .file(URL(fileURLWithPath: path))
            }
            #endif
            return .microphone
        }
    }

    private(set) var state: State = .idle
    /// Words the speech model has settled on.
    private(set) var confirmed = ""
    /// Words it's still making out, which may change.
    private(set) var tentative = ""
    /// The microphone's loudness, 0 to 1, for a level meter.
    private(set) var level: Double = 0
    /// The locale the words are read in, once listening.
    private(set) var locale: Locale?

    /// What was heard, once listening ends with no failure; empty when nothing was.
    @ObservationIgnored var onStop: ((String) -> Void)?

    var transcript: String { (confirmed + tentative).trimmingCharacters(in: .whitespacesAndNewlines) }

    var isActive: Bool {
        switch state {
        case .preparing, .listening, .stopping: true
        case .idle, .stopped, .failed: false
        }
    }

    /// How long a pause ends listening: shorter once every word is settled.
    static let pauseAfterSettled: TimeInterval = 1.3
    static let pauseWhileSettling: TimeInterval = 2.4
    /// Listening stops with nothing heard after this, and in any case after `longest`.
    static let silenceBeforeGivingUp: TimeInterval = 10
    static let longest: TimeInterval = 90

    @ObservationIgnored private var analyzer: SpeechAnalyzer?
    @ObservationIgnored private var capture: CaptureInputSequenceProvider?
    @ObservationIgnored private var input: AsyncStream<AnalyzerInput>.Continuation?
    @ObservationIgnored private var feeder: Task<Void, Never>?
    @ObservationIgnored private var reader: Task<Void, Never>?
    @ObservationIgnored private var watcher: Task<Void, Never>?
    @ObservationIgnored private var lastHeard = Date.distantPast
    @ObservationIgnored private var startedAt = Date.distantPast
    /// Bumped by each start and cancel, so a run that's been left behind stops.
    @ObservationIgnored private var run = 0

    /// Starts listening. `contextualStrings` are names worth recognising,
    /// such as the library's lists and labels.
    func start(_ source: Source = .microphone, contextualStrings: [String] = [], locale: Locale = .current) {
        guard !isActive else { return }
        run += 1
        let run = run
        confirmed = ""
        tentative = ""
        level = 0
        state = .preparing(progress: nil)
        Task { await begin(source, contextualStrings: contextualStrings, locale: locale, run: run) }
    }

    /// Stops listening and keeps what was heard: `onStop` gets it once the
    /// last words are confirmed.
    func stop() {
        switch state {
        case .listening:
            state = .stopping
            let run = run
            Task { await finish(run: run) }
        case .preparing:
            cancel()
            state = .stopped
            onStop?("")
        default:
            break
        }
    }

    /// Stops listening and forgets what was heard.
    func cancel() {
        run += 1
        let analyzer = analyzer
        tearDown()
        confirmed = ""
        tentative = ""
        state = .idle
        if let analyzer { Task { await analyzer.cancelAndFinishNow() } }
    }

    // MARK: Listening

    private func begin(_ source: Source, contextualStrings: [String], locale: Locale, run: Int) async {
        do {
            if case .microphone = source, !(await Self.microphoneAccess()) { return fail(.microphoneDenied, run: run) }
            guard let module = await VoiceModule.make(for: locale) else { return fail(.unsupportedLanguage, run: run) }
            try await install(module, run: run)
            guard self.run == run else { return }
            self.locale = module.locale

            let analyzer = SpeechAnalyzer(modules: [module.module],
                                          options: SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .lingering))
            let context = AnalysisContext()
            context.contextualStrings[.general] = contextualStrings
            try await analyzer.setContext(context)
            let (stream, input) = AsyncStream<AnalyzerInput>.makeStream()
            try await analyzer.start(inputSequence: stream)
            guard self.run == run else {
                await analyzer.cancelAndFinishNow()
                return
            }
            self.analyzer = analyzer
            self.input = input
            reader = Task { await read(module.updates, run: run) }

            switch source {
            case .microphone:
                guard let device = AVCaptureDevice.default(for: .audio) else { return fail(.noMicrophone, run: run) }
                let capture = try await CaptureInputSequenceProvider.providerWithSession(from: device, compatibleWith: [module.module])
                guard self.run == run else { return }
                self.capture = capture
                let inputs = capture.analyzerInputs
                feeder = Task.detached {
                    do { for try await element in inputs { input.yield(element) } } catch {}
                }
                nonisolated(unsafe) let session = capture.captureSession
                await Task.detached { session.startRunning() }.value
                // Cancelled while the microphone was starting.
                guard self.run == run else {
                    Task.detached { session.stopRunning() }
                    return
                }
                guard session.isRunning else { return fail(.failed("The microphone didn’t start."), run: run) }
            case let .file(url):
                let converter = try await AnalyzerInputConverter.converter(compatibleWith: [module.module])
                nonisolated(unsafe) let converting = converter
                feeder = Task.detached { [weak self] in
                    await Self.play(url, converter: converting, into: input)
                    await self?.stop()
                }
            }
            guard self.run == run else { return }
            startedAt = .now
            lastHeard = .now
            state = .listening
            watcher = Task { await watch(run: run) }
        } catch {
            fail(.failed(error.localizedDescription), run: run)
        }
    }

    /// The speech model's words as they come: settled words add up, and the
    /// ones still being made out replace the last guess.
    private func read(_ updates: AsyncThrowingStream<(text: String, isFinal: Bool), Error>, run: Int) async {
        do {
            for try await update in updates {
                guard self.run == run else { return }
                if update.isFinal {
                    confirmed += update.text
                    tentative = ""
                } else {
                    tentative = update.text
                }
                lastHeard = .now
            }
        } catch {}
    }

    /// Meters the microphone and ends listening at a pause, after a silence
    /// with nothing said, or at the longest capture.
    private func watch(run: Int) async {
        while self.run == run, state == .listening {
            try? await Task.sleep(for: .milliseconds(50))
            guard self.run == run, state == .listening else { return }
            if let channel = capture?.captureAudioDataOutput.connections.first?.audioChannels.first {
                // -55 dB and below is a quiet room; -10 dB is loud speech.
                let loudness = max(0, min(1, (Double(channel.averagePowerLevel) + 55) / 45))
                level = level * 0.6 + loudness * 0.4
            }
            let now = Date.now
            let quiet = now.timeIntervalSince(lastHeard)
            if transcript.isEmpty {
                if now.timeIntervalSince(startedAt) > Self.silenceBeforeGivingUp { stop() }
            } else if quiet > (tentative.isEmpty ? Self.pauseAfterSettled : Self.pauseWhileSettling) {
                stop()
            }
            if now.timeIntervalSince(startedAt) > Self.longest { stop() }
        }
    }

    /// Confirms the last words, ends the input and waits for the model to say
    /// it has nothing more.
    private func finish(run: Int) async {
        let analyzer = analyzer
        await stopCapture()
        try? await analyzer?.finalize(through: nil)
        input?.finish()
        let done = Task { try? await analyzer?.finalizeAndFinishThroughEndOfInput() }
        let deadline = Task {
            try? await Task.sleep(for: .seconds(3))
            await analyzer?.cancelAndFinishNow()
        }
        await done.value
        await reader?.value
        deadline.cancel()
        guard self.run == run else { return }
        // Words never settled still count: they're the best guess there is.
        confirmed += tentative
        tentative = ""
        tearDown()
        state = .stopped
        onStop?(transcript)
    }

    private func fail(_ failure: VoiceCaptureFailure, run: Int) {
        guard self.run == run else { return }
        let analyzer = analyzer
        tearDown()
        if let analyzer { Task { await analyzer.cancelAndFinishNow() } }
        state = .failed(failure)
    }

    private func stopCapture() async {
        feeder?.cancel()
        feeder = nil
        watcher?.cancel()
        watcher = nil
        level = 0
        guard let capture else { return }
        self.capture = nil
        nonisolated(unsafe) let session = capture.captureSession
        await Task.detached { session.stopRunning() }.value
    }

    private func tearDown() {
        feeder?.cancel()
        watcher?.cancel()
        reader?.cancel()
        input?.finish()
        if let capture {
            nonisolated(unsafe) let session = capture.captureSession
            Task.detached { session.stopRunning() }
        }
        feeder = nil
        watcher = nil
        reader = nil
        input = nil
        capture = nil
        analyzer = nil
        level = 0
    }

    // MARK: Set-up

    private static func microphoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .audio)
        default: false
        }
    }

    /// Fetches the language's speech model the first time it's used.
    private func install(_ module: VoiceModule, run: Int) async throws {
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [module.module]) else { return }
        let progress = request.progress
        let meter = Task {
            while !Task.isCancelled, self.run == run {
                state = .preparing(progress: progress.fractionCompleted)
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        defer { meter.cancel() }
        try await request.downloadAndInstall()
    }

    /// Plays a recording into the analyzer at the pace it was spoken, as the
    /// microphone would, then ends.
    nonisolated private static func play(_ url: URL, converter: AnalyzerInputConverter,
                                         into input: AsyncStream<AnalyzerInput>.Continuation) async {
        guard let file = try? AVAudioFile(forReading: url) else { return }
        let format = file.processingFormat
        let chunk = AVAudioFrameCount(max(1, format.sampleRate / 10))
        // A moment of quiet first, as a microphone has before anyone speaks,
        // so the first word isn't clipped.
        if let quiet = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk * 3) {
            quiet.frameLength = quiet.frameCapacity
            for element in (try? converter.convert(quiet, at: nil)) ?? [] { input.yield(element) }
        }
        while file.framePosition < file.length, !Task.isCancelled {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk),
                  (try? file.read(into: buffer, frameCount: chunk)) != nil,
                  let inputs = try? converter.convert(buffer, at: nil) else { return }
            for element in inputs { input.yield(element) }
            try? await Task.sleep(for: .milliseconds(100))
        }
        if let rest = try? converter.flush() { for element in rest { input.yield(element) } }
        // A moment of silence after the last word, as a speaker pauses.
        try? await Task.sleep(for: .milliseconds(600))
    }
}

/// The speech model voice capture listens with: the system's newest one
/// where the device runs it, else the dictation model every device has.
private enum VoiceModule {
    case speech(SpeechTranscriber)
    case dictation(DictationTranscriber)

    static func make(for locale: Locale) async -> VoiceModule? {
        if SpeechTranscriber.isAvailable, let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
            return .speech(SpeechTranscriber(locale: supported, transcriptionOptions: [],
                                             reportingOptions: [.volatileResults, .fastResults], attributeOptions: []))
        }
        if let supported = await DictationTranscriber.supportedLocale(equivalentTo: locale) {
            return .dictation(DictationTranscriber(locale: supported, contentHints: [.shortForm],
                                                   transcriptionOptions: [.punctuation],
                                                   reportingOptions: [.volatileResults], attributeOptions: []))
        }
        return nil
    }

    var module: any SpeechModule {
        switch self {
        case let .speech(transcriber): transcriber
        case let .dictation(transcriber): transcriber
        }
    }

    var locale: Locale? {
        switch self {
        case let .speech(transcriber): transcriber.selectedLocales.first
        case let .dictation(transcriber): transcriber.selectedLocales.first
        }
    }

    /// Each result's words, and whether the model has settled on them.
    var updates: AsyncThrowingStream<(text: String, isFinal: Bool), Error> {
        switch self {
        case let .speech(transcriber): Self.updates(transcriber.results) { (String($0.text.characters), $0.isFinal) }
        case let .dictation(transcriber): Self.updates(transcriber.results) { (String($0.text.characters), $0.isFinal) }
        }
    }

    private static func updates<Results: AsyncSequence & Sendable>(
        _ results: Results, _ read: @escaping @Sendable (Results.Element) -> (text: String, isFinal: Bool)
    ) -> AsyncThrowingStream<(text: String, isFinal: Bool), Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached {
                do {
                    for try await result in results { continuation.yield(read(result)) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
