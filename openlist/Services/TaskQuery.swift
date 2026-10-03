//
//  TaskQuery.swift
//  openlist
//

import Foundation

/// The task filter's word language, the Mac's Tasks field and the phone's
/// Find: dates, flags, list keys and `#labels` combine, and anything else
/// matches the title. UI-free: segments name their list or label, and each
/// screen colours them its own way.
struct TaskQuery {
    enum Kind { case date, flag, list, label, status }

    struct Word {
        let word: String
        let kind: Kind
        var listID: UUID?
        var labelID: UUID?
    }

    struct Segment: Identifiable {
        let id: Int
        let text: String
        let kind: Kind?
        var listID: UUID?
        var labelID: UUID?
    }

    struct Filter {
        var lists: [UUID] = []
        var due: [String] = []
        var labels: [UUID] = []
        var flags: [String] = []
        var status: [String] = []
        var text: [String] = []
    }

    static let dateWords = ["overdue", "today", "tomorrow", "week", "later", "undated"]
    static let flagWords = ["starred", "planned", "high"]
    /// The phone's Find chip for done tasks. The Mac's Tasks screen filters
    /// status on its own, so it never reserves the word.
    static let statusWords = ["done"]

    let vocab: [Word]
    /// Whether `statusWords` are words of the language: then a query holds
    /// open tasks only unless it says "done", which lets done tasks in too.
    let readsStatus: Bool
    private let listKeys: [UUID: String]
    private let labelKeys: [UUID: String]

    /// Every word means one thing: date, flag (and status) words are reserved,
    /// then each list claims its last title word (else its full slug, else a
    /// numbered slug), then labels, then extra title words. `lists` are the
    /// active lists in sidebar order, `labels` in their own order.
    init(lists: [TaskList], labels: [TaskLabel], readsStatus: Bool = false) {
        let reserved = Self.dateWords + Self.flagWords + (readsStatus ? Self.statusWords : [])
        var taken = Set(reserved + ["inbox"])
        var listKeys: [UUID: String] = [:]
        for list in lists {
            let words = Self.titleWords(list)
            listKeys[list.id] = list.isSystemInbox ? "inbox"
                : Self.claim(words.last ?? "list", fallback: words.isEmpty ? "list" : words.joined(separator: "-"), in: &taken)
        }
        var labelKeys: [UUID: String] = [:]
        for label in labels {
            let slug = "#" + label.name.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: "-")
            labelKeys[label.id] = Self.claim(slug, fallback: slug, in: &taken)
        }
        var vocab = Self.dateWords.map { Word(word: $0, kind: .date) } + Self.flagWords.map { Word(word: $0, kind: .flag) }
        if readsStatus { vocab += Self.statusWords.map { Word(word: $0, kind: .status) } }
        for list in lists {
            guard let key = listKeys[list.id] else { continue }
            var keys = [key]
            for word in Self.titleWords(list) where word.count >= 4 && !taken.contains(word) {
                taken.insert(word)
                keys.append(word)
            }
            vocab += keys.map { Word(word: $0, kind: .list, listID: list.id) }
        }
        for label in labels {
            guard let key = labelKeys[label.id] else { continue }
            vocab.append(Word(word: key, kind: .label, labelID: label.id))
        }
        self.vocab = vocab
        self.readsStatus = readsStatus
        self.listKeys = listKeys
        self.labelKeys = labelKeys
    }

    func key(for list: TaskList) -> String { listKeys[list.id] ?? "list" }

    func key(for label: TaskLabel) -> String { labelKeys[label.id] ?? "#" }

    private static func titleWords(_ list: TaskList) -> [String] {
        list.displayTitle.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// `base` if free, else `fallback`, else `fallback-2`, `-3`…; marks the result as taken.
    private static func claim(_ base: String, fallback: String, in taken: inout Set<String>) -> String {
        var key = taken.contains(base) ? fallback : base
        var suffix = 2
        while taken.contains(key) {
            key = "\(fallback)-\(suffix)"
            suffix += 1
        }
        taken.insert(key)
        return key
    }

    /// The query as pills and plain runs, what it filters by, and the rest of
    /// the word its last one starts, for Tab to complete.
    func parse(_ query: String) -> (segments: [Segment], filter: Filter, ghost: String) {
        var segments: [Segment] = []
        var filter = Filter()
        var index = 0
        var current = ""
        var currentIsSpace: Bool?
        func flush() {
            guard !current.isEmpty else { return }
            defer { current = ""; index += 1 }
            if currentIsSpace == true {
                segments.append(Segment(id: index, text: current, kind: nil))
                return
            }
            let lower = current.lowercased()
            guard let hit = vocab.first(where: { $0.word == lower }) else {
                segments.append(Segment(id: index, text: current, kind: nil))
                filter.text.append(lower)
                return
            }
            segments.append(Segment(id: index, text: current, kind: hit.kind, listID: hit.listID, labelID: hit.labelID))
            switch hit.kind {
            case .list: filter.lists.append(hit.listID!)
            case .label: filter.labels.append(hit.labelID!)
            case .date: filter.due.append(lower)
            case .flag: filter.flags.append(lower)
            case .status: filter.status.append(lower)
            }
        }
        for character in query {
            let isSpace = character.isWhitespace
            if currentIsSpace != isSpace { flush(); currentIsSpace = isSpace }
            current.append(character)
        }
        flush()

        var ghost = ""
        if let last = query.split(whereSeparator: \.isWhitespace).last, query.last?.isWhitespace == false {
            let lower = last.lowercased()
            if !vocab.contains(where: { $0.word == lower }), let match = vocab.first(where: { $0.word.hasPrefix(lower) }) {
                ghost = String(match.word.dropFirst(lower.count))
            }
        }
        return (segments, filter, ghost)
    }

    /// The tasks of `pool` the query keeps, in `pool`'s order. Date words go
    /// by day offset, so "today" is due today rather than Today's set; lists
    /// and labels each match any of theirs, flags all of theirs, and free
    /// words must all be in the title, or with `searchesNotes` in the title
    /// or note, ignoring case, accents and width.
    func apply(_ query: String, to pool: [Block], now: Date = .now, calendar: Calendar = .current,
               searchesNotes: Bool = false, isPlanned: ((Block) -> Bool)? = nil) -> [Block] {
        let filter = parse(query).filter
        let isPlanned = isPlanned ?? { $0.isPlanned(on: now, calendar: calendar) }
        let today = calendar.startOfDay(for: now)
        // By day, as the design and the row chips: overdue is earlier days, so a
        // time already past today still counts as today.
        func dueMatches(_ word: String, _ offset: Int?) -> Bool {
            switch word {
            case "overdue": offset.map { $0 < 0 } ?? false
            case "today": offset == 0
            case "tomorrow": offset == 1
            case "week": offset.map { (0...6).contains($0) } ?? false
            case "later": offset.map { $0 > 6 } ?? false
            default: offset == nil
            }
        }
        func textMatches(_ task: Block) -> Bool {
            guard !filter.text.isEmpty else { return true }
            guard searchesNotes else {
                let title = task.displayTitle.lowercased()
                return filter.text.allSatisfy { title.contains($0) }
            }
            let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
            return filter.text.allSatisfy { word in
                task.displayTitle.range(of: word, options: options) != nil || task.note.range(of: word, options: options) != nil
            }
        }
        let includesDone = !readsStatus || filter.status.contains("done")
        // Runs over every task on each keystroke: the day is worked out only
        // when a due word asks for it, and the title read only for words.
        return pool.filter { task in
            func offset() -> Int? {
                task.dueDate.map { calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: $0)).day ?? 0 }
            }
            return (includesDone || !task.isCompleted)
                && (filter.lists.isEmpty || task.listID.map(filter.lists.contains) == true)
                && (filter.due.isEmpty || { let offset = offset(); return filter.due.contains { dueMatches($0, offset) } }())
                && (filter.labels.isEmpty || filter.labels.contains { task.labelIDs.contains($0) })
                && filter.flags.allSatisfy { flag in
                    switch flag {
                    case "starred": task.isStarred
                    case "planned": isPlanned(task)
                    default: task.priority == .high
                    }
                }
                && textMatches(task)
        }
    }

    /// Adds or removes one word, leaving a trailing space to keep typing.
    static func toggle(_ word: String, in query: String) -> String {
        var parts = query.split(whereSeparator: \.isWhitespace).map(String.init)
        if let index = parts.firstIndex(where: { $0.lowercased() == word }) {
            parts.remove(at: index)
        } else {
            parts.append(word)
        }
        return parts.isEmpty ? "" : parts.joined(separator: " ") + " "
    }

    static func words(in query: String) -> Set<String> {
        Set(query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init))
    }
}
