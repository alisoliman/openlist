//
//  VoiceTaskInterpreter.swift
//  openlist
//

import Foundation
import FoundationModels

/// What Apple Intelligence can do for voice capture here and now.
enum VoiceIntelligence: Equatable {
    case available
    /// Turned off in Settings: what's said is read as one task.
    case off
    /// The model is still downloading or otherwise getting ready.
    case notReady
    /// This device, or the language spoken, can't run it.
    case unsupported

    static func current(for locale: Locale = .current) -> VoiceIntelligence {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return model.supportsLocale(locale) ? .available : .unsupported
        case .unavailable(.appleIntelligenceNotEnabled):
            return .off
        case .unavailable(.modelNotReady):
            return .notReady
        case .unavailable:
            return .unsupported
        }
    }

    /// What the capture says about it, when it isn't helping.
    var note: String? {
        switch self {
        case .available, .unsupported: nil
        case .off: "Turn on Apple Intelligence to say several tasks at once."
        case .notReady: "Apple Intelligence is getting ready; this reads as one task."
        }
    }
}

/// The to-dos Apple Intelligence heard: each one's title, the words said
/// about it, and its day or time in English.
@Generable(description: "The separate to-dos in what someone said")
nonisolated struct HeardTasks {
    @Guide(description: "One entry per separate thing to do, in the order said", .maximumCount(12))
    var tasks: [HeardTask]
}

@Generable
nonisolated struct HeardTask {
    @Guide(description: "The to-do in the speaker's own language and words, starting with a verb and keeping what it's about, without filler and without its day, time, repeat, list, labels, priority or duration")
    var title: String
    @Guide(description: "The exact words said about this to-do, copied from what they said, including its day, time, list, labels, priority and duration")
    var said: String
    @Guide(description: "The day, time or repeat said for this to-do, in short English such as 'tomorrow 5pm', 'every monday 9am' or 'dec 3'")
    var when: String?
}

/// Reads a transcript into tasks. With Apple Intelligence, the on-device
/// model splits it into separate to-dos and titles each; `SpokenCapture`
/// then reads each one's list, labels, priority, duration and date from the
/// words actually said. Without it, or if the model fails, everything said
/// is one task, read the same way.
@MainActor
final class VoiceTaskInterpreter {
    struct Result {
        var tasks: [SpokenTask]
        /// Whether Apple Intelligence split and titled them.
        var usedIntelligence: Bool
    }

    let locale: Locale
    private var session: LanguageModelSession?

    init(locale: Locale = .current) {
        self.locale = locale
    }

    /// Loads the model while the speaker is still talking, so reading what
    /// they said doesn't wait for it.
    func prepare() {
        guard VoiceIntelligence.current(for: locale) == .available, session == nil else { return }
        let session = LanguageModelSession(instructions: Self.instructions)
        session.prewarm()
        self.session = session
    }

    func interpret(_ transcript: String, vocabulary: SpokenCapture.Vocabulary, reference: Date) async -> Result {
        let transcript = String(transcript.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2000))
        guard !transcript.isEmpty else { return Result(tasks: [], usedIntelligence: false) }
        if VoiceIntelligence.current(for: locale) == .available {
            let session = self.session ?? LanguageModelSession(instructions: Self.instructions)
            // One transcript per session: a session remembers its turns.
            self.session = nil
            if let heard = await Self.split(transcript, with: session) {
                let tasks = Self.tasks(from: heard, transcript: transcript, vocabulary: vocabulary, reference: reference,
                                       translatesDates: locale.language.languageCode != .english)
                if !tasks.isEmpty { return Result(tasks: tasks, usedIntelligence: true) }
            }
        }
        return Result(tasks: SpokenCapture.fallback(transcript, vocabulary: vocabulary, reference: reference),
                      usedIntelligence: false)
    }

    /// The model's to-dos, or nil if it fails or takes too long.
    private static func split(_ transcript: String, with session: LanguageModelSession) async -> [HeardTask]? {
        let work = Task { @MainActor in
            try await session.respond(to: "They said: \"\(transcript)\"", generating: HeardTasks.self,
                                      options: GenerationOptions(samplingMode: .greedy)).content.tasks
        }
        let deadline = Task { @MainActor in
            try await Task.sleep(for: .seconds(15))
            work.cancel()
        }
        defer { deadline.cancel() }
        return try? await work.value
    }

    /// The tasks in what the model heard, read against what was said: a
    /// to-do whose title wasn't said (its instructions' example, say) is
    /// dropped, and one it heard twice is kept once. Each is read from its
    /// own part of what was said, and a single to-do from all of it, so a
    /// list or priority said anywhere is its.
    /// The model's English `when` is read only for a language `DateParser`
    /// doesn't read (`translatesDates`); in English the words said decide.
    static func tasks(from heard: [HeardTask], transcript: String, vocabulary: SpokenCapture.Vocabulary,
                      reference: Date, translatesDates: Bool = false) -> [SpokenTask] {
        let grounded = heard.filter { SpokenCapture.isGrounded($0.title, in: transcript) }
        // Each to-do's words run to the next one's, and a part that only says
        // how long, how urgent or where ("It takes 15 minutes.") belongs to the
        // to-do before it, even when the model made it one of its own.
        let spans = SpokenCapture.spans(startingWith: grounded.map { $0.said.isEmpty ? $0.title : $0.said }, in: transcript)
        var parts: [(task: HeardTask, said: String)] = []
        for (task, span) in zip(grounded, spans) {
            if let span, !parts.isEmpty, SpokenCapture.isOnlyCues(span, vocabulary: vocabulary) {
                parts[parts.count - 1].said += span
                continue
            }
            let said = span ?? (SpokenCapture.isGrounded(task.said, in: transcript) ? task.said : task.title)
            parts.append((task, said))
        }
        var tasks: [SpokenTask] = []
        for (task, said) in parts {
            let said = parts.count == 1 ? transcript : said
            // Where dates aren't read from the words, they'd stay in them.
            let own = !translatesDates && SpokenCapture.isGrounded(task.said, in: transcript) ? task.said : nil
            guard let spoken = SpokenCapture.task(from: said, title: task.title, ownWords: own,
                                                  when: translatesDates ? task.when : nil,
                                                  vocabulary: vocabulary, reference: reference),
                  !tasks.contains(where: { $0.snapshot.title.caseInsensitiveCompare(spoken.snapshot.title) == .orderedSame })
            else { continue }
            tasks.append(spoken)
        }
        return tasks
    }

    private static let instructions = """
        You split what someone said aloud into the separate to-dos they want in their task app. \
        Never add a to-do, day or time they didn't say. Things done together, such as buying several \
        groceries, are one to-do. A sentence that only says when, how long, how urgent, or which list or label \
        is about the to-do before it, not a new to-do. Leave out anything that isn't a to-do, such as thanks.

        For example, "remind me to call the plumber tomorrow at 9 and email Sam about the invoice" is two to-dos: \
        title "Call the plumber", said "call the plumber tomorrow at 9", when "tomorrow 9am"; and \
        title "Email Sam about the invoice", said "email Sam about the invoice".
        """
}
