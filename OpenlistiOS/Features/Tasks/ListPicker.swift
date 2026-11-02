//
//  ListPicker.swift
//  OpenlistiOS
//

import SwiftUI

/// Every list a task can go to, in a sheet with a search field: the list
/// its words point to first, then the lists in the sidebar's order, a nested
/// one by its path, narrowed as a name is typed. Triage's More, a row's Move
/// to list and Select's move all pick here, however many lists there are.
struct ListPickerSheet: View {
    let title: String
    /// Lists it can't go to, such as the one it's in.
    var excluding: Set<UUID> = []
    /// The list triage suggests, which leads while nothing's typed.
    var suggested: TaskList?
    let pick: (TaskList) -> Void
    @Environment(\.phoneLibrary) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        let matches = matches
        NavigationStack {
            List {
                if query.isEmpty, let suggested, !excluding.contains(suggested.id) {
                    Section("Suggested") { row(suggested) }
                }
                Section {
                    ForEach(matches) { row($0) }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Find a list")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("listPicker.cancel")
                }
            }
            .overlay {
                if matches.isEmpty { ContentUnavailableView.search(text: query) }
            }
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("screen.listPicker")
    }

    /// The lists whose path holds what's typed, in the sidebar's order.
    private var matches: [TaskList] {
        let lists = library.lists.filter { !excluding.contains($0.id) }
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return lists }
        return lists.filter { library.hierarchy.path(for: $0.id).localizedStandardContains(needle) }
    }

    private func row(_ list: TaskList) -> some View {
        let path = library.hierarchy.path(for: list.id)
        return Button {
            pick(list)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                OLListGlyph(icon: list.isSystemInbox ? "📥" : list.icon, accent: list.accent.color, size: 18)
                    .frame(width: 24)
                Text(path)
                    .foregroundStyle(OL.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Text("\(library.openCount(in: list.id))")
                    .font(OLFont.meta)
                    .monospacedDigit()
                    .foregroundStyle(OL.muted)
            }
        }
        .accessibilityLabel(path)
        .accessibilityValue("\(library.openCount(in: list.id)) open")
        .accessibilityIdentifier("listPicker.row")
    }
}
