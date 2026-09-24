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
/// It reads as the design's note block, with the match in the accent as its
/// search hits have it.
struct ContentRevealNote: View {
    @Environment(\.nextStyle) private var style
    let text: String
    let query: String
    let requestID: UUID?
    @State private var hasAppeared = false
    @State private var showsFullNote = false
    @AccessibilityFocusState private var isAccessibilityFocused: Bool

    var body: some View {
        let snippet = SearchProjection.snippet(text, matching: query)
        // A short note shows whole, line breaks and all.
        let isWhole = snippet == text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        VStack(alignment: .leading, spacing: 6) {
            Text("Matched note")
                .font(.system(size: 10.5, weight: .semibold))
                .kerning(0.735)
                .textCase(.uppercase)
                .foregroundStyle(NX.ink(0.36))
                .accessibilityAddTraits(.isHeader)
            note(highlighted(isWhole ? text : snippet))
            if !isWhole {
                Button { withAnimation(style.ease(220)) { showsFullNote.toggle() } } label: {
                    HStack(spacing: 5) {
                        Text("Full note")
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8.5, weight: .bold))
                            .rotationEffect(.degrees(showsFullNote ? 0 : -90))
                    }
                }
                .buttonStyle(NXPanelButtonStyle(kind: .quiet, size: .small))
                .padding(.leading, -5)
                .accessibilityValue(showsFullNote ? "Expanded" : "Collapsed")
                if showsFullNote { note(AttributedString(text)) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(NX.ink(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Search result in note")
        // VoiceOver goes to the match; the keyboard stays with the page's
        // keys, and no focus ring is drawn around a card the design has none on.
        .accessibilityFocused($isAccessibilityFocused)
        .preference(key: ContentRevealNoteReadyKey.self, value: hasAppeared ? requestID : nil)
        .onAppear { hasAppeared = true }
        .onDisappear { hasAppeared = false }
        .task(id: requestID) {
            guard requestID != nil else { return }
            await Task.yield()
            guard !Task.isCancelled else { return }
            isAccessibilityFocused = true
        }
    }

    /// The design's note type: 13/1.55 at ink 0.7.
    private func note(_ value: AttributedString) -> some View {
        let font = NSFont.systemFont(ofSize: 13)
        let leading = max(0, 13 * 1.55 - (font.ascender - font.descender + font.leading))
        return Text(value)
            .font(.system(size: 13))
            .lineSpacing(leading)
            .foregroundStyle(NX.ink(0.7))
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    /// The match as the design's search marks it: the accent on its faint
    /// tint, in the note's own weight.
    private func highlighted(_ excerpt: String) -> AttributedString {
        var value = AttributedString(excerpt)
        if let range = value.range(of: query, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) {
            value[range].foregroundColor = style.accent
            value[range].backgroundColor = style.accent.opacity(0.15)
        }
        return value
    }
}
