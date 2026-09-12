//
//  SearchView.swift
//  openlist
//

import SwiftData
import SwiftUI

/// ⌘F — full-text search across tasks, notes and lists.
struct SearchView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @Query private var blocks: [Block]
    @Query(filter: #Predicate<TaskList> { $0.mergedIntoID == nil }) private var lists: [TaskList]

    @State private var query = ""
    @State private var scope: Scope = .everything
    @State private var selectedResult: SearchDestination?
    @FocusState private var isFieldFocused: Bool

    private enum SearchDestination: Hashable {
        case list(UUID)
        case block(UUID)
    }

    enum Scope: String, CaseIterable, Identifiable {
        case everything, tasks, notes, lists
        var id: String { rawValue }
        var title: String {
            switch self {
            case .everything: "All"
            case .tasks: "Tasks"
            case .notes: "Notes"
            case .lists: "Lists"
            }
        }
    }

    var body: some View {
        // Scanning the whole corpus is the expensive part, so it happens once
        // per render rather than once per `body` read.
        let blockHits = matchingBlocks
        let listHits = matchingLists
        let listsByID = Dictionary(lists.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let destinations = listHits.map { SearchDestination.list($0.id) }
            + blockHits.map { SearchDestination.block($0.id) }

        return VStack(spacing: 0) {
            header(destinations: destinations)
            Divider()

            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "Search everything",
                    message: "Find tasks, notes and lists by name or content."
                )
                .frame(maxHeight: .infinity)
            } else if listHits.isEmpty && blockHits.isEmpty {
                EmptyStateView(
                    icon: "questionmark.circle",
                    title: "No results",
                    message: "Nothing matches “\(query)”."
                )
                .frame(maxHeight: .infinity)
            } else {
                resultsList(blockHits: blockHits, listHits: listHits, listsByID: listsByID)
                Divider()
                HStack {
                    Text("\(destinations.count) results")
                    Spacer()
                    Text("↑↓ to choose · Return to open · Esc to close")
                }
                .font(Theme.Font.metadata)
                .foregroundStyle(Theme.secondaryText)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
        }
        .frame(width: 640, height: 480)
        .background(.regularMaterial)
        .task {
            // A sheet's initial responder is assigned after it appears.
            await Task.yield()
            isFieldFocused = true
        }
        .onChange(of: query) { _, _ in selectedResult = destinations.first }
        .onChange(of: scope) { _, _ in selectedResult = destinations.first }
        .onChange(of: destinations, initial: true) { _, updated in
            if selectedResult.map({ !updated.contains($0) }) ?? true {
                selectedResult = updated.first
            }
        }
    }

    private func header(destinations: [SearchDestination]) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.tertiaryText)

                TextField("Search tasks, notes and lists", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($isFieldFocused)
                    .onSubmit { activate(selectedResult ?? destinations.first) }
                    .onKeyPress(.upArrow) {
                        moveSelection(by: -1, in: destinations)
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        moveSelection(by: 1, in: destinations)
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        dismiss()
                        return .handled
                    }

                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.tertiaryText)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }

            Picker("Search scope", selection: $scope) {
                ForEach(Scope.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func resultsList(
        blockHits: [Block],
        listHits: [TaskList],
        listsByID: [UUID: TaskList]
    ) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if !listHits.isEmpty {
                        SectionLabel("Lists")
                            .padding(.horizontal, 10)
                            .padding(.top, 8)
                            .padding(.bottom, 3)

                        ForEach(listHits) { list in
                            SearchResultRow(
                                symbol: nil,
                                emoji: list.icon,
                                title: list.displayTitle,
                                subtitle: list.summary.isEmpty
                                    ? (list.isArchived ? "Archived list" : "List")
                                    : list.summary + (list.isArchived ? " · Archived" : ""),
                                accent: list.accent,
                                highlight: query,
                                isSelected: selectedResult == .list(list.id)
                            ) {
                                activate(.list(list.id))
                            }
                            .id(SearchDestination.list(list.id))
                            .onHover { if $0 { selectedResult = .list(list.id) } }
                        }
                    }

                    if !blockHits.isEmpty {
                        SectionLabel("Content")
                            .padding(.horizontal, 10)
                            .padding(.top, 10)
                            .padding(.bottom, 3)

                        ForEach(blockHits) { block in
                            SearchResultRow(
                                symbol: block.isTask
                                    ? (block.isCompleted ? "checkmark.circle.fill" : "circle")
                                    : block.kind.symbol,
                                emoji: nil,
                                title: block.displayTitle,
                                subtitle: subtitle(for: block, list: block.listID.flatMap { listsByID[$0] }),
                                accent: block.listID.flatMap { listsByID[$0] }?.accent ?? .graphite,
                                highlight: query,
                                isSelected: selectedResult == .block(block.id)
                            ) {
                                activate(.block(block.id))
                            }
                            .id(SearchDestination.block(block.id))
                            .onHover { if $0 { selectedResult = .block(block.id) } }
                        }
                    }
                }
                .padding(6)
            }
            .onChange(of: selectedResult) { _, destination in
                guard let destination else { return }
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo(destination, anchor: .center)
                }
            }
        }
    }

    private func moveSelection(by offset: Int, in destinations: [SearchDestination]) {
        guard !destinations.isEmpty else { selectedResult = nil; return }
        guard let selectedResult, let index = destinations.firstIndex(of: selectedResult) else {
            self.selectedResult = offset < 0 ? destinations.last : destinations.first
            return
        }
        self.selectedResult = destinations[min(destinations.count - 1, max(0, index + offset))]
    }

    private func activate(_ destination: SearchDestination?) {
        switch destination {
        case let .list(id):
            env.navigator.go(to: .list(id))
            dismiss()
        case let .block(id):
            if let block = env.store.block(id: id) { open(block) }
        case nil:
            break
        }
    }

    // MARK: - Matching

    private var needle: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var matchingLists: [TaskList] {
        guard scope == .everything || scope == .lists, !needle.isEmpty else { return [] }
        return lists.filter {
            $0.title.localizedCaseInsensitiveContains(needle)
                || $0.summary.localizedCaseInsensitiveContains(needle)
        }
        .sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
    }

    private var matchingBlocks: [Block] {
        guard !needle.isEmpty else { return [] }

        let candidates = blocks.filter { block in
            switch scope {
            case .lists: return false
            case .tasks: return block.isTask
            case .notes: return !block.isTask
            case .everything: return true
            }
        }

        let lowered = needle.lowercased()
        return candidates
            .filter {
                $0.text.lowercased().contains(lowered) || $0.note.lowercased().contains(lowered)
            }
            // Open tasks first, then most recently touched.
            .sorted { lhs, rhs in
                if lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }
                return lhs.updatedAt > rhs.updatedAt
            }
            .prefix(80)
            .map(\.self)
    }

    private func subtitle(for block: Block, list: TaskList?) -> String {
        var parts: [String] = []
        if let list {
            parts.append("\(list.icon) \(list.displayTitle)")
            if list.isArchived { parts.append("Archived") }
        }
        if block.isTask, let dueDate = block.dueDate {
            parts.append(Store.relativeDateText(dueDate).capitalizedFirstLetter)
        }
        if !block.note.isEmpty, block.note.localizedCaseInsensitiveContains(needle) {
            parts.append(block.note.replacingOccurrences(of: "\n", with: " "))
        }
        return parts.joined(separator: " · ")
    }

    private func open(_ block: Block) {
        if let listID = block.listID, env.store.list(id: listID) != nil {
            env.navigator.go(to: .list(listID))
        }
        env.navigator.selection = [block.id]
        if block.isTask {
            env.navigator.openTask(block.id)
        }
        dismiss()
    }
}

/// A search hit, with the matched substring emphasised.
struct SearchResultRow: View {
    let symbol: String?
    let emoji: String?
    let title: String
    let subtitle: String
    let accent: ListAccent
    let highlight: String
    var isSelected: Bool = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Group {
                    if let emoji {
                        Text(emoji)
                            .font(.system(size: 13))
                    } else if let symbol {
                        Image(systemName: symbol)
                            .font(.system(size: 12))
                            .foregroundStyle(accent.color)
                    }
                }
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(accent.softBackground)
                )

                VStack(alignment: .leading, spacing: 1) {
                    Text(attributed(title))
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.tertiaryText)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Theme.accent.opacity(0.12) : (isHovering ? Theme.rowHover : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .onHover { isHovering = $0 }
    }

    /// Bolds the matched run inside the title.
    private func attributed(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        let needle = highlight.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty, let range = result.range(of: needle, options: .caseInsensitive) else {
            return result
        }
        result[range].foregroundColor = Theme.accent
        result[range].font = .system(size: 13, weight: .bold)
        return result
    }
}
