//
//  SpokenCapture.swift
//  openlist
//

import Foundation

/// A task heard in speech, as voice capture shows it before Add: what saving
/// it makes (the `CaptureSnapshot` a typed capture saves) and the list the
/// speaker named, if they named one.
struct SpokenTask: Identifiable {
    let id = UUID()
    var snapshot: CaptureSnapshot
    /// A list the speaker named; nil files it where the capture is aimed.
    var listID: UUID?
    /// The words its day, time and repeat were read from, for `line`.
    var whenText: String?

    /// The task as a capture line, to edit as typed text: its title, the
    /// words its date was read from, then its labels, priority and estimate
    /// as tokens, which the capture card tints and reads back the same way.
    var line: String {
        var parts = [snapshot.title]
        if let whenText, !whenText.isEmpty { parts.append(whenText) }
        parts += snapshot.labels.filter { !$0.contains(" ") }.map { "#" + $0 }
        switch snapshot.priority {
        case .high: parts.append("!high")
        case .medium: parts.append("!med")
        case .low: parts.append("!low")
        case .none: break
        }
        let minutes = snapshot.estimateMinutes
        if minutes > 0 { parts.append(minutes % 60 == 0 ? "~\(minutes / 60)h" : "~\(minutes)m") }
        return parts.joined(separator: " ")
    }
}

extension SpokenTask {
    /// Whether `line`, typed into the capture field, saves this same task.
    /// The capture puts a single heard task there, to edit before Add; one
    /// that wouldn't read back the same (a title holding a date's words, or
    /// dates the capture isn't reading) stays a row instead.
    func fitsField(parsesDates: Bool, reference: Date) -> Bool {
        let back = CaptureParse(line, parsesDates: parsesDates, reference: reference).snapshot()
        return back.title == snapshot.title && back.date == snapshot.date && back.includesTime == snapshot.includesTime
            && back.recurrence == snapshot.recurrence && Set(back.labels) == Set(snapshot.labels)
            && back.priority == snapshot.priority && back.estimateMinutes == snapshot.estimateMinutes
    }
}

extension SpokenTask {
    /// Chips for what Add saves, as a capture card shows a typed task's: its
    /// day, time, repeat, labels, priority and estimate.
    func chips(now: Date = .now) -> [CaptureChip] {
        var chips: [CaptureChip] = []
        if let date = snapshot.date {
            chips.append(CaptureChip(id: "date", kind: .day, label: NXFormat.typedDay(date, now: now)))
            if snapshot.includesTime { chips.append(CaptureChip(id: "time", kind: .time, label: NXFormat.clock(date))) }
        }
        if let rule = snapshot.recurrence {
            chips.append(CaptureChip(id: "repeat", kind: .repeatRule, label: rule.displayText))
        }
        for label in snapshot.labels { chips.append(CaptureChip(id: "label-\(label)", kind: .label, label: label)) }
        if snapshot.priority != .none {
            chips.append(CaptureChip(id: "priority", kind: .priority(snapshot.priority), label: snapshot.priority.title))
        }
        let minutes = snapshot.estimateMinutes
        if minutes > 0 {
            chips.append(CaptureChip(id: "estimate", kind: .estimate,
                                     label: "\(minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes)m") estimate"))
        }
        return chips
    }
}

/// Reads what someone said as a capture: the filler around a task ("remind
/// me to", "um"), and the list, labels, priority and duration said in words
/// ("to my Kyoto trip list", "tag it travel", "it's urgent", "takes 15
/// minutes"), which typed capture reads from `#`, `!` and `~` tokens. Days
/// and times go to the typed capture's own `DateParser`, after spoken times
/// are put the way it reads them ("at 5" said aloud is 5pm).
///
/// It is the whole reading when Apple Intelligence is off, and grounds it
/// when on: the model only splits the words into tasks and titles them, and
/// everything else here is read from what was actually said, so a model
/// can't invent a list, a label or a date.
enum SpokenCapture {
    /// What the capture knows of the library to read speech against.
    struct Vocabulary {
        var lists: [(id: UUID, name: String)] = []
        var labels: [String] = []

        init(lists: [(id: UUID, name: String)] = [], labels: [String] = []) {
            self.lists = lists
            self.labels = labels
        }

        /// The lists that take tasks, by the names they show, and every label.
        init(lists: [TaskList], labels: [TaskLabel]) {
            self.init(lists: lists.filter { !$0.isEffectivelyArchived }.map { ($0.id, $0.displayTitle) },
                      labels: labels.map(\.name))
        }

        /// Names worth biasing the speech model towards.
        var contextualStrings: [String] {
            Array((lists.map(\.name) + labels).prefix(100))
        }
    }

    /// What `cues(in:vocabulary:)` read, and what's left to read dates and a
    /// title from.
    struct Cues {
        var priority: TaskPriority?
        var estimateMinutes: Int?
        var labels: [String] = []
        var listID: UUID?
        /// The words without the cues, filler and lead-in.
        var remainder: String
    }

    // MARK: Tasks

    /// Everything said, read as one task, as it is without Apple Intelligence.
    static func fallback(_ transcript: String, vocabulary: Vocabulary, reference: Date) -> [SpokenTask] {
        task(from: transcript, vocabulary: vocabulary, reference: reference).map { [$0] } ?? []
    }

    /// One task from the words said about it. `title` is a model's reading
    /// of them, used in place of the words left once everything else is
    /// taken out, unless those words (from `ownWords`, the model's copy of
    /// just this task's) start with it and say more: "Email Priya" said as
    /// "email Priya about the hotel" is the latter. `when` is its reading of
    /// the day and time, used only when the words themselves name none (a
    /// language `DateParser` doesn't read).
    static func task(from said: String, title: String? = nil, ownWords: String? = nil, when: String? = nil,
                     vocabulary: Vocabulary, reference: Date) -> SpokenTask? {
        let cues = cues(in: said, vocabulary: vocabulary)
        let parse = CaptureParse(spokenTimes(cues.remainder), parsesDates: true, reference: reference)
        var schedule = parse.schedule
        var whenWords = parse.marks.filter { [.date, .time, .repeatRule].contains($0.kind) }
            .map { $0.raw.trimmingCharacters(in: CharacterSet(charactersIn: ".,")) }
        if schedule == nil, let when = when?.trimmingCharacters(in: .whitespacesAndNewlines), !when.isEmpty {
            let parsed = DateParser.parse(spokenTimes(when), reference: reference)
            if !parsed.isEmpty {
                schedule = parsed
                whenWords = [when]
            }
        }
        var name = tidyTitle(title.map { without(whenWords, in: $0, reference: reference) } ?? parse.title)
        if title != nil, let ownWords {
            let own = tidyTitle(CaptureParse(spokenTimes(Self.cues(in: ownWords, vocabulary: vocabulary).remainder),
                                             parsesDates: true, reference: reference).title)
            let short = words(name), long = words(own)
            if long.count > short.count, long.starts(with: short) { name = own }
        }
        guard !name.isEmpty else { return nil }
        var labels: [String] = []
        for label in cues.labels + parse.labels where !labels.contains(label) { labels.append(label) }
        let snapshot = CaptureSnapshot(
            title: name,
            date: schedule?.date,
            includesTime: schedule?.includesTime ?? false,
            recurrence: schedule?.recurrence,
            labels: labels,
            priority: cues.priority ?? parse.priority ?? .none,
            estimateMinutes: cues.estimateMinutes ?? parse.estimateMinutes ?? 0)
        return SpokenTask(snapshot: snapshot, listID: cues.listID,
                          whenText: whenWords.isEmpty ? nil : whenWords.joined(separator: " "))
    }

    /// A model's title without the day and time it was asked to leave out
    /// but kept anyway: only phrases also read from what was said, so a
    /// "Monday" that is part of the task's name stays.
    private static func without(_ whenWords: [String], in title: String, reference: Date) -> String {
        let said = Set(whenWords.map { $0.lowercased() })
        let parse = CaptureParse(title, parsesDates: true, reference: reference)
        var text = title
        for mark in parse.marks.reversed() where [.date, .time, .repeatRule].contains(mark.kind) {
            if said.contains(where: { $0.contains(mark.raw.lowercased()) }) { text.removeSubrange(mark.range) }
        }
        return text.replacingOccurrences(of: #"\s+(?:on|at|by|due)\s*$"#, with: "", options: [.regularExpression, .caseInsensitive])
    }

    // MARK: Cues

    /// Reads the spoken list, labels, priority and duration out of `said`,
    /// and takes them, the lead-in and filler words out of what's left.
    static func cues(in said: String, vocabulary: Vocabulary) -> Cues {
        var text = " " + said + " "
        var cues = Cues(remainder: "")
        cues.priority = takePriority(from: &text)
        cues.estimateMinutes = takeEstimate(from: &text)
        cues.labels = takeLabels(from: &text, known: vocabulary.labels)
        let startsWithVerb = matches(addVerb, in: stripLeadIn(text))
        cues.listID = takeList(from: &text, lists: vocabulary.lists, afterAddVerb: startsWithVerb)
        text = stripLeadIn(text)
        // "Add call mum to my Family list": with the list read, the verb was
        // the request, not the task.
        if cues.listID != nil {
            text = replacing(addVerb, in: text, with: "")
            text = replacing(#",?\s*\b(?:put|add|file|save|stick|throw|move)\s+(?:it|this|that|them)\b"#, in: text, with: " ")
        }
        text = replacing(#"(?:^|(?<=[\s,]))(?:um+|uh+|uhm|erm|er|hmm+)(?=[\s,.!?]|$),?"#, in: text, with: " ")
        text = replacing(#"[\s,]*\b(?:please|thanks|thank\s+you|thx|okay|ok|for\s+me)[\s.!]*$"#, in: text, with: "")
        cues.remainder = tidy(text)
        return cues
    }

    // MARK: Priority

    private static let predicate = #"(?:(?:it'?s|it\s+is|this\s+is|that'?s|make\s+it|mark\s+it(?:\s+as)?|flag\s+it(?:\s+as)?)\s+)"#
    private static let intensifier = #"(?:(?:very|really|super|extremely|quite)\s+)"#

    /// Low first, so "not urgent" is low rather than urgent.
    private static let priorityPatterns: [(TaskPriority, String)] = [
        (.low, #"\b\#(predicate)?(?:a\s+)?(?:low|lowest)[\s-]*priority\b"#),
        (.low, #"\b\#(predicate)?not\s+(?:urgent|important|a\s+priority)\b"#),
        (.low, #"\bno\s+rush\b"#),
        (.medium, #"\b\#(predicate)?(?:a\s+)?(?:medium|normal|mid|moderate)[\s-]*priority\b"#),
        (.high, #"\b\#(predicate)?(?:a\s+)?\#(intensifier)?(?:high|top|highest|urgent)[\s-]*priority\b"#),
        (.high, #"\bpriority\s+(?:one|1|high)\b"#),
        (.high, #"\b\#(predicate)\#(intensifier)?(?:urgent|important|critical|a\s+priority)\b"#),
        // On its own between commas or full stops: "…, urgent." "Important."
        (.high, #"(?:^|(?<=[,.;!?]))\s*\#(intensifier)?(?:urgent|important|critical)\s*(?=[,.;!?]|$)"#),
        (.high, #"\b(?:asap|a\.s\.a\.p\.?)"#),
        (.high, #"\burgently\b"#),
    ]

    private static func takePriority(from text: inout String) -> TaskPriority? {
        for (priority, pattern) in priorityPatterns where take(pattern, from: &text) != nil {
            return priority
        }
        return nil
    }

    // MARK: Estimate

    private static let smallNumbers = ["a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
                                       "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
                                       "fifteen": 15, "twenty": 20, "thirty": 30, "forty": 40, "forty five": 45,
                                       "forty-five": 45, "fifty": 50, "sixty": 60, "ninety": 90]

    private static let amount = #"(?:\d+(?:[.,]\d+)?|an?|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|fifteen|twenty|thirty|forty[\s-]five|forty|fifty|sixty|ninety)"#
    private static let duration = #"(half\s+an?\s+hour|(?:an?|one)\s+hour\s+and\s+a\s+half|\#(amount)\s+and\s+a\s+half\s+hours?|a\s+couple(?:\s+of)?\s+hours|\#(amount)[\s-]*(?:minutes?|mins?|hours?|hrs?))\b"#
    private static let hedge = #"(?:(?:about|around|roughly|approximately|like|maybe|only|just)\s+)"#

    private static let estimatePatterns = [
        #"\b(?:(?:it|this|that)\s+)?(?:(?:will|'ll|should|might|would|could)\s+)?(?:takes?|taking|lasts?|needs?)\s+\#(hedge)?\#(duration)"#,
        // "for 2 hours", "about 15 minutes"; "in 15 minutes" is a due time.
        #"(?<!\bin\s)\b(?:for|about|around|roughly|approximately)\s+\#(hedge)?\#(duration)"#,
    ]

    private static func takeEstimate(from text: inout String) -> Int? {
        for pattern in estimatePatterns {
            guard let groups = take(pattern, from: &text), let phrase = groups[1] else { continue }
            if let minutes = minutes(in: phrase) { return minutes }
        }
        return nil
    }

    /// Minutes in "15 minutes", "2 hours", "an hour and a half", "1.5 hrs",
    /// capped at the store's four-week limit.
    static func minutes(in phrase: String) -> Int? {
        let text = phrase.lowercased().replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let cap = 60 * 24 * 28
        if text.hasPrefix("half a") { return 30 }
        if text.contains("couple") { return 120 }
        let isHours = text.range(of: #"\b(?:hours?|hrs?)\b"#, options: .regularExpression) != nil
        let lead = text.range(of: amount, options: [.regularExpression, .anchored]).map { String(text[$0]) } ?? ""
        guard var number = smallNumbers[lead].map(Double.init) ?? Double(lead.replacingOccurrences(of: ",", with: "."))
        else { return nil }
        if text.contains("and a half") { number += 0.5 }
        guard number > 0 else { return nil }
        return min(Int((isHours ? number * 60 : number).rounded()), cap)
    }

    // MARK: Labels

    private static let labelWord = #"#?([\p{L}\p{N}_-]+)"#
    private static let notLabels: Set<String> = ["it", "this", "that", "them", "as", "with", "the", "a", "an", "to", "and", "under"]

    private static func takeLabels(from text: inout String, known: [String]) -> [String] {
        // "tag it travel and family": a label after "and" or a comma counts
        // only when it's one of the library's, so "tag it travel and call
        // mum" keeps its second task.
        let names = known.filter { !$0.isEmpty }.sorted { $0.count > $1.count }
            .map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        let more = names.isEmpty ? "()" : #"((?:\s*(?:,|\band\b|&)\s*#?(?:\#(names))\b)*)"#
        let patterns = [
            // "Tag it" is often heard as "tag to".
            #"\b(?:tag(?:ged)?|label(?:l?ed)?)\s+(?:it|this|that|them|to)\s+(?:(?:as|with|under)\s+)?\#(labelWord)\#(more)"#,
            #"\b(?:tag(?:ged)?|label(?:l?ed)?)\s+(?:as|with|under)\s+\#(labelWord)\#(more)"#,
            #"\b(?:tagged|label(?:l?ed))\s+\#(labelWord)\#(more)"#,
            #"\bhash\s?tag\s+\#(labelWord)\#(more)"#,
            #"\b(?:with|under)\s+(?:the\s+|a\s+)?\#(labelWord)\s+(?:tag|label)\b()"#,
            #"(?<![\p{L}\p{N}])#([\p{L}\p{N}_-]+)()"#,
        ]
        var labels: [String] = []
        func add(_ raw: String) {
            let name = TaskLabel.normalize(raw).lowercased()
            guard !name.isEmpty, !notLabels.contains(name), !labels.contains(name) else { return }
            labels.append(name)
        }
        for pattern in patterns {
            while let groups = take(pattern, from: &text) {
                if let first = groups[1] { add(first) }
                for word in (groups[2] ?? "").components(separatedBy: CharacterSet(charactersIn: ",&#"))
                    .flatMap({ $0.components(separatedBy: " and ") }) {
                    add(word.trimmingCharacters(in: .whitespaces))
                }
            }
        }
        return labels
    }

    // MARK: List

    private static let addVerb = #"^\s*(?:please\s+)?(?:add|put|file|save|stick|throw|move|drop|place)\b\s*"#

    /// "to my Kyoto trip list", "on the Work list"; after "add" or "put", a
    /// list's name alone at the end: "add call mum to Family"; and a list's
    /// name of more than a word anywhere: "flights for the Kyoto trip".
    private static func takeList(from text: inout String, lists: [(id: UUID, name: String)], afterAddVerb: Bool) -> UUID? {
        let named = lists.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { $0.name.count > $1.name.count }
        guard !named.isEmpty else { return nil }
        let names = named.map {
            NSRegularExpression.escapedPattern(for: $0.name).replacingOccurrences(of: #"\ "#, with: #"\s+"#)
        }.joined(separator: "|")
        let preposition = #"\b(?:to|on|in|into|onto|under|for)\s+(?:(?:my|the|our|your)\s+)?"#
        if let groups = take(#"\#(preposition)(\#(names))(?:'s)?\s+(?:list|project|folder|page)\b"#, from: &text),
           let id = list(named: groups[1], in: named) {
            return id
        }
        var probe = text
        if let groups = take(#"\#(preposition)([\p{L}\p{N}'’ &-]{1,40}?)\s+list\b"#, from: &probe),
           let id = list(named: groups[1], in: named) {
            text = probe
            return id
        }
        if afterAddVerb, let groups = take(#"\#(preposition)(\#(names))\s*(?=[.,;!?]|\s*$)"#, from: &text),
           let id = list(named: groups[1], in: named) {
            return id
        }
        // A list whose name is more than a word, mentioned with the task, is
        // where it goes, and its name stays in the title: "book flights for
        // the Japan trip". A one-word name is too often just a word: "drive to work".
        let phrases = named.filter { $0.name.split(separator: " ").count > 1 }.map {
            NSRegularExpression.escapedPattern(for: $0.name).replacingOccurrences(of: #"\ "#, with: #"\s+"#)
        }
        if !phrases.isEmpty,
           let groups = groups(#"\b(?:for|to|on|in|into|about)\s+(?:(?:my|the|our|your)\s+)?(\#(phrases.joined(separator: "|")))\b"#, in: text),
           let id = list(named: groups[1], in: named) {
            return id
        }
        return nil
    }

    /// The list `spoken` names: the same name, or the one list whose name
    /// contains it or is contained in it, singular or plural.
    static func list(named spoken: String?, in lists: [(id: UUID, name: String)]) -> UUID? {
        guard let spoken else { return nil }
        let heard = folded(spoken)
        guard heard.count >= 2 else { return nil }
        func stem(_ text: String) -> String {
            text.hasSuffix("es") ? String(text.dropLast(2)) : text.hasSuffix("s") ? String(text.dropLast()) : text
        }
        if let exact = lists.first(where: { folded($0.name) == heard || stem(folded($0.name)) == stem(heard) }) {
            return exact.id
        }
        guard heard.count >= 3 else { return nil }
        let near = lists.filter {
            let name = folded($0.name)
            return name.count >= 3 && (name.contains(heard) || heard.contains(name))
        }
        return near.count == 1 ? near[0].id : nil
    }

    // MARK: Lead-in and times

    private static let leadIn = #"^\s*(?:(?:hey|hi|ok|okay|so|um+|uh+|er+|erm|well|oh|alright|all\s+right|please|and|also|then|right)\b[\s,]*)*(?:(?:can|could|would|will)\s+you\s+(?:please\s+)?)?(?:please\s+)?(?:remind\s+me\s+(?:to|that\s+i\s+(?:need|have)\s+to|about)|remember\s+to|don'?t\s+(?:let\s+me\s+)?forget\s+(?:to|about)|i\s+(?:really\s+|still\s+|also\s+)?(?:need|have|want|ought)\s+to|i'?ve\s+got\s+to|i\s+got\s+to|i\s+gotta|i\s+should(?:\s+probably|\s+really)?|i\s+must|i'?d\s+like\s+to|i'?m\s+(?:going\s+to|gonna)|i'?ll|we\s+(?:need|have)\s+to|we\s+should|note\s+to\s+self|(?:add|create|make|new)\s+(?:a\s+)?(?:new\s+)?(?:task|to-?do|reminder|item)(?:\s+(?:to|for|that\s+says|called))?|to-?do)\b[\s:,]*"#

    /// `text` without what a request to remember something starts with:
    /// "Remind me to", "I need to", "Add a task to", and the "um, so" before it.
    static func stripLeadIn(_ text: String) -> String {
        replacing(leadIn, in: text, with: "")
    }

    private static let months = "january|jan|february|feb|march|mar|april|apr|may|june|jun|july|jul|august|aug|september|sept|sep|october|oct|november|nov|december|dec"

    /// Spoken times written as `DateParser` reads them: "the 3rd of October"
    /// is "3 October", "5 o'clock" is "at 5", "at 230" is "at 2:30", and "at
    /// 5" or "at 2:30" said aloud is in the afternoon, from one to six, where
    /// a typed "at 5" is 5am.
    static func spokenTimes(_ text: String) -> String {
        var text = text
        text = replacing(#"\b(?:the\s+)?(\d{1,2})(?:st|nd|rd|th)?\s+of\s+(\#(months))\b"#, in: text, with: "$1 $2")
        text = replacing(#"\b(?:at\s+)?(\d{1,2})\s*o'?\s*clock\b"#, in: text, with: "at $1")
        // The speech model writes "two thirty" as "230".
        text = replacing(#"\b(at|by|around|@)\s+([01]?\d|2[0-3])([0-5]\d)\b(?!\s*(?:%|percent))"#, in: text, with: "$1 $2:$3")
        text = replacing(#"\b(at|by|around|@)\s+([1-6])(:[0-5]\d)?\b(?!\s*(?:[ap]\.?\s?m\b|:\d|[\d%]|(?:minutes?|mins?|hours?|hrs?|days?|weeks?|percent)\b))"#,
                         in: text, with: "$1 $2$3pm")
        return text
    }

    // MARK: Spans

    /// Each to-do's part of what was said, from where it starts to where the
    /// next one does, given the words each starts with (a model's copy of
    /// them). The first part runs from the start, so a lead-in goes with it;
    /// the last to the end, so a closing "It's urgent" is the last to-do's.
    /// Nil for a to-do whose words can't be found.
    static func spans(startingWith leads: [String], in transcript: String) -> [String?] {
        let spoken = wordRanges(transcript)
        var starts: [Int?] = []
        var cursor = 0
        for lead in leads {
            let words = wordRanges(lead).map(\.word)
            var found: Int?
            search: for count in [3, 2, 1] where count <= words.count {
                let first = Array(words.prefix(count))
                if count == 1, minorWords.contains(first[0]) { continue }
                guard spoken.count >= count, cursor <= spoken.count - count else { continue }
                for index in cursor...(spoken.count - count)
                where zip(first, spoken[index..<(index + count)]).allSatisfy({ sameWord($0, $1.word) }) {
                    found = index
                    break search
                }
            }
            starts.append(found)
            if let found { cursor = found + 1 }
        }
        let anchored = starts.compactMap { $0 }
        return starts.map { start in
            guard let start, let position = anchored.firstIndex(of: start) else { return nil }
            let lower = position == 0 ? transcript.startIndex : spoken[start].range.lowerBound
            let upper = position + 1 < anchored.count ? spoken[anchored[position + 1]].range.lowerBound : transcript.endIndex
            return String(transcript[lower..<upper])
        }
    }

    /// Whether `said` only says something about a to-do (when, how long, how
    /// urgent, which list or label) and names nothing to do.
    static func isOnlyCues(_ said: String, vocabulary: Vocabulary) -> Bool {
        let remainder = cues(in: said, vocabulary: vocabulary).remainder
        return words(remainder).allSatisfy { minorWords.contains($0) || fillerWords.contains($0) }
    }

    private static let fillerWords: Set<String> = ["oh", "also", "then", "so", "um", "uh", "s", "okay", "ok", "please",
                                                   "thanks", "and", "but", "yeah", "yes", "well", "just"]

    private static func sameWord(_ lhs: String, _ rhs: String) -> Bool {
        lhs == rhs || (lhs.count >= 4 && rhs.count >= 4 && lhs.prefix(4) == rhs.prefix(4))
    }

    /// Each word's folded form and where it is in `text`.
    private static func wordRanges(_ text: String) -> [(word: String, range: Range<String.Index>)] {
        var result: [(word: String, range: Range<String.Index>)] = []
        var start: String.Index?
        for index in text.indices {
            let character = text[index]
            if character.isLetter || character.isNumber {
                if start == nil { start = index }
            } else if let from = start {
                result.append((folded(String(text[from..<index])), from..<index))
                start = nil
            }
        }
        if let from = start { result.append((folded(String(text[from...])), from..<text.endIndex)) }
        return result
    }

    // MARK: Grounding

    /// Whether `text` came from `transcript`: two in three of its words
    /// that say something were said. A model's task that wasn't, such as its
    /// instructions' example, isn't the speaker's.
    static func isGrounded(_ text: String, in transcript: String) -> Bool {
        let heard = words(transcript)
        let all = words(text)
        let said = all.filter { !minorWords.contains($0) }.isEmpty ? all : all.filter { !minorWords.contains($0) }
        guard !said.isEmpty else { return false }
        let found = said.filter { word in heard.contains { sameWord($0, word) } }
        return Double(found.count) / Double(said.count) >= 0.66
    }

    /// Words too common to show a title was said.
    private static let minorWords: Set<String> = ["the", "a", "an", "to", "and", "or", "of", "for", "in", "on", "at", "by",
                                                  "my", "me", "i", "it", "is", "be", "with", "up", "out", "about", "this",
                                                  "that", "some", "our", "your", "from", "into", "off"]

    static func words(_ text: String) -> [String] {
        folded(text).split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    private static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Text

    /// A title as the list shows it: tidied, without a closing full stop,
    /// and starting with a capital, as the speech model writes a sentence.
    static func tidyTitle(_ text: String) -> String {
        var title = tidy(text)
        while let last = title.last, ".!,;:".contains(last) { title.removeLast() }
        // A joiner left behind by a date taken out after it: "report for".
        title = replacing(#"\s+(?:on|at|by|due|for)$"#, in: title, with: "").trimmingCharacters(in: .whitespaces)
        guard let first = title.first, first.isLowercase else { return title }
        return first.uppercased() + title.dropFirst()
    }

    /// Single spaces, no space before punctuation or doubled punctuation, and
    /// no stray punctuation or dangling "and" at either end.
    static func tidy(_ text: String) -> String {
        var text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        text = replacing(#"\s+([,.;:!?])"#, in: text, with: "$1")
        text = replacing(#"([,.;:!?])(?:\s*[,.;:!?])+"#, in: text, with: "$1")
        text = replacing(#"^[\s,.;:!?-]+"#, in: text, with: "")
        text = replacing(#"(?:[\s,]+(?:and(?:\s+then)?|then|also|oh|so|plus))+[\s.,!]*$"#, in: text, with: "")
        text = replacing(#"[\s,;:-]+$"#, in: text, with: "")
        return text.trimmingCharacters(in: .whitespaces)
    }

    private static let cache = RegexCache(options: [.caseInsensitive])

    private static func matches(_ pattern: String, in text: String) -> Bool {
        cache.regex(for: pattern)?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func replacing(_ pattern: String, in text: String, with template: String) -> String {
        guard let regex = cache.regex(for: pattern) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    /// The groups of the first match of `pattern` in `text` (0 is the whole match).
    private static func groups(_ pattern: String, in text: String) -> [String?]? {
        guard let regex = cache.regex(for: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) }
        }
    }

    /// Takes the first match of `pattern` out of `text`, leaving a space in
    /// its place, and returns its groups (0 is the whole match).
    private static func take(_ pattern: String, from text: inout String) -> [String?]? {
        guard let regex = cache.regex(for: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.range.length > 0, let whole = Range(match.range, in: text) else { return nil }
        let groups = (0..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) }
        }
        text.replaceSubrange(whole, with: " ")
        return groups
    }
}

// MARK: - Saving

/// What `saveSpokenTasks` saved, and what it couldn't.
struct SpokenSave {
    var saved: [Block] = []
    /// Folded headings the tasks opened, to fold again on Undo.
    var opened: [UUID] = []
    var unsaved: [SpokenTask] = []
    var error: Error?
}

extension Store {
    /// Saves spoken tasks in the order they were said, each as its own
    /// capture (`saveCapture`): into the list it named while that list takes
    /// tasks, else `destinationID`, else Inbox. A task said without a day
    /// gets `undatedDay` (Today's capture makes one due today), and every
    /// task gets `labels` too (a label screen's own). A failure stops there,
    /// with the tasks before it saved and it and the rest returned unsaved.
    func saveSpokenTasks(_ tasks: [SpokenTask], destinationID: UUID?, undatedDay: Date? = nil,
                         labels: [String] = []) -> SpokenSave {
        var result = SpokenSave()
        for (index, task) in tasks.enumerated() {
            let named = task.listID.flatMap { list(id: $0) }.flatMap { $0.isEffectivelyArchived ? nil : $0 }
            let destination = named?.id ?? destinationID
            var snapshot = task.snapshot
            if snapshot.date == nil, let undatedDay {
                snapshot.date = Calendar.current.startOfDay(for: undatedDay)
                snapshot.includesTime = false
            }
            for label in labels where !snapshot.labels.contains(label) { snapshot.labels.append(label) }
            let folded = (list(id: destination) ?? inboxList()).map { foldedSections(atEndOf: $0.id) } ?? []
            do {
                result.saved.append(try saveCapture(snapshot, destinationID: destination))
                result.opened += folded.filter { !$0.isCollapsed }.map(\.id)
            } catch {
                result.unsaved = Array(tasks[index...])
                result.error = error
                break
            }
        }
        return result
    }
}
