import SwiftUI

struct SearchResultRow: View {
    let hit: SearchHit
    let query: String
    let isSelected: Bool
    var focusedResult: FocusState<SearchDestination?>.Binding
    let onReturn: () -> Void
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Group {
                    if let emoji = hit.emoji { Text(emoji) }
                    else if let symbol = hit.symbol { Image(systemName: symbol).foregroundStyle(hit.accent.color) }
                }
                .font(.system(size: 13))
                .frame(width: 24, height: 24)
                .background(hit.accent.softBackground, in: .rect(cornerRadius: 6))
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(highlighted(hit.title)).font(.system(size: 13, weight: .medium)).lineLimit(2)
                    Text(hit.context).font(.system(size: 11)).foregroundStyle(Theme.secondaryText).lineLimit(2)
                    if !hit.snippet.isEmpty {
                        Text(highlighted(hit.snippet)).font(.system(size: 12)).lineLimit(2)
                    }
                }
                Spacer(minLength: 4)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Theme.accent.opacity(0.12) : .clear, in: .rect(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable()
        .focused(focusedResult, equals: hit.id)
        .onKeyPress(.return) { onReturn(); return .handled }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityLabel([hit.title, hit.context, hit.field == .note ? "Note: \(hit.snippet)" : hit.snippet].joined(separator: ". "))
        .accessibilityHint("Open and reveal this result")
    }

    private func highlighted(_ text: String) -> AttributedString {
        var value = AttributedString(text)
        if let range = value.range(of: query, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) {
            value[range].foregroundColor = Theme.accent
            value[range].inlinePresentationIntent = .stronglyEmphasized
        }
        return value
    }
}
