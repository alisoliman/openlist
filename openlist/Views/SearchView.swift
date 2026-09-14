import SwiftData
import SwiftUI

/// Query changes are isolated from SwiftData observation: editing the query or
/// moving selection does not rebuild the immutable corpus.
struct SearchView: View {
    @State private var session = SearchSession()

    var body: some View {
        SearchContentView(session: session)
            .background { SearchCorpusObserver(session: session) }
            .onDisappear { session.cancel() }
    }
}

private struct SearchCorpusObserver: View {
    let session: SearchSession
    @Query private var blocks: [Block]
    @Query private var lists: [TaskList]

    var body: some View {
        let corpus = SearchCorpus(blocks: blocks, lists: lists)
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: corpus, initial: true) { _, updated in session.update(corpus: updated) }
            .accessibilityHidden(true)
    }
}

private struct SearchContentView: View {
    let session: SearchSession
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var options = SearchOptions()
    @State private var selection = SearchResultSelection()
    @State private var unavailable: String?
    @FocusState private var isFieldFocused: Bool
    @FocusState private var focusedResult: SearchDestination?

    private var destinations: [SearchDestination] { session.hits.map(\.id) }
    private var hasCustomFilters: Bool {
        let defaults = SearchOptions()
        return options.scope != defaults.scope || options.includesCompleted != defaults.includesCompleted
            || options.includesArchived != defaults.includesArchived
    }
    private var filterSummary: String {
        var parts = [options.scope.title]
        if !options.includesCompleted { parts.append("Open only") }
        parts.append(options.includesArchived ? "Including archived" : "Active lists")
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let unavailable {
                Text(unavailable)
                    .font(.callout)
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .accessibilityIdentifier("search-unavailable")
            }
            if options.needle.isEmpty {
                EmptyStateView(icon: "magnifyingglass", title: "Find a task, note, or list")
                    .frame(maxHeight: .infinity)
            } else if session.isSearching || session.options != options {
                ProgressView("Searching…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if session.hits.isEmpty {
                EmptyStateView(icon: "questionmark.circle", title: "No results",
                    message: "Nothing matches “\(options.needle)” with these filters.")
                    .frame(maxHeight: .infinity)
            } else {
                results
                Divider()
                HStack {
                    Text("\(min(selection.limit, session.hits.count)) of \(session.hits.count) results")
                        .accessibilityIdentifier("search-result-count")
                    Spacer()
                }
                .font(Theme.Font.metadata)
                .foregroundStyle(Theme.secondaryText)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
        }
        .frame(width: 640, height: 540)
        .background(.regularMaterial)
        .task {
            await Task.yield()
            isFieldFocused = true
        }
        .onChange(of: options, initial: true) { _, updated in
            unavailable = nil
            selection = SearchResultSelection()
            session.update(options: updated)
        }
        .onChange(of: destinations) { _, updated in
            if !session.isSearching { selection.reconcile(updated) }
        }
        .onChange(of: focusedResult) { _, focused in
            if let focused { selection.selected = focused }
        }
        .onExitCommand { dismiss() }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.tertiaryText).accessibilityHidden(true)
                TextField("Search tasks, notes and lists", text: $options.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($isFieldFocused)
                    .accessibilityIdentifier("search-query")
                    .accessibilityLabel("Search tasks, notes and lists")
                    .accessibilityHint("Use arrow keys to choose a result and Return to open it.")
                    .onSubmit { activate(selection.selected ?? destinations.first) }
                    .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
                    .onKeyPress(.downArrow) { moveSelection(1); return .handled }
                    .onKeyPress(.escape) { dismiss(); return .handled }
                if !options.query.isEmpty {
                    Button("Clear search", systemImage: "xmark.circle.fill") {
                        options.query = ""
                        isFieldFocused = true
                    }.labelStyle(.iconOnly).buttonStyle(.plain)
                }
                Menu {
                    Picker("Search scope", selection: $options.scope) {
                        ForEach(SearchOptions.Scope.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                    Divider()
                    Toggle("Include completed", isOn: $options.includesCompleted)
                    Toggle("Include archived", isOn: $options.includesArchived)
                    if hasCustomFilters {
                        Divider()
                        Button("Reset filters") {
                            let query = options.query
                            options = SearchOptions()
                            options.query = query
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .foregroundStyle(hasCustomFilters ? Theme.accent : Theme.secondaryText)
                        .frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Search filters")
                .accessibilityValue(filterSummary)
                .help("Filter by type, completion, or archive")
                Button("Close search", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly).buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
            }
            if hasCustomFilters {
                Text(filterSummary)
                    .font(Theme.Font.metadata)
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var results: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(session.hits.prefix(selection.limit)) { hit in
                        SearchResultRow(hit: hit, query: options.needle, isSelected: selection.selected == hit.id,
                            focusedResult: $focusedResult,
                            onReturn: { activate(selection.keyboardDestination(focused: hit.id)) }) {
                            activate(hit.id)
                        }
                        .id(hit.id)
                        .onHover { if $0 { selection.selected = hit.id } }
                    }
                    if selection.limit < session.hits.count {
                        Button("Load next \(min(SearchResultSelection.batchSize, session.hits.count - selection.limit)) results") {
                            selection.loadMore(total: session.hits.count)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .accessibilityIdentifier("search-load-more")
                    }
                }.padding(6)
            }
            .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
            .onKeyPress(.downArrow) { moveSelection(1); return .handled }
            .task(id: selection.selected) {
                guard let id = selection.selected else { return }
                await Task.yield()
                guard !Task.isCancelled else { return }
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }

    private func moveSelection(_ offset: Int) {
        selection.move(offset, in: destinations)
        if focusedResult != nil { focusedResult = selection.selected }
    }

    private func activate(_ destination: SearchDestination?) {
        guard !session.isSearching, session.options == options, let destination else { return }
        do {
            let hit = session.hits.first { $0.id == destination }
            let request = try ContentReveal.resolve(destination, field: hit?.field ?? .text, query: options.needle,
                blocks: context.fetch(FetchDescriptor<Block>()), lists: context.fetch(FetchDescriptor<TaskList>()))
            env.navigator.reveal(request)
            dismiss()
        } catch {
            unavailable = error.localizedDescription
            isFieldFocused = true
        }
    }
}
