//
//  FindScreen.swift
//  OpenlistiOS
//

import SwiftData
import SwiftUI

/// Find (mockup 13), pushed from Lists: words and filters in one field, the
/// Mac's task query language. A word it knows (a #label, a list, today,
/// overdue, starred, done…) becomes a chip in the field once typed; tapping
/// one takes it out. The chips under the field toggle the common filters.
/// Results are open tasks, done ones too with "done", late first, then by
/// when they're due, each with its list.
struct FindScreen: View {
    let query: String
    @Environment(\.phoneLibrary) private var library
    @Query(filter: #Predicate<Block> { $0.trashID == nil }) private var blocks: [Block]

    static let filters = ["today", "overdue", "starred", "done"]

    var body: some View {
        // Ordered here, out of typing's way, so a keystroke filters the tasks
        // without walking every outline again.
        FindPage(query: query, pool: library.tasksInOutlineOrder(blocks: blocks))
    }

    /// A token's words: done in green, everything else ink. A label's
    /// colour is its dot's (`dot(of:in:library:)`), not its words'.
    static func tint(of token: String, in language: TaskQuery) -> Color {
        switch language.vocab.first(where: { $0.word == token })?.kind {
        case .date: OL.accentText
        case .status: OL.successText
        case .label, .flag, .list, nil: OL.ink
        }
    }

    /// A label token's own colour, for the dot before its name.
    static func dot(of token: String, in language: TaskQuery, library: NextLibrary) -> Color? {
        language.vocab.first { $0.word == token && $0.kind == .label }?.labelID.flatMap(library.label)?.accent.color
    }

    // MARK: Results

    /// The query's tasks, open first: late, then by due date, then undated
    /// in the lists' order; done ones after, most recently done first.
    static func results(for query: String, language: TaskQuery, library: NextLibrary, blocks: [Block], now: Date,
                        calendar: Calendar) -> [Block] {
        results(for: query, language: language, pool: library.tasksInOutlineOrder(blocks: blocks), now: now,
                calendar: calendar)
    }

    /// The same from `pool`, every task already in the lists' order.
    static func results(for query: String, language: TaskQuery, pool: [Block], now: Date, calendar: Calendar) -> [Block] {
        let found = language.apply(query, to: pool, now: now, calendar: calendar, searchesNotes: true)
        let place = Dictionary(pool.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        let open = found.filter { !$0.isCompleted }.sorted { lhs, rhs in
            switch (lhs.dueDate, rhs.dueDate) {
            case let (left?, right?) where left != right: left < right
            case (_?, nil): true
            case (nil, _?): false
            default: (place[lhs.id] ?? 0) < (place[rhs.id] ?? 0)
            }
        }
        return open + found.filter(\.isCompleted).sorted(by: Block.byCompletionDate)
    }
}

/// Find's field, its filters and what they find in `pool`.
private struct FindPage: View {
    let query: String
    /// Every task in the lists' order.
    let pool: [Block]
    @Environment(PhoneEnvironment.self) private var env
    @Environment(\.phoneLibrary) private var library
    /// The words the field shows as chips, in the order they came.
    @State private var tokens: [String] = []
    /// The common filters on, which light their chips under the field
    /// rather than joining the field.
    @State private var filters: [String] = []
    /// What's typed after them.
    @State private var text = ""
    @State private var didStart = false
    @FocusState private var isFocused: Bool

    var body: some View {
        let navigator = env.navigator
        let language = library.findQuery
        let full = (tokens + filters + [text]).joined(separator: " ")
        let isEmpty = full.trimmingCharacters(in: .whitespaces).isEmpty
        let results = isEmpty ? [] : FindScreen.results(for: full, language: language, pool: pool,
                                                       now: env.now, calendar: env.settings.calendar)
        OLScreen(identifier: PhoneRoute.find(query).screenIdentifier) {
            OLTopBar { OLBackButton(env.backTitle(for: .find(query))) { navigator.pop() } }
        } content: {
            OLHeader("Find")
            OLSearchField(text: $text, prompt: tokens.isEmpty ? "Find a task, note or #label" : "Add words or filters",
                          focus: $isFocused, clearTokens: tokens.isEmpty ? nil : { tokens = [] }) {
                ForEach(tokens, id: \.self) { token in
                    OLChipButton(OLChip(token, style: .token, tint: FindScreen.tint(of: token, in: language),
                                        dot: FindScreen.dot(of: token, in: language, library: library))) { remove(token) }
                        .accessibilityLabel("\(token), filter")
                        .accessibilityHint("Removes it")
                }
            }
            .padding(.top, OLMetrics.headerGap)
            .onChange(of: text) { _, typed in absorb(typed, language: language) }
            .onSubmit { absorb(text + " ", language: language) }
            .accessibilityIdentifier("find.field")
            OLFlowLayout {
                ForEach(FindScreen.filters, id: \.self) { word in
                    OLChipButton(OLChip(word, style: filters.contains(word) ? .on : .plain, small: true)) { toggle(word) }
                        .accessibilityIdentifier("find.filter.\(word)")
                }
            }
            .padding(.top, 12)
            if isEmpty {
                Text("Type words, or add a #label, a list’s name, today, overdue, starred or done.")
                    .font(OLFont.note)
                    .foregroundStyle(OL.muted)
                    .padding(.horizontal, 4)
                    .padding(.top, OLMetrics.groupGap)
            } else if results.isEmpty {
                noResults(for: full.trimmingCharacters(in: .whitespaces), language: language)
                    .padding(.top, OLMetrics.groupGap)
                    .accessibilityIdentifier("find.noResults")
            } else {
                OLGroup("\(results.count) \(results.count == 1 ? "task" : "tasks")") {
                    OLCardRows(results, lazy: true) { task, separator in
                        PhoneTaskRow(task: task, context: .list, subtitle: library.list(task.listID)?.displayTitle,
                                     separator: separator)
                    }
                }
                .accessibilityIdentifier("find.results")
            }
        }
        .onAppear {
            guard !didStart else { return }
            didStart = true
            absorb(query.hasSuffix(" ") || query.isEmpty ? query : query + " ", language: language)
            if query.isEmpty { isFocused = true }
        }
    }

    // MARK: No results

    /// Nothing found, with the ways on: the done tasks it leaves out, when
    /// some would match, and an empty search to start again.
    private func noResults(for query: String, language: TaskQuery) -> some View {
        let done = filters.contains("done") ? 0
            : FindScreen.results(for: query + " done", language: language, pool: pool, now: env.now,
                                 calendar: env.settings.calendar).count
        return ContentUnavailableView {
            Label("No results for “\(query)”", systemImage: "magnifyingglass")
        } description: {
            Text(done == 0 ? "Check the spelling or try a new search."
                 : "\(done) done \(done == 1 ? "task matches" : "tasks match").")
        } actions: {
            if done > 0 {
                Button("Include done tasks") { filters.append("done") }
            }
            Button("Clear search", action: clear)
        }
    }

    /// Starts over: no chips, no filters, nothing typed, and the field ready.
    private func clear() {
        tokens = []
        filters = []
        text = ""
        isFocused = true
    }

    // MARK: The field

    /// Moves each finished word the language knows (one a space follows) out
    /// of the text and into the chips; the rest stays as typed.
    private func absorb(_ typed: String, language: TaskQuery) {
        guard let lastSpace = typed.lastIndex(where: \.isWhitespace) else { return }
        let tail = String(typed[typed.index(after: lastSpace)...])
        var kept: [String] = []
        var moved = false
        for word in typed[..<lastSpace].split(whereSeparator: \.isWhitespace).map(String.init) {
            let lower = word.lowercased()
            if FindScreen.filters.contains(lower) {
                // A common filter typed lights its chip.
                if !filters.contains(lower) { filters.append(lower) }
                moved = true
            } else if language.vocab.contains(where: { $0.word == lower }) {
                if !tokens.contains(lower) { tokens.append(lower) }
                moved = true
            } else {
                kept.append(word)
            }
        }
        guard moved else { return }
        text = kept.isEmpty ? tail : kept.joined(separator: " ") + " " + tail
    }

    private func toggle(_ word: String) {
        if let index = filters.firstIndex(of: word) { filters.remove(at: index) } else { filters.append(word) }
    }

    private func remove(_ token: String) {
        tokens.removeAll { $0 == token }
    }
}
