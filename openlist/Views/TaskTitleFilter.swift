import SwiftUI

struct TaskTitleFilter: View {
    @Binding var query: String
    var onFocus: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("Filter task titles", text: $query)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .accessibilityLabel("Filter task titles")
                .accessibilityHint("Matches titles within the selected status and list. Notes and labels are not searched.")
                .accessibilityIdentifier("tasks-title-filter")
                .onChange(of: isFocused) { _, focused in
                    if focused { onFocus() }
                }
                .onKeyPress(.escape) {
                    guard !query.isEmpty else { return .ignored }
                    query = ""
                    return .handled
                }

            if !query.isEmpty {
                Button("Clear title filter", systemImage: "xmark.circle.fill") { query = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("tasks-clear-title-filter")
            }
        }
        .font(.body)
        .padding(10)
        .background(Theme.chipFill, in: .rect(cornerRadius: 8))
    }
}
