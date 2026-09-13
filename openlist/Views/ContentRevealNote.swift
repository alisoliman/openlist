import SwiftUI

/// Report a laid-out note card so the page can refine its initial row scroll.
struct ContentRevealNoteReadyKey: PreferenceKey {
    static var defaultValue: UUID? { nil }
    static func reduce(value: inout UUID?, nextValue: () -> UUID?) {
        value = nextValue() ?? value
    }
}

/// Non-task notes have no inspector editor. Reveal the matching passage in
/// its owning document, with the full retained note available for reading.
struct ContentRevealNote: View {
    let text: String
    let query: String
    let requestID: UUID?
    @State private var hasAppeared = false
    @FocusState private var isFocused: Bool
    @AccessibilityFocusState private var isAccessibilityFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Matched note").font(.callout.weight(.semibold))
            Text(excerpt).textSelection(.enabled)
            DisclosureGroup("Full note") { Text(text).textSelection(.enabled) }
        }
        .font(Theme.Font.body)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.accent.opacity(0.08), in: .rect(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Search result in note")
        .focusable()
        .focused($isFocused)
        .accessibilityFocused($isAccessibilityFocused)
        .preference(key: ContentRevealNoteReadyKey.self, value: hasAppeared ? requestID : nil)
        .onAppear { hasAppeared = true }
        .onDisappear { hasAppeared = false }
        .task(id: requestID) {
            guard requestID != nil else { return }
            await Task.yield()
            guard !Task.isCancelled else { return }
            isFocused = true
            isAccessibilityFocused = true
        }
    }

    private var excerpt: AttributedString {
        var value = AttributedString(SearchProjection.snippet(text, matching: query))
        if let range = value.range(of: query, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) {
            value[range].foregroundColor = Theme.accent
            value[range].inlinePresentationIntent = .stronglyEmphasized
        }
        return value
    }
}
