//
//  CaptureDraft.swift
//  openlist
//

import Foundation
import Observation

/// What a capture card types into: the text, where it goes, and what Return
/// saves. The main window's draft is the workbench's; the Quick Add panel
/// keeps one of its own, so the two never share half-typed text. UI-free, so
/// the phone's Capture sheet keeps a draft of its own too.
@MainActor
protocol NXCaptureDraft: AnyObject, Observable {
    var store: Store { get }
    var settings: AppSettings { get }
    var captureText: String { get set }
    var captureListID: UUID? { get set }
    /// Whether a task with no date of its own is due today.
    var captureForToday: Bool { get }
    /// The label screen capture opened on; the new task gets that label.
    var captureLabelID: UUID? { get }
    /// Tasks waiting as rows, heard by voice capture or pasted as lines,
    /// which Return adds in place of the text.
    var spokenTasks: [SpokenTask] { get set }
    /// The note written under the task, which Return saves with it.
    var captureNote: String { get set }
    /// The words kept as text, and where the card's suggestions stand.
    var captureAssist: CaptureAssist { get set }
}

/// What a capture card keeps beside its text and note: the note line open
/// and whether it has the keyboard, the tokens the writer said to keep as
/// words, and the suggestion ↑ and ↓ have moved to, or the text Escape put
/// the suggestions away on.
struct CaptureAssist: Equatable {
    var writesNote = false
    var focusesNote = false
    var literals: Set<String> = []
    var completionIndex = 0
    var completionDismissed: String?
}

extension NXCaptureDraft {
    var hasCaptureDraft: Bool {
        !captureText.isEmpty || !spokenTasks.isEmpty || !captureNote.isEmpty
    }

    /// The lists an `@` token can name, by the names they show: those that
    /// take tasks, Inbox included.
    var captureLists: [(id: UUID, name: String)] {
        store.allLists().filter { !$0.isEffectivelyArchived }.map { ($0.id, $0.displayTitle) }
    }

    /// The capture text read as the card tints it and Return saves it, with
    /// dates only while Settings reads them from typed text.
    func captureParse() -> CaptureParse {
        CaptureParse(captureText, parsesDates: settings.parsesNaturalLanguageDates, lists: captureLists,
                     literals: captureAssist.literals)
    }

    /// What Return saves, which the capture card's chips preview. A task with
    /// no date of its own is due today when the draft is for today; captured
    /// on a label screen it also gets that label.
    func capturePreview(_ parse: CaptureParse) -> CaptureSnapshot {
        let screenLabel = captureLabelID.flatMap { store.label(id: $0) }.map { [$0.name.lowercased()] } ?? []
        var snapshot = parse.snapshot(dueToday: captureForToday, labels: screenLabel)
        snapshot.note = captureNote
        return snapshot
    }

    /// Where Return files the draft: the list its `@` token names, else the
    /// one picked, else Inbox.
    func captureDestinationID(_ parse: CaptureParse) -> UUID? {
        parse.listID ?? captureListID ?? store.inboxList()?.id
    }

    /// The destination the card lights: where Return files what it shows.
    /// While rows wait, that's the list picked, which a row naming none goes
    /// to; the typed text's token is its own task's.
    var litCaptureDestinationID: UUID? {
        spokenTasks.isEmpty ? captureDestinationID(captureParse()) : captureListID ?? store.inboxList()?.id
    }

    /// Saves the draft into its list, or Inbox: one capture, saved at once,
    /// for the title, date, repeat, labels, priority and estimate its tokens
    /// name, and its note. Returns the task and the folded headings the
    /// capture opened to show it, for an Undo that folds them again.
    func saveCapture(_ parse: CaptureParse) throws -> (block: Block, opened: [UUID]) {
        let destinationID = captureDestinationID(parse)
        let folded = (store.list(id: destinationID) ?? store.inboxList()).map { store.foldedSections(atEndOf: $0.id) } ?? []
        let block = try store.saveCapture(capturePreview(parse), destinationID: destinationID)
        return (block, folded.filter { !$0.isCollapsed }.map(\.id))
    }

    /// The draft done with once its task is added and the card stays for
    /// another: the text, the note and the words kept as text go.
    func clearCaptureText() {
        captureText = ""
        captureNote = ""
        captureAssist = CaptureAssist()
    }

    /// "Keep as text" on a token's chip: wherever `raw` is typed, it's read
    /// as plain words, and stays in the title.
    func keepAsText(_ raw: String) {
        captureAssist.literals.insert(CaptureParse.literal(raw))
    }

    // MARK: Suggestions

    /// The `@list` or `#label` being typed at the end of the text, with what
    /// it could be, unless Escape put the suggestions away for this text.
    func captureCompletion() -> CaptureCompletion? {
        guard captureAssist.completionDismissed != captureText else { return nil }
        return CaptureCompletion.typing(captureText, lists: captureLists,
                                        labels: store.allLabels().map(\.name))
    }

    /// The suggestion ↑ and ↓ have moved to, within `completion`'s options.
    func highlightedOption(in completion: CaptureCompletion) -> CaptureCompletion.Option? {
        completion.options.indices.contains(captureAssist.completionIndex)
            ? completion.options[captureAssist.completionIndex] : completion.options.first
    }

    /// ↑ and ↓ through the suggestions, stopping at either end.
    func moveCompletion(by delta: Int, in completion: CaptureCompletion) {
        captureAssist.completionIndex = max(0, min(completion.options.count - 1, captureAssist.completionIndex + delta))
    }

    /// Tab or Return on a suggestion, or a click: the token being typed
    /// becomes the list's or label's name, with a space for the next word.
    func complete(with option: CaptureCompletion.Option, in completion: CaptureCompletion) {
        captureText = completion.completing(captureText, with: option)
        captureAssist.completionIndex = 0
    }

    /// Escape over the suggestions: they go until the text changes.
    func dismissCompletion() {
        captureAssist.completionDismissed = captureText
        captureAssist.completionIndex = 0
    }

    // MARK: Destination

    /// A destination picked by its chip, Tab or ⇧Tab. An `@` token naming
    /// another list gives way to the pick: its words leave the text.
    func chooseCaptureDestination(_ id: UUID?) {
        let parse = captureParse()
        // While rows wait, the typed text is out of sight, and kept as it is.
        if spokenTasks.isEmpty, let token = parse.first(.list) {
            var text = captureText
            text.removeSubrange(token.range)
            captureText = text.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        }
        captureListID = id
    }

    // MARK: Sharing

    /// Words another app shared, through Services or the Share sheet, with a
    /// note such as the link they came from: in the field, the note under
    /// it, when nothing's being written; else waiting as a row of their own,
    /// as tasks said over a draft do. More than one line is a task a line,
    /// as pasted.
    func takeShared(_ text: String, note: String? = nil, now: Date = .now) {
        if CaptureLines.tasks(in: text) != nil {
            takePasted(text, now: now)
            return
        }
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !line.isEmpty || !note.isEmpty else { return }
        guard hasCaptureDraft else {
            captureText = line
            captureNote = note
            captureAssist.writesNote = !note.isEmpty
            return
        }
        // A row needs a title: a link alone goes by its address.
        let parse = CaptureParse(line.isEmpty ? note : line, parsesDates: settings.parsesNaturalLanguageDates, reference: now,
                                 lists: captureLists)
        var snapshot = parse.snapshot()
        snapshot.note = line.isEmpty ? "" : note
        spokenTasks.append(SpokenTask(snapshot: snapshot, listID: parse.listID))
    }

    // MARK: Pasting

    /// Text of more than one line pasted into the field: one task a line,
    /// each read for its own tokens, `@` list included, waiting as rows for
    /// Return to add together, as tasks said do. What's typed stays in the
    /// field. Returns whether the text was taken as rows.
    @discardableResult
    func takePasted(_ pasted: String, now: Date = .now) -> Bool {
        guard let lines = CaptureLines.tasks(in: pasted) else { return false }
        let lists = captureLists
        spokenTasks += lines.map { line in
            let parse = CaptureParse(line, parsesDates: settings.parsesNaturalLanguageDates, reference: now, lists: lists)
            return SpokenTask(snapshot: parse.snapshot(), listID: parse.listID)
        }.filter { !$0.snapshot.title.isEmpty }
        return true
    }

    /// What Return and ⇧↩ do with the draft, the window's card and Quick
    /// Add's alike: save it, or say on the card why it wasn't saved. Tokens
    /// with no title save nothing and say nothing, as the design's Return.
    /// Tasks heard by voice are added instead of the text, when there are any.
    func addCapture() -> NXCaptureOutcome {
        if !spokenTasks.isEmpty { return addSpokenTasks() }
        let parse = captureParse()
        guard !parse.title.isEmpty else { return .untitled }
        do {
            let saved = try saveCapture(parse)
            return .saved(saved.block, opened: saved.opened)
        } catch {
            return .failed(NXCaptureNotice(text: "Task wasn’t added. \(error.localizedDescription) Your draft is still here; try again.",
                                           failed: true))
        }
    }

    /// Takes what voice capture heard. A single task goes in the field as
    /// its capture line, aimed at the list it named, to edit as though typed;
    /// several, or one the field wouldn't read back the same, wait as rows
    /// for Return to add together. Returns whether it filled the field.
    @discardableResult
    func take(_ heard: [SpokenTask], now: Date = .now) -> Bool {
        guard !heard.isEmpty else { return false }
        if hasCaptureDraft {
            spokenTasks += heard
            return false
        }
        if heard.count == 1, let task = heard.first,
           task.fitsField(parsesDates: settings.parsesNaturalLanguageDates, reference: now) {
            spokenTasks = []
            captureText = task.line
            if let listID = task.listID { captureListID = listID }
            return true
        }
        spokenTasks = heard
        return false
    }

    func receiveVoice(_ heard: [SpokenTask], afterCapture: AppSettings.AfterVoiceCapture, now: Date = .now) -> NXCaptureOutcome? {
        guard !heard.isEmpty else { return nil }
        if afterCapture == .saveAutomatically, !hasCaptureDraft {
            spokenTasks = heard
            return addSpokenTasks()
        }
        take(heard, now: now)
        return nil
    }

    /// Adds the tasks heard, each to the list it named or the draft's, due
    /// today when an undated task would be, with the label screen's label.
    /// Any it couldn't add stay, with the reason on the card.
    func addSpokenTasks() -> NXCaptureOutcome {
        guard !spokenTasks.isEmpty else { return .untitled }
        let screenLabel = captureLabelID.flatMap { store.label(id: $0) }.map { [$0.name.lowercased()] } ?? []
        let result = store.saveSpokenTasks(spokenTasks, destinationID: captureListID ?? store.inboxList()?.id,
                                           undatedDay: captureForToday ? NXFormat.day(offset: 0) : nil,
                                           labels: screenLabel)
        spokenTasks = result.unsaved
        let failure = result.error.map {
            NXCaptureNotice(text: "“\(result.unsaved[0].snapshot.title)” wasn’t added. \($0.localizedDescription) Try again.",
                            failed: true)
        }
        if result.saved.isEmpty, let failure { return .failed(failure) }
        return .savedSeveral(result.saved, opened: result.opened, failure: failure)
    }

    /// Tab and Shift-Tab step the destination through Inbox and every list.
    /// From a list no longer among them, Tab starts at Inbox and Shift-Tab
    /// at the last list.
    /// Steps from the lit destination, an `@` token's list included, which
    /// gives way to the step.
    func cycleCaptureDestination(by delta: Int, among ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let current = litCaptureDestinationID
        guard let index = ids.firstIndex(where: { $0 == current }) else {
            chooseCaptureDestination(delta > 0 ? ids.first : ids.last)
            return
        }
        chooseCaptureDestination(ids[(index + delta + ids.count) % ids.count])
    }
}

/// The `@list` or `#label` being typed at the end of a capture's text, and
/// the lists or labels it could become, for the card to suggest.
struct CaptureCompletion: Equatable {
    enum Kind: Equatable { case list, label }

    struct Option: Equatable, Identifiable {
        let name: String
        /// The list it names; nil for a label.
        let listID: UUID?
        var id: String { listID?.uuidString ?? "#" + name }
    }

    let kind: Kind
    /// From the token's `@` or `#` to the end of the text.
    let range: Range<String.Index>
    let options: [Option]

    /// What `text` could be finishing: a `#label` as its last word, or an
    /// `@` after a space or the start with all that follows it the start of
    /// a list's name, spaces and all. Names that begin with what's typed come
    /// first, then those with a word that does. A token already a name in
    /// full, or one nothing matches, has nothing to suggest, so Return adds
    /// the task as typed. Labels with spaces can't be typed, so they're left out.
    static func typing(_ text: String, lists: [(id: UUID, name: String)], labels: [String],
                       limit: Int = 6) -> CaptureCompletion? {
        guard let last = text.last, !last.isNewline else { return nil }
        let wordStart = text.lastIndex(where: \.isWhitespace).map { text.index(after: $0) } ?? text.startIndex
        if !last.isWhitespace, text[wordStart] == "#" {
            let typed = String(text[text.index(after: wordStart)...])
            guard typed.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else { return nil }
            let names = labels.filter { !$0.contains(where: \.isWhitespace) }
            let options = matches(typed, in: names, allowsWordMatch: true).map { Option(name: $0, listID: nil) }
            return completion(.label, typed, wordStart..<text.endIndex, options, limit)
        }
        var search = text.endIndex
        while let at = text[..<search].lastIndex(of: "@") {
            search = at
            guard at == text.startIndex || text[text.index(before: at)].isWhitespace else { continue }
            let typed = String(text[text.index(after: at)...])
            guard !typed.contains(where: \.isNewline) else { return nil }
            let byName = Dictionary(lists.map { ($0.name, $0.id) }, uniquingKeysWith: { first, _ in first })
            let options = matches(typed, in: lists.map(\.name), allowsWordMatch: !typed.contains(where: \.isWhitespace))
                .compactMap { name in byName[name].map { Option(name: name, listID: $0) } }
            return completion(.list, typed, at..<text.endIndex, options, limit)
        }
        return nil
    }

    private static func completion(_ kind: Kind, _ typed: String, _ range: Range<String.Index>, _ options: [Option],
                                   _ limit: Int) -> CaptureCompletion? {
        let folded = fold(typed)
        guard !options.isEmpty, !options.contains(where: { fold($0.name) == folded }) else { return nil }
        return CaptureCompletion(kind: kind, range: range, options: Array(options.prefix(limit)))
    }

    /// `names` that start with `typed`, then, with `allowsWordMatch`, those
    /// with a later word that does, each in the order given.
    private static func matches(_ typed: String, in names: [String], allowsWordMatch: Bool) -> [String] {
        let query = fold(typed)
        let starts = names.filter { fold($0).hasPrefix(query) }
        guard allowsWordMatch, !query.isEmpty else { return starts }
        let words = names.filter { name in
            !starts.contains(name) && fold(name).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).dropFirst()
                .contains { $0.hasPrefix(query) }
        }
        return starts + words
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// `text` with the token being typed spelled as `option`, and a space
    /// after it for the next word.
    func completing(_ text: String, with option: Option) -> String {
        guard range.lowerBound >= text.startIndex, range.upperBound <= text.endIndex else { return text }
        return text.replacingCharacters(in: range, with: (kind == .list ? "@" : "#") + option.name + " ")
    }
}

/// Text pasted into a capture's field, read as a task a line.
enum CaptureLines {
    /// The tasks in `text`, one a line, without the bullets, numbers and
    /// boxes of the list it came from. Blank lines, and items a box or a tick
    /// marks done, are left out. Nil unless more than one is left: a single
    /// line pastes into the field as words.
    static func tasks(in text: String) -> [String]? {
        let lines = text.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            var item = String(line).trimmingCharacters(in: .whitespaces)
            if let marker = item.range(of: #"^(?:[-*•◦▪‣–—+]|\d{1,3}[.)])\s+"#, options: .regularExpression) {
                item.removeSubrange(marker)
            }
            if let box = item.range(of: #"^(?:\[[ xX✓✔]?\]|[☐☑☒✅✓✔])\s*"#, options: .regularExpression) {
                let mark = item[box].trimmingCharacters(in: .whitespaces)
                guard !mark.contains(where: { "xX✓✔☑☒✅".contains($0) }) else { return nil }
                item.removeSubrange(box)
            }
            item = item.trimmingCharacters(in: .whitespaces)
            return item.isEmpty ? nil : item
        }
        return lines.count > 1 ? lines : nil
    }
}

struct VoiceCaptureSession {
    private(set) var generation = 0
    private var pending = false
    private var understanding = false
    private var afterCapture = AppSettings.AfterVoiceCapture.reviewBeforeSaving

    mutating func begin(afterCapture: AppSettings.AfterVoiceCapture, hasDraft: Bool) -> Int {
        generation += 1
        pending = true
        understanding = false
        self.afterCapture = hasDraft ? .reviewBeforeSaving : afterCapture
        return generation
    }

    func isCurrent(run: Int) -> Bool { generation == run && pending }

    mutating func beginUnderstanding(run: Int) -> Bool {
        guard isCurrent(run: run), !understanding else { return false }
        understanding = true
        return true
    }

    mutating func complete(run: Int, hasTasks: Bool) -> AppSettings.AfterVoiceCapture? {
        guard isCurrent(run: run), understanding else { return nil }
        pending = false
        return hasTasks ? afterCapture : nil
    }

    mutating func cancel() {
        generation += 1
        pending = false
        understanding = false
    }

    mutating func requireReview() {
        afterCapture = .reviewBeforeSaving
    }
}

/// A line the card shows where there is no tray to say it: what ⇧↩ just
/// added, or why Return couldn't add the task.
struct NXCaptureNotice: Equatable {
    var text: String
    var failed = false
}

/// What `addCapture` made of the draft.
enum NXCaptureOutcome {
    /// Nothing but tokens, or nothing at all, was typed.
    case untitled
    /// The task, and the folded headings the capture opened to show it.
    case saved(Block, opened: [UUID])
    /// Why the task wasn't added, for the card; the draft stays.
    case failed(NXCaptureNotice)
    /// Tasks heard by voice, and the folded headings they opened; with why
    /// the rest weren't, when some weren't.
    case savedSeveral([Block], opened: [UUID], failure: NXCaptureNotice?)
}
