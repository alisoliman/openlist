import SwiftUI

/// A native picker keeps the selected mode visible and exposes checked menu
/// items to keyboard navigation and VoiceOver.
struct TodaySortMenu: View {
    @Binding var selection: TodaySorting

    var body: some View {
        Menu {
            Picker("Sort Today", selection: $selection) {
                ForEach(TodaySorting.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label(selection == .default ? "Sort" : selection.title, systemImage: "arrow.up.arrow.down")
                .font(Theme.Font.metadata)
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(selection.explanation)
        .accessibilityLabel("Sort Today")
        .accessibilityValue(selection.title)
        .accessibilityHint(selection.explanation)
        .accessibilityIdentifier("today-sort-menu")
    }
}
