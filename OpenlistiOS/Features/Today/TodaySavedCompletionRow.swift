import SwiftUI

/// A saved occurrence can open its task, while its completed state stays read-only.
struct TodaySavedCompletionRow: View {
    let completion: ActivityCompletion
    let separator: OLSeparator
    @Environment(PhoneEnvironment.self) private var env

    var body: some View {
        let title = completion.title.isEmpty ? "Untitled" : completion.title
        let time = CompactText.clock(completion.date, calendar: env.settings.calendar)
        let label = HStack(spacing: 14) {
            OLCheckmark(state: .done)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(OLFont.rowTitle).strikethrough().foregroundStyle(OL.muted)
                Text([completion.listTitle, time].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(OL.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 16)
        .frame(minHeight: 62)
        .contentShape(.rect)
        let value = ["Completed", completion.listTitle, time].filter { !$0.isEmpty }.joined(separator: ", ")

        Group {
            if let id = completion.taskID, env.store.block(id: id) != nil {
                Button { env.navigator.open(.taskDetail(id)) } label: { label }
                    .buttonStyle(OLRowPressStyle())
            } else {
                label.accessibilityElement(children: .combine)
            }
        }
        .accessibilityLabel(title)
        .accessibilityValue(value)
        .overlay(alignment: .top) { OLSeparatorLine(separator: separator) }
    }
}
