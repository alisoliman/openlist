import SwiftUI

/// A quiet, full-width switch with a complete 44-point target for each view.
struct ListsViewPicker: View {
    @Binding var selection: ListsViewMode
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 3) {
            ForEach(ListsViewMode.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    HStack(spacing: 6) {
                        if !dynamicTypeSize.isAccessibilitySize { Image(systemName: mode.symbol) }
                        Text(mode.title)
                    }
                        .font(OLFont.segment)
                        .foregroundStyle(selection == mode ? OL.ink : OL.muted)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(selection == mode ? OL.surface : .clear, in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == mode ? .isSelected : [])
                .accessibilityIdentifier("lists.view.\(mode.rawValue)")
            }
        }
        .padding(3)
        .background(OL.sunken, in: .capsule)
        .olFeedback(.selection, trigger: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Lists view")
    }
}
